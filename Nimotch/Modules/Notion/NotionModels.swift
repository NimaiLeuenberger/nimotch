import AppKit
import SwiftUI

struct RichText: Decodable, Equatable, Sendable {
    struct Annotations: Equatable, Sendable {
        var bold = false, italic = false, strikethrough = false, underline = false, code = false
    }

    var plainText: String
    var href: String?
    var annotations = Annotations()

    init(plain: String) { plainText = plain }

    private enum CodingKeys: String, CodingKey { case plainText = "plain_text", href, annotations }
    private enum AnnotationKeys: String, CodingKey { case bold, italic, strikethrough, underline, code }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plainText = try c.decodeIfPresent(String.self, forKey: .plainText) ?? ""
        href = try c.decodeIfPresent(String.self, forKey: .href)
        if let a = try? c.nestedContainer(keyedBy: AnnotationKeys.self, forKey: .annotations) {
            annotations.bold = (try? a.decode(Bool.self, forKey: .bold)) ?? false
            annotations.italic = (try? a.decode(Bool.self, forKey: .italic)) ?? false
            annotations.strikethrough = (try? a.decode(Bool.self, forKey: .strikethrough)) ?? false
            annotations.underline = (try? a.decode(Bool.self, forKey: .underline)) ?? false
            annotations.code = (try? a.decode(Bool.self, forKey: .code)) ?? false
        }
    }
}

extension [RichText] {
    var plainText: String { map(\.plainText).joined() }

    var attributed: AttributedString {
        var result = AttributedString()
        for segment in self {
            var part = AttributedString(segment.plainText)
            var intent: InlinePresentationIntent = []
            if segment.annotations.bold { intent.insert(.stronglyEmphasized) }
            if segment.annotations.italic { intent.insert(.emphasized) }
            if segment.annotations.code { intent.insert(.code) }
            if !intent.isEmpty { part.inlinePresentationIntent = intent }
            if segment.annotations.strikethrough { part.strikethroughStyle = .single }
            if segment.annotations.underline { part.underlineStyle = .single }
            if let href = segment.href, let url = URL(string: href) {
                part.link = url
                part.foregroundColor = .orange
            }
            result += part
        }
        return result
    }
}

struct NotionIcon: Decodable, Sendable {
    let emoji: String?
}

/// One block of a page, with its (rendered) children.
struct NotionBlock: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case paragraph, heading1, heading2, heading3, toDo, bulleted, numbered, toggle, quote, callout, divider, childPage
        case unsupported(String)

        init(apiType: String) {
            self = switch apiType {
            case "paragraph": .paragraph
            case "heading_1": .heading1
            case "heading_2": .heading2
            case "heading_3": .heading3
            case "to_do": .toDo
            case "bulleted_list_item": .bulleted
            case "numbered_list_item": .numbered
            case "toggle": .toggle
            case "quote": .quote
            case "callout": .callout
            case "divider": .divider
            case "child_page": .childPage
            default: .unsupported(apiType)
            }
        }

        var apiType: String {
            switch self {
            case .paragraph: "paragraph"
            case .heading1: "heading_1"
            case .heading2: "heading_2"
            case .heading3: "heading_3"
            case .toDo: "to_do"
            case .bulleted: "bulleted_list_item"
            case .numbered: "numbered_list_item"
            case .toggle: "toggle"
            case .quote: "quote"
            case .callout: "callout"
            case .divider: "divider"
            case .childPage: "child_page"
            case .unsupported(let type): type
            }
        }

        /// Blocks whose text nimotch can edit inline.
        var isEditableText: Bool {
            switch self {
            case .paragraph, .heading1, .heading2, .heading3, .toDo, .bulleted, .numbered, .toggle, .quote, .callout: true
            default: false
            }
        }

        /// Kind of the line the "+" button adds below a block: lists continue as the same
        /// list type, anything else (headings, text, dividers…) gets a to-do.
        var newLineKind: Kind {
            switch self {
            case .toDo, .bulleted, .numbered: self
            default: .toDo
            }
        }

        /// Blocks whose children nimotch fetches and renders.
        var rendersChildren: Bool {
            switch self {
            case .paragraph, .toDo, .bulleted, .numbered, .toggle, .quote, .callout: true
            default: false
            }
        }
    }

    let id: String
    var parentID: String
    var kind: Kind
    var richText: [RichText]
    var checked: Bool
    var hasChildren: Bool
    var icon: String?
    var title: String?
    var children: [NotionBlock] = []

    var plainText: String { richText.plainText }
}

/// Raw block JSON: `{ id, type, has_children, <type>: { rich_text, checked, icon, title } }`.
struct RawBlock: Decodable, Sendable {
    struct Content: Decodable, Sendable {
        let rich_text: [RichText]?
        let checked: Bool?
        let icon: NotionIcon?
        let title: String?
    }

    let id: String
    let type: String
    let hasChildren: Bool
    let content: Content?

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        id = try c.decode(String.self, forKey: Key(stringValue: "id"))
        type = try c.decode(String.self, forKey: Key(stringValue: "type"))
        hasChildren = (try? c.decode(Bool.self, forKey: Key(stringValue: "has_children"))) ?? false
        content = try? c.decode(Content.self, forKey: Key(stringValue: type))
    }

    func block(parentID: String) -> NotionBlock {
        NotionBlock(id: id, parentID: parentID, kind: .init(apiType: type),
                    richText: content?.rich_text ?? [], checked: content?.checked ?? false,
                    hasChildren: hasChildren, icon: content?.icon?.emoji, title: content?.title)
    }
}

/// Page metadata (title, icon, URL, last edit).
struct NotionPage: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let icon: String?
    let url: URL?
    let lastEdited: String

    private enum CodingKeys: String, CodingKey { case id, url, icon, properties, lastEdited = "last_edited_time" }
    private struct Property: Decodable { let type: String; let title: [RichText]? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        url = try? c.decode(URL.self, forKey: .url)
        icon = (try? c.decode(NotionIcon.self, forKey: .icon))?.emoji
        lastEdited = (try? c.decode(String.self, forKey: .lastEdited)) ?? ""
        let properties = (try? c.decode([String: Property].self, forKey: .properties)) ?? [:]
        let title = properties.values.first { $0.type == "title" }?.title?.plainText ?? ""
        self.title = title.isEmpty ? "Untitled" : title
    }
}

enum NotionLinks {
    /// Opens a notion.so URL in the Notion app when installed, else in the browser.
    static func open(_ url: URL?, blockID: String? = nil) {
        guard var string = url?.absoluteString else { return }
        if let blockID { string += "#" + blockID.replacingOccurrences(of: "-", with: "") }
        if let appURL = URL(string: string.replacingOccurrences(of: "https://", with: "notion://")),
           NSWorkspace.shared.urlForApplication(toOpen: appURL) != nil {
            NSWorkspace.shared.open(appURL)
        } else if let webURL = URL(string: string) {
            NSWorkspace.shared.open(webURL)
        }
    }

    /// Extracts a page ID from a pasted Notion URL or raw ID.
    static func pageID(from text: String) -> String? {
        let compact = text.replacingOccurrences(of: "-", with: "")
        guard let match = compact.range(of: #"[0-9a-fA-F]{32}(?![0-9a-fA-F])"#, options: [.regularExpression, .backwards]) else { return nil }
        return String(compact[match]).lowercased()
    }
}
