import Foundation

enum ClaudeCodeTranscriptScanner {
    /// Parses one line of a Claude Code transcript (`~/.claude/projects/**/*.jsonl`)
    /// into a usage record. Only reads `type`, `message.id`, `message.model`,
    /// `message.usage`, and the top-level `timestamp` — never `message.content`,
    /// so conversation text is never touched.
    ///
    /// Returns nil for non-assistant lines, lines with no usage/model/timestamp,
    /// or the synthetic `<synthetic>` model placeholder some entries carry.
    static func parseLine(_ line: String) -> (id: String, record: ClaudeCodeUsageRecord)? {
        guard line.contains("\"type\":\"assistant\"") else { return nil }
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any],
              let messageID = message["id"] as? String,
              let model = message["model"] as? String,
              model != "<synthetic>",
              let usage = message["usage"] as? [String: Any],
              let timestampString = obj["timestamp"] as? String,
              let date = FlexibleISO8601.date(from: timestampString)
        else {
            return nil
        }

        let record = ClaudeCodeUsageRecord(
            messageID: messageID,
            date: date,
            model: model,
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0
        )
        return (messageID, record)
    }

    static var projectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    /// Scans every transcript under `directory`, deduplicating by message ID —
    /// resumed/compacted sessions can copy the same message into multiple
    /// files, and counting a message twice would inflate the totals.
    static func scan(directory: URL = projectsDirectory) -> [ClaudeCodeUsageRecord] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var seenMessageIDs = Set<String>()
        var records: [ClaudeCodeUsageRecord] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            contents.enumerateLines { line, _ in
                guard let (messageID, record) = parseLine(line) else { return }
                guard seenMessageIDs.insert(messageID).inserted else { return }
                records.append(record)
            }
        }
        return records
    }
}
