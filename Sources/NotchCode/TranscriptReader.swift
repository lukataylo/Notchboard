import Foundation
import os.log

private let log = Logger(subsystem: "com.notchcode", category: "transcript")

/// Reads and tails Claude Code transcript .jsonl files to extract
/// Claude's reasoning, token usage, and session state.
class TranscriptReader {
    let path: String
    var lastOffset: UInt64 = 0
    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0

    init(path: String) {
        self.path = path
        // Start from the end of the file so we only read new entries
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64 {
            // Read last 10KB on init to get recent context
            lastOffset = size > 10000 ? size - 10000 : 0
        }
    }

    /// Read new lines since last check. Returns parsed entries.
    func readNew() -> [TranscriptEntry] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { handle.closeFile() }

        handle.seek(toFileOffset: lastOffset)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return [] }

        lastOffset = handle.offsetInFile

        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var entries: [TranscriptEntry] = []

        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = json["type"] as? String ?? ""
            guard let message = json["message"] as? [String: Any] else { continue }

            if type == "assistant" {
                // Extract text blocks (Claude's reasoning)
                if let content = message["content"] as? [[String: Any]] {
                    for block in content {
                        if block["type"] as? String == "text",
                           let text = block["text"] as? String, !text.isEmpty {
                            entries.append(.reasoning(text))
                        }
                    }
                }

                // Extract token usage
                if let usage = message["usage"] as? [String: Any] {
                    let input = (usage["input_tokens"] as? Int ?? 0)
                        + (usage["cache_read_input_tokens"] as? Int ?? 0)
                        + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                    let output = usage["output_tokens"] as? Int ?? 0
                    totalInputTokens += input
                    totalOutputTokens += output
                    entries.append(.usage(input: totalInputTokens, output: totalOutputTokens))
                }
            } else if type == "user" {
                // Check if Claude is waiting for user input (no toolUseResult means user typed)
                if json["toolUseResult"] == nil, let content = message["content"] as? [[String: Any]] {
                    for block in content {
                        if block["type"] as? String == "text",
                           let text = block["text"] as? String, !text.isEmpty {
                            entries.append(.userMessage(text))
                        }
                    }
                }
            }
        }
        return entries
    }
}

enum TranscriptEntry {
    case reasoning(String)
    case usage(input: Int, output: Int)
    case userMessage(String)
}

/// Format token count to human-readable (e.g. "12.5k", "1.2M")
func formatTokens(_ count: Int) -> String {
    if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
    if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1_000) }
    return "\(count)"
}
