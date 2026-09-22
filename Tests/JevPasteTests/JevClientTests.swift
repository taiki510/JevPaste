import ApplicationServices
import Foundation
import Testing
@testable import JevPaste

@Test func singleLineStartQuestionsIncludeExplicitMatchDecision() {
    let line = "Order ID ABC123"
    let boundaries = SelectionGeometry.boundaries(in: line)
    let marker = SelectionGeometry.boundaryMarker(in: line)

    let questions = JevClient.startQuestions(
        boundaries: boundaries,
        boundaryMarker: marker,
        requireLineMatch: true
    )

    #expect(questions["line_match"] != nil)
    #expect(questions["start_boundary"] != nil)
    #expect(questions["end_boundary"] == nil)
}

@Test func multiLineStartQuestionsDoNotRepeatLineMatchDecision() {
    let line = "Order ID ABC123"
    let boundaries = SelectionGeometry.boundaries(in: line)
    let marker = SelectionGeometry.boundaryMarker(in: line)

    let questions = JevClient.startQuestions(
        boundaries: boundaries,
        boundaryMarker: marker,
        requireLineMatch: false
    )

    #expect(questions["line_match"] == nil)
    #expect(questions["start_boundary"] != nil)
}

@Test func endQuestionsDependOnTheSelectedStartBoundary() {
    let line = "Primary alice@example.com backup bob@example.com"
    let boundaries = SelectionGeometry.boundaries(in: line)
    let marker = SelectionGeometry.boundaryMarker(in: line)
    let start = boundaries.first { $0.characterOffset == 8 }!

    let questions = JevClient.endQuestions(
        boundaries: boundaries,
        startBoundary: start,
        boundaryMarker: marker
    )
    let endQuestion = questions["end_boundary"]!

    #expect(endQuestion.instructions.contains("character offset 8"))
    #expect(endQuestion.criteria["no_match"] != nil)
    #expect(endQuestion.criteria[start.id] == nil)
    #expect(boundaries
        .filter { $0.index <= start.index }
        .allSatisfy { endQuestion.criteria[$0.id] == nil })
    #expect(boundaries
        .filter { $0.index > start.index }
        .allSatisfy { endQuestion.criteria[$0.id] != nil })
}

@Test func lineDecisionKeepsNoMatchButAcceptsLowConfidenceChoice() {
    let client = JevClient()
    let lines = [
        SourceLine(id: "line_0", text: "Primary email alice@example.com"),
        SourceLine(id: "line_1", text: "Backup email bob@example.com"),
    ]

    #expect(isNoMatch(client.lineResult(
        JevResponse(answers: [
            "source_line": .init(choice: "no_match", confidence: 0.01),
        ]),
        lines: lines
    )))

    let lowConfidenceChoice = client.lineResult(
        JevResponse(answers: [
            "source_line": .init(choice: "line_1", confidence: 0.01),
        ]),
        lines: lines
    )
    guard case .success(let selectedLine) = lowConfidenceChoice else {
        Issue.record("Expected the concrete line choice to be accepted regardless of confidence")
        return
    }
    #expect(selectedLine.id == "line_1")

    #expect(isInvalidResponse(client.lineResult(
        JevResponse(answers: [
            "source_line": .init(choice: "line_99", confidence: 0.99),
        ]),
        lines: lines
    )))
}

@Test func singleLineNoMatchRejectsStartSelection() {
    let client = JevClient()
    let line = "Order ID ABC123"
    let boundaries = SelectionGeometry.boundaries(in: line)
    let start = boundaries.first { $0.characterOffset == 9 }!.id
    let response = JevResponse(answers: [
        "line_match": .init(choice: "no_match", confidence: 0.01),
        "start_boundary": .init(choice: start, confidence: 0.99),
    ])

    let result = client.startBoundaryResult(
        response,
        boundaries: boundaries,
        requireLineMatch: true
    )

    #expect(isNoMatch(result))
}

@Test func boundaryDecisionsAcceptConcreteChoicesRegardlessOfConfidence() {
    let client = JevClient()
    let line = "Order ID ABC123"
    let boundaries = SelectionGeometry.boundaries(in: line)
    let startID = boundaries.first { $0.characterOffset == 9 }!.id
    let startResponse = JevResponse(answers: [
        "line_match": .init(choice: "match", confidence: 0.01),
        "start_boundary": .init(choice: startID, confidence: 0.01),
    ])

    let startResult = client.startBoundaryResult(
        startResponse,
        boundaries: boundaries,
        requireLineMatch: true
    )
    guard case .success(let startBoundary) = startResult else {
        Issue.record("Expected concrete line-match and start-boundary choices to ignore confidence")
        return
    }

    let endResponse = JevResponse(answers: [
        "end_boundary": .init(choice: boundaries.last!.id, confidence: nil),
    ])
    let endResult = client.endResult(
        endResponse,
        in: line,
        boundaries: boundaries,
        startBoundary: startBoundary
    )

    guard case .success(let value) = endResult else {
        Issue.record("Expected the concrete end-boundary choice to ignore confidence")
        return
    }
    #expect(value == "ABC123")
}

