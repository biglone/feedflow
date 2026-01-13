import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var feedFlowOPML: UTType {
        UTType(filenameExtension: "opml") ?? .xml
    }
}

struct OPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.feedFlowOPML, .xml, .plainText] }
    static var writableContentTypes: [UTType] { [.feedFlowOPML] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            self.text = ""
            return
        }
        self.text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

enum OPMLService {
    struct Item: Hashable {
        let title: String?
        let xmlUrl: String
        let htmlUrl: String?
        let kind: String?
        let categories: [String]
    }

    enum ParseError: LocalizedError {
        case invalidOPML
        case noFeeds

        var errorDescription: String? {
            switch self {
            case .invalidOPML:
                return "Invalid OPML file."
            case .noFeeds:
                return "No feeds found in OPML."
            }
        }
    }

    static func generate(items: [Item], title: String = "FeedFlow Subscriptions") -> String {
        let iso = ISO8601DateFormatter()
        let created = iso.string(from: Date())

        var lines: [String] = []
        lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        lines.append(#"<opml version="1.0">"#)
        lines.append("  <head>")
        lines.append("    <title>\(escapeXMLText(title))</title>")
        lines.append("    <dateCreated>\(escapeXMLText(created))</dateCreated>")
        lines.append("  </head>")
        lines.append("  <body>")

        let grouped = groupItemsByCategories(items)
        appendOutlines(for: grouped, into: &lines, indent: "    ")

        lines.append("  </body>")
        lines.append("</opml>")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func parse(data: Data) throws -> [Item] {
        let parser = XMLParser(data: data)
        let delegate = OPMLParserDelegate()
        parser.delegate = delegate

        let ok = parser.parse()
        if !ok {
            throw ParseError.invalidOPML
        }
        if delegate.items.isEmpty {
            throw ParseError.noFeeds
        }
        return delegate.items
    }

    static func normalizeURLString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)?.absoluteString ?? trimmed
    }

    private static func escapeXMLText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeXMLAttribute(_ value: String) -> String {
        escapeXMLText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func groupItemsByCategories(_ items: [Item]) -> CategoryNode {
        let root = CategoryNode(name: nil, items: [])

        for item in items {
            let categories = item.categories.filter { !$0.isEmpty }
            if categories.isEmpty {
                root.items.append(item)
                continue
            }

            var node: CategoryNode = root
            for category in categories {
                node = node.child(named: category)
            }
            node.items.append(item)
        }

        return root
    }

    private static func appendOutlines(for node: CategoryNode, into lines: inout [String], indent: String) {
        for item in node.items.sorted(by: { ($0.title ?? $0.xmlUrl) < ($1.title ?? $1.xmlUrl) }) {
            var attributes: [String] = []

            let rawTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (rawTitle?.isEmpty == false) ? rawTitle : nil
            if let title {
                attributes.append(#"text="\#(escapeXMLAttribute(title))""#)
                attributes.append(#"title="\#(escapeXMLAttribute(title))""#)
            }

            attributes.append(#"type="rss""#)
            attributes.append(#"xmlUrl="\#(escapeXMLAttribute(item.xmlUrl))""#)

            if let htmlUrl = item.htmlUrl, !htmlUrl.isEmpty {
                attributes.append(#"htmlUrl="\#(escapeXMLAttribute(htmlUrl))""#)
            }

            if let kind = item.kind?.trimmingCharacters(in: .whitespacesAndNewlines), !kind.isEmpty {
                attributes.append(#"feedflowKind="\#(escapeXMLAttribute(kind))""#)
            }

            lines.append("\(indent)<outline \(attributes.joined(separator: " ")) />")
        }

        for child in node.children.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
            let name = (child.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            lines.append("\(indent)<outline text=\"\(escapeXMLAttribute(name))\" title=\"\(escapeXMLAttribute(name))\">")
            appendOutlines(for: child, into: &lines, indent: indent + "  ")
            lines.append("\(indent)</outline>")
        }
    }
}

private final class OPMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var items: [OPMLService.Item] = []
    private var categoryStack: [String] = []
    private var outlineScopeStack: [Bool] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard elementName.lowercased() == "outline" else { return }

        let attrs = attributeDict.reduce(into: [String: String]()) { acc, pair in
            acc[pair.key.lowercased()] = pair.value
        }

        let xmlUrl = attrs["xmlurl"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !xmlUrl.isEmpty {
            let title = attrs["title"] ?? attrs["text"]
            let htmlUrl = attrs["htmlurl"]
            let kind = attrs["feedflowkind"]
            let categories = categoryStack
            items.append(
                OPMLService.Item(
                    title: title,
                    xmlUrl: xmlUrl,
                    htmlUrl: htmlUrl,
                    kind: kind,
                    categories: categories
                )
            )
            outlineScopeStack.append(false)
            return
        }

        let name = (attrs["title"] ?? attrs["text"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty {
            categoryStack.append(name)
            outlineScopeStack.append(true)
        } else {
            outlineScopeStack.append(false)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName.lowercased() == "outline" else { return }
        guard let didPushCategory = outlineScopeStack.popLast() else { return }
        if didPushCategory {
            _ = categoryStack.popLast()
        }
    }
}

private final class CategoryNode {
    let name: String?
    var items: [OPMLService.Item]
    var children: [CategoryNode]

    init(name: String?, items: [OPMLService.Item], children: [CategoryNode] = []) {
        self.name = name
        self.items = items
        self.children = children
    }

    func child(named name: String) -> CategoryNode {
        if let existing = children.first(where: { $0.name == name }) {
            return existing
        }
        let created = CategoryNode(name: name, items: [])
        children.append(created)
        return created
    }
}
