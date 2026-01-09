import SwiftUI
import SwiftData

@main
struct FeedFlowApp: App {
    @StateObject private var authManager = AuthManager.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Feed.self,
            Article.self,
            Folder.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
        .modelContainer(sharedModelContainer)
    }
}
