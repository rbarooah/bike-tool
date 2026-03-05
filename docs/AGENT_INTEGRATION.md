# BikeToolCore Agent Integration

This guide is the shortest path for agents integrating `BikeToolCore` in another Swift codebase.

## 1) Add the package and import

Add the package dependency, then import:

```swift
import BikeToolCore
```

## 2) Use the canonical workflow

```swift
let bike = try BikeDocument(path: "/absolute/path/file.bike")
let rows = try bike.readRows()

_ = try bike.addRow(text: "Body text", type: "item", parentID: nil)
_ = try bike.addLinkRow(href: "file:///absolute/path/ref.bike", text: "ref.bike", type: "item", parentID: nil)

try bike.saveWithBackup(writeMode: .coordinated, backupMode: .managed)
```

## 3) Handle errors predictably

- Catch `BikeToolCoreError` first for expected domain/validation failures.
- Handle remaining errors as infrastructure failures (file system, XML parser, coordination).

## 4) Respect data-fidelity guarantees

- Do not hand-edit `.bike` XML when `BikeToolCore` APIs can express the change.
- Prefer `addLinkRow` for file references rather than plain text paths.
- Use `addRichRow` / `setRichText` for inline styling.
- Keep backups enabled (`.managed`) for agent workflows unless explicitly overridden.

## 5) Validate changes

- Run `swift test` in the integrating project.
- Confirm the edited file can be re-read by `BikeDocument(path:)`.
- Verify links and rich text in parsed `Row` values when those features are used.

## Primary references

- DocC catalog root: `Sources/BikeToolCore/BikeToolCore.docc/BikeToolCore.md`
- Public API source docs: `Sources/BikeToolCore/*.swift`
- Core architecture notes: [CORE_MODULE_SPLIT.md](CORE_MODULE_SPLIT.md)
