import Foundation

struct SourceLine: Equatable {
    let id: String
    let text: String
}

struct TextBoundary {
    let id: String
    let index: String.Index
    let characterOffset: Int
    let preview: String
}

enum SelectionGeometry {
    static let maximumChoiceCount = 255

    static func boundaryMarker(in line: String) -> String {
        let base = "[[JevPasteBoundary]]"
        guard line.contains(base) else { return base }

        var suffix = 1
        while true {
            let candidate = "[[JevPasteBoundary_\(suffix)]]"
            if !line.contains(candidate) { return candidate }
            suffix += 1
        }
    }

    static func sourceLines(in text: String) -> [SourceLine] {
        text.split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .enumerated()
            .map { SourceLine(id: "line_\($0.offset)", text: $0.element) }
    }

    static func boundaries(in line: String) -> [TextBoundary] {
        let marker = boundaryMarker(in: line)
        var indices: [String.Index] = [line.startIndex]
        var cursor = line.startIndex

        scan: while cursor < line.endIndex {
            if line[cursor].isWhitespace {
                var next = line.index(after: cursor)
                while next < line.endIndex, line[next].isWhitespace {
                    next = line.index(after: next)
                }
                indices.append(next)
                cursor = next
                if indices.count >= maximumChoiceCount { break scan }
                continue
            }

            var tokenEnd = line.index(after: cursor)
            while tokenEnd < line.endIndex, !line[tokenEnd].isWhitespace {
                tokenEnd = line.index(after: tokenEnd)
            }

            let tokenHasNonASCII = line[cursor..<tokenEnd].contains { !isASCII($0) }
            if tokenHasNonASCII {
                while cursor < tokenEnd {
                    cursor = line.index(after: cursor)
                    indices.append(cursor)
                    if indices.count >= maximumChoiceCount { break scan }
                }
                continue
            }

            while cursor < tokenEnd {
                let currentCategory = category(of: line[cursor])
                var next = line.index(after: cursor)

                if currentCategory == .asciiLetter || currentCategory == .asciiDigit {
                    while next < tokenEnd, category(of: line[next]) == currentCategory {
                        next = line.index(after: next)
                    }
                }

                indices.append(next)
                cursor = next
                if indices.count >= maximumChoiceCount { break scan }
            }
        }

        return indices.enumerated().map { offset, index in
            TextBoundary(
                id: "boundary_\(offset)",
                index: index,
                characterOffset: line.distance(from: line.startIndex, to: index),
                preview: preview(in: line, at: index, marker: marker)
            )
        }
    }

    static func exactSubstring(
        in line: String,
        boundaries: [TextBoundary],
        startID: String,
        endID: String
    ) -> String? {
        guard let start = boundaries.first(where: { $0.id == startID }),
              let end = boundaries.first(where: { $0.id == endID }),
              start.index < end.index
        else {
            return nil
        }

        return String(line[start.index..<end.index])
    }

    private enum CharacterCategory: Equatable {
        case asciiLetter
        case asciiDigit
        case other
    }

    private static func category(of character: Character) -> CharacterCategory {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.isASCII
        else {
            return .other
        }

        switch scalar.value {
        case 65...90, 97...122:
            return .asciiLetter
        case 48...57:
            return .asciiDigit
        default:
            return .other
        }
    }

    private static func isASCII(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1 && character.unicodeScalars.first?.isASCII == true
    }

    private static func preview(
        in line: String,
        at index: String.Index,
        marker: String,
        radius: Int = 24
    ) -> String {
        let left = line[..<index]
        let right = line[index...]
        let leftText = String(left.suffix(radius))
        let rightText = String(right.prefix(radius))
        let leftPrefix = left.count > radius ? "…" : ""
        let rightSuffix = right.count > radius ? "…" : ""
        return "\(leftPrefix)\(leftText)\(marker)\(rightText)\(rightSuffix)"
    }
}
