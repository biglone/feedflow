import Foundation
import SwiftUI
import SwiftData
import WebKit

struct ArticleReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    let article: Article

    @State private var showingSafari = false
    @State private var showingVideoPlayer = false
    @StateObject private var playerManager = PlayerManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(article.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack(spacing: 12) {
                        if let feed = article.feed {
                            HStack(spacing: 4) {
                                AsyncImage(url: URL(string: feed.iconURL ?? "")) { image in
                                    image
                                        .resizable()
                                        .scaledToFit()
                                } placeholder: {
                                    Image(systemName: "newspaper")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 3))

                                Text(feed.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let author = article.author, !author.isEmpty {
                            Text("by \(author)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let publishedAt = article.publishedAt {
                        Text(publishedAt, style: .date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // YouTube Play Button
                if youtubeVideoId != nil {
                    Button {
                        showingVideoPlayer = true
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 44))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Play Video")
                                    .font(.headline)
                                Text("Watch on FeedFlow")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }

                Divider()

                // Content
                if let content = article.content ?? article.summary {
                    HTMLContentView(htmlContent: content, colorScheme: colorScheme)
                        .padding(.horizontal)
                } else {
                    Text("No content available")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    toggleStar()
                } label: {
                    Image(systemName: article.isStarred ? "star.fill" : "star")
                        .foregroundStyle(article.isStarred ? .yellow : .primary)
                }

                if let url = article.articleURL, let _ = URL(string: url) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                Menu {
                    if let url = article.articleURL, let articleURL = URL(string: url) {
                        Button {
                            UIApplication.shared.open(articleURL)
                        } label: {
                            Label("Open in Safari", systemImage: "safari")
                        }
                    }

                    Button {
                        toggleRead()
                    } label: {
                        Label(
                            article.isRead ? "Mark as Unread" : "Mark as Read",
                            systemImage: article.isRead ? "circle" : "checkmark.circle"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            // Avoid mutating SwiftData while the originating List is still
            // completing its navigation/selection/layout updates (can crash
            // SwiftUI's internal UICollectionView-backed List).
            Task { @MainActor in
                await Task.yield()
                try? await Task.sleep(nanoseconds: 200_000_000)
                markAsRead()
            }
        }
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            if let videoId = youtubeVideoId {
                VideoPlayerView(
                    videoId: videoId,
                    title: article.title,
                    channelTitle: article.feed?.title ?? article.author ?? "",
                    thumbnailUrl: article.resolvedThumbnailURL
                )
            }
        }
    }

    private var youtubeVideoId: String? {
        article.youtubeVideoId
    }

    private func markAsRead() {
        if !article.isRead {
            withAnimation(nil) {
                article.isRead = true
                if let feed = article.feed, feed.unreadCount > 0 {
                    feed.unreadCount -= 1
                }
            }
            try? modelContext.save()
        }
    }

    private func toggleRead() {
        withAnimation(nil) {
            article.isRead.toggle()
            if let feed = article.feed {
                feed.unreadCount = feed.articles.filter { !$0.isRead }.count
            }
        }
        try? modelContext.save()
    }

    private func toggleStar() {
        withAnimation(nil) {
            article.isStarred.toggle()
        }
        try? modelContext.save()
    }
}

struct HTMLContentView: View {
    let htmlContent: String
    let colorScheme: ColorScheme
    @State private var contentHeight: CGFloat = 300

    var body: some View {
        HTMLWebView(htmlContent: styledHTML, colorScheme: colorScheme, contentHeight: $contentHeight)
            .frame(height: max(contentHeight, 300))
    }

    private var styledHTML: String {
        let textColor = colorScheme == .dark ? "#FFFFFF" : "#000000"
        let backgroundColor = colorScheme == .dark ? "#000000" : "#FFFFFF"
        let linkColor = colorScheme == .dark ? "#0A84FF" : "#007AFF"

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * {
                    box-sizing: border-box;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    font-size: 17px;
                    line-height: 1.6;
                    color: \(textColor);
                    background-color: \(backgroundColor);
                    margin: 0;
                    padding: 0;
                    word-wrap: break-word;
                    -webkit-text-size-adjust: 100%;
                }
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 8px;
                    margin: 12px 0;
                }
                a {
                    color: \(linkColor);
                    text-decoration: none;
                }
                a:hover {
                    text-decoration: underline;
                }
                p {
                    margin: 0 0 16px 0;
                }
                h1, h2, h3, h4, h5, h6 {
                    margin: 24px 0 12px 0;
                    line-height: 1.3;
                }
                blockquote {
                    border-left: 4px solid \(linkColor);
                    margin: 16px 0;
                    padding-left: 16px;
                    color: \(textColor);
                    opacity: 0.8;
                }
                pre, code {
                    background-color: \(colorScheme == .dark ? "#1C1C1E" : "#F2F2F7");
                    border-radius: 6px;
                    padding: 2px 6px;
                    font-family: 'SF Mono', Menlo, monospace;
                    font-size: 15px;
                }
                pre {
                    padding: 12px;
                    overflow-x: auto;
                }
                pre code {
                    padding: 0;
                    background: none;
                }
                ul, ol {
                    padding-left: 24px;
                }
                li {
                    margin-bottom: 8px;
                }
                hr {
                    border: none;
                    border-top: 1px solid \(colorScheme == .dark ? "#38383A" : "#C6C6C8");
                    margin: 24px 0;
                }
                table {
                    width: 100%;
                    border-collapse: collapse;
                    margin: 16px 0;
                }
                th, td {
                    border: 1px solid \(colorScheme == .dark ? "#38383A" : "#C6C6C8");
                    padding: 8px;
                    text-align: left;
                }
                figure {
                    margin: 16px 0;
                }
                figcaption {
                    font-size: 14px;
                    color: \(textColor);
                    opacity: 0.6;
                    text-align: center;
                    margin-top: 8px;
                }
                iframe {
                    max-width: 100%;
                }
                video {
                    max-width: 100%;
                }
            </style>
        </head>
        <body>
            \(htmlContent)
        </body>
        </html>
        """
    }
}

struct HTMLWebView: UIViewRepresentable {
    let htmlContent: String
    let colorScheme: ColorScheme
    @Binding var contentHeight: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.startObservingContentSize(of: webView)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastLoadedHTML != htmlContent else { return }
        context.coordinator.lastLoadedHTML = htmlContent
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObservingContentSize()
        uiView.navigationDelegate = nil
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        private var contentHeight: Binding<CGFloat>
        fileprivate var lastLoadedHTML: String?
        private var contentSizeObservation: NSKeyValueObservation?

        init(contentHeight: Binding<CGFloat>) {
            self.contentHeight = contentHeight
        }

        func startObservingContentSize(of webView: WKWebView) {
            contentSizeObservation = webView.scrollView.observe(\.contentSize, options: [.new]) { [weak self] scrollView, _ in
                guard let self else { return }
                self.updateContentHeight(scrollView.contentSize.height)
            }
        }

        func stopObservingContentSize() {
            contentSizeObservation?.invalidate()
            contentSizeObservation = nil
        }

        private func updateContentHeight(_ height: CGFloat) {
            guard height.isFinite, !height.isNaN, height > 0 else { return }

            DispatchQueue.main.async {
                if abs(self.contentHeight.wrappedValue - height) > 1 {
                    self.contentHeight.wrappedValue = height
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateContentHeight(webView.scrollView.contentSize.height)
        }
    }
}

#Preview {
    NavigationStack {
        ArticleReaderView(article: Article(
            guid: "preview",
            title: "Sample Article Title",
            content: "<p>This is a sample article content with <strong>bold</strong> and <em>italic</em> text.</p>",
            summary: "A brief summary",
            publishedAt: Date()
        ))
    }
    .modelContainer(for: [Feed.self, Article.self, Folder.self], inMemory: true)
}
