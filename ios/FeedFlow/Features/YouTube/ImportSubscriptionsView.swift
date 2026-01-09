import SwiftUI

struct YouTubeSubscription: Codable, Identifiable {
    let channelId: String
    let title: String
    let description: String
    let thumbnailUrl: String
    let rssUrl: String

    var id: String { channelId }
}

struct ImportSubscriptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var authManager = GoogleAuthManager.shared
    @State private var subscriptions: [YouTubeSubscription] = []
    @State private var selectedIds: Set<String> = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var showingError = false
    @State private var importedCount = 0
    @State private var showingSuccess = false

    private let apiClient = APIClient.shared

    var body: some View {
        NavigationStack {
            Group {
                if !authManager.isAuthenticated {
                    // Login view
                    VStack(spacing: 24) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.red)

                        Text("Import YouTube Subscriptions")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Sign in with your Google account to import your YouTube subscriptions as RSS feeds.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Button {
                            Task { await signIn() }
                        } label: {
                            HStack {
                                if authManager.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "person.circle.fill")
                                }
                                Text("Sign in with Google")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(authManager.isLoading)
                        .padding(.horizontal, 32)
                    }
                    .padding()
                } else if isLoading && subscriptions.isEmpty {
                    // Loading view
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading subscriptions...")
                            .foregroundStyle(.secondary)
                    }
                } else if subscriptions.isEmpty {
                    // Empty state
                    ContentUnavailableView(
                        "No Subscriptions",
                        systemImage: "play.rectangle",
                        description: Text("No YouTube subscriptions found in your account.")
                    )
                } else {
                    // Subscriptions list
                    List(subscriptions) { subscription in
                        SubscriptionRow(
                            subscription: subscription,
                            isSelected: selectedIds.contains(subscription.channelId)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSelection(subscription.channelId)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Import Subscriptions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if authManager.isAuthenticated && !subscriptions.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Import (\(selectedIds.count))") {
                            Task { await importSelected() }
                        }
                        .disabled(selectedIds.isEmpty || isLoading)
                    }

                    ToolbarItem(placement: .bottomBar) {
                        HStack {
                            Button("Select All") {
                                selectedIds = Set(subscriptions.map { $0.channelId })
                            }
                            Spacer()
                            Button("Deselect All") {
                                selectedIds.removeAll()
                            }
                        }
                    }
                }

                if authManager.isAuthenticated {
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Sign Out", role: .destructive) {
                            authManager.logout()
                            subscriptions = []
                            selectedIds = []
                        }
                    }
                }
            }
            .task {
                if authManager.isAuthenticated {
                    await loadSubscriptions()
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error?.localizedDescription ?? "Unknown error")
            }
            .alert("Success", isPresented: $showingSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Successfully imported \(importedCount) YouTube channels.")
            }
        }
    }

    private func signIn() async {
        do {
            try await authManager.startOAuthFlow()
            await loadSubscriptions()
        } catch {
            self.error = error
            showingError = true
        }
    }

    private func loadSubscriptions() async {
        guard let accessToken = authManager.accessToken else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            struct SubscriptionsResponse: Codable {
                let subscriptions: [YouTubeSubscription]
            }

            let response: SubscriptionsResponse = try await apiClient.requestWithToken(
                method: "GET",
                path: "/youtube/subscriptions",
                token: accessToken
            )

            subscriptions = response.subscriptions
            // Select all by default
            selectedIds = Set(subscriptions.map { $0.channelId })
        } catch {
            self.error = error
            showingError = true
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func importSelected() async {
        isLoading = true
        defer { isLoading = false }

        let selectedSubscriptions = subscriptions.filter { selectedIds.contains($0.channelId) }
        var successCount = 0

        for subscription in selectedSubscriptions {
            let feed = Feed(
                title: subscription.title,
                feedURL: subscription.rssUrl,
                iconURL: subscription.thumbnailUrl,
                feedDescription: subscription.description
            )

            modelContext.insert(feed)
            successCount += 1
        }

        try? modelContext.save()

        importedCount = successCount
        showingSuccess = true
    }
}

struct SubscriptionRow: View {
    let subscription: YouTubeSubscription
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: subscription.thumbnailUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(subscription.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(subscription.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? .blue : .gray)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ImportSubscriptionsView()
}
