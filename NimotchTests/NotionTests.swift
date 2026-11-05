import Foundation
import Testing
@testable import nimotch

@Suite("Notion: decoding")
struct NotionDecodingTests {
    private struct BlockList: Decodable { let results: [RawBlock] }

    static let annotations = #""annotations":{"bold":false,"italic":false,"strikethrough":false,"underline":false,"code":false,"color":"default"}"#

    @Test func decodesSupportedAndUnsupportedBlocks() throws {
        let json = """
        {"results":[
          {"id":"h","type":"heading_2","has_children":false,"heading_2":{"rich_text":[{"plain_text":"Today",\(Self.annotations)}]}},
          {"id":"t","type":"to_do","has_children":true,"to_do":{"rich_text":[{"plain_text":"Buy ",\(Self.annotations)},{"plain_text":"milk","href":"https://x.y","annotations":{"bold":true}}],"checked":true}},
          {"id":"c","type":"callout","has_children":false,"callout":{"rich_text":[],"icon":{"type":"emoji","emoji":"🔥"}}},
          {"id":"d","type":"child_database","has_children":false,"child_database":{"title":"Tasks"}},
          {"id":"x","type":"divider","has_children":false,"divider":{}}
        ]}
        """
        let blocks = try JSONDecoder().decode(BlockList.self, from: Data(json.utf8)).results.map { $0.block(parentID: "page") }
        #expect(blocks.map(\.kind) == [.heading2, .toDo, .callout, .unsupported("child_database"), .divider])
        #expect(blocks[1].plainText == "Buy milk")
        #expect(blocks[1].checked)
        #expect(blocks[1].hasChildren)
        #expect(blocks[1].richText[1].annotations.bold)
        #expect(blocks[2].icon == "🔥")
        #expect(blocks.allSatisfy { $0.parentID == "page" })
    }

    @Test func decodesPageTitleIconAndTimestamp() throws {
        let json = """
        {"id":"abc","url":"https://www.notion.so/To-do-abc","last_edited_time":"2026-11-05T09:12:00.000Z",
         "icon":{"type":"emoji","emoji":"✅"},
         "properties":{"Name":{"type":"title","title":[{"plain_text":"To-do",\(Self.annotations)}]},"Tags":{"type":"multi_select"}}}
        """
        let page = try JSONDecoder().decode(NotionPage.self, from: Data(json.utf8))
        #expect(page.title == "To-do")
        #expect(page.icon == "✅")
        #expect(page.lastEdited == "2026-11-05T09:12:00.000Z")
    }

    @Test func untitledPageFallsBack() throws {
        let page = try JSONDecoder().decode(NotionPage.self, from: Data(#"{"id":"a","properties":{}}"#.utf8))
        #expect(page.title == "Untitled")
    }

    @Test func blockKindRoundTripsAPIType() {
        for type in ["paragraph", "heading_1", "heading_2", "heading_3", "to_do", "bulleted_list_item",
                     "numbered_list_item", "toggle", "quote", "callout", "divider", "child_page", "table"] {
            #expect(NotionBlock.Kind(apiType: type).apiType == type)
        }
    }

    @Test func extractsPageIDFromLinksAndIDs() {
        #expect(NotionLinks.pageID(from: "https://www.notion.so/me/My-To-do-1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d?pvs=4") == "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d")
        #expect(NotionLinks.pageID(from: "1A2B3C4D-5E6F-7A8B-9C0D-1E2F3A4B5C6D") == "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d")
        #expect(NotionLinks.pageID(from: "groceries") == nil)
    }

    @Test func richTextBecomesAttributedString() {
        var bold = RichText(plain: "bold")
        bold.annotations.bold = true
        var link = RichText(plain: "link")
        link.href = "https://example.com"
        let attributed = [RichText(plain: "a "), bold, link].attributed
        #expect(String(attributed.characters) == "a boldlink")
        #expect(attributed.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
        #expect(attributed.runs.contains { $0.link == URL(string: "https://example.com") })
    }
}

@Suite("Notion: block tree editing")
struct NotionBlockTreeTests {
    func block(_ id: String, parent: String = "page", children: [NotionBlock] = []) -> NotionBlock {
        var b = NotionBlock(id: id, parentID: parent, kind: .toDo, richText: [RichText(plain: id)],
                            checked: false, hasChildren: !children.isEmpty)
        b.children = children
        return b
    }

    /// page: a, b(c, d), e
    var tree: [NotionBlock] {
        [block("a"), block("b", children: [block("c", parent: "b"), block("d", parent: "b")]), block("e")]
    }

    @Test func findsNestedBlocks() {
        #expect(NotionBlockTree.find("d", in: tree)?.parentID == "b")
        #expect(NotionBlockTree.find("zzz", in: tree) == nil)
    }

    @Test func updatesNestedBlock() {
        var list = tree
        #expect(NotionBlockTree.update("c", in: &list) { $0.checked = true })
        #expect(NotionBlockTree.find("c", in: list)?.checked == true)
        #expect(!NotionBlockTree.update("zzz", in: &list) { $0.checked = true })
    }

    @Test func removesNestedBlock() {
        var list = tree
        #expect(NotionBlockTree.remove("c", from: &list))
        #expect(list[1].children.map(\.id) == ["d"])
        #expect(NotionBlockTree.remove("a", from: &list))
        #expect(list.map(\.id) == ["b", "e"])
    }

    @Test func insertsAfterSiblingOrAtEnd() {
        var list = tree
        NotionBlockTree.insert(block("new1"), after: "a", parentID: "page", pageID: "page", into: &list)
        #expect(list.map(\.id) == ["a", "new1", "b", "e"])
        NotionBlockTree.insert(block("new2"), after: nil, parentID: "page", pageID: "page", into: &list)
        #expect(list.last?.id == "new2")
        NotionBlockTree.insert(block("new3", parent: "b"), after: "c", parentID: "b", pageID: "page", into: &list)
        #expect(NotionBlockTree.find("b", in: list)?.children.map(\.id) == ["c", "new3", "d"])
    }

    @Test func replacesTemporaryBlock() {
        var list = tree
        NotionBlockTree.replace("e", with: block("server-id"), in: &list)
        #expect(list.last?.id == "server-id")
    }
}

@Suite("Notion: adding lines")
struct NotionNewLineTests {
    @Test func plusContinuesListsElseAddsToDo() {
        #expect(NotionBlock.Kind.toDo.newLineKind == .toDo)
        #expect(NotionBlock.Kind.bulleted.newLineKind == .bulleted)
        #expect(NotionBlock.Kind.numbered.newLineKind == .numbered)
        #expect(NotionBlock.Kind.heading2.newLineKind == .toDo)
        #expect(NotionBlock.Kind.paragraph.newLineKind == .toDo)
        #expect(NotionBlock.Kind.divider.newLineKind == .toDo)
    }
}
