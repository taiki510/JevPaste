import Foundation
import ApplicationServices

struct Clip: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let sourceApp: String
    let createdAt: Date
}

struct FocusedFieldContext {
    let element: AXUIElement
    let label: String
    let role: String
    let subrole: String
    let app: String
    let bundleIdentifier: String
    let isWebContent: Bool
}

enum JevPasteError: LocalizedError {
    case missingAPIKey
    case accessibilityUnavailable
    case sensitiveField
    case emptyHistory
    case emptyProfile
    case noMatch
    case lowConfidence
    case sourceTooComplex
    case invalidResponse
    case insertionFailed
    case http(Int)
    case unsafeRedirect

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "TypeSafe APIキーが設定されていません。"
        case .accessibilityUnavailable: return "入力欄を取得できません。アクセシビリティ権限を確認してください。"
        case .sensitiveField: return "機密情報を扱う可能性がある入力欄ではSmart Pasteを実行しません。"
        case .emptyHistory: return "現在のクリップボードに利用できるテキストがありません。"
        case .emptyProfile: return "プロフィールが未登録です。メニューの「プロフィールを編集…」から登録してください。"
        case .noMatch: return "現在の入力欄に対応する値を、現在の入力元から特定できませんでした。"
        case .lowConfidence: return "候補の確信度が低いため貼り付けませんでした。"
        case .sourceTooComplex: return "入力元の行数または選択境界が多すぎるためSmart Pasteを実行できません。"
        case .invalidResponse: return "Jev APIから解釈できない応答が返りました。"
        case .insertionFailed: return "入力欄は取得できましたが、テキストを入力できませんでした。診断画面を確認してください。"
        case .http(let status): return "Jev APIがHTTP \(status)を返しました。"
        case .unsafeRedirect: return "許可されていない通信先へのリダイレクトを拒否しました。"
        }
    }
}
