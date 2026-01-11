import SwiftUI
import SwiftData

struct StarredArticlesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Article> { $0.isStarred })
    private var starredArticles: [Article]

    private var sortedStarredArticles: [Article] {
        starredArticles.sorted {
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
    }

    var body: some View {
        NavigationStack {
            List {
                if sortedStarredArticles.isEmpty {
                    ContentUnavailableView(
                        "No Starred Articles",
                        systemImage: "star",
                        description: Text("Star articles to save them here")
                    )
                } else {
                    ForEach(sortedStarredArticles) { article in
                        NavigationLink {
                            ArticleReaderView(article: article)
                        } label: {
                            TimelineArticleRowView(article: article)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                unstar(article)
                            } label: {
                                Label("Unstar", systemImage: "star.slash")
                            }
                        }
                    }
                }
            }
            .transaction { $0.animation = nil }
            .navigationTitle("Starred")
        }
    }

    private func unstar(_ article: Article) {
        article.isStarred = false
        try? modelContext.save()
    }
}

#Preview {
    StarredArticlesView()
        .modelContainer(for: [Feed.self, Article.self, Folder.self], inMemory: true)
}
