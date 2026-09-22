import Foundation

enum PasteCandidateKind: String, Equatable {
    case explicitGroup
    case structuredValue
    case tokenSpan
    case structuralFragment
}

struct PasteCandidate: Equatable {
    let value: String
    let sourceApp: String
    let sourceClipID: UUID
    let kind: PasteCandidateKind
}

enum CandidateExtractor {
    private struct Draft {
        let value: String
        let kind: PasteCandidateKind
        let sourceApp: String
        let sourceClipID: UUID
    }

    private static let maximumSpanTokens = 8
    private static let maximumCandidateCharacters = 500

    private static let backtickPattern = try! NSRegularExpression(
        pattern: #"`([^`]*)`"#,
        options: [.dotMatchesLineSeparators]
    )
    private static let quotedPairPattern = try! NSRegularExpression(
        pattern: #"[\"']([^\"']{1,50})[\"']\s*[:=]\s*[\"']([^\"']+)[\"']"#
    )
    private static let quotedTextPattern = try! NSRegularExpression(
        pattern: #"[\"']([^\"']+)[\"']"#
    )
    private static let lexicalTokenPattern = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9](?:[A-Za-z0-9@._+:/-]*[A-Za-z0-9@_+:/-])?"#
    )
    private static let commonURISchemes: Set<String> = [
        "data", "file", "ftp", "ftps", "http", "https", "mailto", "ssh", "tel", "urn", "ws", "wss"
    ]

    static func extract(from clips: [Clip], limit: Int = 150) -> [PasteCandidate] {
        guard limit > 0 else { return [] }

        var output: [PasteCandidate] = []
        var seen = Set<String>()

        func append(_ draft: Draft) {
            guard output.count < limit else { return }
            let cleaned = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count <= maximumCandidateCharacters else { return }
            guard seen.insert(cleaned).inserted else { return }
            output.append(PasteCandidate(
                value: cleaned,
                sourceApp: draft.sourceApp,
                sourceClipID: draft.sourceClipID,
                kind: draft.kind
            ))
        }

        for clip in clips {
            for value in explicitGroups(in: clip.text) {
                append(Draft(
                    value: value,
                    kind: .explicitGroup,
                    sourceApp: clip.sourceApp,
                    sourceClipID: clip.id
                ))
            }
        }
        if output.count >= limit { return output }

        var candidateGroups: [[Draft]] = []
        for clip in clips {
            for ordinarySegment in ordinarySegments(in: clip.text) {
                for value in structuredValues(from: ordinarySegment) {
                    append(Draft(
                        value: value,
                        kind: .structuredValue,
                        sourceApp: clip.sourceApp,
                        sourceClipID: clip.id
                    ))
                }

                let segments = [ordinarySegment] + structuralFragments(in: ordinarySegment)
                for segment in segments {
                    for value in quotedValues(in: segment) {
                        append(Draft(
                            value: value,
                            kind: .structuredValue,
                            sourceApp: clip.sourceApp,
                            sourceClipID: clip.id
                        ))
                    }
                    let lexicalDrafts = embeddedLexicalValues(in: segment).map {
                        Draft(
                            value: $0,
                            kind: .tokenSpan,
                            sourceApp: clip.sourceApp,
                            sourceClipID: clip.id
                        )
                    }
                    if !lexicalDrafts.isEmpty { candidateGroups.append(lexicalDrafts) }

                    let spanDrafts = spanCandidates(in: segment).map {
                        Draft(
                            value: $0.value,
                            kind: $0.kind,
                            sourceApp: clip.sourceApp,
                            sourceClipID: clip.id
                        )
                    }
                    if !spanDrafts.isEmpty { candidateGroups.append(spanDrafts) }
                }
            }
        }
        if output.count >= limit { return output }

        var index = 0
        while output.count < limit {
            var foundCandidateAtThisIndex = false
            for group in candidateGroups where index < group.count {
                foundCandidateAtThisIndex = true
                append(group[index])
                if output.count >= limit { break }
            }
            guard foundCandidateAtThisIndex else { break }
            index += 1
        }

        return output
    }

    private static func explicitGroups(in text: String) -> [String] {
        backtickMatches(in: text).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[valueRange])
        }
    }

    private static func backtickMatches(in text: String) -> [NSTextCheckingResult] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return backtickPattern.matches(in: text, range: range)
    }

    private static func ordinarySegments(in text: String) -> [String] {
        var segments: [String] = []

        func appendLines(_ range: Range<String.Index>) {
            segments.append(contentsOf: text[range]
                .split(whereSeparator: \Character.isNewline)
                .map(String.init))
        }

        var cursor = text.startIndex
        for match in backtickMatches(in: text) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            if cursor < matchRange.lowerBound {
                appendLines(cursor..<matchRange.lowerBound)
            }
            cursor = matchRange.upperBound
        }
        if cursor < text.endIndex {
            appendLines(cursor..<text.endIndex)
        }

        return segments
    }
    private static func structuredValues(from line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var values: [String] = []
        let fullRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        values.append(contentsOf: quotedPairPattern.matches(in: trimmed, range: fullRange).compactMap { match in
            guard let valueRange = Range(match.range(at: 2), in: trimmed) else { return nil }
            return String(trimmed[valueRange])
        })

        let tabParts = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if tabParts.count >= 2, tabParts.count.isMultiple(of: 2) {
            for index in stride(from: 0, to: tabParts.count, by: 2) {
                let label = tabParts[index]
                let value = tabParts[index + 1]
                if !label.isEmpty, label.count <= 50, !value.isEmpty {
                    values.append(value)
                }
            }
        }

        if let separator = trimmed.firstIndex(where: { $0 == ":" || $0 == "：" || $0 == "=" }) {
            let label = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            let separatorCharacter = trimmed[separator]
            if !label.isEmpty,
               label.count <= 50,
               !value.isEmpty,
               !isEmbeddedSeparator(separatorCharacter, at: separator, in: trimmed) {
                values.append(value)
            }
        }

        return values
    }

    private static func isEmbeddedSeparator(
        _ separator: Character,
        at index: String.Index,
        in text: String
    ) -> Bool {
        guard separator == ":" || separator == "：" else { return false }
        let nextIndex = text.index(after: index)
        guard nextIndex < text.endIndex else { return false }

        if index > text.startIndex {
            let previousIndex = text.index(before: index)
            if text[previousIndex].isNumber, text[nextIndex].isNumber {
                return true
            }
        }

        if separator == ":" {
            let label = String(text[..<index]).trimmingCharacters(in: .whitespaces).lowercased()
            if !label.contains(where: \Character.isWhitespace), commonURISchemes.contains(label) {
                return true
            }

            if looksLikeBareIPv6(text) {
                return true
            }
        }

        return false
    }

    private static func looksLikeBareIPv6(_ text: String) -> Bool {
        guard !text.contains(where: \Character.isWhitespace),
              text.filter({ $0 == ":" }).count >= 2
        else {
            return false
        }
        return text.allSatisfy { character in
            character == ":" || character == "." || isHexDigit(character)
        }
    }

    private static func isHexDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value
        else {
            return false
        }
        return (48...57).contains(value) || (65...70).contains(value) || (97...102).contains(value)
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
        }.filter { !$0.isEmpty && $0.count <= maximumCandidateCharacters }
    }

    private static func quotedValues(in text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return quotedTextPattern.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[valueRange])
        }
    }

    private static func embeddedLexicalValues(in text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return lexicalTokenPattern.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range, in: text) else { return nil }
            let value = String(text[valueRange])
            let hasUsefulBoundarySignal = value.contains(where: { $0.isNumber }) ||
                value.rangeOfCharacter(from: CharacterSet(charactersIn: "@._+:/-")) != nil
            return hasUsefulBoundarySignal ? value : nil
        }
    }

    private static func spanCandidates(in text: String) -> [(value: String, kind: PasteCandidateKind)] {
        let ranges = tokenRanges(in: text)
        guard !ranges.isEmpty else { return [] }

        let maximumWidth = min(maximumSpanTokens, ranges.count)
        var result: [(String, PasteCandidateKind)] = []

        for width in 1...ranges.count {
            let start = ranges.count - width
            let value = substring(in: text, ranges: ranges, start: start, width: width)
            guard value.count <= maximumCandidateCharacters else { break }
            result.append((value, .tokenSpan))
        }

        for width in 1...maximumWidth {
            for start in 0...(ranges.count - width) {
                result.append((substring(in: text, ranges: ranges, start: start, width: width), .tokenSpan))
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed.count <= maximumCandidateCharacters {
            result.append((trimmed, .structuralFragment))
        }
        return result
    }

    private static func tokenRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var tokenStart: String.Index?

        for index in text.indices {
            if text[index].isWhitespace {
                if let start = tokenStart {
                    ranges.append(start..<index)
                    tokenStart = nil
                }
            } else if tokenStart == nil {
                tokenStart = index
            }
        }
        if let tokenStart {
            ranges.append(tokenStart..<text.endIndex)
        }
        return ranges
    }


    private static func substring(
        in text: String,
        ranges: [Range<String.Index>],
        start: Int,
        width: Int
    ) -> String {
        let lower = ranges[start].lowerBound
        let upper = ranges[start + width - 1].upperBound
        return String(text[lower..<upper])
    }
}
