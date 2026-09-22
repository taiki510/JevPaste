import Testing
@testable import JevPaste

@Test func singleLineRangeQuestionsIncludeExplicitMatchDecision() {
    let line = "Order ID ABC123"
    let boundaries = SelectionGeometry.boundaries(in: line)
    let marker = SelectionGeometry.boundaryMarker(in: line)

    let questions = JevClient.rangeQuestions(
        boundaries: boundaries,
        boundaryMarker: marker,
        requireLineMatch: true
    )

    #expect(questions["line_match"] != nil)
    #expect(questions["start_boundary"] != nil)
    #expect(questions["end_boundary"] != nil)
}

@Test func multiLineRangeQuestionsDoNotRepeatLineMatchDecision() {
    let line = "Order ID ABC123"
    let boundaries = SelectionGeometry.boundaries(in: line)
    let marker = SelectionGeometry.boundaryMarker(in: line)

    let questions = JevClient.rangeQuestions(
        boundaries: boundaries,
        boundaryMarker: marker,
        requireLineMatch: false
    )

    #expect(questions["line_match"] == nil)
}

@Test func singleLineNoMatchRejectsAnOtherwiseValidRange() {
    let client = JevClient()
    let line = "Order ID ABC123"
    let boundaries = SelectionGeometry.boundaries(in: line)
    let start = boundaries.first { $0.characterOffset == 9 }!.id
    let end = boundaries.last!.id
    let response = JevResponse(answers: [
        "line_match": .init(choice: "no_match", confidence: 0.99),
        "start_boundary": .init(choice: start, confidence: 0.99),
        "end_boundary": .init(choice: end, confidence: 0.99),
    ])

    let result = client.rangeResult(
        response,
        in: line,
        boundaries: boundaries,
        requireLineMatch: true
    )

    #expect(isNoMatch(result))
}

@Test func rangeDecisionsAcceptMinimumConfidenceIndividually() {
    let client = JevClient()
    let line = "Order ID ABC123"
    let boundaries = SelectionGeometry.boundaries(in: line)
    let start = boundaries.first { $0.characterOffset == 9 }!.id
    let end = boundaries.last!.id
    let response = JevResponse(answers: [
        "line_match": .init(choice: "match", confidence: 0.55),
        "start_boundary": .init(choice: start, confidence: 0.55),
        "end_boundary": .init(choice: end, confidence: 0.55),
    ])

    let result = client.rangeResult(
        response,
        in: line,
        boundaries: boundaries,
        requireLineMatch: true
    )

    guard case .success(let value) = result else {
        Issue.record("Expected the three individual 0.55-confidence decisions to be accepted")
        return
    }
    #expect(value == "ABC123")
}

private func isNoMatch(_ result: Result<String, Error>) -> Bool {
    guard case .failure(let error) = result,
          let pasteError = error as? JevPasteError
    else {
        return false
    }

    if case .noMatch = pasteError {
        return true
    }
    return false
}
