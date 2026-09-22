# JevPaste

[![CI](https://github.com/taiki510/JevPaste/actions/workflows/ci.yml/badge.svg)](https://github.com/taiki510/JevPaste/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

JevPasteは、コピーしたまとまったテキストから現在の入力欄に合う値をJevに選ばせる、macOS用のSmart Pasteアプリです。TypeSafeのJev APIへ直接接続し、メニューバーから動作します。

たとえば複数の連絡先項目を一度にコピーした後、メールアドレス欄、電話番号欄、氏名欄などでそれぞれ`⌘J`を押すと、Jevがコピー全文と入力欄の文脈を照合して対応する値を入力します。

このプロジェクトは独立したオープンソースプロジェクトであり、JasteおよびTypeSafeの公式製品ではありません。

## 主な機能

- `⌘J`: 現在のクリップボードからSmart Paste
- `⌘⇧J`: Keychainに保存したプロフィールからSmart Paste
- コピー全文、並び順、入力欄のラベルや説明をJevへ渡して判断
- 原文にない値の結合・生成・変換を禁止
- 暗号化されたローカル履歴
- APIキーと保存プロフィールをmacOS Keychainへ保存
- パスワードや認証コードなどの入力欄では処理を中止
- 外部通信先をTypeSafeのJev APIに限定

## 必要なもの

- macOS 14以降
- Xcode 16以降、または互換性のあるCommand Line Tools
- TypeSafe APIキー
- アクセシビリティ権限

入力監視権限はCarbonグローバルホットキーの通常動作には不要です。

## ビルドと実行

```sh
git clone https://github.com/taiki510/JevPaste.git
cd JevPaste
swift test
./Scripts/package-app.sh
open dist/JevPaste.app
```

`package-app.sh`はリリースビルドを作成し、`dist/JevPaste.app`をad-hoc署名します。配布する場合は、自分のDeveloper IDによる署名とAppleの公証を行ってください。

初回起動後は、メニューバーのJevPasteアイコンから次の設定を行います。

1. 「TypeSafe APIキーを設定…」でAPIキーを保存
2. 「操作・入力監視権限を確認…」からアクセシビリティを許可
3. 必要に応じて「プロフィールを編集…」で固定プロフィールを登録

## 動作の考え方

ローカル側は、コピー内容を電話番号、氏名、住所などの用途へ分類しません。コピー全文と、原文から機械的に列挙した部分文字列をJevへ渡し、現在の入力欄との対応判断をJevに任せます。

通常のSmart Pasteでは、`⌘J`を押した瞬間のクリップボードだけを判定対象にします。過去の履歴は送信しません。同じコピー内容は、次にコピーするまで何度でも利用できます。

プロフィールSmart Pasteでは、クリップボードの代わりに保存プロフィールを利用します。プロフィールは通常の履歴と分離され、メニューから編集または削除できます。

## プライバシーとセキュリティ

- Smart Pasteを明示的に実行した時だけJev APIへ送信します。
- アプリに組み込まれた外部通信先は`https://api.typesafe.ai/v1/systemone`のみです。
- APIキーと保存プロフィールはKeychainに保存します。
- 履歴はAES-GCMで暗号化し、最大200件をローカル保存します。
- 画像は記録・送信しません。
- 秘密鍵、代表的なAPIキー、カード番号などは履歴から除外します。
- APIへ送る本文は先頭12,000文字、候補は最大150件に制限します。

詳しくは[SECURITY.md](SECURITY.md)を参照してください。

## コントリビューション

[CONTRIBUTING.md](CONTRIBUTING.md)を確認のうえ、IssueまたはPull Requestを送ってください。

## ライセンス

[MIT License](LICENSE)
