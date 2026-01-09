import SwiftUI
import SwiftData

struct ArticlesListView: View {
    @Environment(\.modelContext) private var modelContext
    let feed: Feed?

    @State private var selectedArticle: Article?

    var articles: [Article] {
        guard let feed = feed else { return [] }
        return feed.articles.sorted { ($0.publishedAt ?? Date.distantPast) > ($1.publishedAt ?? Date.distantPast) }
    }

    var body: some View {
        List {
            if articles.isEmpty {
                ContentUnavailableView(
                    "No Articles",
                    systemImage: "doc.text",
                    description: Text("Pull to refresh and check for new articles")
                )
            } else {
                ForEach(articles) { article in
                    NavigationLink(value: article) {
                        ArticleRowView(article: article)
                    }
                }
            }
        }
        .navigationTitle(feed?.title ?? "Articles")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Article.self) { article in
            ArticleReaderView(article: article)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        markAllAsRead()
                    } label: {
                        Label("Mark All as Read", systemImage: "checkmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func markAllAsRead() {
        guard let feed = feed else { return }
        let feedManager = FeedManager(modelContext: modelContext)
        feedManager.markAllAsRead(in: feed)
    }
}

struct ArticleRowView: View {
    let article: Article

    var body: some View {
        HStack(spacing: 12) {
            if let imageURL = article.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }
                .frame(width: 80, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.headline)
                    .fontWeight(article.isRead ? .regular : .semibold)
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let author = article.author {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let publishedAt = article.publishedAt {
                        Text(publishedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if article.isStarred {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                if let summary = article.summary {
                    Text(summary.strippingHTML())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

extension String {
    func strippingHTML() -> String {
        guard let data = self.data(using: .utf8) else { return self }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        return attributedString.string
    }
}

#Preview {
    NavigationStack {
        ArticlesListView(feed: nil)
    }
    .modelContainer(for: [Feed.self, Article.self, Folder.self], inMemory: true)
}
