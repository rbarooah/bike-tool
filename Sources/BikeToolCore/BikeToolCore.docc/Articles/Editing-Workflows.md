# Editing Workflows

Use ``BikeDocument`` for structured operations instead of direct XML manipulation.

## Read and inspect outline rows

```swift
let bike = try BikeDocument(path: "/absolute/path/outline.bike")
let rows = try bike.readRows()
```

`Row` values preserve row attributes, inline rich text, link extraction, and children.

## Add plain rows

```swift
_ = try bike.addRow(
    text: "Daily summary",
    type: "item",
    parentID: nil,
    placement: .atEnd
)
```

## Add linked rows

```swift
_ = try bike.addLinkRow(
    href: "file:///absolute/path/spec.bike",
    text: "spec.bike",
    type: "item",
    parentID: nil,
    placement: .atEnd
)
```

## Add or update rich text

```swift
_ = try bike.addRichRow(
    richText: "<strong>Status:</strong> On track",
    type: "item",
    parentID: nil,
    placement: .atEnd
)

_ = try bike.setRichText(
    id: "abc123",
    richText: "Updated <mark>priority</mark>"
)
```

## Mark done / undone and delete

```swift
_ = try bike.setDone(id: "abc123", markDone: true)
_ = try bike.setDone(id: "abc123", markDone: false)
_ = try bike.deleteRow(id: "abc123")
```

## Persist changes

```swift
try bike.saveWithBackup(writeMode: .coordinated, backupMode: .managed)
```
