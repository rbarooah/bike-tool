# Error Handling

Core operations can throw either ``BikeToolCoreError`` (validation/domain failures) or Foundation file/XML errors.

## Recommended pattern

```swift
do {
    let bike = try BikeDocument(path: path)
    _ = try bike.addRow(text: "Note", type: "item", parentID: nil)
    try bike.saveWithBackup(writeMode: .coordinated, backupMode: .managed)
} catch let error as BikeToolCoreError {
    // User-safe message for expected domain errors.
    print("BikeToolCore error: \(error.message)")
} catch {
    // Unexpected infrastructure/file-system errors.
    print("Unexpected failure: \(error)")
}
```

## Common error cases

- Missing source file on initialization.
- Invalid Bike structure (`/html/body/ul` missing).
- Target/parent row id not found for placement operations.
- Rich-text fragment that is malformed or uses unsupported tags/attributes.
- Backup/write failures from file coordination or file system operations.
