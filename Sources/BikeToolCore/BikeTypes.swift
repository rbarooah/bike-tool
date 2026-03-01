import Foundation

public enum WriteMode: String {
    case coordinated
    case atomic
    case inplace
}

public enum BackupMode: String {
    case managed
    case inline
    case none
}

public enum AddPlacement {
    case atEnd
    case atStart
    case before(id: String)
    case after(id: String)
}

public struct Row {
    public let id: String
    public let type: String?
    public let text: String
    public let richText: String
    public let links: [RowLink]
    public let done: String?
    public let attributes: [String: String]
    public let children: [Row]

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

public struct RowLink: Encodable {
    public let href: String
    public let text: String
    public let title: String?
    public let rel: String?

    public init(href: String, text: String, title: String?, rel: String?) {
        self.href = href
        self.text = text
        self.title = title
        self.rel = rel
    }
}
