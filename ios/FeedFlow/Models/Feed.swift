import Foundation
import SwiftData

@Model
final class Feed {
    var id: UUID
    var title: String
    var feedURL: String
    var siteURL: String?
    var iconURL: String?
    var feedDescription: String?
    var lastUpdated: Date?
    var unreadCount: Int

    @Relationship(deleteRule: .cascade, inverse: \Article.feed)
    var articles: [Article] = []

    @Relationship(inverse: \Folder.feeds)
    var folder: Folder?

    init(
        id: UUID = UUID(),
        title: String,
        feedURL: String,
        siteURL: String? = nil,
        iconURL: String? = nil,
        feedDescription: String? = nil
    ) {
        self.id = id
        self.title = title
        self.feedURL = feedURL
        self.siteURL = siteURL
        self.iconURL = iconURL
        self.feedDescription = feedDescription
        self.lastUpdated = nil
        self.unreadCount = 0
    }
}
