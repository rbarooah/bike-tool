# Development

## Build

```bash
cd /Users/robin/src/bike-tool
swift build
```

## Test

```bash
cd /Users/robin/src/bike-tool
swift test
```

The test suite includes a regression fixture with complex rich text and custom attributes.

## Local Debug Run

```bash
cd /Users/robin/src/bike-tool
.build/debug/bike-tool help
```

Quick smoke checks:

```bash
# Default coordinated write
.build/debug/bike-tool done "/tmp/test.bike" --id someRowId

# Explicit alternate modes
.build/debug/bike-tool done "/tmp/test.bike" --id someRowId --write-mode atomic
.build/debug/bike-tool done "/tmp/test.bike" --id someRowId --write-mode inplace

# Delete row
.build/debug/bike-tool delete "/tmp/test.bike" --id someRowId
```

## Release Install

```bash
cd /Users/robin/src/bike-tool
scripts/install.sh
```

## Notes

- Keep `.bike` paths absolute in examples and automation prompts.
- Preserve unknown row attributes and inline paragraph markup.
- Add regression tests when introducing new write behavior.
