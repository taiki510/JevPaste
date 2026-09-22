# JevPaste Usage Guide

This guide covers initial setup, clipboard-based Smart Paste, saved profiles, recommended profile formatting, and troubleshooting.

## Initial Setup

1. Build and open `JevPaste.app` as described in the [README](../README.md).
2. Open the JevPaste menu bar item.
3. Choose the API-key command and enter your TypeSafe API key. The key is stored in macOS Keychain.
4. Choose the permissions command and grant Accessibility permission to JevPaste in System Settings.
5. Open the diagnostics command and confirm that `Command-J`, Accessibility, and the API key are shown as available.

Input Monitoring permission is normally unnecessary because JevPaste registers its shortcuts through the Carbon global-hotkey API.

## Smart Paste from the Clipboard

Use `Command-J` when the information you want to enter is currently on the clipboard.

1. Copy a text block containing all potentially relevant values.
2. Focus the destination input field.
3. Press `Command-J`.
4. Wait for JevPaste to select and insert the value.
5. Focus another field and press `Command-J` again to reuse the same copied block.

JevPaste reads the clipboard at the moment the shortcut is pressed. It does not consume the copied text, and it does not use older history entries for the decision.

Example source text:

```text
Full name Jane Doe
Family name Doe
Given name Jane
Phone 2025550123
Email jane.doe@example.com
Organization Example Company
```

If the email field is focused, Jev can select the email line and then the exact `jane.doe@example.com` range within it. If the full-name field is focused next, the same source can be reused and Jev can select `Jane Doe` without JevPaste needing a local rule for names.

### Source layout

Smart Paste is intentionally based on one selected source line per pasted value. The line may contain a label, punctuation, delimiters, prose, or other surrounding text; Jev selects the relevant range within that line.

Values that span multiple source lines are not supported. For normal web-form use this keeps the interaction and failure modes simple. If you control the source, put each complete value that may be pasted on one line.

## Saved Profile Smart Paste

Use a saved profile for information you enter frequently and do not want to copy before every use.

### Create or Edit a Profile

1. Open the JevPaste menu bar item.
2. Choose the profile-editing command.
3. Enter the complete profile as plain text.
4. Save it.

The profile is stored in macOS Keychain, separately from clipboard history. Open the same editor whenever you need to update it. Saving an empty profile removes it.

### Use the Profile

1. Focus the destination input field.
2. Press `Command-Shift-J`.
3. JevPaste sends the saved profile and the focused-field context to Jev.
4. Jev selects the relevant line and exact range, and JevPaste inserts that unchanged source substring.

The current clipboard is not used as the source for this shortcut. Profile Smart Paste does not replace the clipboard or add the profile to clipboard history.

## Writing a Useful Profile

Jev makes the semantic decision, so the profile should provide enough context for Jev to distinguish similar values. The local app does not maintain a fixed list of profile fields.

The recommended format is one clearly labeled, complete value per line:

```text
Full name Jane Doe
Family name Doe
Given name Jane
Full name (phonetic) JAYN DOE

Phone (complete) 2025550123
Phone (part 1) 202
Phone (part 2) 555
Phone (part 3) 0123

Email jane.doe@example.com

Postal code (with separator) 100-0001
Postal code (without separator) 1000001
Postal code (first part) 100
Postal code (second part) 0001

Address (full) 123 Example Street, Example City
State Example State
City Example City
Street address 123 Example Street
Building and unit Sample Building 305
```

These labels are examples, not built-in field definitions. Use labels that describe your own data clearly. Labels and values may be written in any language.

### Recommended Practices

- Put each complete value that may be pasted on one line.
- Give similar values distinct labels, such as `Phone (complete)` and `Phone (part 1)`.
- Store every exact representation that a form may require.
- Keep related fields near each other so the full source gives Jev useful context.
- Include both a complete address and its component fields when you regularly encounter both form styles.
- Use realistic labels rather than unlabeled lists of values.
- Remove obsolete values instead of leaving conflicting alternatives in the profile.

### Exact Values and Variants

JevPaste only inserts a contiguous substring that already exists on the selected source line. It does not combine, generate, reformat, normalize, or transform values.

