import Foundation
import Testing
@testable import JevPaste

@Test func sourceLinesKeepExactNonemptyLineText() {
    let lines = SelectionGeometry.sourceLines(in: "Full Name John Smith\n\n  \n氏名山田太郎")

    #expect(lines == [
        SourceLine(id: "line_0", text: "Full Name John Smith"),
        SourceLine(id: "line_1", text: "氏名山田太郎"),
    ])
}

@Test func englishAsciiRunsUseWordScaleBoundaries() {
    let line = "Full Name John Smith"
    let boundaries = SelectionGeometry.boundaries(in: line)

    #expect(boundaries.map(\.characterOffset) == [0, 4, 5, 9, 10, 14, 15, 20])
    #expect(boundaries.count == 8)
}

@Test func asciiLettersAndDigitsUseSeparateRuns() {
    let line = "Room305 ABC123XYZ"
    let boundaries = SelectionGeometry.boundaries(in: line)

    let roomStart = boundaries.first { $0.characterOffset == 0 }!.id
    let roomEnd = boundaries.first { $0.characterOffset == 4 }!.id
    let numberEnd = boundaries.first { $0.characterOffset == 7 }!.id

    #expect(SelectionGeometry.exactSubstring(
        in: line,
        boundaries: boundaries,
        startID: roomStart,
        endID: roomEnd
    ) == "Room")
    #expect(SelectionGeometry.exactSubstring(
        in: line,
        boundaries: boundaries,
        startID: roomEnd,
        endID: numberEnd
    ) == "305")
}

@Test func nonAsciiCharactersHavePerCharacterBoundaries() {
    let line = "氏名山田太郎"
    let boundaries = SelectionGeometry.boundaries(in: line)

    #expect(boundaries.map(\.characterOffset) == Array(0...6))
}

@Test func asciiPunctuationHasBoundariesOnBothSides() {
    let line = "john.smith@example.com"
    let boundaries = SelectionGeometry.boundaries(in: line)
    let offsets = boundaries.map(\.characterOffset)

    #expect(offsets.contains(4))
    #expect(offsets.contains(5))
    #expect(offsets.contains(10))
    #expect(offsets.contains(11))
    #expect(offsets.contains(18))
    #expect(offsets.contains(19))
}

@Test func japaneseAndAsciiTextCanBeSelectedWithoutSemanticParsing() {
    let line = "郵便番号100-0001"
    let boundaries = SelectionGeometry.boundaries(in: line)
    let start = boundaries.first { $0.characterOffset == 4 }!.id
    let end = boundaries.last!.id

    #expect(SelectionGeometry.exactSubstring(
        in: line,
        boundaries: boundaries,
        startID: start,
        endID: end
    ) == "100-0001")
}

@Test func previewsUseFullwidthBoundaryMarker() {
    let line = "Full Name John Smith"
    let boundary = SelectionGeometry.boundaries(in: line)
        .first { $0.characterOffset == 10 }!

    #expect(boundary.preview == "Full Name ｜John Smith")
    #expect(!boundary.preview.contains("|"))
}

@Test func invalidOrEmptyRangesAreRejected() {
    let line = "John Smith"
    let boundaries = SelectionGeometry.boundaries(in: line)

    #expect(SelectionGeometry.exactSubstring(
        in: line,
        boundaries: boundaries,
        startID: boundaries[2].id,
        endID: boundaries[1].id
    ) == nil)
    #expect(SelectionGeometry.exactSubstring(
        in: line,
        boundaries: boundaries,
        startID: boundaries[1].id,
        endID: boundaries[1].id
    ) == nil)
}
