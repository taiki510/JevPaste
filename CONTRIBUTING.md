# Contributing

Issues and pull requests are welcome.

## Development Environment

- macOS 14 or later
- Xcode 16 or compatible Command Line Tools

Run the following commands before and after making changes:

```sh
swift test
swift build
```

## Pull Requests

- Explain the purpose of the change and its user-facing impact.
- Before adding local classification rules, consider whether the problem can be solved by providing Jev with better source context.
- Never include API keys, saved profiles, or real clipboard contents in tests or logs.
- Update the README when changing the UI, keyboard shortcuts, setup, or data handling.
