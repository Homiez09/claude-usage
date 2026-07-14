import Foundation
import Network

/// Minimal HTTP server so an iPhone on the same Wi-Fi can view the same usage
/// numbers as the Mac menu bar, in Safari, with no app to install. Only ever
/// serves `UsageSnapshot` (percentages + timestamps) — the session key stored
/// in Keychain never leaves this Mac process.
@MainActor
final class LocalWebServer {
    nonisolated static let defaultPort: UInt16 = 8765

    private weak var store: UsageStore?
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    let port: UInt16

    private(set) var isRunning = false

    init(store: UsageStore, port: UInt16 = LocalWebServer.defaultPort) {
        self.store = store
        self.port = port
    }

    deinit {
        listener?.cancel()
        for connection in connections {
            connection.cancel()
        }
    }

    func start() {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: parameters, on: nwPort) else { return }

        listener.newConnectionHandler = { [weak self] connection in
            // `listener.start(queue: .main)` below guarantees this closure always
            // runs on the main thread, so it's safe to assume MainActor isolation
            // here rather than paying for a Task hop per incoming connection.
            MainActor.assumeIsolated {
                self?.handle(connection)
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                case .failed, .cancelled:
                    self.isRunning = false
                default:
                    break
                }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        isRunning = false
    }

    private func handle(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        receive(on: connection, buffered: Data())
    }

    private func receive(on connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            // `connection.start(queue: .main)` guarantees this runs on the main
            // thread, so MainActor isolation can be assumed synchronously here.
            MainActor.assumeIsolated {
                guard let self else { return }
                var buffer = buffered
                if let data, !data.isEmpty {
                    buffer.append(data)
                }

                if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let requestLine = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8)?
                        .components(separatedBy: "\r\n")
                        .first ?? ""
                    self.respond(to: requestLine, on: connection)
                    return
                }

