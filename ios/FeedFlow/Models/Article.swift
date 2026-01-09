import Foundation
import SwiftData

@Model
final class Article {
    var id: UUID
    var guid: String
    var title: String
    var content: String?
    var summary: String?
    var articleURL: String?
    var author: String?
    var imageURL: String?
    var publishedAt: Date?
    var isRead: Bool
    var isStarred: Bool
    var createdAt: Date

    var feed: Feed?

    init(
        id: UUID = UUID(),
        guid: String,
        title: String,
        content: String? = nil,
        summary: String? = nil,
        articleURL: String? = nil,
        author: String? = nil,
        imageURL: String? = nil,
        publishedAt: Date? = nil
    ) {
        self.id = id
        self.guid = guid
        self.title = title
        self.content = content
        self.summary = summary
        self.articleURL = articleURL
        self.author = author
        self.imageURL = imageURL
        self.publishedAt = publishedAt
        self.isRead = false
        self.isStarred = false
        self.createdAt = Date()
    }
}
