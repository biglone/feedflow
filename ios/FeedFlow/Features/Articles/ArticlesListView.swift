import Foundation
import SwiftUI
import SwiftData

struct ArticlesListView: View {
    @Environment(\.modelContext) private var modelContext
    let feed: Feed?

    @State private var isLoadingMoreYouTubeVideos = false
    @State private var youTubeLoadError: Error?
    @State private var showingYouTubeLoadError = false
    @State private var youTubeLoadedCount: Int?
    @State private var youTubeReachedEnd = false

    var articles: [Article] {
        guard let feed = feed else { return [] }
        return feed.articles.sorted {
            let lhsDate = $0.publishedAt ?? Date.distantPast
            let rhsDate = $1.publishedAt ?? Date.distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            if $0.guid != $1.guid {
                return $0.guid > $1.guid
            }
            return $0.id.uuidString > $1.id.uuidString
        }
    }

    var body: some View {
        List {
            if articles.isEmpty {
                ContentUnavailableView(
                    "No Articles",
                    systemImage: "doc.text",
                    description: Text("Pull to refresh and check for new articles")
                )
            } else {
                ForEach(articles) { article in
                    NavigationLink {
                        ArticleReaderView(article: article)
                    } label: {
                        ArticleRowView(article: article)
                    }
                }
            }

            if let channelId = youTubeChannelId {
                Section("YouTube") {
                    Button {
                        Task { await loadMoreYouTubeVideos(channelId: channelId) }
                    } label: {
                        HStack {
                            Text(youTubeReachedEnd ? "All history loaded" : "Load older videos")
                            Spacer()
                            if isLoadingMoreYouTubeVideos {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoadingMoreYouTubeVideos || youTubeReachedEnd)

                    if let youTubeLoadedCount {
                        Text("Added \(youTubeLoadedCount) videos (marked as read).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("YouTube RSS only includes the latest ~15 items. Load more to browse older videos.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(feed?.title ?? "Articles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        markAllAsRead()
                    } label: {
                        Label("Mark All as Read", systemImage: "checkmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            if let channelId = youTubeChannelId {
                youTubeReachedEnd = UserDefaults.standard.bool(forKey: "youtubeVideosReachedEnd.\(channelId)")
            }
        }
        .alert("YouTube", isPresented: $showingYouTubeLoadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(youTubeLoadError?.localizedDescription ?? "Failed to load videos")
        }
    }

    private func markAllAsRead() {
        guard let feed = feed else { return }
        let feedManager = FeedManager(modelContext: modelContext)
        feedManager.markAllAsRead(in: feed)
    }

    private var youTubeChannelId: String? {
        guard let urlString = feed?.feedURL else { return nil }
        guard let url = URL(string: urlString) else { return nil }
        guard (url.host ?? "").contains("youtube.com") else { return nil }
        guard url.path.contains("/feeds/videos.xml") else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "channel_id" })?.value
    }

    @MainActor
    private func loadMoreYouTubeVideos(channelId: String) async {
        guard let feed else { return }

        isLoadingMoreYouTubeVideos = true
        defer { isLoadingMoreYouTubeVideos = false }

        // Avoid re-entrant List updates while SwiftUI is laying out visible cells.
        await Task.yield()

        do {
            let feedManager = FeedManager(modelContext: modelContext)
            youTubeLoadedCount = try await feedManager.loadMoreYouTubeVideos(for: feed)
            youTubeReachedEnd = UserDefaults.standard.bool(forKey: "youtubeVideosReachedEnd.\(channelId)")
        } catch {
            youTubeLoadError = error
            showingYouTubeLoadError = true
        }
    }
}

struct ArticleRowView: View {
    let article: Article

    var body: some View {
        HStack(spacing: 12) {
            if let imageURL = article.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }
                .frame(width: 80, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.headline)
                    .fontWeight(article.isRead ? .regular : .semibold)
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let author = article.author {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let publishedAt = article.publishedAt {
                        Text(publishedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if article.isStarred {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                if let summary = article.summary {
                    Text(summary.strippingHTML())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

extension String {
    func strippingHTML() -> String {
        guard let data = self.data(using: .utf8) else { return self }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        return attributedString.string
    }
}

#Preview {
    NavigationStack {
        ArticlesListView(feed: nil)
    }
    .modelContainer(for: [Feed.self, Article.self, Folder.self], inMemory: true)
}
