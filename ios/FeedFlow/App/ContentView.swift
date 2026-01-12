import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: AuthManager
    @Query private var feeds: [Feed]
    @State private var selectedFeed: Feed?
    @State private var showingAddFeed = false
    @State private var selectedTab: Tab = .timeline
    @State private var showingFullPlayer = false
    @State private var isSyncing = false
    @StateObject private var playerManager = PlayerManager.shared

    enum Tab {
        case timeline
        case feeds
        case starred
        case settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TimelineView()
                .tabItem {
                    Label("Timeline", systemImage: "newspaper")
                }
                .tag(Tab.timeline)

            FeedsListView()
                .tabItem {
                    Label("Feeds", systemImage: "list.bullet")
                }
                .tag(Tab.feeds)

            StarredArticlesView()
                .tabItem {
                    Label("Starred", systemImage: "star")
                }
                .tag(Tab.starred)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(Tab.settings)
        }
        .onChange(of: authManager.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                Task {
                    await syncWithCloud()
                }
            }
        }
        .overlay(alignment: .top) {
            if isSyncing {
                SyncIndicatorView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if playerManager.currentVideoId != nil {
                MiniPlayerView(
                    onTap: {
                        showingFullPlayer = true
                    },
                    onDismiss: {
                        playerManager.stop()
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showingFullPlayer) {
            if playerManager.nowPlayingFeedKind == .podcast {
                AudioPlayerView()
            } else if let videoId = playerManager.currentVideoId,
                      let info = playerManager.nowPlayingInfo {
                VideoPlayerView(
                    videoId: videoId,
                    title: info.title,
                    channelTitle: info.artist ?? "",
                    thumbnailUrl: info.thumbnailUrl
                )
            }
        }
    }

    @MainActor
    private func syncWithCloud() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let feedManager = FeedManager(modelContext: modelContext)
        await feedManager.syncWithCloud()
    }
}

struct SyncIndicatorView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Syncing...")
                .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.top, 8)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Feed.self, Article.self, Folder.self], inMemory: true)
        .environmentObject(AuthManager.shared)
}
