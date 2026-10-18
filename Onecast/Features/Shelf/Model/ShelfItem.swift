import Foundation

/// One thing held on the shelf: a file stays where it is, a link or text is carried by value.
struct ShelfItem: Identifiable, Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case file(URL)
        case link(URL)
        case text(String)
    }

    let id: UUID
    let content: Content
    /// Where a file moved onto the shelf came from, so letting it go puts it back.
    let origin: URL?

    init(_ content: Content, origin: URL? = nil, id: UUID = UUID()) {
        self.id = id
        self.content = content
        self.origin = origin
    }

    static let titleLimit = 80

    var title: String {
        switch content {
        case .file(let url): url.lastPathComponent
        case .link(let url): url.host() ?? url.absoluteString
        case .text(let text):
            String(
                text.split(whereSeparator: \.isNewline).first?
                    .trimmingCharacters(in: .whitespaces).prefix(Self.titleLimit) ?? "")
        }
    }

    var subtitle: String {
        switch content {
        case .file(let url):
            ((origin ?? url).deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        case .link(let url): url.absoluteString
        case .text(let text): "\(text.count) characters"
        }
    }

    var fileURL: URL? {
        if case .file(let url) = content { return url }
        return nil
    }

    /// Paths compare standardized, so the same file dropped twice by two apps is still one item.
    fileprivate var identity: String {
        switch content {
        case .file(let url): "file:" + url.standardizedFileURL.path
        case .link(let url): "link:" + url.absoluteString
        case .text(let text): "text:" + text
        }
    }
}

/// One drop's worth of items, kept together so they drag back out as one.
struct ShelfGroup: Identifiable, Equatable, Sendable {
    let id: UUID
    var items: [ShelfItem]

    var title: String {
        items.count == 1 ? items[0].title : ShelfStack.summary(of: items)
    }

    var subtitle: String {
        items.count == 1 ? items[0].subtitle : items.map(\.title).joined(separator: ", ")
    }
}

enum ShelfStack {
    /// A drop becomes its own group; a later delivery for the same drop, like a promised file, joins it.
    static func adding(
        _ added: [ShelfItem], as groupID: UUID, to groups: [ShelfGroup]
    ) -> [ShelfGroup] {
        var seen = Set(groups.flatMap(\.items).map(\.identity))
        let fresh = added.filter { seen.insert($0.identity).inserted }
        guard !fresh.isEmpty else { return groups }
        var result = groups
        if let index = result.firstIndex(where: { $0.id == groupID }) {
            result[index].items += fresh
        } else {
            result.append(ShelfGroup(id: groupID, items: fresh))
        }
        return result
    }

    /// Drops the items, and any group left empty by it.
    static func removing(_ ids: Set<UUID>, from groups: [ShelfGroup]) -> [ShelfGroup] {
        groups.compactMap { group in
            var group = group
            group.items.removeAll { ids.contains($0.id) }
            return group.items.isEmpty ? nil : group
        }
    }

    /// "3 Files" when every item is one kind, else "4 Items".
    static func summary(of items: [ShelfItem]) -> String {
        guard !items.isEmpty else { return "Shelf" }
        let kinds = Set(items.map(\.kindName))
        let noun = kinds.count == 1 ? kinds.first! : "Item"
        return "\(items.count) \(noun)\(items.count == 1 ? "" : "s")"
    }
}

extension ShelfItem {
    fileprivate var kindName: String {
        switch content {
        case .file: "File"
        case .link: "Link"
        case .text: "Text"
        }
    }
}

/// Where a held file goes when the shelf lets it go: back where it was, beside anything now there.
enum ShelfReturn {
    /// `taken` says whether a path is occupied; a clash gains " 2", " 3"… before its extension.
    static func destination(for origin: URL, taken: (URL) -> Bool) -> URL {
        guard taken(origin) else { return origin }
        let folder = origin.deletingLastPathComponent()
        let ext = origin.pathExtension
        let stem = origin.deletingPathExtension().lastPathComponent
        var number = 2
        while true {
            let name = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
            let candidate = folder.appending(path: name, directoryHint: .notDirectory)
            if !taken(candidate) { return candidate }
            number += 1
        }
    }
}
