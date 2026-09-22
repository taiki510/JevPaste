# Security Policy

## Supported Version

Security fixes are applied to the latest version on the `main` branch.

## Reporting a Vulnerability

Do not post sensitive information or personal reproduction data in a public issue. Use **Private vulnerability reporting** from the repository's **Security** tab.

Include the affected version, impact, and reproducible steps in the report.

## Data Handling

- JevPaste communicates with TypeSafe's Jev API only when the user invokes Smart Paste.
- `Command-J` sends the current clipboard contents; `Command-Shift-J` sends the saved profile.
- Older clipboard-history entries are not used in Jev requests.
- The API key and saved profile are stored in macOS Keychain.
- Clipboard history is encrypted with AES-GCM and stored at `~/Library/Application Support/JevPaste/history.enc`.
- The only external endpoint is `https://api.typesafe.ai/v1/systemone`; redirects to other hosts are rejected.

See the **Privacy and Security** section of the README for additional details.
