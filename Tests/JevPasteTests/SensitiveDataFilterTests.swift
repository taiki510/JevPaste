import Foundation
import Testing
@testable import JevPaste

@Test func sensitiveFieldsAreDetectedAsSubstringsAndInJapanese() {
    #expect(SensitiveDataFilter.isSensitiveField(label: "New password", role: "AXTextField", subrole: ""))
    #expect(SensitiveDataFilter.isSensitiveField(label: "認証コードを入力", role: "AXTextField", subrole: ""))
    #expect(SensitiveDataFilter.isSensitiveField(label: "Name", role: "AXTextField", subrole: "AXSecureTextField"))
    #expect(!SensitiveDataFilter.isSensitiveField(label: "Email address", role: "AXTextField", subrole: ""))
}

@Test func secretsAreRejected() {
    #expect(SensitiveDataFilter.isSensitiveText("4111 1111 1111 1111"))
    #expect(SensitiveDataFilter.isSensitiveText("-----BEGIN PRIVATE KEY-----"))
    #expect(SensitiveDataFilter.isSensitiveText("eyJabcdefghijk.abcdefghijk.abcdefghijk"))
    #expect(!SensitiveDataFilter.isSensitiveText("hello@example.com"))
}

@Test func candidatesAreBounded() {
    #expect(SensitiveDataFilter.sanitizedCandidate("  hello  ") == "hello")
    #expect(SensitiveDataFilter.sanitizedCandidate(String(repeating: "a", count: 600))?.count == 600)
}

@Test func copiedFormBlockIsSplitIntoExactValues() {
    let block = """
    姓 山田
    名 太郎
    姓（カナ） ヤマダ
    名（カナ） タロウ
    電話番号 09012345678
    メールアドレス yamada@example.com
    """
    let candidates = CandidateExtractor.extract(from: [clip(block)])

    #expect(candidates.contains(where: { $0.value == "山田" }))
    #expect(candidates.contains(where: { $0.value == "タロウ" }))
    #expect(candidates.contains(where: { $0.value == "09012345678" }))
    #expect(candidates.contains(where: { $0.value == "yamada@example.com" }))
    #expect(!candidates.contains(where: { $0.value == block }))
}

@Test func embeddedEmailAndPhoneAreExtractedFromProse() {
    let candidates = CandidateExtractor.extract(
        from: [clip("連絡先は yamada@example.com、携帯は090-1234-5678です。")]
    )
    #expect(candidates.contains(where: { $0.value == "yamada@example.com" }))
    #expect(candidates.contains(where: { $0.value == "090-1234-5678" }))
}

@Test func tabularAndQuotedDataProduceExactValueCandidates() {
    let text = "姓\t山田\t名\t太郎\nメール,電話番号\nyamada@example.com,09012345678\n{\"company\":\"例示株式会社\"}"
    let candidates = CandidateExtractor.extract(from: [clip(text)])
    #expect(candidates.contains(where: { $0.value == "山田" }))
    #expect(candidates.contains(where: { $0.value == "太郎" }))
    #expect(candidates.contains(where: { $0.value == "yamada@example.com" }))
    #expect(candidates.contains(where: { $0.value == "09012345678" }))
    #expect(candidates.contains(where: { $0.value == "例示株式会社" }))
}

@Test func nonProfileKeyValueDataIsHandledGenerically() {
    let text = "環境 production\nリージョン ap-northeast-1\nSKU: ABC-123\npriority\thigh\n{\"deployment\":\"blue\"}"
    let candidates = CandidateExtractor.extract(from: [clip(text)])
    #expect(candidates.contains(where: { $0.value == "production" }))
    #expect(candidates.contains(where: { $0.value == "ap-northeast-1" }))
    #expect(candidates.contains(where: { $0.value == "ABC-123" }))
    #expect(candidates.contains(where: { $0.value == "high" }))
    #expect(candidates.contains(where: { $0.value == "blue" }))
}

@Test func candidatesRemainExactSubstringsAndAreNeverSynthesized() {
    let text = "姓 山田\n名 太郎"
    let candidates = CandidateExtractor.extract(from: [clip(text)])

    #expect(candidates.allSatisfy { text.contains($0.value) })
    #expect(!candidates.contains(where: { $0.value == "山田 太郎" }))
}

@Test func multiwordValuesRemainAvailableAsExactCandidates() {
    let text = "Family Name Goto\nLegal organization name Example Company\nAccount owner `Jane Mary Doe`"
    let candidates = CandidateExtractor.extract(from: [clip(text)])

    #expect(candidates.contains(where: { $0.value == "Goto" }))
    #expect(candidates.contains(where: { $0.value == "Example Company" }))
    #expect(candidates.contains(where: { $0.value == "Jane Mary Doe" }))
    #expect(candidates.allSatisfy { text.contains($0.value) })
}

private func clip(_ text: String) -> Clip {
    Clip(id: UUID(), text: text, sourceApp: "Test", createdAt: Date())
}
