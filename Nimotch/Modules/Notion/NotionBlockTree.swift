import Foundation

/// Pure helpers for editing the nested block tree of a page (unit-tested).
enum NotionBlockTree {
    static func find(_ id: String, in list: [NotionBlock]) -> NotionBlock? {
        for block in list {
            if block.id == id { return block }
            if let hit = find(id, in: block.children) { return hit }
        }
        return nil
    }

    @discardableResult
    static func update(_ id: String, in list: inout [NotionBlock], _ transform: (inout NotionBlock) -> Void) -> Bool {
        for index in list.indices {
            if list[index].id == id { transform(&list[index]); return true }
            if update(id, in: &list[index].children, transform) { return true }
        }
        return false
    }

    @discardableResult
    static func remove(_ id: String, from list: inout [NotionBlock]) -> Bool {
        if let index = list.firstIndex(where: { $0.id == id }) { list.remove(at: index); return true }
        for index in list.indices where remove(id, from: &list[index].children) { return true }
        return false
    }

    static func replace(_ id: String, with block: NotionBlock, in list: inout [NotionBlock]) {
        update(id, in: &list) { $0 = block }
    }

    static func insert(_ block: NotionBlock, after afterID: String?, parentID: String, pageID: String, into list: inout [NotionBlock]) {
        if parentID == pageID {
            if let afterID, let index = list.firstIndex(where: { $0.id == afterID }) {
                list.insert(block, at: index + 1)
            } else {
                list.append(block)
            }
            return
        }
        update(parentID, in: &list) { parent in
            if let afterID, let index = parent.children.firstIndex(where: { $0.id == afterID }) {
                parent.children.insert(block, at: index + 1)
            } else {
                parent.children.append(block)
            }
        }
    }
}
