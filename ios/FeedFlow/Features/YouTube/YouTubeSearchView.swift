import SwiftUI
import SwiftData

struct YouTubeSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var channels: [APIClient.YouTubeChannelDTO] = []
    @State private var searchQuery = ""
    @State private var nextPageToken: String?
    @State private var isSearching = false
    @State private var isLoadingMore = false
    @State private var error: Error?
    @State private var showingError = false
    @State private var subscribingChannelId: String?

    private let apiClient = APIClient.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search YouTube channels", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .onSubmit {
                            Task { await search() }
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            channels = []
                            searchQuery = ""
                            nextPageToken = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()

                // Results
                if isSearching {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                } else if channels.isEmpty && !searchText.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No Channels Found",
                        systemImage: "play.rectangle",
                        description: Text("Try a different search term")
                    )
                    Spacer()
                } else if channels.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("Search for YouTube channels")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Subscribe to your favorite creators")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(channels, id: \.id) { channel in
                            YouTubeChannelRowView(
                                channel: channel,
                                isSubscribing: subscribingChannelId == channel.id,
                                onSubscribe: { await subscribeToChannel(channel) }
                            )
                        }

                        if let nextPageToken {
                            Button {
                                Task { await loadMore(nextPageToken: nextPageToken) }
                            } label: {
                                HStack {
                                    Text("Load more")
                                    Spacer()
                                    if isLoadingMore {
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(isLoadingMore)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error?.localizedDescription ?? "An unknown error occurred")
            }
        }
    }

    @MainActor
    private func search() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        isSearching = true
        defer { isSearching = false }

        do {
            let page = try await apiClient.searchYouTubeChannelsPage(query: query, limit: 50, pageToken: nil)
            searchQuery = query
            channels = page.channels
            nextPageToken = page.nextPageToken
        } catch {
            self.error = error
            self.showingError = true
        }
    }

    @MainActor
    private func loadMore(nextPageToken: String) async {
        guard !searchQuery.isEmpty else { return }
        guard !isSearching else { return }
        guard !isLoadingMore else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await apiClient.searchYouTubeChannelsPage(
                query: searchQuery,
                limit: 50,
                pageToken: nextPageToken
            )

            let existingIds = Set(channels.map(\.id))
            channels.append(contentsOf: page.channels.filter { !existingIds.contains($0.id) })
            self.nextPageToken = page.nextPageToken
        } catch {
            self.error = error
            self.showingError = true
        }
    }

    @MainActor
    private func subscribeToChannel(_ channel: APIClient.YouTubeChannelDTO) async {
        subscribingChannelId = channel.id
        defer { subscribingChannelId = nil }

        do {
            // Get the RSS feed URL
            let rssUrl = try await apiClient.getYouTubeChannelRssUrl(channelId: channel.id)

            // Add the feed using FeedManager
            let feedManager = FeedManager(modelContext: modelContext)
            _ = try await feedManager.addFeed(url: rssUrl, kindHint: .youtube)

            // Dismiss the view on success
            dismiss()
        } catch {
            self.error = error
            self.showingError = true
        }
    }
}

struct YouTubeChannelRowView: View {
    let channel: APIClient.YouTubeChannelDTO
    let isSubscribing: Bool
    let onSubscribe: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Channel thumbnail
            AsyncImage(url: URL(string: channel.thumbnailUrl)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.2))
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())

            // Channel info
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(formatSubscriberCount(channel.subscriberCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !channel.description.isEmpty {
                    Text(channel.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Subscribe button
            Button {
                Task { await onSubscribe() }
            } label: {
                if isSubscribing {
                    ProgressView()
                        .frame(width: 80)
                } else {
                    Text("Subscribe")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubscribing)
        }
        .padding(.vertical, 8)
    }

    private func formatSubscriberCount(_ count: String) -> String {
        guard let number = Int(count) else { return count }

        if number >= 1_000_000 {
            return String(format: "%.1fM subscribers", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK subscribers", Double(number) / 1_000)
        } else {
            return "\(number) subscribers"
        }
    }
}

#Preview {
    YouTubeSearchView()
        .modelContainer(for: [Feed.self, Article.self, Folder.self], inMemory: true)
}
