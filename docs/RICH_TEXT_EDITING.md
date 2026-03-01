# Rich Text Editing Spec

This spec defines safe write support for inline rich text in Bike row paragraphs.

## Scope

Add two new write commands:

- `add-rich`: create a new row whose paragraph content is provided as inline rich text XML fragment.
- `set-rich-text`: replace an existing row paragraph with inline rich text XML fragment.

This spec only covers inline paragraph content (inside `<p>`), not block-level structures.

## Goals

- Let agents/users author inline styles directly without hand-editing `.bike` XML.
- Preserve unknown row attributes and overall document structure.
- Prevent unsafe or structurally invalid markup from being written.
- Keep behavior deterministic and easy to validate in tests.

## Non-Goals

- No support for editing arbitrary XML outside paragraph content.
- No support for block-level elements inside paragraph fragments (`ul`, `li`, `div`, etc.).
- No automatic migration of existing plain text rows to rich text.

## Proposed CLI

### `add-rich`

```bash
bike-tool add-rich <file.bike> --rich-text "<inline-xml-fragment>" [--parent-id <id>] [--type item|body|task|note|heading|quote|code|ordered|unordered] [--before-id <row-id> | --after-id <row-id> | --at-start | --at-end] [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]
```

Notes:

- `--type` defaults to `item`.
- `body` aliases to `item`.
- Placement semantics match `add`.

### `set-rich-text`

```bash
bike-tool set-rich-text <file.bike> --id <id> --rich-text "<inline-xml-fragment>" [--write-mode coordinated|atomic|inplace] [--backup-mode managed|inline|none]
```

Notes:

- Replaces only paragraph child nodes for the target row.
- Row attributes (`id`, `data-type`, `data-done`, custom attributes) remain unchanged.
- Child outlines (`<ul>...</ul>`) remain unchanged.

## Input Model

`--rich-text` is interpreted as an XML fragment that becomes children of `<p>`.

Examples:

- Plain text: `--rich-text "Hello world"`
- Styled: `--rich-text "<strong>Bold</strong> and <em>italic</em>"`
- Link: `--rich-text "Open <a href=\"file:///tmp/x.bike\">x.bike</a>"`

## Allowed Markup

Allowed inline tags:

- `a`
- `strong`
- `em`
- `s`
- `code`
- `mark`
- `span`
- text nodes

Allowed attributes:

- `a`: `href`, `title`, `rel`
- `span`: `style` (optional; may be restricted later)
- all others: no attributes by default

Any other tag or attribute must be rejected with a clear error.

## Validation and Sanitization Rules

1. Fragment must be well-formed XML when wrapped in a temporary container.
2. Resulting node set must contain only allowed inline tags/text nodes.
3. Disallowed tags/attributes fail the command (no write performed).
4. Empty `--rich-text` is allowed and writes an empty paragraph (`<p/>`).
5. Links:
   - `href` must be non-empty when `a` is present.
   - Relative/absolute/file URLs are accepted as raw values; no URL rewriting.
6. No namespace rewriting in fragment content.

## Write Semantics

- Build paragraph element in-memory:
  - `add-rich`: new `<li>` with `<p>` containing parsed fragment nodes.
  - `set-rich-text`: target row `<p>` children replaced atomically in-memory.
- Save path uses existing backup/write-mode behavior.
- On validation failure, file remains unchanged.

## Read Interop

Existing read behavior remains:

- `text`: plain text projection.
- `richText` (with `--rich-text`): inner XML of paragraph.
- `links`: extracted from anchor tags.

No JSON schema change is required for this feature.

## Error Behavior

Use actionable errors:

- malformed fragment
- unsupported tag
- unsupported attribute
- missing target row id (`set-rich-text`)
- missing required flags

Commands return non-zero and do not write on error.

## Test Plan

Add tests for:

1. `add-rich` with mixed inline styles writes expected XML.
2. `add-rich` with link populates `links` in JSON output.
3. `set-rich-text` replaces only paragraph content, preserving row attributes/children.
4. Reject disallowed tags (for example `script`, `div`, `ul`).
5. Reject disallowed attributes (for example `onclick` on `a`).
6. Empty fragment writes `<p/>`.
7. Backup + write mode behavior remains unchanged.

## Backward Compatibility

- No behavior change to existing commands (`add`, `add-link`, `done`, `undone`, `delete`).
- Users that do not use new commands are unaffected.
