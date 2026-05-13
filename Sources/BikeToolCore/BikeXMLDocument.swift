import Foundation

final class BikeXMLDocument {
    private(set) var root: BikeXMLElement

    init(data: Data) throws {
        let parserDelegate = BikeXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = parserDelegate

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "Unable to parse XML."
            throw BikeToolCoreError(message: message)
        }

        guard let root = parserDelegate.rootElement else {
            throw BikeToolCoreError(message: "Invalid Bike structure. Missing XML root element.")
        }

        self.root = root
    }

    init(root: BikeXMLElement) {
        self.root = root
    }

    func elements(named name: String) -> [BikeXMLElement] {
        root.descendantsAndSelf().filter { $0.isNamed(name) }
    }

    func serializedData() throws -> Data {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + root.xmlString()
        guard let data = xml.data(using: .utf8) else {
            throw BikeToolCoreError(message: "Unable to encode XML output as UTF-8.")
        }
        return data
    }
}

final class BikeXMLElement {
    let name: String
    private(set) var attributeNames: [String]
    private var attributeValues: [String: String]
    weak var parent: BikeXMLElement?
    var children: [BikeXMLNode]

    init(
        name: String,
        attributes: [String: String] = [:],
        attributeNames: [String]? = nil,
        children: [BikeXMLNode] = []
    ) {
        self.name = name
        self.attributeValues = attributes
        self.attributeNames = attributeNames ?? attributes.keys.sorted()
        self.children = []
        for child in children {
            addChild(child)
        }
    }

    func attribute(forName name: String) -> String? {
        attributeValues[name]
    }

    func setAttribute(name: String, value: String) {
        if attributeValues[name] == nil {
            attributeNames.append(name)
        }
        attributeValues[name] = value
    }

    func removeAttribute(forName name: String) {
        attributeValues[name] = nil
        attributeNames.removeAll { $0 == name }
    }

    var attributes: [String: String] {
        attributeValues
    }

    var stringValue: String {
        children.map(\.stringValue).joined()
    }

    func addChild(_ child: BikeXMLNode) {
        child.detach()
        child.parent = self
        child.element?.parent = self
        children.append(child)
    }

    func insertChild(_ child: BikeXMLNode, at index: Int) {
        child.detach()
        child.parent = self
        child.element?.parent = self
        children.insert(child, at: max(0, min(index, children.count)))
    }

    func removeChild(_ child: BikeXMLNode) {
        children.removeAll { $0 === child }
        child.parent = nil
        child.element?.parent = nil
    }

    func detach() {
        guard let parent else { return }
        for child in parent.children where child.element === self {
            parent.removeChild(child)
            return
        }
        self.parent = nil
    }

    func firstChildElement(named expectedName: String) -> BikeXMLElement? {
        children.compactMap(\.element).first { $0.isNamed(expectedName) }
    }

    func descendantsAndSelf() -> [BikeXMLElement] {
        var elements = [self]
        for child in children {
            if let element = child.element {
                elements.append(contentsOf: element.descendantsAndSelf())
            }
        }
        return elements
    }

    func isNamed(_ expectedName: String) -> Bool {
        name == expectedName || name.split(separator: ":").last == Substring(expectedName)
    }

    func clone() -> BikeXMLElement {
        let cloned = BikeXMLElement(
            name: name,
            attributes: attributeValues,
            attributeNames: attributeNames
        )
        for child in children {
            cloned.addChild(child.clone())
        }
        return cloned
    }

    func xmlString() -> String {
        let attributes = attributeNames
            .compactMap { name -> String? in
                guard let value = attributeValues[name] else { return nil }
                return "\(name)=\"\(Self.escapeAttribute(value))\""
            }
            .joined(separator: " ")
        let startTag = attributes.isEmpty ? "<\(name)" : "<\(name) \(attributes)"

        if children.isEmpty {
            return "\(startTag)/>"
        }

        return "\(startTag)>\(children.map { $0.xmlString() }.joined())</\(name)>"
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

final class BikeXMLNode {
    enum Storage {
        case element(BikeXMLElement)
        case text(String)
    }

    var storage: Storage
    weak var parent: BikeXMLElement?

    init(element: BikeXMLElement) {
        self.storage = .element(element)
    }

    init(text: String) {
        self.storage = .text(text)
    }

    var element: BikeXMLElement? {
        if case .element(let element) = storage {
            return element
        }
        return nil
    }

    var stringValue: String {
        switch storage {
        case .element(let element):
            element.stringValue
        case .text(let text):
            text
        }
    }

    func detach() {
        parent?.removeChild(self)
        parent = nil
        element?.parent = nil
    }

    func clone() -> BikeXMLNode {
        switch storage {
        case .element(let element):
            BikeXMLNode(element: element.clone())
        case .text(let text):
            BikeXMLNode(text: text)
        }
    }

    func xmlString() -> String {
        switch storage {
        case .element(let element):
            element.xmlString()
        case .text(let text):
            Self.escapeText(text)
        }
    }

    private static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private final class BikeXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var rootElement: BikeXMLElement?
    private var stack: [BikeXMLElement] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = BikeXMLElement(
            name: qName ?? elementName,
            attributes: attributeDict
        )
        if let parent = stack.last {
            parent.addChild(BikeXMLNode(element: element))
        } else {
            rootElement = element
        }
        stack.append(element)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.addChild(BikeXMLNode(text: string))
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        stack.last?.addChild(BikeXMLNode(text: string))
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        _ = stack.popLast()
    }
}
