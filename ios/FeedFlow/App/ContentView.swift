import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: AuthManager
    @Query private var feeds: [Feed]
    @State private var selectedFeed: Feed?
    @State private var showingAddFeed = false
    @State private var selectedTab: Tab = .timeline
    @State private var showingFullPlayer = false
    @State private var isSyncing = false
    @State private var tabBarVisibleHeight: CGFloat = 0
    @StateObject private var playerManager = PlayerManager.shared

    enum Tab {
        case timeline
        case feeds
        case starred
        case settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            tabRoot(TimelineView())
                .tabItem {
                    Label("Timeline", systemImage: "newspaper")
                }
                .tag(Tab.timeline)

            tabRoot(FeedsListView())
                .tabItem {
                    Label("Feeds", systemImage: "list.bullet")
                }
                .tag(Tab.feeds)

            tabRoot(StarredArticlesView())
                .tabItem {
                    Label("Starred", systemImage: "star")
                }
                .tag(Tab.starred)

            tabRoot(SettingsView())
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(Tab.settings)
        }
        .background(TabBarVisibleHeightReader(height: $tabBarVisibleHeight).allowsHitTesting(false))
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

    @ViewBuilder
    private func tabRoot<Content: View>(_ content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if playerManager.currentVideoId != nil {
                VStack(spacing: 0) {
                    MiniPlayerView(
                        onTap: {
                            showingFullPlayer = true
                        },
                        onDismiss: {
                            playerManager.stop()
                        }
                    )

                    if tabBarVisibleHeight > 0 {
                        Color.clear
                            .frame(height: tabBarVisibleHeight)
                            .allowsHitTesting(false)
                    }
                }
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

struct TabBarVisibleHeightReader: UIViewControllerRepresentable {
    @Binding var height: CGFloat

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let tabBar = uiViewController.tabBarController?.tabBar else {
                height = 0
                return
            }

            let safeBottom = uiViewController.view.window?.safeAreaInsets.bottom ?? uiViewController.view.safeAreaInsets.bottom
            let visibleHeight = max(tabBar.frame.height - safeBottom, 0)

            if abs(height - visibleHeight) > 0.5 {
                height = visibleHeight
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Feed.self, Article.self, Folder.self], inMemory: true)
        .environmentObject(AuthManager.shared)
}
