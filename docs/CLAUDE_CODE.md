# Claude Code

This guide is for using `bike-tool` from Claude Code.

## Quick Start

Install the CLI with Homebrew:

```bash
brew tap rbarooah/bike-tool https://github.com/rbarooah/bike-tool
brew install bike-tool
```

Create a project-level `CLAUDE.md` so Claude Code follows the safe `.bike` workflow:

```bash
cat > CLAUDE.md <<'EOF'
# bike-tool workflow for .bike files

- Use bike-tool for all .bike mutations.
- Never hand-edit .bike XML directly.
- Use absolute file paths for .bike command arguments.
- Validate before and after edits:
  - bike-tool validate "/absolute/path/file.bike"
- Use:
  - bike-tool list
  - bike-tool to-json
  - bike-tool add / add-link / add-rich / set-rich-text / done / undone / delete
EOF
```

Verify install:

```bash
bike-tool help
```

## First Commands

```bash
bike-tool validate "/absolute/path/file.bike"
bike-tool list "/absolute/path/file.bike"
bike-tool to-json "/absolute/path/file.bike"
bike-tool add-link "/absolute/path/file.bike" --href "file:///absolute/path/target.bike" --text "target.bike" --type item
bike-tool add-rich "/absolute/path/file.bike" --rich-text "<strong>Bold</strong> text" --type item
```

## Notes

- `bike-tool` preserves unknown row attributes and inline rich-text markup.
- Use `to-json --rich-text` when paragraph markup detail is needed.
- JSON output includes `links` when rows contain anchor tags.
- `add` and `add-link` default to `item` (normal body text); reserve `note` for annotation-style content.
