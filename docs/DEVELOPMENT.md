# Development

## Build

```bash
cd /path/to/bike-tool
swift build
```

Current package targets:

- `BikeToolCore` (library module with parse/mutate/backup logic)
- `bike-tool` (CLI executable that maps commands to `BikeToolCore`)

## Test

```bash
cd /path/to/bike-tool
swift test
```

The test suite includes a regression fixture with complex rich text and custom attributes.

Targeted runs:

```bash
# Core library tests
swift test --filter BikeToolCoreTests

# CLI-oriented tests
swift test --filter BikeToolTests
```

## Local Debug Run

```bash
cd /path/to/bike-tool
.build/debug/bike-tool help
```

Quick smoke checks:

```bash
# Default coordinated write
.build/debug/bike-tool done "/tmp/test.bike" --id someRowId

# Add a link row (file reference)
.build/debug/bike-tool add-link "/tmp/test.bike" --href "file:///tmp/target.bike" --text "target.bike" --type item

# Add a row with inline rich text
.build/debug/bike-tool add-rich "/tmp/test.bike" --rich-text "<strong>Bold</strong> and <a href=\"file:///tmp/target.bike\">target</a>" --type item

# Explicit alternate modes
.build/debug/bike-tool done "/tmp/test.bike" --id someRowId --write-mode atomic
.build/debug/bike-tool done "/tmp/test.bike" --id someRowId --write-mode inplace

# Delete row
.build/debug/bike-tool delete "/tmp/test.bike" --id someRowId

# Update existing row rich text
.build/debug/bike-tool set-rich-text "/tmp/test.bike" --id someRowId --rich-text "<mark>Updated</mark> paragraph"

# Position-aware add
.build/debug/bike-tool add "/tmp/test.bike" --text "Top task" --type task --at-start
.build/debug/bike-tool add "/tmp/test.bike" --text "Insert before row" --type item --before-id someRowId
.build/debug/bike-tool add "/tmp/test.bike" --text "Insert after row" --type item --after-id someRowId
.build/debug/bike-tool add "/tmp/test.bike" --text "Quoted block" --type quote

# Confirm structured link extraction in JSON output
.build/debug/bike-tool to-json "/tmp/test.bike" | rg '"links"|target.bike'

# Backup tools
.build/debug/bike-tool backup list "/tmp/test.bike"
.build/debug/bike-tool backup prune "/tmp/test.bike" --keep 10 --days 30
```

## Release Install

```bash
cd /path/to/bike-tool
scripts/install.sh
```

## Notes

- Keep `.bike` paths absolute in examples and automation prompts.
- Preserve unknown row attributes and inline paragraph markup.
- Default to `item` for normal body text; use `note` for annotation-style content.
- Prefer `add-link` for file references instead of plain text path rows.
- Use `add-rich` and `set-rich-text` for inline styled content instead of direct XML edits.
- JSON output includes a `links` field when row paragraphs contain anchor markup.
- Add regression tests when introducing new write behavior.
- Default backup mode is managed; use `--backup-mode inline` only when sidecar `.bak` files are explicitly desired.
