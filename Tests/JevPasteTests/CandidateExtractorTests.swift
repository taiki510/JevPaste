import Foundation
import Testing
@testable import JevPaste

@Test func firstWhitespaceIsNotAssumedToBeTheLabelBoundary() {
    let candidates = CandidateExtractor.extract(from: [clip("Family Name Johnson")])
    let values = candidates.map(\.value)

    #expect(values.contains("Johnson"))
    #expect(values.contains("Name Johnson"))
    #expect(values.firstIndex(of: "Johnson")! < values.firstIndex(of: "Name Johnson")!)
}

@Test func multiwordValuesAreAvailableAsContiguousCandidates() {
    let text = "Full Name John Smith\nCity New York\nOrganization Acme Holdings LLC\n氏名 山田 太郎"
    let values = CandidateExtractor.extract(from: [clip(text)]).map(\.value)

    #expect(values.contains("John Smith"))
    #expect(values.contains("New York"))
    #expect(values.contains("Acme Holdings LLC"))
    #expect(values.contains("山田 太郎"))
}

@Test func tokenSpansPreserveOriginalWhitespace() {
    let text = "Full Name John   Smith"
    let values = CandidateExtractor.extract(from: [clip(text)]).map(\.value)

    #expect(values.contains("John   Smith"))
    #expect(!values.contains("John Smith"))
}

@Test func backticksCreateHighestPriorityExplicitGroups() {
    let candidates = CandidateExtractor.extract(
        from: [clip("Full Name `John Michael Smith`\nCity `New York`")]
    )

    #expect(candidates[0].value == "John Michael Smith")
    #expect(candidates[0].kind == .explicitGroup)
    #expect(candidates[1].value == "New York")
    #expect(candidates[1].kind == .explicitGroup)
}

@Test func backtickGroupsMaySpanLines() {
    let text = "Mailing Address `123 Main Street\nApartment 4B`"
    let candidates = CandidateExtractor.extract(from: [clip(text)])

    #expect(candidates.first?.value == "123 Main Street\nApartment 4B")
    #expect(candidates.first?.kind == .explicitGroup)
}

@Test func asciiBackticksCreateExclusiveCandidateBoundaries() {
    let text = "Prefix Alpha `John Smith` Suffix Omega"
    let candidates = CandidateExtractor.extract(from: [clip(text)])
    let values = candidates.map(\.value)

    #expect(candidates.first?.value == "John Smith")
    #expect(candidates.first?.kind == .explicitGroup)
    #expect(!values.contains("John"))
    #expect(!values.contains("Smith"))
    #expect(!values.contains(where: { $0.contains("`") }))
    #expect(!values.contains(where: { $0.contains("Alpha") && $0.contains("Suffix") }))
}

@Test func fullwidthBackticksRemainOrdinaryText() {
    let text = "Full Name ｀John Smith｀"
    let candidates = CandidateExtractor.extract(from: [clip(text)])
    let values = candidates.map(\.value)

    #expect(!candidates.contains(where: { $0.kind == .explicitGroup }))
    #expect(values.contains("｀John Smith｀"))
}

@Test func oversizedBacktickGroupIsStillExcludedFromOrdinaryExtraction() {
    let groupedValue = String(repeating: "a", count: 501)
    let candidates = CandidateExtractor.extract(
        from: [clip("Label `\(groupedValue)` Tail")]
    )
    let values = candidates.map(\.value)

    #expect(!values.contains(groupedValue))
    #expect(!values.contains(where: { $0.contains("`") }))
}

@Test func clearStructuralSeparatorsStillProduceWholeValues() {
    let text = "Full Name: John Smith\nCompany=Acme Holdings LLC\nCity\tNew York"
    let candidates = CandidateExtractor.extract(from: [clip(text)])

    #expect(candidates.contains(where: { $0.value == "John Smith" && $0.kind == .structuredValue }))
    #expect(candidates.contains(where: { $0.value == "Acme Holdings LLC" && $0.kind == .structuredValue }))
    #expect(candidates.contains(where: { $0.value == "New York" && $0.kind == .structuredValue }))
}

@Test func candidateLimitIsSharedFairlyAcrossLines() {
    let text = "Field One Alpha\nField Two Beta\nField Three Gamma"
    let values = CandidateExtractor.extract(from: [clip(text)], limit: 3).map(\.value)

    #expect(values == ["Alpha", "Beta", "Gamma"])
}

@Test func lexicalCandidatesDoNotConsumeTheBudgetBeforeLaterLines() {
    let text = "1 2 3\nFamily Name Johnson"
    let values = CandidateExtractor.extract(from: [clip(text)], limit: 4).map(\.value)

    #expect(values.contains("Johnson"))
}

@Test func delimiterHeavyLineDoesNotCrowdOutLaterLines() {
    let text = "A1,B2,C3,D4,E5,F6\nFamily Name Johnson"
    let values = CandidateExtractor.extract(from: [clip(text)], limit: 2).map(\.value)

    #expect(values.contains("Johnson"))
}

@Test func lexicalCandidatesExcludeTrailingSentencePeriods() {
    let text = "Contact jane@example.com. Call 090-1234-5678."
    let values = CandidateExtractor.extract(from: [clip(text)]).map(\.value)

    #expect(values.contains("jane@example.com"))
    #expect(values.contains("090-1234-5678"))
}

@Test func longTrailingValuesAreAvailableBeyondEightTokens() {
    let value = "123 Main Street Building Alpha Floor Two Unit Nine Tokyo Japan"
    let values = CandidateExtractor.extract(from: [clip("Address \(value)")]).map(\.value)

    #expect(value.split(separator: " ").count > 8)
    #expect(values.contains(value))
}

@Test func embeddedTimeColonIsNotTreatedAsAKeyValueBoundary() {
    let candidates = CandidateExtractor.extract(from: [clip("Meeting 09:30")])

    #expect(!candidates.contains(where: { $0.value == "30" && $0.kind == .structuredValue }))
    #expect(candidates.contains(where: { $0.value == "09:30" }))
}

@Test func explicitTimeKeyValueStillUsesTheLabelSeparator() {
    let candidates = CandidateExtractor.extract(from: [clip("Time: 09:30")])

    #expect(candidates.contains(where: { $0.value == "09:30" && $0.kind == .structuredValue }))
}

@Test func uriSchemeColonIsNotTreatedAsAKeyValueBoundary() {
    let candidates = CandidateExtractor.extract(from: [clip("mailto:user@example.com")])

    #expect(!candidates.contains(where: {
        $0.value == "user@example.com" && $0.kind == .structuredValue
    }))
}

@Test func bareIPv6IsNotTreatedAsAKeyValueBoundary() {
    let text = "2001:db8::1"
    let candidates = CandidateExtractor.extract(from: [clip(text)])

    #expect(!candidates.contains(where: { $0.kind == .structuredValue }))
    #expect(candidates.contains(where: { $0.value == text }))
}

@Test func compactColonKeyValueRemainsSupported() {
    let candidates = CandidateExtractor.extract(from: [clip("Name:John")])

    #expect(candidates.contains(where: { $0.value == "John" && $0.kind == .structuredValue }))
}

@Test func urlIsNotMisreadAsColonKeyValuePair() {
    let text = "https://example.com/account"
    let candidates = CandidateExtractor.extract(from: [clip(text)])

    #expect(!candidates.contains(where: {
        $0.value == "//example.com/account" && $0.kind == .structuredValue
    }))
    #expect(candidates.contains(where: { $0.value == text }))
}

private func clip(_ text: String) -> Clip {
    Clip(id: UUID(), text: text, sourceApp: "Test", createdAt: Date())
}
