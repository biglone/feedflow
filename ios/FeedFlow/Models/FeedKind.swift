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

    static func extractYouTubeChannelId(from feedURLString: String) -> String? {
        guard let url = URL(string: feedURLString) else { return nil }
        guard (url.host ?? "").lowercased().contains("youtube.com") else { return nil }
        guard url.path.lowercased().contains("/feeds/videos.xml") else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "channel_id" })?.value
    }

    static func isGenericYouTubeIconURL(_ value: String?) -> Bool {
        let normalized = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return true }

        if normalized.contains("youtube.com/favicon") {
            return true
        }

        if normalized.contains("youtube.com/s/desktop") && normalized.contains("favicon") {
            return true
        }

        return false
    }

    static func isAudioEnclosureURL(_ urlString: String?) -> Bool {
        guard let urlString, let url = URL(string: urlString) else { return false }
        let ext = url.pathExtension.lowercased()
        return ["mp3", "m4a", "aac", "ogg", "opus", "wav", "flac"].contains(ext)
    }

    static func isAudioMIMEType(_ value: String?) -> Bool {
        let type = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return type.hasPrefix("audio/")
    }

    static func isImageURL(_ urlString: String?) -> Bool {
        guard let urlString, let url = URL(string: urlString) else { return false }
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "tiff"].contains(ext)
    }

    static func isImageMIMEType(_ value: String?) -> Bool {
        let type = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return type.hasPrefix("image/")
    }
}
