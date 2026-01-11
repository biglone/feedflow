import SwiftUI
import SwiftData

struct FeedsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @State private var showingAddFeed = false
    @State private var showingYouTubeSearch = false
    @State private var showingImportSubscriptions = false

    var body: some View {
        NavigationStack {
            List {
                if feeds.isEmpty {
                    ContentUnavailableView(
                        "No Feeds",
                        systemImage: "newspaper",
                        description: Text("Add your first RSS feed to get started")
                    )
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
            .sheet(isPresented: $showingAddFeed) {
                AddFeedView()
            }
            .sheet(isPresented: $showingYouTubeSearch) {
                YouTubeSearchView()
            }
            .sheet(isPresented: $showingImportSubscriptions) {
                ImportSubscriptionsView()
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

#Preview {
    FeedsListView()
        .modelContainer(for: [Feed.self, Article.self, Folder.self], inMemory: true)
}
