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

    #expect(boundaries.map(\.characterOffset) == [0, 4, 7, 8, 11, 14, 17])
}

@Test func nonAsciiCharactersHavePerCharacterBoundaries() {
    let line = "氏名山田太郎"
    let boundaries = SelectionGeometry.boundaries(in: line)

    #expect(boundaries.map(\.characterOffset) == Array(0...6))
}

@Test func asciiAdjacentToNonAsciiAlsoUsesPerCharacterBoundaries() {
    let line = "郵便番号100-0001"
    let boundaries = SelectionGeometry.boundaries(in: line)

    #expect(boundaries.map(\.characterOffset) == Array(0...12))
}

@Test func ordinaryAsciiPunctuationHasBoundariesOnBothSides() {
    let line = "john.smith@example.com"
    let boundaries = SelectionGeometry.boundaries(in: line)
    let offsets = boundaries.map(\.characterOffset)

    #expect(offsets == [0, 4, 5, 10, 11, 18, 19, 22])
}

@Test func mixedTextStillAllowsSelectingTheWholeAsciiValue() {
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

@Test func previewsUseCollisionFreeBoundaryMarker() {
    let line = "Full Name John Smith"
    let marker = SelectionGeometry.boundaryMarker(in: line)
    let boundary = SelectionGeometry.boundaries(in: line)
        .first { $0.characterOffset == 10 }!

    #expect(marker == "[[JevPasteBoundary]]")
    #expect(!line.contains(marker))
    #expect(boundary.preview == "Full Name [[JevPasteBoundary]]John Smith")
}

@Test func boundaryMarkerChangesWhenTheSourceAlreadyContainsMarkerText() {
    let line = "Label [[JevPasteBoundary]] value [[JevPasteBoundary_1]]"
    let marker = SelectionGeometry.boundaryMarker(in: line)
    let boundaries = SelectionGeometry.boundaries(in: line)

    #expect(marker == "[[JevPasteBoundary_2]]")
    #expect(!line.contains(marker))
    #expect(boundaries.allSatisfy { $0.preview.contains(marker) })
}

@Test func boundaryEnumerationStopsOnceTheChoiceBudgetIsKnownToBeExceeded() {
    let line = String(repeating: "日", count: 1_000)
    let boundaries = SelectionGeometry.boundaries(in: line)

    #expect(boundaries.count == SelectionGeometry.maximumChoiceCount)
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
