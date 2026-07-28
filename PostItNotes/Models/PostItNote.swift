import Foundation

/// One sub-card inside a note. A note shows a single page at a time and keeps
/// the others here; only the visible one is mirrored into the note's own
/// content/rtfContent fields.
struct NotePage: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var content: String
    var rtfContent: String?

    init(id: UUID = UUID(), name: String, content: String = "", rtfContent: String? = nil) {
        self.id = id
        self.name = name
        self.content = content
        self.rtfContent = rtfContent
    }
}

struct PostItNote: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var content: String
    var rtfContent: String?
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var color: String
    var createdAt: Date
    var modifiedAt: Date
    /// Closed notes stay in storage but are not shown as a window or tab.
    /// Optional so notes.json written by older versions still decodes.
    var closed: Bool?
    /// Sub-cards. Optional for the same reason: a note saved before sub-cards
    /// existed is read as a single page holding content/rtfContent.
    var pages: [NotePage]?
    /// Sub-card that was on screen last.
    var selectedPage: Int?
    /// Whether long lines wrap in the editor. Optional so older notes decode;
    /// nil means wrapping, which is how the app always behaved.
    var wordWrap: Bool?

    var wrapsText: Bool { return wordWrap ?? true }

    var isClosed: Bool { return closed ?? false }

    /// The note's sub-cards, standing in one page for a note that predates them.
    var effectivePages: [NotePage] {
        if let pages = pages, !pages.isEmpty { return pages }
        return [NotePage(name: "1", content: content, rtfContent: rtfContent)]
    }

    /// Index of the sub-card to show, clamped to what the note actually has.
    var selectedPageIndex: Int {
        let index = selectedPage ?? 0
        return effectivePages.indices.contains(index) ? index : 0
    }

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        rtfContent: String? = nil,
        x: Double = 100,
        y: Double = 100,
        width: Double = 250,
        height: Double = 250,
        color: String = "#FFFF88",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        closed: Bool? = nil,
        pages: [NotePage]? = nil,
        selectedPage: Int? = nil,
        wordWrap: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.rtfContent = rtfContent
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.color = color
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.closed = closed
        self.pages = pages
        self.selectedPage = selectedPage
        self.wordWrap = wordWrap
    }
}
