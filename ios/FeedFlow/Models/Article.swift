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

extension Article {
    var youtubeVideoId: String? {
        extractYouTubeVideoId(from: articleURL) ?? extractYouTubeVideoId(from: guid)
    }

    var resolvedThumbnailURL: String? {
        if let imageURL, !imageURL.isEmpty {
            return imageURL
        }
        guard let videoId = youtubeVideoId else { return nil }
        return "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
    }

    private func extractYouTubeVideoId(from value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let patterns = [
            #"(?:yt:video:|video:)([A-Za-z0-9_-]{11})"#,
            #"youtu\.be/([A-Za-z0-9_-]{11})"#,
            #"youtube\.com/watch\?[^"'\s]*v=([A-Za-z0-9_-]{11})"#,
            #"youtube\.com/shorts/([A-Za-z0-9_-]{11})"#,
            #"youtube\.com/embed/([A-Za-z0-9_-]{11})"#,
            #"ytimg\.com/vi/([A-Za-z0-9_-]{11})"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }
            let range = NSRange(value.startIndex..., in: value)
            guard let match = regex.firstMatch(in: value, options: [], range: range) else { continue }
            guard match.numberOfRanges > 1 else { continue }
            guard let idRange = Range(match.range(at: 1), in: value) else { continue }
            return String(value[idRange])
        }

        return nil
    }
}
