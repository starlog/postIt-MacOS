import Foundation

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
        modifiedAt: Date = Date()
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
    }
}
