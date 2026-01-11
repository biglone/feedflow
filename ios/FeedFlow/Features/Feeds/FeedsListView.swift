import SwiftUI
import SwiftData

struct FeedsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @State private var showingAddFeed = false
    @State private var showingYouTubeSearch = false
    @State private var showingImportSubscriptions = false
    @State private var showingRecommendedFeeds = false
    @AppStorage("didShowRecommendedFeeds") private var didShowRecommendedFeeds = false

    var body: some View {
        NavigationStack {
            List {
                if feeds.isEmpty {
                    ContentUnavailableView(
                        "No Feeds",
                        systemImage: "newspaper",
                        description: Text("Add your first RSS feed to get started")
                    )
                    Button("Browse Popular Subscriptions") {
                        showingRecommendedFeeds = true
                        didShowRecommendedFeeds = true
                    }
                } else {
                    ForEach(feeds) { feed in
                        NavigationLink {
                            ArticlesListView(feed: feed)
                        } label: {
                            FeedRowView(feed: feed)
                        }
                    }
                    .onDelete(perform: deleteFeeds)
                }
            }
            .transaction { $0.animation = nil }
            .navigationTitle("Feeds")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingAddFeed = true
                        } label: {
                            Label("Add RSS Feed", systemImage: "newspaper")
                        }

                        Button {
                            showingYouTubeSearch = true
                        } label: {
                            Label("Subscribe YouTube", systemImage: "play.rectangle")
                        }

                        Divider()

                        Button {
                            showingRecommendedFeeds = true
                            didShowRecommendedFeeds = true
                        } label: {
                            Label("Popular Subscriptions", systemImage: "sparkles")
                        }

                        Button {
                            showingImportSubscriptions = true
                        } label: {
                            Label("Import from YouTube", systemImage: "arrow.down.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                let feedManager = FeedManager(modelContext: modelContext)
                await feedManager.refreshAllFeeds()
            }
            .task {
                if feeds.isEmpty && !didShowRecommendedFeeds {
                    showingRecommendedFeeds = true
                    didShowRecommendedFeeds = true
                }
            }
            .sheet(isPresented: $showingAddFeed) {
                AddFeedView()
            }
            .sheet(isPresented: $showingYouTubeSearch) {
                YouTubeSearchView()
            }
            .sheet(isPresented: $showingImportSubscriptions) {
                ImportSubscriptionsView()
            }
            .sheet(isPresented: $showingRecommendedFeeds) {
                RecommendedFeedsView()
            }
        }
    }

    private func deleteFeeds(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(feeds[index])
        }
        try? modelContext.save()
    }
}

struct FeedRowView: View {
    let feed: Feed

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: feed.iconURL ?? "")) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Image(systemName: "newspaper")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(.body)
                    .lineLimit(1)

                if let description = feed.feedDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if feed.unreadCount > 0 {
                Text("\(feed.unreadCount)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RecommendedFeed: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case rss = "RSS"
        case podcast = "Podcast"
    }

    let id: String
    let title: String
    let url: String
    let category: String
    let kind: Kind
    let description: String?

    init(
        title: String,
        url: String,
        category: String,
        kind: Kind = .rss,
        description: String? = nil
    ) {
        self.id = url
        self.title = title
        self.url = url
        self.category = category
        self.kind = kind
        self.description = description
    }
}

private enum RecommendedFeedCatalog {
    static let categoryOrder: [String: Int] = [
        "中文": 0,
        "Linux": 1,
        "Programming": 2,
        "DevOps": 3,
        "AI": 4,
        "Tech": 5,
        "Community": 6,
        "Design": 7,
        "Security": 8,
        "Science": 9,
        "Podcast": 10,
    ]

