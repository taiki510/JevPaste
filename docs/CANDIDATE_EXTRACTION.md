# Candidate Extraction Algorithm

JevPaste separates two responsibilities:

1. The local app mechanically enumerates exact substrings that could be pasted.
2. Jev decides which candidate best matches the currently focused field.

The extractor deliberately does not classify text as a person name, address, company, phone number, or any other semantic type. That distinction is important for `Command-J`, where the clipboard can contain arbitrary text in formats that JevPaste has never seen before.

## Design goals

The candidate extractor is designed around five constraints:

- **Preserve exact source text.** A selected value must already occur in the source. JevPaste must not construct a new full name, normalize whitespace, join fields from different lines, or otherwise synthesize a value.
- **Support multi-word values.** Names such as `John Smith`, places such as `New York`, organizations such as `Acme Holdings LLC`, and street addresses must remain selectable as complete values.
- **Avoid assuming that the first space separates a label and value.** In `Family Name Johnson`, the first space is inside the label, not the label/value boundary.
- **Allow explicit author intent without requiring it.** Matched half-width ASCII backticks can reserve one exact value as a single candidate in a saved profile or controlled clipboard source, but ordinary `Command-J` input must continue to work without special markup.
- **Remain bounded.** Candidate enumeration must stay useful under the 150-candidate request limit instead of letting one long line consume the entire budget.

## Candidate kinds

Each candidate carries a syntactic kind. The kind does not determine what the text means; it only records how the exact substring was discovered.

| Kind | Meaning | Example |
| --- | --- | --- |
| `explicitGroup` | Text explicitly enclosed in matched ASCII backticks | <code>Full Name `John Smith`</code> -> `John Smith` |
| `structuredValue` | A value found through clear source syntax | `Full Name: John Smith` -> `John Smith` |
| `tokenSpan` | A contiguous run of whitespace-delimited tokens | `Full Name John Smith` -> `John Smith` |
| `structuralFragment` | A complete line or delimiter-separated fragment | `New York` -> `New York` |

When the same textual value is found more than once, only the first occurrence in candidate priority order is retained. This means an explicitly grouped value keeps its stronger kind even if the same text is found again as a token span.

## Extraction pipeline

### 1. Explicit ASCII-backtick groups

The extractor scans the complete source before ordinary line and token processing. Text between a matched pair of half-width ASCII backticks (U+0060) is added first as one `explicitGroup` candidate.

```text
Full Name `John Michael Smith`
City `New York`
```

produces the complete high-priority candidates `John Michael Smith` and `New York`.

Matched ASCII backticks are dedicated grouping syntax. The delimiters themselves are never candidate text, the enclosed range is not separately processed for ordinary quoted, lexical, token-span, or structural-fragment candidates, and no ordinary candidate is allowed to cross the grouped range. Thus <code>Full Name `John Smith`</code> exposes `John Smith` as the grouped value without also deriving `John`, `Smith`, or backtick-containing spans from inside that group.

A matched group may span a newline:

```text
Mailing Address `123 Main Street
Apartment 4B`
```

The enclosed two-line text is one explicit candidate. Leading and trailing whitespace inside the group is trimmed when the candidate is stored, while internal whitespace is preserved. A matched group still acts as a boundary if its enclosed value is empty or exceeds the 500-character candidate limit; in that case no explicit candidate is added, but the grouped range does not fall back into ordinary extraction.

Only the half-width ASCII backtick U+0060 is special. Visually similar full-width text such as `｀John Smith｀` is ordinary source text and receives no grouping semantics. Unmatched ASCII backticks likewise do not form a group.

Grouping is optional. It is most useful in saved profiles, where the author controls the source text. Clipboard Smart Paste does not depend on it.

### 2. Clear structured values

Each non-empty line is checked for syntax that provides an explicit value boundary:

- quoted key/value pairs such as `"company": "Acme Holdings LLC"`
- alternating tab-separated key/value pairs
- the first `:`, `：`, or `=` separator when it looks like a key/value line

A colon is ignored as a structured boundary when it is clearly embedded inside another lexical value, including digit-to-digit time forms such as `09:30`, common URI schemes such as `https:` or `mailto:`, and bare IPv6 addresses. A real key/value form such as `Time: 09:30` still yields `09:30` as a structured value.

Unlike the previous algorithm, ordinary whitespace is **not** treated as a key/value separator. There is no rule that says "everything after the first space is the value."

### 3. Structural fragments

Lines containing common tabular or list delimiters are also split into exact fragments. The recognized delimiters are:

- tab
- `|`
- `,` and `，`
- `、`
- `;` and `；`

Both the original line and its fragments remain available for later token-span generation. This is useful for CSV-like data without making CSV semantics mandatory.

### 4. Quoted and embedded lexical values

Quoted text is retained as a structured candidate. A lightweight ASCII lexical scan also recovers tokens that contain digits or common machine-readable separators such as `@`, `.`, `_`, `+`, `:`, `/`, or `-`.

This stage exists mainly for values embedded directly in prose, for example:

```text
Contact yamada@example.com、mobile 090-1234-5678.
```

It can recover `yamada@example.com` and `090-1234-5678` even when punctuation is attached without surrounding spaces. Sentence-final periods are not absorbed into those lexical candidates, so `jane@example.com.` still exposes the exact substring `jane@example.com`.

The lexical scan is supplemental; it is not the primary tokenizer and therefore does not impose ASCII-only behavior on names or other natural-language values.

### 5. Unicode whitespace tokenization

Every line and structural fragment is tokenized on Unicode whitespace. Tokens themselves are not classified.

