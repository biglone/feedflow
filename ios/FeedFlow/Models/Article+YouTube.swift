import Foundation

extension Article {
    var youTubeVideoId: String? {
        extractYouTubeVideoId(from: articleURL) ?? extractYouTubeVideoId(from: guid)
    }

    var resolvedThumbnailURL: String? {
        if let imageURL, !imageURL.isEmpty {
            return imageURL
        }
        guard let videoId = youTubeVideoId else { return nil }
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
