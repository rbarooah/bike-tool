# bike-tool

A Swift CLI for reading and safely editing [Bike.app](https://www.hogbaysoftware.com/bike/) `.bike` outline files.

`bike-tool` is designed for deterministic command-line edits instead of ad-hoc XML manipulation.

## Features

- Validate `.bike` XML structure
- List outline rows with type, id, and done state
- Export rows to JSON (`--rich-text` optional)
- Add rows (`task`, `note`, `heading`)
- Mark rows done/undone by id
- Delete rows by id
- Managed backup history with retention (default), plus optional inline `.bak`

## Requirements

- macOS
- Swift 6+

## Install

From source:

```bash
cd /path/to/bike-tool
scripts/install.sh
```

Default install location:

- `~/.codex/bin/bike-tool`

If `CODEX_HOME` is set, the installer uses `$CODEX_HOME/bin/bike-tool`.

## Codex Skill

This repo includes a companion skill at `skills/bike-outline/`.

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
bike-tool add "/absolute/path/file.bike" --text "New task" --type task
bike-tool add "/absolute/path/file.bike" --text "Child note" --type note --parent-id abc123 --write-mode coordinated
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

## Safety Model

On write commands (`add`, `done`, `undone`, `delete`), the tool:

1. Reads and updates XML in-memory.
2. Creates a backup according to `--backup-mode` (default: `managed`).
3. Writes updated content using coordinated writes by default (`NSFileCoordinator`).

Backup modes:

- `managed` (default): stores backups under `$CODEX_HOME/state/bike-tool/backups` (or `~/.codex/state/bike-tool/backups`) with automatic retention pruning.
- `inline`: creates/replaces `<file>.bak` in the source directory.
- `none`: skips backup creation.

Optional write modes:

- `coordinated` (default): `NSFileCoordinator` + atomic write
- `atomic`: non-coordinated atomic write
- `inplace`: non-coordinated direct write

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Agent Instructions

For Codex-oriented repo guidance (workflow, safety constraints, command mapping), see [AGENTS.md](AGENTS.md).
