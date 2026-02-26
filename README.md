# bike-tool

A Swift CLI for reading and safely editing [Bike.app](https://www.hogbaysoftware.com/bike/) `.bike` outline files.

`bike-tool` is designed for deterministic command-line edits instead of ad-hoc XML manipulation.

## Features

- Validate `.bike` XML structure
- List outline rows with type, id, and done state
- Export rows to JSON (`--rich-text` optional)
- Add rows (`task`, `note`, `heading`)
- Mark rows done/undone by id
- Create a `.bak` backup before every write

## Requirements

- macOS
- Swift 6+

## Install

From source:

```bash
cd /Users/robin/Desktop/bike-tool
scripts/install.sh
```

Default install location:

- `/Users/robin/.codex/bin/bike-tool`

If `CODEX_HOME` is set, the installer uses `$CODEX_HOME/bin/bike-tool`.

## Codex Skill

This repo includes a companion skill at `skills/bike-outline/`.

To install/update that skill in your local Codex skills directory:

```bash
mkdir -p /Users/robin/.codex/skills/bike-outline/agents
cp /Users/robin/Desktop/bike-tool/skills/bike-outline/SKILL.md /Users/robin/.codex/skills/bike-outline/SKILL.md
cp /Users/robin/Desktop/bike-tool/skills/bike-outline/agents/openai.yaml /Users/robin/.codex/skills/bike-outline/agents/openai.yaml
```

## Usage

```bash
bike-tool help
bike-tool validate "/absolute/path/file.bike"
bike-tool list "/absolute/path/file.bike"
bike-tool to-json "/absolute/path/file.bike"
bike-tool to-json "/absolute/path/file.bike" --rich-text
bike-tool add "/absolute/path/file.bike" --text "New task" --type task
bike-tool add "/absolute/path/file.bike" --text "Child note" --type note --parent-id abc123
bike-tool done "/absolute/path/file.bike" --id abc123
bike-tool undone "/absolute/path/file.bike" --id abc123
```

## JSON Output Notes

- Includes `attributes` for each row to preserve custom metadata (for example, `indent`).
- `--rich-text` includes paragraph inner XML in `richText`.
- `text` always provides plain text.

## Safety Model

On write commands (`add`, `done`, `undone`), the tool:

1. Reads and updates XML in-memory.
2. Copies the source file to `<file>.bak`.
3. Writes updated content atomically.

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
