import Foundation

struct PasteCandidate: Equatable {
    let value: String
    let sourceApp: String
    let sourceClipID: UUID
}

enum CandidateExtractor {
    private static let quotedPairPattern = try! NSRegularExpression(
        pattern: #"[\"']([^\"']{1,50})[\"']\s*[:=]\s*[\"']([^\"']+)[\"']"#
    )
    private static let quotedTextPattern = try! NSRegularExpression(
        pattern: #"[\"']([^\"']+)[\"']"#
    )
    private static let backtickTextPattern = try! NSRegularExpression(
        pattern: #"`([^`]+)`"#
    )
    private static let lexicalTokenPattern = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9][A-Za-z0-9@._+:/-]*"#
    )
    private static let nonWhitespacePattern = try! NSRegularExpression(pattern: #"\S+"#)

    static func extract(from clips: [Clip], limit: Int = 150) -> [PasteCandidate] {
        var output: [PasteCandidate] = []
        var seen = Set<String>()

        func append(value: String, sourceApp: String, sourceClipID: UUID) {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count <= 500 else { return }
            guard seen.insert(cleaned).inserted else { return }
            output.append(PasteCandidate(
                value: cleaned,
                sourceApp: sourceApp,
                sourceClipID: sourceClipID
            ))
        }

        for clip in clips {
            let lines = clip.text.split(whereSeparator: \Character.isNewline).map(String.init)
            for line in lines {
                let segments = [line] + structuralFragments(in: line)
                for segment in segments {
                    for value in syntacticValues(in: segment) {
                        append(value: value, sourceApp: clip.sourceApp, sourceClipID: clip.id)
                    }
                }
                for value in explicitlyDelimitedValues(from: line) {
                    append(
                        value: value,
                        sourceApp: clip.sourceApp,
                        sourceClipID: clip.id
                    )
                }
                for segment in segments {
                    append(value: segment, sourceApp: clip.sourceApp, sourceClipID: clip.id)
                }
                if output.count >= limit { return Array(output.prefix(limit)) }
            }
        }
        return Array(output.prefix(limit))
    }

    private static func explicitlyDelimitedValues(from line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let fullRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let quotedPairs = quotedPairPattern.matches(in: trimmed, range: fullRange).compactMap { match -> (String, String)? in
            guard let labelRange = Range(match.range(at: 1), in: trimmed),
                  let valueRange = Range(match.range(at: 2), in: trimmed)
            else { return nil }
            return (String(trimmed[labelRange]), String(trimmed[valueRange]))
        }
        if !quotedPairs.isEmpty { return quotedPairs.map(\.1) }

        let tabParts = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if tabParts.count >= 2, tabParts.count.isMultiple(of: 2) {
            let pairs = stride(from: 0, to: tabParts.count, by: 2).compactMap { index -> (String, String)? in
                let label = tabParts[index]
                let value = tabParts[index + 1]
                guard !label.isEmpty, label.count <= 50, !value.isEmpty else { return nil }
                return (label, value)
            }
            if !pairs.isEmpty { return pairs.map(\.1) }
        }

        if let separator = trimmed.firstIndex(where: { $0 == ":" || $0 == "：" || $0 == "=" }) {
            let label = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if !label.isEmpty, label.count <= 50, !value.isEmpty { return [value] }
        }

        return []
    }

    private static func structuralFragments(in line: String) -> [String] {
        guard line.contains("\t") || line.contains("|") || line.contains(",") || line.contains("，") ||
                line.contains("、") || line.contains(";") || line.contains("；")
        else {
            return []
        }
        return line.split(whereSeparator: { character in
            character == "\t" || character == "|" || character == "," || character == "，" ||
                character == "、" || character == ";" || character == "；"
        }).map {
            $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'")))
        }.filter { !$0.isEmpty && $0.count <= 500 }
    }

    private static func syntacticValues(in text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var values = text.split(whereSeparator: \Character.isWhitespace).map(String.init)
        values.append(contentsOf: contiguousTokenSpans(in: text))

        for pattern in [quotedTextPattern, backtickTextPattern, lexicalTokenPattern] {
            values.append(contentsOf: pattern.matches(in: text, range: range).compactMap { match in
                let matchRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                guard let valueRange = Range(matchRange, in: text) else { return nil }
                return String(text[valueRange])
            })
        }
        return values
    }

    private static func contiguousTokenSpans(in text: String) -> [String] {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let tokenRanges = nonWhitespacePattern.matches(in: text, range: fullRange).compactMap {
            Range($0.range, in: text)
        }
        guard (2...12).contains(tokenRanges.count) else { return [] }

        var values: [String] = []
        let maximumWords = min(5, tokenRanges.count)
        for wordCount in 2...maximumWords {
            for start in 0...(tokenRanges.count - wordCount) {
                let end = start + wordCount - 1
                let span = tokenRanges[start].lowerBound..<tokenRanges[end].upperBound
                values.append(String(text[span]))
            }
        }
        return values
    }

}
