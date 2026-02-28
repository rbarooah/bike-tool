# Development

## Build

```bash
cd /path/to/bike-tool
swift build
```

## Test

```bash
cd /path/to/bike-tool
swift test
```

The test suite includes a regression fixture with complex rich text and custom attributes.

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

# Explicit alternate modes
.build/debug/bike-tool done "/tmp/test.bike" --id someRowId --write-mode atomic
.build/debug/bike-tool done "/tmp/test.bike" --id someRowId --write-mode inplace

# Delete row
.build/debug/bike-tool delete "/tmp/test.bike" --id someRowId

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
- JSON output includes a `links` field when row paragraphs contain anchor markup.
- Add regression tests when introducing new write behavior.
- Default backup mode is managed; use `--backup-mode inline` only when sidecar `.bak` files are explicitly desired.
