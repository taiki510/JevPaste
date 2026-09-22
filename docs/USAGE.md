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

If the email field is focused, Jev can select `jane.doe@example.com`. If the phone field is focused next, the same clipboard source can be reused to select `2025550123`.

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
4. Jev selects an exact value from the profile and JevPaste inserts it.

The current clipboard is not used as the source for this shortcut. Profile Smart Paste does not replace the clipboard or add the profile to clipboard history.

## Writing a Useful Profile

Jev makes the semantic decision, so the profile should provide enough context for Jev to distinguish similar values. The local app does not maintain a fixed list of profile fields.

The most reliable format is one clearly labeled value per line:

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

- Put one logical value on each line.
- Give similar values distinct labels, such as `Phone (complete)` and `Phone (part 1)`.
- Store every exact representation that a form may require.
- Keep related fields near each other so their ordering provides additional context.
- Include both a complete address and its component fields when you regularly encounter both form styles.
- Use realistic labels rather than unlabeled lists of values.
- Remove obsolete values instead of leaving conflicting alternatives in the profile.

### Exact Values and Variants

JevPaste only inserts text that appears exactly in the source. It does not combine, generate, reformat, or transform values.

For example, if a profile stores separate family and given names but does not contain a full-name value, JevPaste will not construct a full name. If forms require both hyphenated and unhyphenated postal codes, store both variants explicitly. The same principle applies to phone-number segments, phonetic spellings, address components, date formats, and other alternate representations.

### Other Supported Source Layouts

The app mechanically enumerates exact substrings from lines, whitespace-separated text, common delimiters, quoted pairs, and table-like text. Jev always receives the original complete source as the authoritative context.

Colon-separated, tab-separated, CSV-like, and simple quoted key-value text can therefore work, but the one-value-per-line format is easier to edit and usually gives Jev clearer context.

## What Is Sent to Jev

Each Smart Paste request includes:

- The focused field's available label, description, role, and application name
- The current clipboard text or saved profile, limited to 12,000 characters
- Up to 150 exact candidate substrings, each limited to 500 characters

Only one source is used per request. `Command-J` uses the current clipboard; `Command-Shift-J` uses the saved profile. Older clipboard history is never included.

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

### Jev Reports No Match

Confirm that the exact desired value exists in the active source. For profile use, add a clearer label or an explicit value variant. JevPaste deliberately refuses to invent or combine missing values.

### The Wrong Value Is Selected

Make ambiguous labels more specific and remove outdated duplicates. Keep the complete source context rather than reducing the profile to an unlabeled list. Jev, rather than a local rule, is responsible for deciding which value matches the field.

### The API Request Fails

Confirm that the TypeSafe API key is configured and valid, then check the HTTP status shown by JevPaste. The app rejects non-HTTPS redirects and redirects to hosts other than `api.typesafe.ai`.

## Clearing Local Data

- Remove the API key with the API-key removal command.
- Remove the saved profile by opening the profile editor and saving it empty.
- Delete clipboard history with the history-clearing command.

Deleting clipboard history does not change the current macOS clipboard.