For:

```text
Full Name John Smith
```

the token boundaries are:

```text
Full | Name | John | Smith
```

The extractor then takes substrings directly from the original source range. It does not rebuild spans by joining tokens. This preserves the original whitespace exactly:

```text
Full Name John   Smith
```

contains the candidate `John   Smith`, not a synthesized `John Smith`.

### 6. Contiguous multi-token spans

For each line or fragment, JevPaste enumerates two bounded classes of contiguous spans. Trailing spans are extended beyond eight tokens while the resulting exact substring remains within the 500-character candidate limit. General spans that may start at any token remain limited to eight tokens. This preserves long label/value tails such as postal addresses without allowing the arbitrary-span search to grow quadratically without bound.

The per-fragment order is intentionally biased toward a common `label value` layout without declaring where the label ends:

1. trailing one-token span
2. trailing two-token span
3. trailing three-token span
4. and so on while the trailing substring remains within 500 characters
5. all contiguous one-token spans from left to right
6. all contiguous two-token spans from left to right
7. and so on, up to eight tokens
8. the complete fragment

For:

```text
Family Name Johnson
```

the early candidates include:

```text
Johnson
Name Johnson
Family Name Johnson
```

`Johnson` therefore becomes available immediately, but the extractor does not claim that the first space is a semantic boundary.

For:

```text
Full Name John Smith
```

the early candidates include:

```text
Smith
John Smith
Name John Smith
Full Name John Smith
```

and the later contiguous-span pass also includes `John`, `Full Name`, `Name John`, and the other exact spans. Jev receives the complete original line and decides whether the focused field requires `John`, `Smith`, or `John Smith`.

The eight-token bound applies to arbitrary-start spans and controls combinatorial growth. Trailing spans are linear in the number of tokens and therefore may extend farther, but stop once they would exceed 500 characters. A complete line is also queued as a `structuralFragment` when its total length is within the per-candidate character limit, although it can still be omitted if the global candidate budget is exhausted first.

### 7. Round-robin allocation across lines and fragments

Candidate generation can produce more values than the request limit. To prevent an early long or delimiter-heavy line from crowding out later lines, embedded lexical candidates and span candidates are allocated in two levels.

First, the candidate streams for an ordinary source segment and its delimiter-separated structural fragments are interleaved. Then those per-segment streams are consumed in round-robin order across the source. This prevents a line with many comma-, pipe-, tab-, or semicolon-separated fragments from receiving many candidate slots before a later line gets its first candidate.

Conceptually:

```text
line 1 candidate 1
line 2 candidate 1
line 3 candidate 1
...
line 1 candidate 2
line 2 candidate 2
line 3 candidate 2
...
```

A matched ASCII-backtick group is not part of an ordinary segment; it is handled separately as an explicit candidate boundary. Explicit groups and clear structured values are inserted before the round-robin phase because they contain stronger source-level boundary information.

### 8. Deduplication and limits

Candidate values are deduplicated globally by exact string value. The first occurrence wins.

Current limits are:

- source context: up to 12,000 characters
- candidate value: up to 500 characters
- candidate count: up to 150
- arbitrary-start contiguous token span: up to eight tokens
- trailing token span: may exceed eight tokens while the exact substring remains within 500 characters

These limits keep the request bounded while preserving the original source text as Jev's authoritative context.

## Jev selection instructions

Jev receives:

- the complete bounded source text
- the focused field context
- the candidate values
- each candidate's syntactic kind

The selection instruction asks Jev to choose the exact candidate that **fully represents** the value requested by the focused field. It specifically says not to prefer a shorter candidate when that would omit part of the requested value.

This replaces the earlier "prefer the smallest complete value" wording, which could create the wrong pressure when both `John` and `John Smith` are valid exact candidates but the focused field asks for a full name.

Explicitly grouped candidates are described as values the source author deliberately marked as one complete candidate. That grouping fixes the candidate boundary, but it does not force a semantic match: Jev must still verify that the complete grouped value fits the focused field.

## Why not parse labels locally?

A deterministic local label parser would need to answer questions such as:

- Is `Family Name Johnson` split after `Family`, `Name`, or neither?
- Is `New York` one value or two values?
- Is `Acme Holdings LLC` one organization value?
- Does `東京都 千代田区 丸の内 1-1-1` contain a label at all?
- Is a copied sentence prose, a key/value record, or a table cell rendered without tabs?

Those decisions are semantic and highly format-dependent. Encoding them as local heuristics would make `Command-J` brittle and language-specific.

JevPaste therefore keeps local processing syntactic: enumerate plausible exact spans, preserve context, and let Jev make the semantic selection.

## Expected behavior examples

| Source | Focused field | Candidate Jev should be able to select |
| --- | --- | --- |
| `Family Name Johnson` | Family name | `Johnson` |
| `Full Name John Smith` | Full name | `John Smith` |
| `Given Name John` | Given name | `John` |
| `City New York` | City | `New York` |
| `Organization Acme Holdings LLC` | Organization | `Acme Holdings LLC` |
| `Full Name: John Smith` | Full name | `John Smith` |
| `"full_name": "John Smith"` | Full name | `John Smith` |
| <code>Full Name `John Smith`</code> | Full name | `John Smith` |
| `氏名 山田 太郎` | Full name | `山田 太郎` |
| `Address 123 Main Street Apt 4B` | Address | `123 Main Street Apt 4B` |

These examples are expected to be available when their candidate survives the configured global budget. The final semantic choice remains Jev's responsibility.
