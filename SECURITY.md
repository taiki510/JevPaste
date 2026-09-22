# Security Policy

## Supported version

Security fixes are applied to the latest version on the `main` branch.

## Reporting a vulnerability

公開Issueへ機密情報や再現用の個人データを投稿しないでください。GitHubリポジトリのSecurityタブにあるPrivate vulnerability reportingから報告してください。

報告には、影響範囲、再現手順、確認したバージョンを含めてください。

## Data handling

- Smart Pasteを実行した時だけTypeSafeのJev APIへ通信します。
- `⌘J`では現在のクリップボード、`⌘⇧J`では保存プロフィールを送信します。
- 過去のクリップボード履歴はJevの判定に使用しません。
- APIキーと保存プロフィールはmacOS Keychainへ保存します。
- 履歴はAES-GCMで暗号化し、`~/Library/Application Support/JevPaste/history.enc`へ保存します。
- 外部通信先は`https://api.typesafe.ai/v1/systemone`に限定し、他ホストへのリダイレクトを拒否します。

詳細な挙動はREADMEの「プライバシーとセキュリティ」を参照してください。
