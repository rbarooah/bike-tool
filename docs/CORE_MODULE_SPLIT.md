# Core Module Split

Status: implemented on `main` (released in Homebrew `0.2.3`).

This document describes the current split of `bike-tool` into:

- a reusable in-process Swift library module (`BikeToolCore`)
- a thin CLI module (`bike-tool`) that depends on that library

## Motivation

- Enable other Swift projects and agents to work with `.bike` files in-process.
- Keep business logic (parse, mutate, validate, backup/write) outside CLI argument handling.
- Improve testability and reduce duplication.

## Goals

- Add a public library target with stable, documented APIs.
- Keep CLI behavior and command surface backward compatible.
- Move core tests to library-level unit tests.
- Preserve strict safety constraints:
  - no ad-hoc XML edits outside controlled APIs
  - preserve unknown row attributes
  - preserve inline rich text markup

## Non-Goals

- No immediate redesign of output formatting.
- No breaking CLI command/flag changes.
- No dependency on external XML libraries.

## Package Layout (Current)

- `Sources/BikeToolCore/`
  - document model, parser, mutation APIs
  - backup manager
  - write strategies
  - shared errors/types
- `Sources/bike-tool/`
  - command routing
  - flag parsing
  - command output formatting
  - maps CLI args to `BikeToolCore` APIs
- `Tests/BikeToolCoreTests/`
  - core document/mutation/backup/rich-text tests
- `Tests/bike-toolTests/`
  - CLI command-routing and integration tests

## Public Core API (Current)

Public symbols currently exposed by `BikeToolCore`:

- `BikeDocument`
  - `init(path:)`
  - `readRows()`
  - `addRow(...)`
  - `addLinkRow(...)`
  - `addRichRow(...)`
  - `setRichText(...)`
  - `setDone(...)`
  - `deleteRow(...)`
  - `saveWithBackup(...)`
- `Row`, `RowLink`
- `WriteMode`, `BackupMode`, `AddPlacement`
- `BackupManager` APIs currently used by CLI
- `BikeToolCoreError` for library-level failures

CLI-only usage/parsing errors remain in the CLI target as `CLIError`.

## Module Boundary Rules

- `BikeToolCore` must not import or depend on CLI parsing/output helpers.
- CLI target can depend on `BikeToolCore`, never the reverse.
- JSON encoding helper types may live in CLI unless needed by library consumers.

## Error Model

`BikeToolCoreError` is used for library-level failures:
  - file not found
  - invalid structure
  - invalid mutation target
  - invalid rich-text fragment
  - serialization/write/backup failure
- The CLI maps these to user-facing terminal output and non-zero exit status.

## Concurrency and Semantics

- Keep value-semantics models (`Row`, `RowLink`) as structs.
- Preserve current write coordination model (`NSFileCoordinator`) behind core APIs.
- No behavior change in backup modes and write modes.

## Completed Migration Phases

- Phase 1: target setup
  - commit: `e62af5d`
  - added `BikeToolCore` library target and wired CLI dependency
- Phase 2: mechanical move
  - commit: `8ea8b05`
  - moved core document/types/backup logic into `Sources/BikeToolCore/`
- Phase 3: error/API cleanup
  - commit: `8ea8b05`
  - introduced `BikeToolCoreError` and separated CLI/core error roles
- Phase 4: test split
  - commit: `71d5c44`
  - added `BikeToolCoreTests` and updated test-target dependencies
- Phase 5: documentation
  - commit: `e2d88d2`
  - updated README and development docs for library consumption

## Acceptance Criteria

- `swift build` succeeds with two targets (`BikeToolCore`, `bike-tool`).
- `swift test` passes with split test targets.
- CLI behavior matches current release for all existing commands and flags.
- Library can be imported by another local Swift package and run in-process operations on a `.bike` file.

All acceptance criteria are currently met.

## Risks and Mitigations

- Risk: hidden coupling between CLI parsing and core mutation logic.
  - Mitigation: move code mechanically first, then refactor.
- Risk: error-message regressions.
  - Mitigation: keep CLI usage/error snapshot tests.
- Risk: accidental behavior change in XML serialization.
  - Mitigation: preserve existing regression fixtures and rich-text tests.
