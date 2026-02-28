# Row Type Policy

This spec defines how `bike-tool` and companion agent skills should choose and write Bike row types.

## Status

- Current state:
  - `bike-tool` can read arbitrary `data-type` values.
  - `bike-tool add` and `bike-tool add-link` accept:
    - `item` (and alias `body`)
    - `task`, `note`, `heading`
    - `quote`, `code`, `ordered`, `unordered`
  - `add` and `add-link` default to `item`.

## Goals

- Match Bike semantics used in the default Bike examples:
  - untyped `item` for normal body prose
  - `note` for annotation-style text
  - special types (`quote`, `code`, lists) only when intended
- Keep agent behavior predictable and visually correct in Bike.
- Preserve backward compatibility where possible.

## Canonical Type Mapping

`bike-tool` should accept the following `--type` values for `add` and `add-link`:

- `item` (or alias `body`)
- `task`
- `note`
- `heading`
- `quote`
- `code`
- `ordered`
- `unordered`

XML mapping when writing:

- `item` / `body`: write `<li id="...">` with no `data-type` attribute.
- Any other supported type `t`: write `<li id="..." data-type="t">`.

## Defaults

- `bike-tool add` default type: `item`.
- `bike-tool add-link` default type: `item`.

Reason: in Bike UI, `note` is visually secondary (annotation style) while body prose is normally untyped.

## Skill Decision Policy

Skills that write `.bike` files should choose type by intent:

- `task`: explicit actionable todo.
- `heading`: section/grouping label.
- `note`: annotation, aside, meta-commentary, footnote-like content.
- `quote`: block quotation requested by user.
- `code`: code block requested by user.
- `ordered`: numbered list item requested by user.
- `unordered`: bulleted list item requested by user.
- `item` (default): all other normal prose, summaries, references, and narrative body text.

For file references:

- Prefer `add-link` with `file:///absolute/path`.
- Default link rows to `item` unless user explicitly asks for another type.

## CLI UX Requirements

Help/validation text should list all supported types.

Example usage to include in docs:

```bash
bike-tool add "/absolute/path/file.bike" --text "Normal paragraph" --type item
bike-tool add-link "/absolute/path/file.bike" --href "file:///absolute/path/doc.bike" --text "doc.bike" --type item
bike-tool add "/absolute/path/file.bike" --text "Design Notes" --type heading
bike-tool add "/absolute/path/file.bike" --text "TODO: ship this" --type task
```

## Backward Compatibility

- Existing documents are unaffected.
- Existing scripts using explicit `--type task|note|heading` remain valid.
- Behavior change risk:
  - Scripts relying on implicit default `task`/`note` must pass explicit `--type` to keep legacy behavior.

## Test Plan

Add/adjust tests to verify:

- `--type item` writes no `data-type`.
- `--type body` behaves identically to `item`.
- `quote|code|ordered|unordered` rows can be added.
- `add` and `add-link` default to `item`.
- JSON/list output reports these types correctly.

## Non-Goals

- No automatic conversion of existing `note` rows to `item`.
- No automatic re-typing of existing documents.
