# Getting Started

Import `BikeToolCore`, load a document, make a structured edit, then save:

```swift
import BikeToolCore

let bike = try BikeDocument(path: "/absolute/path/outline.bike")
let rows = try bike.readRows()

_ = try bike.addLinkRow(
    href: "file:///absolute/path/reference.bike",
    text: "reference.bike",
    type: "item",
    parentID: nil
)

try bike.saveWithBackup(writeMode: .coordinated, backupMode: .managed)
print("Top-level rows: \(rows.count)")
```

## Next Steps

- For insertion semantics, see <doc:Editing-Workflows>.
- For failure handling, see <doc:Error-Handling>.
