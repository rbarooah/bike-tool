# AGENTS.md

## Project intent

`bike-tool` is a Swift CLI for reading and safely editing Bike.app `.bike` outline files.

Use this project when requests involve:

- validating `.bike` files
- listing/summarizing rows and tasks
- exporting `.bike` structure to JSON
- structured edits (`add`, `done`, `undone`, `delete`)

## First steps for Codex

1. Read `README.md`.
2. If needed, read `docs/DEVELOPMENT.md`.
3. Prefer running commands from the repository root.

## Core commands

```bash
cd /path/to/bike-tool
swift build
swift test
scripts/install.sh
```

Installed binary path:

- `~/.codex/bin/bike-tool`
- or `$CODEX_HOME/bin/bike-tool` when `CODEX_HOME` is set

## Companion skill

This repo includes a Codex skill at:

- `skills/bike-outline/`

Install/update it with:

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills/bike-outline/agents"
cp skills/bike-outline/SKILL.md "${CODEX_HOME:-$HOME/.codex}/skills/bike-outline/SKILL.md"
cp skills/bike-outline/agents/openai.yaml "${CODEX_HOME:-$HOME/.codex}/skills/bike-outline/agents/openai.yaml"
```

If `~/.codex/bin/bike-tool` (or `$CODEX_HOME/bin/bike-tool`) is missing, run `scripts/install.sh` before using the skill.

## Safety constraints

- Do not hand-edit `.bike` XML directly for requested content changes.
- Use `bike-tool` for all mutations.
- Preserve unknown row attributes and inline rich-text markup.
- Use absolute paths for `.bike` command arguments.
- Default backup mode is managed (no sidecar file): backups go to `$CODEX_HOME/state/bike-tool/backups` or `~/.codex/state/bike-tool/backups`.
- Use `--backup-mode inline` only when a sidecar `<file>.bak` is explicitly requested.

## Typical user requests and mapping

- "What is next?" -> `bike-tool list` or `bike-tool to-json`, then pick first open `task` in outline order.
- "Summarize this outline" -> `bike-tool to-json` (optionally `--rich-text`) and summarize rows.
- "Mark task done/undone" -> `bike-tool done` / `bike-tool undone`.
- "Add a task/note/heading" -> `bike-tool add`.
- "Delete a row" -> `bike-tool delete`.