@Test func endNoMatchRemainsAuthoritative() {
    let client = JevClient()
    let line = "Order ID ABC123"
    let boundaries = SelectionGeometry.boundaries(in: line)
    let start = boundaries.first { $0.characterOffset == 9 }!
    let response = JevResponse(answers: [
        "end_boundary": .init(choice: "no_match", confidence: 0.01),
    ])

    let result = client.endResult(
        response,
        in: line,
        boundaries: boundaries,
        startBoundary: start
    )

    #expect(isNoMatch(result))
}

@Test func noMatchIsSilentWhileOperationalErrorsRemainVisible() {
    #expect(!shouldPresentSmartPasteError(JevPasteError.noMatch))
    #expect(shouldPresentSmartPasteError(JevPasteError.invalidResponse))
    #expect(shouldPresentSmartPasteError(URLError(.notConnectedToInternet)))
}

@Test func endDecisionRejectsBoundaryAtOrBeforeSelectedStart() {
    let client = JevClient()
    let line = "Primary alice@example.com backup bob@example.com"
    let boundaries = SelectionGeometry.boundaries(in: line)
    let start = boundaries.first { $0.characterOffset == 33 }!
    let earlierEnd = boundaries.first { $0.characterOffset == 25 }!
    let response = JevResponse(answers: [
        "end_boundary": .init(choice: earlierEnd.id, confidence: 0.99),
    ])

    let result = client.endResult(
        response,
        in: line,
        boundaries: boundaries,
        startBoundary: start
    )

    #expect(isInvalidResponse(result))
}

@Test func multiLineChooseUsesSelectedLineThenDependentStartAndEndRequests() async {
    let selectedLine = "Backup email bob@example.com"
    let boundaries = SelectionGeometry.boundaries(in: selectedLine)
    let start = boundaries.first { $0.characterOffset == 13 }!
    let end = boundaries.last!
    var requests: [JevRequest] = []

    let client = JevClient(sendHandler: { request, _, completion in
        requests.append(request)

        if request.questions["source_line"] != nil {
            completion(.success(JevResponse(answers: [
                "source_line": .init(choice: "line_1", confidence: 0.99),
            ])))
        } else if request.questions["start_boundary"] != nil {
            completion(.success(JevResponse(answers: [
                "start_boundary": .init(choice: start.id, confidence: 0.99),
            ])))
        } else if request.questions["end_boundary"] != nil {
            completion(.success(JevResponse(answers: [
                "end_boundary": .init(choice: end.id, confidence: 0.99),
            ])))
        } else {
            completion(.failure(JevPasteError.invalidResponse))
        }
    })

    let result: Result<String, Error> = await withCheckedContinuation { continuation in
        client.choose(
            field: focusedField(),
            clips: [clip("Primary email alice@example.com\n\(selectedLine)")],
            apiKey: "test-key"
        ) { result in
            continuation.resume(returning: result)
        }
    }

    guard case .success(let value) = result else {
        Issue.record("Expected the staged selection flow to succeed")
        return
    }

    #expect(value == "bob@example.com")
    #expect(requests.count == 3)
    #expect(requests[0].questions["source_line"] != nil)
    #expect(requests[1].questions["start_boundary"] != nil)
    #expect(requests[1].questions["end_boundary"] == nil)
    #expect(requests[1].state.selectedStartOffset == nil)
    #expect(requests[2].questions["end_boundary"] != nil)
    #expect(requests[2].questions["start_boundary"] == nil)
    #expect(requests[2].state.selectedStartOffset == 13)
    #expect(requests[2].questions["end_boundary"]?.criteria[start.id] == nil)
}

private func focusedField() -> FocusedFieldContext {
    FocusedFieldContext(
        element: AXUIElementCreateSystemWide(),
        label: "Email",
        role: "AXTextField",
        subrole: "",
        app: "Test App",
        bundleIdentifier: "com.example.test",
        isWebContent: false
    )
}

private func clip(_ text: String) -> Clip {
    Clip(id: UUID(), text: text, sourceApp: "Test", createdAt: Date())
}

private func isNoMatch<T>(_ result: Result<T, Error>) -> Bool {
    isPasteError(result) { error in
        if case .noMatch = error { return true }
        return false
    }
}


private func isInvalidResponse<T>(_ result: Result<T, Error>) -> Bool {
    isPasteError(result) { error in
        if case .invalidResponse = error { return true }
        return false
    }
}

private func isPasteError<T>(
    _ result: Result<T, Error>,
    matching predicate: (JevPasteError) -> Bool
) -> Bool {
    guard case .failure(let error) = result,
          let pasteError = error as? JevPasteError
    else {
        return false
    }
    return predicate(pasteError)
}
