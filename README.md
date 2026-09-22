# JevPaste

[![CI](https://github.com/taiki510/JevPaste/actions/workflows/ci.yml/badge.svg)](https://github.com/taiki510/JevPaste/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

JevPaste is a macOS menu bar app that asks Jev to select the value that best fits the currently focused input field from a block of copied text. It connects directly to TypeSafe's Jev API.

For example, copy several contact fields at once, focus an email, phone, or name field, and press `Command-J`. Jev identifies the relevant source line, selects the exact range within that line, and JevPaste inserts that unchanged substring.

This is an independent open-source project. It is not an official Jaste or TypeSafe product.

## Features

- `Command-J`: Smart Paste from the current clipboard
- `Command-Shift-J`: Smart Paste from a profile stored in Keychain
- Sends the complete bounded source text and focused field context to Jev
- Uses Jev, rather than local domain rules, to decide which line and text range match the field
- Inserts only an exact contiguous substring that already exists on one source line
- Keeps an encrypted local clipboard history
- Stores the API key and saved profile in macOS Keychain
- Refuses to operate in password, verification-code, and similar sensitive fields
- Restricts external communication to TypeSafe's Jev API

## Requirements

- macOS 14 or later
- Xcode 16 or compatible Command Line Tools
- A TypeSafe API key
- Accessibility permission

Input Monitoring permission is not required for the normal Carbon global-hotkey path.

## Build and Run

```sh
git clone https://github.com/taiki510/JevPaste.git
cd JevPaste
swift test
./Scripts/package-app.sh
open dist/JevPaste.app
```

`package-app.sh` creates a release build, packages it as `dist/JevPaste.app`, and applies an ad-hoc signature. If you distribute the app, sign it with your own Developer ID and submit it for Apple notarization.

After the first launch, open the JevPaste menu bar item and complete the following setup:

1. Select **Set TypeSafe API Key…** and save your API key.
2. Select **Check Permissions…** and grant Accessibility permission.
3. Optionally select **Edit Profile…** to save reusable profile text.

The current app UI is in Japanese; the English labels above describe the corresponding menu actions.

## Usage

- Use `Command-J` when the source is the current clipboard.
- Use `Command-Shift-J` when the source is your saved profile.
- Keep the destination field focused until JevPaste finishes.
- Reuse the same copied block across multiple fields without copying it again.
- Keep each value that may be pasted on a single source line. Multi-line values are intentionally outside the Smart Paste selection model.

See the [complete usage guide](docs/USAGE.md) for setup, profile-writing recommendations, examples, expected behavior, and troubleshooting.

## How It Works

JevPaste deliberately avoids local semantic parsing. It does not classify text as names, addresses, phone numbers, URLs, or other domain-specific types.

For a multi-line source, Jev first chooses the single line that contains the value for the focused field. For the selected line, JevPaste mechanically generates selectable text boundaries. A second Jev request chooses the start and end boundaries. JevPaste then slices the original line at those exact positions and inserts the resulting substring without generating, joining, or normalizing text.

Boundary generation is lexical rather than semantic. In ordinary ASCII-only text, consecutive ASCII letters and consecutive ASCII digits are grouped into runs, while punctuation remains separately selectable. Whitespace is grouped into runs. If a non-whitespace token contains any non-ASCII grapheme, every grapheme in that token—including adjacent ASCII characters—is selectable one by one. This keeps ordinary English lines compact while retaining fine-grained selection for Japanese and mixed-script text.

For regular Smart Paste, only the clipboard contents present when `Command-J` is pressed are used. Older history entries are never included in the Jev request. The same copied text remains reusable until the clipboard changes.

Profile Smart Paste uses the saved profile instead of the clipboard. The profile is separate from clipboard history and can be edited or deleted from the menu.

See [Smart Paste Selection](docs/SELECTION.md) for the full selection algorithm, limits, and design rationale.

## Privacy and Security

- Network communication occurs only when the user explicitly invokes Smart Paste.
- The only external endpoint embedded in the app is `https://api.typesafe.ai/v1/systemone`.
- The API key and saved profile are stored in macOS Keychain.
- Clipboard history is encrypted with AES-GCM and limited to 200 local entries.
- Images are neither recorded nor transmitted.
- Private keys, common API-key formats, payment-card numbers, and similar values are excluded from history.
- Request source text is limited to 12,000 characters.
- Each Jev choice question is capped at 255 choices, including `no_match`. Inputs that exceed the line or boundary budget are rejected rather than heuristically truncated.

See [SECURITY.md](SECURITY.md) for reporting and data-handling details.

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before contributing.

## Acknowledgements

JevPaste was inspired by the Smart Paste concept demonstrated by [Jaste](https://jaste.app/). JevPaste is an independent open-source implementation and is not affiliated with or endorsed by Jaste.

## License

[MIT License](LICENSE)
