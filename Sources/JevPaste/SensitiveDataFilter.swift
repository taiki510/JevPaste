import Foundation

enum SensitiveDataFilter {
    private static let sensitiveFieldTerms = [
        "password", "passcode", "pin", "otp", "one-time", "one time",
        "verification code", "security code", "credit card", "card number",
        "cvv", "cvc", "secret", "private key", "api key", "access token",
        "パスワード", "暗証番号", "認証コード", "確認コード", "ワンタイム",
        "カード番号", "セキュリティコード", "秘密鍵", "APIキー", "アクセストークン",
    ]

    private static let blockedPatterns = [
        #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
        #"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"#,
        #"\b(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{12,}\b"#,
        #"\bgh[opusr]_[A-Za-z0-9]{20,}\b"#,
        #"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#,
        #"\bjv_(?:live|test)_[A-Za-z0-9_-]{12,}\b"#,
        #"\b\d{3}-\d{2}-\d{4}\b"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    static func isSensitiveField(label: String, role: String, subrole: String) -> Bool {
        if subrole.localizedCaseInsensitiveContains("secure") { return true }
        let normalized = label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return sensitiveFieldTerms.contains { normalized.localizedCaseInsensitiveContains($0) }
    }

    static func isSensitiveText(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if blockedPatterns.contains(where: { $0.firstMatch(in: text, range: range) != nil }) {
            return true
        }

        let digitRuns = text.split(whereSeparator: { !$0.isNumber && $0 != " " && $0 != "-" })
        for run in digitRuns {
            let digits = run.filter(\.isNumber)
            if (13...19).contains(digits.count), passesLuhn(String(digits)) {
                return true
            }
        }
        return false
    }

    static func sanitizedCandidate(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 20_000, !isSensitiveText(trimmed) else { return nil }
        return trimmed
    }

    private static func passesLuhn(_ digits: String) -> Bool {
        guard digits.allSatisfy(\.isNumber) else { return false }
        let values = digits.reversed().compactMap { $0.wholeNumberValue }
        guard values.count == digits.count else { return false }
        let sum = values.enumerated().reduce(0) { partial, pair in
            let (index, value) = pair
            if index.isMultiple(of: 2) { return partial + value }
            let doubled = value * 2
            return partial + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum % 10 == 0
    }
}
