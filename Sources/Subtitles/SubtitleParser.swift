import Foundation

struct SubtitleCue: Identifiable, Hashable {
    let id: Int
    let start: Double
    let end: Double
    let text: String
}

enum SubtitleParser {
    static func parse(_ raw: String) -> [SubtitleCue] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []
        var nextId = 0

        for block in blocks {
            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }
            if lines[0].uppercased().hasPrefix("WEBVTT") || lines[0].uppercased().hasPrefix("NOTE") {
                continue
            }

            guard let timeLineIdx = lines.firstIndex(where: { $0.contains("-->") }) else {
                continue
            }

            let timeLine = lines[timeLineIdx]
            let parts = timeLine.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0]),
                  let end = parseTimestamp(parts[1]) else {
                continue
            }

            let textLines = lines[(timeLineIdx + 1)...]
            let joined = textLines.joined(separator: "\n")
            let cleaned = stripTags(joined)
            guard !cleaned.isEmpty else { continue }

            cues.append(SubtitleCue(id: nextId, start: start, end: end, text: cleaned))
            nextId += 1
        }

        return cues.sorted { $0.start < $1.start }
    }

    static func activeCue(in cues: [SubtitleCue], at playbackTime: Double, offset: Double) -> SubtitleCue? {
        let adjusted = playbackTime - offset
        return cues.first { adjusted >= $0.start && adjusted <= $0.end }
    }

    private static func parseTimestamp(_ raw: String) -> Double? {
        let token = raw.trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .first
            .map(String.init) ?? ""
        let normalized = token.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":").map(String.init)

        if parts.count == 3,
           let h = Double(parts[0]),
           let m = Double(parts[1]),
           let s = Double(parts[2]) {
            return h * 3600 + m * 60 + s
        } else if parts.count == 2,
                  let m = Double(parts[0]),
                  let s = Double(parts[1]) {
            return m * 60 + s
        }
        return nil
    }

    private static func stripTags(_ text: String) -> String {
        var result = ""
        var insideTag = false
        for char in text {
            if char == "<" {
                insideTag = true
            } else if char == ">" {
                insideTag = false
            } else if !insideTag {
                result.append(char)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
