import Foundation

/// Persistence strategy used when saving updates back to the `.bike` file.
public enum WriteMode: String {
    /// Use `NSFileCoordinator` and atomic replacement for coordinated writes.
    case coordinated
    /// Write atomically without file coordination.
    case atomic
    /// Write directly in-place without atomic replacement.
    case inplace
}

/// Backup policy used before write operations.
public enum BackupMode: String {
    /// Store backups in the managed backup directory with retention pruning.
    case managed
    /// Create or replace a sidecar `<file>.bak` file next to the source file.
    case inline
    /// Skip backup creation.
    case none
}

/// Placement for insertion operations when adding a new row.
public enum AddPlacement {
    /// Insert as the last row in the target list.
    case atEnd
    /// Insert as the first row in the target list.
    case atStart
    /// Insert immediately before the row with the provided identifier.
    case before(id: String)
    /// Insert immediately after the row with the provided identifier.
    case after(id: String)
}

/// Parsed Bike outline row with plain/rich content, metadata, and children.
public struct Row {
    /// Stable Bike row identifier (`li/@id`).
    public let id: String
    /// Bike row type (`li/@data-type`), or `nil` for untyped body rows.
    public let type: String?
    /// Plain-text paragraph content.
    public let text: String
    /// Paragraph inner XML used for inline rich text fidelity.
    public let richText: String
    /// Parsed anchors found in paragraph content.
    public let links: [RowLink]
    /// Completion timestamp (`li/@data-done`) when present.
    public let done: String?
    /// Raw row attributes, including unknown/custom metadata.
    public let attributes: [String: String]
    /// Child outline rows.
    public let children: [Row]

    /// Creates a row value.
    /// - Parameters:
    ///   - id: Bike row identifier.
    ///   - type: Optional row type.
    ///   - text: Plain-text paragraph content.
    ///   - richText: Paragraph inner XML.
    ///   - links: Parsed links from paragraph content.
    ///   - done: Optional completion timestamp.
    ///   - attributes: Raw row attributes.
    ///   - children: Child rows.
    public init(
        id: String,
        type: String?,
        text: String,
        richText: String,
        links: [RowLink],
        done: String?,
        attributes: [String: String],
        children: [Row]
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.richText = richText
        self.links = links
        self.done = done
        self.attributes = attributes
        self.children = children
    }
}

/// Parsed anchor metadata from a row paragraph.
public struct RowLink: Encodable {
    /// Destination URI from the anchor `href`.
    public let href: String
    /// Link label text.
    public let text: String
    /// Optional anchor `title` attribute.
    public let title: String?
    /// Optional anchor `rel` attribute.
    public let rel: String?

    /// Creates link metadata for a row anchor.
    /// - Parameters:
    ///   - href: Link destination URI.
    ///   - text: Link label text.
    ///   - title: Optional title attribute.
    ///   - rel: Optional relation attribute.
    public init(href: String, text: String, title: String?, rel: String?) {
        self.href = href
        self.text = text
        self.title = title
        self.rel = rel
    }
}
