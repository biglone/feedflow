import SwiftUI
import SwiftData

struct AddFeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var feedURL = ""
    @State private var isLoading = false
    @State private var error: Error?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feed URL or website", text: $feedURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Enter RSS feed URL")
                } footer: {
                    Text("Enter an RSS feed URL or a website URL. FeedFlow will try to discover the feed automatically.")
                }

                Section {
                    Button {
                        Task {
                            await addFeed()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Add Feed")
                            }
                            Spacer()
                        }
                    }
                    .disabled(feedURL.isEmpty || isLoading)
                }
            }
            .navigationTitle("Add Feed")
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
                Text(error?.localizedDescription ?? "Unknown error")
            }
        }
    }

    private func addFeed() async {
        isLoading = true
        defer { isLoading = false }

        let feedManager = FeedManager(modelContext: modelContext)

        do {
            _ = try await feedManager.addFeed(url: feedURL)
            dismiss()
        } catch {
            self.error = error
            self.showingError = true
        }
    }
}

#Preview {
    AddFeedView()
        .modelContainer(for: [Feed.self, Article.self, Folder.self], inMemory: true)
}
