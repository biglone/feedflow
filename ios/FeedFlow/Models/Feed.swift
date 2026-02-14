import Foundation
import SwiftData

@Model
final class Feed {
    var id: UUID
    var cloudId: String?
    var title: String
    var feedURL: String
    var siteURL: String?
    var iconURL: String?
    var feedDescription: String?
    var kind: String?
    var lastUpdated: Date?
    var unreadCount: Int

    @Relationship(deleteRule: .cascade, inverse: \Article.feed)
    var articles: [Article] = []

    @Relationship(inverse: \Folder.feeds)
    var folder: Folder?

    init(
        id: UUID = UUID(),
        cloudId: String? = nil,
        title: String,
        feedURL: String,
        siteURL: String? = nil,
        iconURL: String? = nil,
        feedDescription: String? = nil,
        kind: String? = nil
    ) {
        self.id = id
        self.cloudId = cloudId
        self.title = title
        self.feedURL = feedURL
        self.siteURL = siteURL
        self.iconURL = iconURL
        self.feedDescription = feedDescription
        self.kind = kind
        self.lastUpdated = nil
        self.unreadCount = 0
    }
}

extension Feed {
    var resolvedKind: FeedKind {
        if let kind, let stored = FeedKind(rawValue: kind) {
            return stored
        }
        return FeedKind.infer(from: feedURL)
    }
}
