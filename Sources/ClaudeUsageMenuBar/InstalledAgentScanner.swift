import Foundation

/// One custom subagent definition installed at `~/.claude/agents/*.md` — the
/// catalog of agent *types* available to spawn, not a record of any
/// particular run (see `ClaudeCodeSessionStatus` for that).
struct InstalledAgent: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
}

enum InstalledAgentScanner {
    /// Only the user-level directory is scanned — project-level
    /// `.claude/agents/` directories live inside individual git checkouts,
    /// and this app has no reliable way to know which project the user
    /// currently cares about.
    static var defaultAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/agents")
    }

    /// Scans every `.md` file directly under `directory` for a Claude Code
    /// custom subagent definition, sorted by name. New files show up the
    /// next time this is called — there's no separate install step to hook
    /// into, so callers just re-scan (e.g. whenever the tab is shown).
    nonisolated static func scan(directory: URL = defaultAgentsDirectory) -> [InstalledAgent] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "md" }
            .compactMap(parseAgent(fileURL:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Reads only the YAML frontmatter block (`name`, `description`) —
    /// never the system-prompt body that follows it.
    nonisolated static func parseAgent(fileURL: URL) -> InstalledAgent? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let fallbackName = fileURL.deletingPathExtension().lastPathComponent
        guard let frontmatter = extractFrontmatter(from: contents) else {
            return InstalledAgent(id: fallbackName, name: fallbackName, description: "")
        }
        let fields = parseFrontmatterFields(frontmatter)
        let name = fields["name"] ?? fallbackName
        return InstalledAgent(id: name, name: name, description: fields["description"] ?? "")
    }

    /// Returns the text between the file's opening `---` and the next
    /// `---` line, or nil if the file doesn't start with a frontmatter block.
    nonisolated static func extractFrontmatter(from contents: String) -> String? {
        guard contents.hasPrefix("---") else { return nil }
        let afterFirst = contents.dropFirst(3)
        guard let range = afterFirst.range(of: "\n---") else { return nil }
        return String(afterFirst[afterFirst.startIndex..<range.lowerBound])
    }

    /// Minimal `key: value` line parser — enough for the flat frontmatter
    /// Claude Code agent definitions use (`name`, `description`, `tools`),
    /// not a full YAML parser. Splits only on the first colon per line, so a
    /// colon inside a description doesn't truncate it.
    nonisolated static func parseFrontmatterFields(_ frontmatter: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in frontmatter.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty else { continue }
            fields[key] = value
        }
        return fields
    }
}
