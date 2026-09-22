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