For example, if a profile stores separate family and given names but never contains the full name contiguously on one line, JevPaste will not construct a full name. If forms require both hyphenated and unhyphenated postal codes, store both variants explicitly. The same principle applies to phone-number segments, phonetic spellings, address components, date formats, and other alternate representations.

## How Selection Works

For a source with multiple non-empty lines, JevPaste first asks Jev which single line contains the value requested by the focused field. A one-line source skips this request.

JevPaste then creates selectable boundaries within the chosen line without trying to understand what the text means. In ASCII-only non-whitespace text, consecutive letters and consecutive digits form runs while punctuation remains separately selectable. Whitespace forms runs. If a non-whitespace token contains any non-ASCII grapheme, every grapheme in that token—including adjacent ASCII characters—is selectable one by one. The boundaries between those units, plus the beginning and end of the line, become choices.

For example:

```text
Name John Smith, 郵便番号100-0001
```

is mechanically segmented approximately as:

```text
｜Name｜ ｜John｜ ｜Smith｜,｜ ｜郵｜便｜番｜号｜1｜0｜0｜-｜0｜0｜0｜1｜
```

The full-width `｜` characters above are explanatory boundary markers and are not inserted into the source. Jev chooses one start boundary and one end boundary in the same request. JevPaste then slices the untouched source line between those two positions.

This design avoids local rules such as deciding whether a colon belongs to a URL, whether a hyphen belongs to a phone number, or how many words make up a name.

See [Smart Paste Selection](SELECTION.md) for the precise algorithm and limits.

## What Is Sent to Jev

A Smart Paste operation sends the focused field context and the bounded active source.

For multi-line input, the first request includes choices for the non-empty source lines. The second request includes the selected line and its boundary choices. For a one-line source, only the boundary-selection request is needed.

Each question reserves `no_match` as a choice. The current implementation allows at most 255 choices per question, so at most 254 real line or boundary choices can be sent. Inputs over that limit are rejected instead of being semantically shortened or partially enumerated.

Only one source is used per operation. `Command-J` uses the current clipboard; `Command-Shift-J` uses the saved profile. Older clipboard history is never included.

## Insertion Behavior

In web browsers, JevPaste temporarily places the selected value on the clipboard and sends one `Command-V` event to the focused field. It then restores the previous clipboard contents. These temporary clipboard changes are excluded from history.

In native macOS apps, JevPaste first attempts Accessibility-based text insertion and falls back to a single `Command-V` event when necessary.

## Troubleshooting

### A Shortcut Does Nothing

Open the diagnostics command from the menu and check the registration state for both shortcuts. Restart JevPaste if a shortcut failed to register. Also check whether another application has claimed the same keyboard shortcut.

### The Focused Field Cannot Be Read

Open System Settings, find JevPaste under **Privacy & Security > Accessibility**, and enable it. If it is already enabled, remove and add it again, then restart JevPaste.

### No Value Is Inserted

Keep the destination field focused while the request runs. Open diagnostics and inspect the latest focus and insertion results. Some custom web components may not expose enough Accessibility information for JevPaste to identify or verify the field.

Also confirm that the complete desired value occurs contiguously on one source line. Multi-line values are intentionally unsupported.

### Jev Reports No Match

Confirm that the exact desired value exists on one line of the active source. For profile use, add a clearer label or an explicit value variant. JevPaste deliberately refuses to invent or combine missing values.

### The Source Is Too Complex

The line-selection and boundary-selection questions each have a finite choice budget. If the source has too many non-empty lines or the selected line creates too many lexical boundaries, simplify the source or put the desired value on a shorter dedicated line.

### The Wrong Value Is Selected

Make ambiguous labels more specific and remove outdated duplicates. Keep enough source context for Jev to distinguish similar values. Jev, rather than a local domain rule, is responsible for deciding which line and exact range match the field.

### The API Request Fails

Confirm that the TypeSafe API key is configured and valid, then check the HTTP status shown by JevPaste. The app rejects non-HTTPS redirects and redirects to hosts other than `api.typesafe.ai`.

## Clearing Local Data

- Remove the API key with the API-key removal command.
- Remove the saved profile by opening the profile editor and saving it empty.
- Delete clipboard history with the history-clearing command.

Deleting clipboard history does not change the current macOS clipboard.
