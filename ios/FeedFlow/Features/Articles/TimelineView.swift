import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allArticles: [Article]

    @State private var filter: ArticleFilter = .all
    @State private var typeFilter: FeedTypeFilter = .all
    @State private var isRefreshing = false

    enum ArticleFilter: String, CaseIterable {
        case all = "All"
        case unread = "Unread"

        var icon: String {
            switch self {
            case .all: return "newspaper"
            case .unread: return "circle"
            }
        }
    }

    enum FeedTypeFilter: String, CaseIterable {
        case all = "All Types"
        case youtube = "YouTube"
        case rss = "RSS"
        case podcast = "Podcast"

        var icon: String {
            switch self {
            case .all: "line.3.horizontal.decrease.circle"
            case .youtube: FeedKind.youtube.systemImageName
            case .rss: FeedKind.rss.systemImageName
            case .podcast: FeedKind.podcast.systemImageName
            }
        }

        var kind: FeedKind? {
            switch self {
            case .all: nil
            case .youtube: .youtube
            case .rss: .rss
            case .podcast: .podcast
            }
        }
    }

    var filteredArticles: [Article] {
        let sorted = allArticles.sorted {
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

        let readFiltered: [Article] = switch filter {
        case .all: sorted
        case .unread: sorted.filter { !$0.isRead }
        }

        guard let kind = typeFilter.kind else {
            return readFiltered
        }

        return readFiltered.filter { article in
            article.feed?.resolvedKind == kind
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredArticles.isEmpty {
                    ContentUnavailableView(
                        filter == .unread ? "All Caught Up" : "No Articles",
                        systemImage: filter == .unread ? "checkmark.circle" : "newspaper",
                        description: Text(filter == .unread ? "You've read all articles" : "Add some feeds to get started")
                    )
                } else {
                    ForEach(filteredArticles) { article in
                        NavigationLink {
                            ArticleReaderView(article: article)
                        } label: {
                            TimelineArticleRowView(article: article)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                toggleRead(article)
                            } label: {
                                Label(
                                    article.isRead ? "Unread" : "Read",
                                    systemImage: article.isRead ? "circle" : "checkmark.circle"
                                )
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                toggleStar(article)
                            } label: {
                                Label(
                                    article.isStarred ? "Unstar" : "Star",
                                    systemImage: article.isStarred ? "star.slash" : "star"
                                )
                            }
                            .tint(.yellow)
                        }
                    }
                }
            }
            .transaction { $0.animation = nil }
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(ArticleFilter.allCases, id: \.self) { filter in
                                Label(filter.rawValue, systemImage: filter.icon)
                                    .tag(filter)
                            }
                        }

                        Picker("Type", selection: $typeFilter) {
                            ForEach(FeedTypeFilter.allCases, id: \.self) { type in
                                Label(type.rawValue, systemImage: type.icon)
                                    .tag(type)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .refreshable {
                await refreshAllFeeds()
            }
        }
    }

    private func toggleRead(_ article: Article) {
        article.isRead.toggle()
        if let feed = article.feed {
            feed.unreadCount = feed.articles.filter { !$0.isRead }.count
        }
        try? modelContext.save()
    }

    private func toggleStar(_ article: Article) {
        article.isStarred.toggle()
        try? modelContext.save()
    }

    private func refreshAllFeeds() async {
        let feedManager = FeedManager(modelContext: modelContext)
        await feedManager.refreshAllFeeds()
    }
}

struct TimelineArticleRowView: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let feed = article.feed {
                    AsyncImage(url: URL(string: feed.iconURL ?? "")) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        Image(systemName: "newspaper")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(feed.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

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

            Text(article.title)
                .font(.headline)
                .fontWeight(article.isRead ? .regular : .semibold)
                .foregroundStyle(article.isRead ? .secondary : .primary)
                .lineLimit(2)

            if let summary = article.summary {
                Text(summary.strippingHTML())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let imageURL = article.resolvedThumbnailURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TimelineView()
        .modelContainer(for: [Feed.self, Article.self, Folder.self], inMemory: true)
}
