import SwiftUI
import SwiftData

private struct RecommendedFeed: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case rss = "RSS"
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
            title: "Hacker News",
            url: "https://hnrss.org/frontpage",
            category: "Tech",
            description: "Tech & startups"
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
            .sorted { $0.category < $1.category }
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
    RecommendedFeedsView()
        .modelContainer(for: [Feed.self, Article.self, Folder.self], inMemory: true)
}
