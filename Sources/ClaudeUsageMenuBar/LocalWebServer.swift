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
    let port: UInt16

    private(set) var isRunning = false

    init(store: UsageStore, port: UInt16 = LocalWebServer.defaultPort) {
        self.store = store
        self.port = port
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
        isRunning = false
    }

    private func handle(_ connection: NWConnection) {
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
                    connection.cancel()
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

        let (contentType, body) = LocalWebServer.route(path: path, snapshotJSON: currentSnapshotJSON)

        var response = "HTTP/1.1 200 OK\r\n"
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(body.utf8.count)\r\n"
        response += "Cache-Control: no-store\r\n"
        response += "Connection: close\r\n\r\n"
        response += body

        connection.send(
            content: response.data(using: .utf8),
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }

    private var currentSnapshotJSON: String {
        guard let store else { return "{}" }
        let snapshot = UsageSnapshotBuilder.build(
            hasSessionKey: store.hasSessionKey,
            usage: store.usage,
            errorMessage: store.errorMessage,
            lastUpdated: store.lastUpdated
        )
        return UsageSnapshotBuilder.encodeJSON(snapshot)
    }

    /// Pure routing logic, separated from the NWConnection plumbing above so it's testable
    /// without opening a real socket.
    nonisolated static func route(path: String, snapshotJSON: @autoclosure () -> String) -> (contentType: String, body: String) {
        switch path {
        case "/api/usage":
            return ("application/json; charset=utf-8", snapshotJSON())
        default:
            return ("text/html; charset=utf-8", Self.htmlPage)
        }
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
      :root { color-scheme: light dark; }
      body { font-family: -apple-system, system-ui, sans-serif; margin: 0; padding: 24px 20px; background: #fff; color: #111; }
      @media (prefers-color-scheme: dark) { body { background: #000; color: #f2f2f2; } }
      h1 { font-size: 17px; margin: 0 0 20px; }
      .row { margin-bottom: 18px; }
      .row-header { display: flex; justify-content: space-between; align-items: baseline; font-size: 14px; margin-bottom: 6px; gap: 8px; }
      .row-header span:first-child { font-weight: 500; }
      .reset { font-size: 12px; color: #8e8e93; white-space: nowrap; }
      .percent { font-size: 12px; color: #8e8e93; }
      .bar-track { height: 7px; background: rgba(142,142,147,0.25); border-radius: 4px; overflow: hidden; }
      .bar-fill { height: 100%; border-radius: 4px; transition: width 0.4s ease; }
      .updated { font-size: 11px; color: #8e8e93; margin-top: 10px; }
      .error { color: #ff3b30; font-size: 13px; }
    </style>
    </head>
    <body>
      <h1>Plan usage limits</h1>
      <div id="rows">Loading…</div>
      <div id="updated" class="updated"></div>
      <script>
        function barColor(p) {
          if (p < 70) return '#007aff';
          if (p < 90) return '#ff9500';
          return '#ff3b30';
        }
        function describeReset(iso) {
          if (!iso) return '';
          const d = new Date(iso);
          const diffMs = d - new Date();
          if (diffMs <= 0) return 'Resetting now';
          const mins = Math.floor(diffMs / 60000);
          const hrs = Math.floor(mins / 60);
          const remMins = mins % 60;
          if (hrs >= 24) {
            return 'Resets ' + d.toLocaleDateString(undefined, { weekday: 'short' }) + ' ' +
              d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
          }
          if (hrs > 0) return 'Resets in ' + hrs + ' hr ' + remMins + ' min';
          return 'Resets in ' + remMins + ' min';
        }
        function escapeHTML(s) {
          return s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
        }
        async function refresh() {
          const rowsEl = document.getElementById('rows');
          try {
            const res = await fetch('/api/usage', { cache: 'no-store' });
            const data = await res.json();

            if (!data.hasSessionKey) {
              rowsEl.innerHTML = '<div class="error">ยังไม่ได้ตั้งค่า Session Key บนแอป Mac</div>';
              document.getElementById('updated').textContent = '';
              return;
            }
            if (data.rows.length === 0) {
              rowsEl.innerHTML = '<div class="error">' + escapeHTML(data.errorMessage || 'กำลังโหลดข้อมูล...') + '</div>';
              return;
            }

            rowsEl.innerHTML = data.rows.map(r => {
              const pct = Math.min(Math.max(r.percent, 0), 100);
              return '<div class="row">' +
                '<div class="row-header">' +
                  '<span>' + escapeHTML(r.title) + '</span>' +
                  '<span class="reset">' + describeReset(r.resetsAt) + '</span>' +
                '</div>' +
                '<div class="bar-track"><div class="bar-fill" style="width:' + pct + '%; background:' + barColor(pct) + '"></div></div>' +
              '</div>';
            }).join('') + (data.errorMessage ? '<div class="error">' + escapeHTML(data.errorMessage) + '</div>' : '');

            document.getElementById('updated').textContent = data.lastUpdated
              ? ('Last updated: ' + new Date(data.lastUpdated).toLocaleTimeString())
              : '';
          } catch (e) {
            rowsEl.innerHTML = '<div class="error">เชื่อมต่อ Mac ไม่ได้ ตรวจสอบว่าเปิดแอปและอยู่ WiFi เดียวกันอยู่</div>';
          }
        }
        refresh();
        setInterval(refresh, 15000);
      </script>
    </body>
    </html>
    """
}
