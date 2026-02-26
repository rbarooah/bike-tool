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
- marking tasks done/undone

## When Not To Use

Do not use this workflow for non-`.bike` formats or when the user only wants prose brainstorming without file inspection/editing.

## Tool Location

Prefer this executable path:

- `/Users/robin/.codex/bin/bike-tool`

If unavailable, build/install from:

- `/Users/robin/src/bike-tool`
- install command: `scripts/install.sh`

## Core Rules

- Always preserve unknown row attributes (for example `indent`).
- Always preserve inline rich paragraph markup (`strong`, `span`, `em`, `mark`, `code`).
- Treat missing `data-type` as generic `item`; do not coerce type unless asked.
- Use absolute file paths for all commands.

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
5. Confirm the `.bak` backup file exists after write operations.

## Commands

```bash
/Users/robin/.codex/bin/bike-tool validate "/absolute/path/file.bike"
/Users/robin/.codex/bin/bike-tool list "/absolute/path/file.bike"
/Users/robin/.codex/bin/bike-tool to-json "/absolute/path/file.bike"
/Users/robin/.codex/bin/bike-tool to-json "/absolute/path/file.bike" --rich-text
/Users/robin/.codex/bin/bike-tool add "/absolute/path/file.bike" --text "New row" --type task
/Users/robin/.codex/bin/bike-tool add "/absolute/path/file.bike" --text "Child row" --type note --parent-id abc123
/Users/robin/.codex/bin/bike-tool done "/absolute/path/file.bike" --id abc123
/Users/robin/.codex/bin/bike-tool undone "/absolute/path/file.bike" --id abc123
```

## Notes

- `to-json` includes each row's `attributes` map, so custom attributes are preserved in output.
- Use `--rich-text` when inline formatting inside `<p>` matters.
- Some rows may have no `data-type`; treat them as generic `item` rows.
