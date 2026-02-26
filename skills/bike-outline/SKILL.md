---
name: bike-outline
description: Read, summarize, and safely edit Bike.app .bike outline files using the local bike-tool CLI. Use when a user asks to inspect headings/tasks, export Bike outlines to JSON, or make structured edits like add row, mark done, and mark undone while preserving XML structure and row metadata.
---

# Bike Outline

Use this skill to work with `.bike` files through the installed CLI instead of ad-hoc XML edits.

## Purpose

Use Bike outlines as structured planning artifacts:

- `heading`: section/grouping focus
- `task`: actionable work item
- `note` or untyped `item`: supporting context, prompts, rationale, or placeholders

Prioritize task-state clarity while preserving document fidelity.

## When To Use

Use this skill when a request involves `.bike` files, including:

- finding what is next
- summarizing outstanding work
- extracting machine-readable structure
- adding tasks/notes/headings
- deleting rows
- marking tasks done/undone

## When Not To Use

Do not use this workflow for non-`.bike` formats or when the user only wants prose brainstorming without file inspection/editing.

## Tool Location

Prefer this executable path:

- `~/.codex/bin/bike-tool` (or `$CODEX_HOME/bin/bike-tool`)

If unavailable, build/install from:

- this repository root
- install command: `scripts/install.sh`

## Core Rules

- Always preserve unknown row attributes (for example `indent`).
- Always preserve inline rich paragraph markup (`strong`, `span`, `em`, `mark`, `code`).
- Treat missing `data-type` as generic `item`; do not coerce type unless asked.
- Use absolute file paths for all commands.

## Enforcement Policy

- Never directly edit `.bike` files with generic file editors or patch tools.
- Never perform ad-hoc XML surgery on `.bike` content.
- Use `bike-tool` for all `.bike` mutations.
- If a requested `.bike` change is not supported by `bike-tool`, refuse direct edit and state that the tool must be extended first.
- If explicitly asked to "edit the XML directly", refuse and restate the `bike-tool`-only policy.

## Next Task Rule

If the user asks for "next task" and does not define a custom policy:

1. Traverse in outline order.
2. Select the first row that is both:
   - type `task`
   - not done (`[ ]`)
3. Ignore `note`, `heading`, and generic `item` rows for "next task" selection.

If no open task exists, report that explicitly.

## Safe Edit Policy

1. Validate input file before editing.
2. Read structure (`list`) or machine-readable data (`to-json`) as needed.
3. Make edits via CLI commands (`add`, `done`, `undone`).
4. Re-validate after edits.
5. Confirm backup creation:
   - default: verify `bike-tool backup list "<file>"` includes a new managed backup
   - if `--backup-mode inline` was requested: verify `<file>.bak` exists

## Commands

```bash
bike-tool validate "/absolute/path/file.bike"
bike-tool list "/absolute/path/file.bike"
bike-tool to-json "/absolute/path/file.bike"
bike-tool to-json "/absolute/path/file.bike" --rich-text
bike-tool add "/absolute/path/file.bike" --text "New row" --type task
bike-tool add "/absolute/path/file.bike" --text "Child row" --type note --parent-id abc123
bike-tool done "/absolute/path/file.bike" --id abc123
bike-tool undone "/absolute/path/file.bike" --id abc123
bike-tool delete "/absolute/path/file.bike" --id abc123
bike-tool done "/absolute/path/file.bike" --id abc123 --write-mode atomic
bike-tool done "/absolute/path/file.bike" --id abc123 --backup-mode inline
bike-tool backup list "/absolute/path/file.bike"
bike-tool backup prune "/absolute/path/file.bike" --keep 10 --days 30
bike-tool backup restore "/absolute/path/file.bike" --id "<backup-id>"
```

## Notes

- `to-json` includes each row's `attributes` map, so custom attributes are preserved in output.
- Use `--rich-text` when inline formatting inside `<p>` matters.
- Some rows may have no `data-type`; treat them as generic `item` rows.
- Write commands default to `--write-mode coordinated` and support `atomic`/`inplace` for troubleshooting.
- Write commands default to `--backup-mode managed` (stored outside the source folder); use `--backup-mode inline` only when sidecar `.bak` is explicitly requested.
