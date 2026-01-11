import Foundation

enum FeedKind: String, CaseIterable, Identifiable, Hashable {
    case rss
    case youtube
    case podcast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rss: "RSS"
        case .youtube: "YouTube"
        case .podcast: "Podcast"
        }
    }

    var systemImageName: String {
        switch self {
        case .rss: "newspaper"
        case .youtube: "play.rectangle"
        case .podcast: "mic"
        }
    }

    static var displayOrder: [FeedKind] {
        [.youtube, .rss, .podcast]
    }

    static func infer(from feedURLString: String) -> FeedKind {
        isYouTubeFeedURL(feedURLString) ? .youtube : .rss
    }

    static func isYouTubeFeedURL(_ feedURLString: String) -> Bool {
        guard let url = URL(string: feedURLString) else {
            return feedURLString.lowercased().contains("youtube.com/feeds/videos.xml")
        }

        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        return host.contains("youtube.com") && path.contains("/feeds/videos.xml")
    }

    static func isAudioEnclosureURL(_ urlString: String?) -> Bool {
        guard let urlString, let url = URL(string: urlString) else { return false }
        let ext = url.pathExtension.lowercased()
        return ["mp3", "m4a", "aac", "ogg", "opus", "wav", "flac"].contains(ext)
    }

    static func isImageURL(_ urlString: String?) -> Bool {
        guard let urlString, let url = URL(string: urlString) else { return false }
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "tiff"].contains(ext)
    }
}

