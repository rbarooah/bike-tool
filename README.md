# bike-tool

A Swift CLI for reading and safely editing [Bike.app](https://www.hogbaysoftware.com/bike/) `.bike` outline files.

`bike-tool` is designed for deterministic command-line edits instead of ad-hoc XML manipulation.

## Features

- Validate `.bike` XML structure
- List outline rows with type, id, and done state
- Export rows to JSON (`--rich-text` optional, `links` included when present)
- Add rows (`item`, `task`, `note`, `heading`, `quote`, `code`, `ordered`, `unordered`)
- Add linked rows with explicit `<a href="...">` content
- Add and update inline rich text safely (`add-rich`, `set-rich-text`)
- Mark rows done/undone by id
- Delete rows by id
- Managed backup history with retention (default), plus optional inline `.bak`

## Requirements

- macOS
- Swift 6+

## Quick Start (Recommended for Codex Users)

If you want the fastest path to using the `bike-outline` skill:

```bash
# 1) Install bike-tool with Homebrew
brew tap rbarooah/bike-tool https://github.com/rbarooah/bike-tool
brew install bike-tool

# 2) Install the bike-outline skill into your Codex skills directory
TAP_REPO="$(brew --repository rbarooah/bike-tool)"
SKILL_DIR="${CODEX_HOME:-$HOME/.codex}/skills/bike-outline"
mkdir -p "$SKILL_DIR/agents"
cp "$TAP_REPO/skills/bike-outline/SKILL.md" "$SKILL_DIR/SKILL.md"
cp "$TAP_REPO/skills/bike-outline/agents/openai.yaml" "$SKILL_DIR/agents/openai.yaml"

# 3) Verify the CLI is installed
bike-tool help
```

## Quick Start (Recommended for Claude Code Users)

If you want the fastest path in Claude Code:

```bash
# 1) Install bike-tool with Homebrew
brew tap rbarooah/bike-tool https://github.com/rbarooah/bike-tool
brew install bike-tool

# 2) Add project instructions for Claude Code
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

# 3) Verify the CLI is installed
bike-tool help
```

Claude-specific notes: [docs/CLAUDE_CODE.md](docs/CLAUDE_CODE.md).

## Install (Other Methods)

From source:

```bash
cd /path/to/bike-tool
scripts/install.sh
```

With Homebrew:

```bash
brew tap rbarooah/bike-tool https://github.com/rbarooah/bike-tool
brew install bike-tool
```

Default install location:

- `~/.codex/bin/bike-tool`

If `CODEX_HOME` is set, the installer uses `$CODEX_HOME/bin/bike-tool`.

Homebrew notes (formula update workflow, release guidance): [docs/HOMEBREW.md](docs/HOMEBREW.md).

## Codex Skill

This repo includes a companion skill at `skills/bike-outline/`.

If you already followed **Quick Start (Recommended for Codex Users)** above, this is already done.

To install/update that skill in your local Codex skills directory:

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills/bike-outline/agents"
cp skills/bike-outline/SKILL.md "${CODEX_HOME:-$HOME/.codex}/skills/bike-outline/SKILL.md"
cp skills/bike-outline/agents/openai.yaml "${CODEX_HOME:-$HOME/.codex}/skills/bike-outline/agents/openai.yaml"
```

## Usage

```bash
bike-tool help
bike-tool validate "/absolute/path/file.bike"
bike-tool list "/absolute/path/file.bike"
bike-tool to-json "/absolute/path/file.bike"
bike-tool to-json "/absolute/path/file.bike" --rich-text
bike-tool add "/absolute/path/file.bike" --text "Normal body row" --type item
bike-tool add "/absolute/path/file.bike" --text "New task" --type task
bike-tool add "/absolute/path/file.bike" --text "Top row" --type heading --at-start
bike-tool add "/absolute/path/file.bike" --text "Quoted row" --type quote
bike-tool add "/absolute/path/file.bike" --text "Before row" --type item --before-id abc123
bike-tool add "/absolute/path/file.bike" --text "After row" --type item --after-id abc123
bike-tool add-link "/absolute/path/file.bike" --href "file:///absolute/path/target.bike" --text "target.bike" --type item
bike-tool add-rich "/absolute/path/file.bike" --rich-text "<strong>Bold</strong> and <a href=\"file:///absolute/path/ref.bike\">ref</a>" --type item
bike-tool set-rich-text "/absolute/path/file.bike" --id abc123 --rich-text "<mark>Updated</mark> text"
bike-tool done "/absolute/path/file.bike" --id abc123 --write-mode atomic
bike-tool undone "/absolute/path/file.bike" --id abc123 --write-mode inplace
bike-tool delete "/absolute/path/file.bike" --id abc123
bike-tool done "/absolute/path/file.bike" --id abc123 --backup-mode inline
bike-tool backup list "/absolute/path/file.bike"
bike-tool backup prune --keep 10 --days 30
bike-tool backup restore "/absolute/path/file.bike" --id "<backup-id>"
```

## JSON Output Notes

- Includes `attributes` for each row to preserve custom metadata (for example, `indent`).
- `--rich-text` includes paragraph inner XML in `richText`.
- `text` always provides plain text.
- Rows with `<a href="...">` markup include a parsed `links` array (`href`, `text`, optional `title`, optional `rel`).
- `add` and `add-link` default to `item` (untyped body rows); use `note` for annotations.

## Safety Model

On write commands (`add`, `add-link`, `add-rich`, `set-rich-text`, `done`, `undone`, `delete`), the tool:

1. Reads and updates XML in-memory.
2. Creates a backup according to `--backup-mode` (default: `managed`).
3. Writes updated content using coordinated writes by default (`NSFileCoordinator`).

Backup modes:

- `managed` (default): stores backups under `$CODEX_HOME/state/bike-tool/backups` (or `~/.codex/state/bike-tool/backups`) with automatic retention pruning.
- `inline`: creates/replaces `<file>.bak` in the source directory.
- `none`: skips backup creation.

Add placement flags (`bike-tool add`, mutually exclusive):

- `--before-id <row-id>`: insert before target row (parent inferred from target).
- `--after-id <row-id>`: insert after target row (parent inferred from target).
- `--at-start`: insert as first sibling (or first child with `--parent-id`).
- `--at-end`: insert as last sibling (default behavior).

Optional write modes:

- `coordinated` (default): `NSFileCoordinator` + atomic write
- `atomic`: non-coordinated atomic write
- `inplace`: non-coordinated direct write

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

Row type semantics and planned/default behavior are defined in [docs/TYPE_POLICY.md](docs/TYPE_POLICY.md).
Rich text write-command design and safety rules are defined in [docs/RICH_TEXT_EDITING.md](docs/RICH_TEXT_EDITING.md).

## Agent Instructions

For Codex-oriented repo guidance (workflow, safety constraints, command mapping), see [AGENTS.md](AGENTS.md).
