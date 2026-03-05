# Data Preservation Guarantees

`BikeToolCore` is designed to preserve document fidelity while performing structured mutations.

## Preserved by default

- Unknown row attributes (`li` attributes not explicitly modeled).
- Inline paragraph markup through `richText` parsing/serialization.
- Existing row hierarchy and untouched row content.
- Namespace-aware Bike XHTML structure.

## Write behavior

- Backup policy is explicit via ``BackupMode``:
  - `.managed` keeps retained backups under the managed backup directory.
  - `.inline` creates/replaces sidecar `<file>.bak`.
  - `.none` skips backup creation.
- Write strategy is explicit via ``WriteMode``:
  - `.coordinated` uses `NSFileCoordinator` and atomic write.
  - `.atomic` uses non-coordinated atomic write.
  - `.inplace` uses non-coordinated direct write.

## Practical guidance

- Use absolute paths for source documents.
- Prefer `.managed` backups for long-running agents.
- Validate post-write behavior in tests for any new mutation workflow.
