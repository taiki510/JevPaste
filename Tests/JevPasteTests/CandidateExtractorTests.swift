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
