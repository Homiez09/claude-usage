import Foundation

/// Wire format for `/api/agents` — an installed agent definition plus
/// whether it's currently running, so the iPhone page can show the same
/// live badge the Mac dropdown does without ever touching a transcript file
/// itself.
struct InstalledAgentSnapshot: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let description: String
    let isRunning: Bool
}

enum InstalledAgentSnapshotBuilder {
    /// `activeSubagentTypes` is the set of `subagentType` values currently
    /// active (see `ClaudeCodeSessionStatus.subagentType`) — an installed
    /// agent is "running" when its `name` matches one of these exactly,
    /// which holds because Claude Code's `subagent_type` argument is the
    /// same string as the agent definition's frontmatter `name`.
    nonisolated static func build(agents: [InstalledAgent], activeSubagentTypes: Set<String>) -> [InstalledAgentSnapshot] {
        agents.map { agent in
            InstalledAgentSnapshot(
                name: agent.name,
                description: agent.description,
                isRunning: activeSubagentTypes.contains(agent.name)
            )
        }
    }

    nonisolated static func encodeJSON(_ snapshots: [InstalledAgentSnapshot]) -> String {
        guard let data = try? JSONEncoder().encode(snapshots),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }
}
