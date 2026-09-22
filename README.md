# JevPaste

[![CI](https://github.com/taiki510/JevPaste/actions/workflows/ci.yml/badge.svg)](https://github.com/taiki510/JevPaste/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

JevPaste is a macOS menu bar app that asks Jev to select the value that best fits the currently focused input field from a block of copied text. It connects directly to TypeSafe's Jev API.

For example, copy several contact fields at once, focus an email, phone, or name field, and press `Command-J`. Jev compares the complete copied text with the field context and inserts the matching value.

This is an independent open-source project. It is not an official Jaste or TypeSafe product.

## Features

- `Command-J`: Smart Paste from the current clipboard
- `Command-Shift-J`: Smart Paste from a profile stored in Keychain
- Sends the complete source text, its ordering, and the focused field's labels and descriptions to Jev
- Enumerates exact single-word and multi-word source spans so names, places, organizations, and addresses can remain intact
- Supports optional backtick grouping for explicitly marking one value in controlled source text
- Prevents combining, generating, whitespace-normalizing, or transforming values that do not appear in the source text
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
- In a saved profile, wrap a value in backticks when you want to mark its exact boundaries explicitly, for example <code>Full name `Jane Doe`</code>.

See the [complete usage guide](docs/USAGE.md) for setup, profile-writing recommendations, examples, expected behavior, and troubleshooting.

## How It Works

The local app does not classify copied data as phone numbers, names, addresses, organizations, or other domain-specific types. It sends the full source text and mechanically enumerated exact substrings to Jev. Jev decides which source value corresponds to the focused field.

Whitespace is treated as a possible boundary, not as proof of a label/value split. For a line such as `Full Name John Smith`, JevPaste makes exact candidates including `John`, `Smith`, and `John Smith` available instead of assuming that everything after the first space is one value. Multi-word candidates are contiguous substrings of the original source, so their original whitespace is preserved.

Matched backticks provide an optional stronger boundary hint. For example, <code>Full Name `John Smith`</code> explicitly contributes `John Smith` as a high-priority candidate while the original source remains available to Jev as context.

For regular Smart Paste, only the clipboard contents present when `Command-J` is pressed are used. Older history entries are never included in the Jev request. The same copied text remains reusable until the clipboard changes.

Profile Smart Paste uses the saved profile instead of the clipboard. The profile is separate from clipboard history and can be edited or deleted from the menu.

See [Candidate Extraction Algorithm](docs/CANDIDATE_EXTRACTION.md) for the detailed extraction order, candidate categories, fairness strategy, limits, and design rationale.

## Privacy and Security

- Network communication occurs only when the user explicitly invokes Smart Paste.
- The only external endpoint embedded in the app is `https://api.typesafe.ai/v1/systemone`.
- The API key and saved profile are stored in macOS Keychain.
- Clipboard history is encrypted with AES-GCM and limited to 200 local entries.
- Images are neither recorded nor transmitted.
- Private keys, common API-key formats, payment-card numbers, and similar values are excluded from history.
- Request source text is limited to 12,000 characters and the candidate list to 150 entries.

See [SECURITY.md](SECURITY.md) for reporting and data-handling details.

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before contributing.

## Acknowledgements

JevPaste was inspired by the Smart Paste concept demonstrated by [Jaste](https://jaste.app/). JevPaste is an independent open-source implementation and is not affiliated with or endorsed by Jaste.

## License

[MIT License](LICENSE)