    static let items: [RecommendedFeed] = [
        RecommendedFeed(
            title: "少数派",
            url: "https://sspai.com/feed",
            category: "中文",
            description: "数字生活与效率"
        ),
        RecommendedFeed(
            title: "阮一峰的网络日志",
            url: "https://www.ruanyifeng.com/blog/atom.xml",
            category: "中文",
            description: "技术、周刊与随笔"
        ),
        RecommendedFeed(
            title: "V2EX",
            url: "https://www.v2ex.com/index.xml",
            category: "中文",
            description: "创意工作者社区"
        ),
        RecommendedFeed(
            title: "Linux Do",
            url: "https://linux.do/latest.rss",
            category: "Linux",
            description: "中文 Linux 社区"
        ),
        RecommendedFeed(
            title: "Linux.com",
            url: "https://www.linux.com/feed/",
            category: "Linux",
            description: "Linux news"
        ),
        RecommendedFeed(
            title: "It's FOSS",
            url: "https://itsfoss.com/feed/",
            category: "Linux",
            description: "Linux tips & news"
        ),
        RecommendedFeed(
            title: "OMG! Ubuntu",
            url: "https://www.omgubuntu.co.uk/feed",
            category: "Linux",
            description: "Ubuntu news"
        ),
        RecommendedFeed(
            title: "Fedora Magazine",
            url: "https://fedoramagazine.org/feed/",
            category: "Linux",
            description: "Fedora community blog"
        ),
        RecommendedFeed(
            title: "Arch Linux News",
            url: "https://archlinux.org/feeds/news/",
            category: "Linux",
            description: "Arch announcements"
        ),
        RecommendedFeed(
            title: "Kernel Releases",
            url: "https://www.kernel.org/feeds/kdist.xml",
            category: "Linux",
            description: "Linux kernel releases"
        ),
        RecommendedFeed(
            title: "GitHub Blog",
            url: "https://github.blog/feed/",
            category: "Programming",
            description: "Engineering, open source, and GitHub updates"
        ),
        RecommendedFeed(
            title: "Martin Fowler",
            url: "https://martinfowler.com/feed.atom",
            category: "Programming",
            description: "Architecture, refactoring, and software design"
        ),
        RecommendedFeed(
            title: "The Go Blog",
            url: "https://go.dev/blog/feed.atom",
            category: "Programming",
            description: "Go official blog"
        ),
        RecommendedFeed(
            title: "Rust Blog",
            url: "https://blog.rust-lang.org/feed.xml",
            category: "Programming",
            description: "Rust language updates"
        ),
        RecommendedFeed(
            title: "Swift.org",
            url: "https://swift.org/atom.xml",
            category: "Programming",
            description: "Swift language updates"
        ),
        RecommendedFeed(
            title: "Kubernetes Blog",
            url: "https://kubernetes.io/feed.xml",
            category: "DevOps",
            description: "Kubernetes blog & announcements"
        ),
        RecommendedFeed(
            title: "Docker Blog",
            url: "https://www.docker.com/blog/feed/",
            category: "DevOps",
            description: "Docker news & engineering"
        ),
        RecommendedFeed(
            title: "Cloudflare Blog",
            url: "https://blog.cloudflare.com/rss/",
            category: "DevOps",
            description: "Networking, security, and performance"
        ),
        RecommendedFeed(
            title: "OpenAI Blog",
            url: "https://openai.com/blog/rss.xml",
            category: "AI",
            description: "OpenAI updates"
        ),
        RecommendedFeed(
            title: "Google AI",
            url: "https://blog.google/technology/ai/rss/",
            category: "AI",
            description: "Google AI news"
        ),
        RecommendedFeed(
            title: "Hacker News",
            url: "https://hnrss.org/frontpage",
            category: "Tech",
            description: "Tech & startups"
        ),
        RecommendedFeed(
            title: "The Register",
            url: "https://www.theregister.com/headlines.atom",
            category: "Tech",
            description: "IT industry news"
        ),
        RecommendedFeed(
            title: "The Verge",
            url: "https://www.theverge.com/rss/index.xml",
            category: "Tech",
            description: "Technology news"
        ),
        RecommendedFeed(
            title: "Ars Technica",
            url: "https://feeds.arstechnica.com/arstechnica/index",
            category: "Tech",
            description: "Technology & science"
        ),
        RecommendedFeed(
            title: "Lobsters",
            url: "https://lobste.rs/rss",
            category: "Community",
            description: "Tech community discussions"
        ),
        RecommendedFeed(
            title: "Smashing Magazine",
            url: "https://www.smashingmagazine.com/feed/",
            category: "Design",
            description: "UX/UI & front-end"
        ),
        RecommendedFeed(
            title: "Nielsen Norman Group",
            url: "https://www.nngroup.com/feed/rss/",
            category: "Design",
            description: "UX research & guidance"
        ),
        RecommendedFeed(
            title: "Krebs on Security",
            url: "https://krebsonsecurity.com/feed/",
            category: "Security",
            description: "Security news & investigations"
        ),
        RecommendedFeed(
            title: "NASA Breaking News",
            url: "https://www.nasa.gov/rss/dyn/breaking_news.rss",
            category: "Science",
            description: "NASA updates"
        ),
        RecommendedFeed(
            title: "The Changelog",
            url: "https://changelog.com/podcast/feed",
            category: "Podcast",
            kind: .podcast,
            description: "Software engineering podcast"
        ),
        RecommendedFeed(
            title: "Go Time",
            url: "https://changelog.com/gotime/feed",
            category: "Podcast",
            kind: .podcast,
            description: "Go podcast"
        ),
        RecommendedFeed(
            title: "JS Party",
            url: "https://changelog.com/jsparty/feed",
            category: "Podcast",
            kind: .podcast,
            description: "JavaScript podcast"
        ),
        RecommendedFeed(
            title: "Syntax",
            url: "https://feed.syntax.fm/rss",
            category: "Podcast",
            kind: .podcast,
            description: "Web dev podcast"
        ),
        RecommendedFeed(
            title: "Linux Unplugged",
            url: "https://linuxunplugged.com/rss",
            category: "Podcast",
            kind: .podcast,
            description: "Linux podcast"
        ),
        RecommendedFeed(
            title: "Darknet Diaries",
            url: "https://feeds.megaphone.fm/darknetdiaries",
            category: "Podcast",
            kind: .podcast,
            description: "True stories from the dark side of the internet"
        ),
    ]
}

