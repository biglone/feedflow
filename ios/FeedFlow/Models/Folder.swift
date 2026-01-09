import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID
    var name: String
    var order: Int
    var createdAt: Date

    @Relationship(deleteRule: .nullify)
    var feeds: [Feed] = []

    var unreadCount: Int {
        feeds.reduce(0) { $0 + $1.unreadCount }
    }

    init(
        id: UUID = UUID(),
        name: String,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.createdAt = Date()
    }
}
