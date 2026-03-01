# Core Module Split Spec

This spec defines how to split `bike-tool` into:

- a reusable in-process Swift library module
- a thin CLI module that depends on that library

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

## Proposed Package Layout

Current:

- `Sources/bike-tool/` (CLI + core mixed)
- `Tests/bike-toolTests/`

Target:

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
  - most current logic tests move here
- `Tests/bike-toolTests/`
  - CLI integration/smoke/error-message tests

## Public Core API (Initial)

Initial public symbols should cover current CLI capabilities:

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
- error type(s) currently represented by `CLIError` should be renamed/split:
  - core-level error type (for library consumers)
  - CLI-only user-facing usage errors

Notes:

- Core API should avoid direct dependency on `CommandLine`.
- CLI remains responsible for user-facing usage text and flag validation messaging.

## Module Boundary Rules

- `BikeToolCore` must not import or depend on CLI parsing/output helpers.
- CLI target can depend on `BikeToolCore`, never the reverse.
- JSON encoding helper types may live in CLI unless needed by library consumers.

## Error Model

- Introduce `BikeToolCoreError` (or similar) for library-level failures:
  - file not found
  - invalid structure
  - invalid mutation target
  - invalid rich-text fragment
  - serialization/write/backup failure
- CLI maps these to readable terminal errors and exit codes.

## Concurrency and Semantics

- Keep value-semantics models (`Row`, `RowLink`) as structs.
- Preserve current write coordination model (`NSFileCoordinator`) behind core APIs.
- No behavior change in backup modes and write modes.

## Migration Plan

Phase 1: Target setup

- Add `BikeToolCore` library target to `Package.swift`.
- Add `BikeToolCoreTests` target.

Phase 2: Mechanical move

- Move core data types and logic from `Sources/bike-tool/bike_tool.swift` into `Sources/BikeToolCore/` with minimal refactor.
- Keep CLI compiling by importing `BikeToolCore`.

Phase 3: Error/API cleanup

- Introduce core error type.
- Limit public API surface intentionally.

Phase 4: Test split

- Move document/mutation/backup/rich-text tests to `BikeToolCoreTests`.
- Keep command parsing/help/CLI integration tests in `bike-toolTests`.

Phase 5: Documentation

- Update README and development docs with library usage examples.
- Keep CLI examples unchanged.

## Acceptance Criteria

- `swift build` succeeds with two targets (`BikeToolCore`, `bike-tool`).
- `swift test` passes with split test targets.
- CLI behavior matches current release for all existing commands and flags.
- Library can be imported by another local Swift package and run in-process operations on a `.bike` file.

## Risks and Mitigations

- Risk: hidden coupling between CLI parsing and core mutation logic.
  - Mitigation: move code mechanically first, then refactor.
- Risk: error-message regressions.
  - Mitigation: keep CLI usage/error snapshot tests.
- Risk: accidental behavior change in XML serialization.
  - Mitigation: preserve existing regression fixtures and rich-text tests.
