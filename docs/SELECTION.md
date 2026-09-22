# Smart Paste Selection

JevPaste is designed around a simple division of responsibility:

1. Local code preserves source text, exposes mechanically valid positions, and enforces hard limits.
2. Jev performs the semantic decisions required to match source text to the focused field.

The local app intentionally avoids rules that classify names, addresses, URLs, phone numbers, dates, organizations, or other semantic types.

## Overview

Smart Paste selects an exact contiguous substring from a single source line.

For a multi-line source:

1. Split the bounded source into non-empty lines.
2. Ask Jev which one line contains the value for the focused field.
3. Mechanically generate selectable boundaries for that line.
4. Ask Jev for the start boundary.
5. Send the fixed start position in a subsequent request and ask Jev for the end boundary, offering only boundaries after that start.
6. Validate the range locally.
7. Slice the original line at those exact indices and insert the result.

For a one-line source, the separate line-selection request in step 2 is skipped. The start-boundary request also includes an explicit match/no-match question so a one-line source is never assumed to contain a suitable value.

Values that span multiple source lines are intentionally unsupported. JevPaste is primarily a web-form input tool, and requiring a pasteable value to exist on one line keeps both the interaction and failure modes substantially simpler.

## Line Selection

The complete bounded source remains available to Jev as context.

Each non-empty source line becomes a choice such as `line_0`, `line_1`, and so on. Jev is asked to choose the single line that contains the exact value appropriate for the focused field.

The selected line may still contain a label, punctuation, or unrelated surrounding text. Line selection only narrows the search space; it does not determine the pasted value.

If there is only one non-empty line, JevPaste skips this request because there is no line decision to make.

## Boundary Generation

JevPaste does not enumerate every possible substring of the selected line. Enumerating all substrings grows quadratically with the number of possible boundaries.

Instead, the app generates a linear set of lexical boundaries. The segmentation rules are deliberately mechanical:

- consecutive whitespace characters form one unit
- in an ASCII-only non-whitespace token, consecutive ASCII letters form one unit and consecutive ASCII digits form one unit
- in an ASCII-only non-whitespace token, each ASCII punctuation or symbol character forms one unit
- if a non-whitespace token contains any non-ASCII grapheme, every grapheme cluster in that token is one unit, including adjacent ASCII characters

A boundary exists at the beginning and end of the line and between every adjacent unit.

For example:

```text
Full Name John Smith
```

has word-scale boundaries:

```text
｜Full｜ ｜Name｜ ｜John｜ ｜Smith｜
```

while:

```text
氏名山田太郎
```

has per-character boundaries:

```text
｜氏｜名｜山｜田｜太｜郎｜
```

Mixed text remains flexible without semantic parsing:

```text
郵便番号100-0001
```

becomes approximately:

```text
｜郵｜便｜番｜号｜1｜0｜0｜-｜0｜0｜0｜1｜
```

and:

```text
Room305
```

becomes:

```text
｜Room｜305｜
```

This keeps ordinary English text compact while preserving character-level precision for Japanese and for half-width characters that are directly mixed into the same non-whitespace token.

## Boundary Presentation

Boundary IDs such as `boundary_12` are the actual choices returned by Jev.

For readability, criteria include a short preview with an inserted marker such as `[[JevPasteBoundary]]`. Before building previews, JevPaste chooses a marker string that does not occur anywhere in the selected source line. If the base marker already appears in the source, a numeric suffix is incremented until a collision-free marker is found. The marker is not part of the source text and is never pasted.

Boundary selection is sequential rather than parallel:

- the first boundary request asks `start_boundary`, choosing the boundary immediately before the first character of the complete value
- after that choice is accepted, JevPaste sends the selected start offset in `selected_start_offset`
- the second boundary request asks `end_boundary` and offers only boundaries after the fixed start

The end-boundary instructions include the fixed start offset and its marked preview, and explicitly require the end to complete the value beginning at exactly that start rather than switching to another occurrence elsewhere on the line.

For a one-line source, the start-boundary request also includes `line_match`, which explicitly asks whether that line contains any complete exact value appropriate for the focused field. This preserves the no-match decision while avoiding a separate line-selection request.

Each returned decision must independently meet the configured confidence threshold. The local app also verifies that the returned end boundary is after the already accepted start boundary.

## Exact Source Preservation

Jev never returns the text that JevPaste inserts. It returns only IDs for a source line and boundary positions.

The final value is produced locally by slicing the original selected line. Therefore JevPaste does not:

- join text from separate ranges
- construct missing values
- normalize whitespace
- rewrite punctuation
- reformat phone numbers, dates, or addresses
- otherwise transform the source

Leading or trailing source characters are preserved if Jev deliberately selects boundaries that include them.

## Choice Limits

Each Jev choice question is capped at 255 choices in the current implementation. One choice is reserved for `no_match`, leaving at most 254 source-line or boundary choices.

JevPaste rejects an input that exceeds the relevant choice budget. It does not silently drop later lines, omit arbitrary boundaries, or introduce semantic heuristics to force the source under the limit.

The source context itself remains bounded to 12,000 characters.

## Why This Replaces Candidate Extraction

An earlier design tried to enumerate plausible paste candidates locally using whitespace spans, structured delimiters, lexical tokens, URL exceptions, and related rules.

That approach creates two problems:

1. plausible substrings grow rapidly as lines become longer
2. every additional local rule introduces assumptions about what the source means

The staged range-selection design removes those semantic assumptions. Local code describes where text can be selected; Jev decides what the text means.