struct RecommendedFeedsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var feeds: [Feed]

    @State private var addingId: String?
    @State private var isAddingAll = false
    @State private var error: Error?
    @State private var showingError = false

    private var subscribedURLs: Set<String> {
        Set(feeds.map(\.feedURL))
    }

    private var categorizedItems: [(category: String, items: [RecommendedFeed])] {
        let grouped = Dictionary(grouping: RecommendedFeedCatalog.items, by: \.category)
        return grouped
            .map { (key, value) in (category: key, items: value.sorted { $0.title < $1.title }) }
            .sorted { lhs, rhs in
                let lhsOrder = RecommendedFeedCatalog.categoryOrder[lhs.category] ?? Int.max
                let rhsOrder = RecommendedFeedCatalog.categoryOrder[rhs.category] ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.category < rhs.category
            }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(categorizedItems, id: \.category) { section in
                    Section(section.category) {
                        ForEach(section.items) { item in
                            RecommendedFeedRow(
                                item: item,
                                isAdded: subscribedURLs.contains(item.url),
                                isAdding: addingId == item.id,
                                onAdd: { Task { await add(item) } }
                            )
                        }
                    }
                }
            }
            .transaction { $0.animation = nil }
            .navigationTitle("Popular Subscriptions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await addAll() }
                    } label: {
                        if isAddingAll {
                            ProgressView()
                        } else {
                            Text("Add All")
                        }
                    }
                    .disabled(isAddingAll)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error?.localizedDescription ?? "Failed to add feed")
            }
        }
    }

    @MainActor
    private func add(_ item: RecommendedFeed) async {
        if subscribedURLs.contains(item.url) { return }
        guard addingId == nil else { return }

        addingId = item.id
        defer { addingId = nil }

        do {
            let feedManager = FeedManager(modelContext: modelContext)
            _ = try await feedManager.addFeed(url: item.url)
        } catch {
            self.error = error
            self.showingError = true
        }
    }

    @MainActor
    private func addAll() async {
        guard !isAddingAll else { return }
        isAddingAll = true
        defer { isAddingAll = false }

        let toAdd = RecommendedFeedCatalog.items.filter { !subscribedURLs.contains($0.url) }
        for item in toAdd {
            await add(item)
            if showingError { break }
        }
    }
}

private struct RecommendedFeedRow: View {
    let item: RecommendedFeed
    let isAdded: Bool
    let isAdding: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(item.kind.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.12))
                        .clipShape(Capsule())
                }

                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(item.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isAdded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if isAdding {
                ProgressView()
            } else {
                Button("Add") { onAdd() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FeedsListView()
        .modelContainer(for: [Feed.self, Article.self, Folder.self], inMemory: true)
}