                if isComplete || error != nil {
                    self.close(connection)
                    return
                }
                self.receive(on: connection, buffered: buffer)
            }
        }
    }

    private func respond(to requestLine: String, on connection: NWConnection) {
        let path = requestLine.split(separator: " ").count > 1
            ? String(requestLine.split(separator: " ")[1])
            : "/"

        let (contentType, body) = LocalWebServer.route(
            path: path,
            snapshotJSON: currentSnapshotJSON,
            historyJSON: { [weak self] granularityKey in self?.historyJSON(granularityQueryKey: granularityKey) ?? "{}" },
            projectsJSON: { [weak self] in self?.projectsJSON() ?? "[]" }
        )

        var response = "HTTP/1.1 200 OK\r\n"
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(body.utf8.count)\r\n"
        response += "Cache-Control: no-store\r\n"
        response += "Connection: close\r\n\r\n"
        response += body

        connection.send(
            content: response.data(using: .utf8),
            completion: .contentProcessed { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.close(connection)
                }
            }
        )
    }

    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections.removeAll { $0 === connection }
    }

    private var currentSnapshotJSON: String {
        guard let store else { return "{}" }
        let activeAgentSessions = store.activityMonitor.activeSessions.map { session -> String in
            var label = session.displayName
            if let model = session.model {
                label += "|\(model)"
            }
            return label
        }
        let snapshot = UsageSnapshotBuilder.build(
            hasSessionKey: store.hasSessionKey,
            usage: store.usage,
            errorMessage: store.errorMessage,
            lastUpdated: store.lastUpdated,
            activeAgentSessions: activeAgentSessions
        )
        return UsageSnapshotBuilder.encodeJSON(snapshot)
    }

    private func historyJSON(granularityQueryKey: String) -> String {
        guard let store else { return "{\"granularity\":\"day\",\"periods\":[]}" }
        let granularity = UsageHistoryGranularity(queryKey: granularityQueryKey) ?? .day
        let buckets = store.historyStore.buckets(for: granularity)
        return UsageHistorySnapshotBuilder.encodeJSON(UsageHistorySnapshotBuilder.build(buckets: buckets, granularity: granularity))
    }

    private func projectsJSON() -> String {
        guard let store else { return "[]" }
        let breakdown = store.historyStore.projectBreakdown()
        if let data = try? JSONEncoder().encode(breakdown),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }

    /// Pure routing logic, separated from the NWConnection plumbing above so it's testable
    /// without opening a real socket. `path` may include a query string (e.g.
    /// "/api/history?granularity=month") — the raw HTTP request-line target.
    nonisolated static func route(
        path: String,
        snapshotJSON: @autoclosure () -> String,
        historyJSON: (String) -> String = { _ in "{}" },
        projectsJSON: () -> String = { "[]" }
    ) -> (contentType: String, body: String) {
        let parts = path.split(separator: "?", maxSplits: 1)
        let basePath = String(parts.first ?? "")

        switch basePath {
        case "/api/usage":
            return ("application/json; charset=utf-8", snapshotJSON())
        case "/api/history":
            let query = parts.count > 1 ? String(parts[1]) : ""
            let granularityKey = queryValue(query, key: "granularity") ?? "day"
            return ("application/json; charset=utf-8", historyJSON(granularityKey))
        case "/api/projects":
            return ("application/json; charset=utf-8", projectsJSON())
        default:
            return ("text/html; charset=utf-8", Self.htmlPage)
        }
    }

    nonisolated private static func queryValue(_ query: String, key: String) -> String? {
        for pair in query.split(separator: "&") {
            let keyValue = pair.split(separator: "=", maxSplits: 1)
            if keyValue.count == 2, keyValue[0] == Substring(key) {
                return String(keyValue[1])
            }
        }
        return nil
    }

    nonisolated static let htmlPage = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <title>Claude Usage</title>
    <style>
      :root {
        color-scheme: light dark;
        --brand-1: #e8985a; --brand-2: #c1521f;
        --bg: #f4f2ef; --card: rgba(255,255,255,0.75); --card-border: rgba(0,0,0,0.06);
        --text: #16130f; --muted: #8a8478; --track: rgba(0,0,0,0.08);
        --shadow: 0 1px 3px rgba(20,15,10,0.06), 0 8px 24px rgba(20,15,10,0.05);
      }
      @media (prefers-color-scheme: dark) {
        :root {
          --bg: #14110e; --card: rgba(255,255,255,0.055); --card-border: rgba(255,255,255,0.08);
          --text: #f3efe9; --muted: #9c9587; --track: rgba(255,255,255,0.1);
          --shadow: 0 1px 3px rgba(0,0,0,0.3), 0 8px 24px rgba(0,0,0,0.35);
        }
      }
      * { box-sizing: border-box; }
      html { -webkit-text-size-adjust: 100%; }
      body {
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
        margin: 0; padding: 22px 16px 44px;
        background:
          radial-gradient(1100px 380px at 50% -120px, color-mix(in srgb, var(--brand-1) 16%, transparent), transparent),
          var(--bg);
        color: var(--text);
        min-height: 100vh;
      }
      .wrap { max-width: 440px; margin: 0 auto; }

      /* ---- Header ---- */
      .header {
        display: flex; align-items: center; gap: 12px;
        margin-bottom: 20px;
      }
      .logo-badge {
        width: 40px; height: 40px; border-radius: 12px; flex-shrink: 0;
        display: flex; align-items: center; justify-content: center;
        background: var(--card);
        border: 1px solid var(--card-border);
        box-shadow: var(--shadow);
      }
      #claudeLogo { width: 24px; height: 24px; will-change: transform; }
      #claudeLogo.bouncing { animation: bounce var(--dur, 0.55s) ease-in-out infinite alternate; }
      @keyframes bounce {
        0%   { transform: translateY(0px); }
        100% { transform: translateY(-5px); }
      }
      .header-titles h1 { font-size: 18px; margin: 0; font-weight: 700; letter-spacing: -0.01em; }
      .header-titles p { font-size: 12px; margin: 1px 0 0; color: var(--muted); }

      /* ---- Cards ---- */
      .card {
        background: var(--card);
        border: 1px solid var(--card-border);
        border-radius: 16px;
        padding: 16px;
        margin-bottom: 14px;
        box-shadow: var(--shadow);
        backdrop-filter: blur(20px);
        -webkit-backdrop-filter: blur(20px);
      }
      .card h2 {
        font-size: 11px; font-weight: 700; letter-spacing: 0.06em;
        text-transform: uppercase; color: var(--muted);
        margin: 0 0 12px;
      }

      /* ---- Active sessions ---- */
      .agent-row {
        display: flex; align-items: flex-start; gap: 8px;
        padding: 5px 0;
      }
      .agent-row-meta {
        display: flex; flex-direction: column; min-width: 0;
      }
      .agent-row-title {
        font-size: 13px; font-weight: 600;
        overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
      }
      .agent-row-model {
        font-size: 11px; color: var(--muted); margin-top: 2px;
      }
      .agents-empty { display: flex; align-items: center; gap: 8px; font-size: 13px; color: var(--muted); padding: 5px 0; }
      .pulsing-dot {
        width: 7px; height: 7px; border-radius: 50%;
        background: #34c759; flex-shrink: 0;
        box-shadow: 0 0 0 0 rgba(52,199,89,0.6);
        animation: pulse 1.2s ease-in-out infinite;
      }
      .idle-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--muted); opacity: 0.5; flex-shrink: 0; }
      @keyframes pulse {
        0%, 100% { transform: scale(0.85); opacity: 0.6; }
        50%       { transform: scale(1.5); opacity: 1; }
      }

      /* ---- Usage rows ---- */
      .row + .row { margin-top: 16px; }
      .row-meta {
        display: flex; justify-content: space-between;
        align-items: flex-end; margin-bottom: 6px; gap: 8px;
      }
      .row-title-group { display: flex; flex-direction: column; gap: 2px; }
      .row-title { font-size: 14px; font-weight: 600; }
      .row-reset { font-size: 11px; color: var(--muted); }
      .row-pct { font-size: 15px; font-weight: 700; white-space: nowrap; font-variant-numeric: tabular-nums; }
      .bar-track {
        height: 8px; background: var(--track);
        border-radius: 5px; overflow: hidden;
      }
      .bar-fill {
        height: 100%; border-radius: 5px;
        transition: width 0.5s cubic-bezier(.4,0,.2,1);
        background-size: 200% 100%;
      }

      /* ---- Section divider ---- */
      .section-label {
        font-size: 10px; font-weight: 700; letter-spacing: 0.06em;
        text-transform: uppercase; color: var(--muted);
        margin: 18px 0 10px;
      }

      /* ---- Misc ---- */
      .updated { font-size: 11px; color: var(--muted); margin-top: 10px; }
      .error    { color: #ff453a; font-size: 13px; font-weight: 500; }

      /* ---- History ---- */
      .history-hint { font-size: 11px; color: var(--muted); margin: -6px 0 12px; }
      select#historyGranularity {
        font-size: 13px; font-weight: 500; padding: 7px 12px; margin-bottom: 12px;
        border-radius: 8px; border: 1px solid var(--card-border);
        background: var(--track); color: inherit;
        appearance: none; -webkit-appearance: none;
        width: 100%;
      }
      .history-row {
        display: flex; justify-content: space-between; align-items: center;
        font-size: 13px; padding: 9px 2px; gap: 8px;
        border-bottom: 1px solid var(--card-border);
      }
      .history-row:last-child { border-bottom: none; }
      .history-row .history-label { font-weight: 600; }
      .history-row .history-amounts { text-align: right; }
      .history-row .history-cost { font-weight: 700; font-variant-numeric: tabular-nums; }
      .history-row .history-tokens { display: block; font-size: 11px; color: var(--muted); margin-top: 1px; }

      footer.credit { text-align: center; font-size: 11px; color: var(--muted); margin-top: 22px; }
    </style>
    </head>
    <body>
    <div class="wrap">
      <div class="header">
        <div class="logo-badge">
          <img id="claudeLogo"
            src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAAXNSR0IArs4c6QAAAHhlWElmTU0AKgAAAAgABAEaAAUAAAABAAAAPgEbAAUAAAABAAAARgEoAAMAAAABAAIAAIdpAAQAAAABAAAATgAAAAAAAABIAAAAAQAAAEgAAAABAAOgAQADAAAAAQABAACgAgAEAAAAAQAAAECgAwAEAAAAAQAAAEAAAAAAdd52hwAAAAlwSFlzAAALEwAACxMBAJqcGAAABNJJREFUeAHtWt1rXEUUn497dzcGoU+iIvgiaTUqlNYKPor66geYiPokNC+CL4oJBnwQKonQP8A860Oi9A9Q8U3B2iJaqk0QqiBCi0pa7SZ779wZf+cms727m72zd29vvnaGbObunJlzfvObYc6Zc5cxXzwDngHPgGfAM+AZ8Ax4BjwDngHPwAgywF1zXpubeiaU4UOtOHZ13VfyehiyOIl/nVhY+SoPWJAnJJnR7M3xMfmCdFLl0rS78kYo2XpTnYPVcgQwxlsbsWKbcbK7MyhpzTAD6LzlUiNcHQ673BNw2FfYNb+R3wFOL+BiMJSCCX7bRURJwgzOnyoKmalJ2VatYShOdPv7MA+lCKBpK20uGqPXyTjmTTvqFAgZN3eYBY7ZY8K3NlVyHnbTWaPtCJ5PlOG7FAFCcBZr9tbDi8vfEgFUrsxNXwoEfzROysDa0pX9D50s0ubqsYXlp237L7OvPBUK/k2ih7dV+gwQgrX35IWZmZAbRhujkkK6yYZVnrVt24rWpQkoanC/9fcE7LcV2W08fgcMwHjuEasFa9+STix9rAwnb1hNId1kw2rP2rZtHXV6I+po6fnCV2env+5p7Wgwk4KLeyjo6C7bx/0PkKzjw+H/Ofz/SVSVxAHQfQu6LwALuGD0OQJMx3uRISBJ4wZ9HbAuo9821O4ZQPDb/Ks7jW/3pEhrp8nbDtlIkBTFFUeCISJBOxvClRcJEgmEL68ELdXewXn9+sryAPQdNKSANmFUAC8R5JpfPj1DAj1IwzwBB2m1qsA68jsgGEP2NK9E8AJlblt5uquWSdwgay4vsKGS07lADJuBK3liN0/7XDwDCsn9AfP3GyZZyhtiXWrfPmvvTn9Sr8nXDlpanN4LtKLk04mPll/vOzkInGcAXG+ppEme8aplg2B3ElA1yL3W7wnY6xXYa/sjvwPcBxw3tUaAWIGueigUF2Rvh+RncUVNb2jUheTZlHgNY8nVON0NKc8U0pXqy1x+yE5qb1tGdsieLXT7s36fMG/GqmZl/WonAXg9fnYj0p9HWm1RYPg8fOwkxQVkEAA+4Npcodyw0SJgXH8ohXiASMKfimI1xwX7k91OHvfD0tWOFyya3Q92F2AGWXGOgEz/0YrZe1xoRWkYI/gxtL9Ptsjvq0RfbiXqDClCxoBj/O9dSnu+Fl0YtjY79UUtCJ6layZFWolInjx65rPzVvPq7NRPuLM/pjTtBPCj4olHzp5zArHjs/XPb7/0oAzCNVrYADlw5BouHV1cedz2WZ1/+ZTU8juKVOtY8UipLycWV56z8kHqwmcAtkFn7Kxl3RraytljvTNFSNnIfC302DuWi+x7AZaxTYp7sA1grQPsAP0PXRdPwKFb0oITKrwD4PDwTpSnHmD7ZO4+SNtyYCmsfwf8ffXBK1Amuo2FsO0wPrfJ6QZ7RhtzE25nnVwPR2I6FLL793M3UjlOZgCKEgN3MGTRGBtw+Y/WpqbxZhTlRlYV2YaZFAvhgdu5mZUP8lyYgEQ23hBhVDcxfBNegf97V/KXNXRyaSn+8Z0Xnx8bqwdRc2tjXBv/G7n54QrGXr2vee9xCqOCGmz9FymyYbVFdXXx7qacbEIuQkrcNJy/CrNjfe0Z8Ax4BjwDngHPgGfAMzDqDPwPzPa/oFZT2iEAAAAASUVORK5CYII="
            alt="Claude">
        </div>
        <div class="header-titles">
          <h1>Claude Usage</h1>
          <p>Plan usage limits</p>
        </div>
      </div>

      <div class="card">
        <h2>Active sessions</h2>
        <div id="agents"></div>
      </div>

      <div class="card">
        <div id="rows">Loading…</div>
        <div id="updated" class="updated"></div>
      </div>

      <div class="card">
        <h2>History</h2>
        <div class="history-hint">ประมาณการเทียบเท่าราคา API ไม่ใช่บิลจริง</div>
        <select id="historyGranularity">
          <option value="day">รายวัน</option>
          <option value="month">รายเดือน</option>
          <option value="year">รายปี</option>
        </select>
        <div id="history">Loading…</div>
      </div>

      <div class="card">
        <h2>ค่าใช้จ่ายแยกตามโปรเจกต์</h2>
        <div class="history-hint">สะสมแยกตามโฟลเดอร์โปรเจกต์</div>
        <div id="projectsBreakdown">Loading…</div>
      </div>

      <footer class="credit">Claude Usage · local network only</footer>
    </div>

      <script>
        // ---- helpers ----
        function barColor(p) {
          if (p < 70) return 'linear-gradient(90deg, #007aff, #32ade6)';
          if (p < 90) return 'linear-gradient(90deg, #ff9500, #ffcc00)';
          return 'linear-gradient(90deg, #ff3b30, #ff2d92)';
        }
        function pctColor(p) {
          if (p < 70) return '#0a84ff';
          if (p < 90) return '#ff9f0a';
          return '#ff453a';
        }
        function describeReset(iso) {
          if (!iso) return '';
          const d = new Date(iso);
          const diffMs = d - new Date();
          if (diffMs <= 0) return 'Resetting now';
          const mins = Math.floor(diffMs / 60000);
          const hrs  = Math.floor(mins / 60);
          const rem  = mins % 60;
          if (hrs >= 24) {
            return 'Resets ' + d.toLocaleDateString(undefined, { weekday: 'short' }) + ' ' +
              d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
          }
          if (hrs > 0) return 'Resets in ' + hrs + ' hr ' + rem + ' min';
          return 'Resets in ' + rem + ' min';
        }
        function escapeHTML(s) {
          return s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
        }

        // ---- bouncing logo ----
        const logo = document.getElementById('claudeLogo');
        let currentBouncing = false;

        function updateLogo(activeCount) {
          if (activeCount > 0) {
            // base duration 0.55s, each extra session speeds it up by 0.1s, min 0.2s
            const dur = Math.max(0.2, 0.55 - (activeCount - 1) * 0.1);
            logo.style.setProperty('--dur', dur + 's');
            if (!currentBouncing) {
              logo.classList.add('bouncing');
              currentBouncing = true;
            }
          } else {
            logo.classList.remove('bouncing');
            logo.style.transform = '';
            currentBouncing = false;
          }
        }

        // ---- main refresh ----
        async function refresh() {
          const rowsEl   = document.getElementById('rows');
          const agentsEl = document.getElementById('agents');
          try {
            const res  = await fetch('/api/usage', { cache: 'no-store' });
            const data = await res.json();

            const activeAgents = data.activeAgentSessions || [];
            updateLogo(activeAgents.length);

            agentsEl.innerHTML = activeAgents.length > 0
              ? activeAgents.map(raw => {
                  const parts = raw.split('|');
                  const title = parts[0];
                  const model = parts[1] || '';
                  return '<div class="agent-row">' +
                           '<div class="pulsing-dot" style="margin-top:5px;"></div>' +
                           '<div class="agent-row-meta">' +
                             '<span class="agent-row-title">' + escapeHTML(title) + '</span>' +
                             (model ? '<span class="agent-row-model">' + escapeHTML(model) + '</span>' : '') +
                           '</div>' +
                         '</div>';
                }).join('')
              : '<div class="agents-empty"><div class="idle-dot"></div><span>Claude Code ว่างอยู่</span></div>';

            if (!data.hasSessionKey) {
              rowsEl.innerHTML = '<div class="error">ยังไม่ได้ตั้งค่า Session Key บนแอป Mac</div>';
              document.getElementById('updated').textContent = '';
              return;
            }
            if (data.rows.length === 0) {
              rowsEl.innerHTML = '<div class="error">' + escapeHTML(data.errorMessage || 'กำลังโหลดข้อมูล...') + '</div>';
              return;
            }

            // Separate "Current session" from weekly limits
            const sessionRows = data.rows.filter(r => r.title === 'Current session');
            const weeklyRows  = data.rows.filter(r => r.title !== 'Current session');

            function renderRow(r) {
              const pct = Math.min(Math.max(r.percent, 0), 100);
              return '<div class="row">' +
                '<div class="row-meta">' +
                  '<div class="row-title-group">' +
                    '<span class="row-title">' + escapeHTML(r.title) + '</span>' +
                    (r.resetsAt ? '<span class="row-reset">' + describeReset(r.resetsAt) + '</span>' : '') +
                  '</div>' +
                  '<span class="row-pct" style="color:' + pctColor(pct) + '">' + pct + '%</span>' +
                '</div>' +
                '<div class="bar-track"><div class="bar-fill" style="width:' + pct + '%;background:' + barColor(pct) + '"></div></div>' +
              '</div>';
            }

            let html = sessionRows.map(renderRow).join('');
            if (weeklyRows.length > 0) {
              html += '<div class="section-label">Weekly limits</div>';
              html += weeklyRows.map(renderRow).join('');
            }
            if (data.errorMessage) {
              html += '<div class="error">' + escapeHTML(data.errorMessage) + '</div>';
            }
            rowsEl.innerHTML = html;

            document.getElementById('updated').textContent = data.lastUpdated
              ? ('Last updated: ' + new Date(data.lastUpdated).toLocaleTimeString())
              : '';
          } catch (e) {
            updateLogo(0);
            rowsEl.innerHTML = '<div class="error">เชื่อมต่อ Mac ไม่ได้ ตรวจสอบว่าเปิดแอปและอยู่ WiFi เดียวกันอยู่</div>';
          }
        }

        // ---- history ----
        const currencyFmt = new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD' });
        const tokenFmt = new Intl.NumberFormat();
        let historyGranularity = document.getElementById('historyGranularity').value;

        async function refreshHistory() {
          const historyEl = document.getElementById('history');
          try {
            const res = await fetch('/api/history?granularity=' + historyGranularity, { cache: 'no-store' });
            const data = await res.json();
            const periods = data.periods || [];
            if (periods.length === 0) {
              historyEl.innerHTML = '<div class="error">ไม่มีข้อมูล</div>';
              return;
            }
            historyEl.innerHTML = periods.map(period =>
              '<div class="history-row">' +
                '<span class="history-label">' + escapeHTML(period.label) + '</span>' +
                '<span class="history-amounts">' +
                  '<span class="history-cost">' + currencyFmt.format(period.costUSD) + '</span>' +
                  '<span class="history-tokens">' + tokenFmt.format(period.tokens) + ' tokens</span>' +
                '</span>' +
              '</div>'
            ).join('');
          } catch (e) {
            historyEl.innerHTML = '<div class="error">โหลดประวัติไม่ได้</div>';
          }
        }
        async function refreshProjects() {
          const projectsEl = document.getElementById('projectsBreakdown');
          try {
            const res = await fetch('/api/projects', { cache: 'no-store' });
            const data = await res.json();
            if (data.length === 0) {
              projectsEl.innerHTML = '<div class="error">ไม่มีข้อมูล</div>';
              return;
            }
            projectsEl.innerHTML = data.map(p =>
              '<div class="history-row">' +
                '<span class="history-label">' + escapeHTML(p.name) + '</span>' +
                '<span class="history-amounts">' +
                  '<span class="history-cost">' + currencyFmt.format(p.costUSD) + '</span>' +
                  '<span class="history-tokens">' + tokenFmt.format(p.tokens) + ' tokens</span>' +
                '</span>' +
              '</div>'
            ).join('');
          } catch (e) {
            projectsEl.innerHTML = '<div class="error">โหลดข้อมูลโปรเจกต์ไม่ได้</div>';
          }
        }
        document.getElementById('historyGranularity').addEventListener('change', e => {
          historyGranularity = e.target.value;
          refreshHistory();
        });

        refresh();
        refreshHistory();
        refreshProjects();
        setInterval(refresh, 3000);
        setInterval(refreshHistory, 20000);
        setInterval(refreshProjects, 20000);
      </script>
    </body>
    </html>
    """
}
