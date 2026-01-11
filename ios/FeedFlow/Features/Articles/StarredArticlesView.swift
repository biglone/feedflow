import SwiftUI
import SwiftData

struct StarredArticlesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Article> { $0.isStarred }, sort: \Article.publishedAt, order: .reverse)
    private var starredArticles: [Article]

    var body: some View {
        NavigationStack {
            List {
                if starredArticles.isEmpty {
                    ContentUnavailableView(
                        "No Starred Articles",
                        systemImage: "star",
                        description: Text("Star articles to save them here")
                    )
                } else {
                    ForEach(starredArticles) { article in
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
