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
    static let boundaryMarker = "｜"

    static func sourceLines(in text: String) -> [SourceLine] {
        text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .enumerated()
            .map { SourceLine(id: "line_\($0.offset)", text: $0.element) }
    }

    static func boundaries(in line: String) -> [TextBoundary] {
        var indices: [String.Index] = [line.startIndex]
        var cursor = line.startIndex

        while cursor < line.endIndex {
            let character = line[cursor]
            let category = category(of: character)
            var next = line.index(after: cursor)

            if category == .asciiLetter || category == .asciiDigit || category == .whitespace {
                while next < line.endIndex, category(of: line[next]) == category {
                    next = line.index(after: next)
                }
            }

            indices.append(next)
            cursor = next
        }

        return indices.enumerated().map { offset, index in
            TextBoundary(
                id: "boundary_\(offset)",
                index: index,
                characterOffset: line.distance(from: line.startIndex, to: index),
                preview: preview(in: line, at: index)
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
        case whitespace
        case other
    }

    private static func category(of character: Character) -> CharacterCategory {
        if character.isWhitespace {
            return .whitespace
        }

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

    private static func preview(in line: String, at index: String.Index, radius: Int = 24) -> String {
        let left = line[..<index]
        let right = line[index...]
        let leftText = String(left.suffix(radius))
        let rightText = String(right.prefix(radius))
        let leftPrefix = left.count > radius ? "…" : ""
        let rightSuffix = right.count > radius ? "…" : ""
        return "\(leftPrefix)\(leftText)\(boundaryMarker)\(rightText)\(rightSuffix)"
    }
}
