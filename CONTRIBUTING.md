# Contributing

IssueやPull Requestを歓迎します。

## 開発環境

- macOS 14以降
- Xcode 16以降、または互換性のあるCommand Line Tools

変更前後に次を実行してください。

```sh
swift test
swift build
```

## Pull Request

- 変更の目的と利用者への影響を説明してください。
- 新しい判断ルールをローカル側へ追加する場合は、Jevへ必要な文脈を渡す方法で解決できないか先に検討してください。
- APIキー、プロフィール、実際のクリップボード内容をテストやログへ含めないでください。
- UIやホットキーを変更した場合は、READMEも更新してください。
