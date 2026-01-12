import SwiftUI
import SwiftData

struct FeedsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @State private var showingAddFeed = false
    @State private var showingYouTubeSearch = false
    @State private var showingImportSubscriptions = false
    @State private var showingRecommendedFeeds = false
    @AppStorage("didShowRecommendedFeeds") private var didShowRecommendedFeeds = false

    private var feedsByKind: [FeedKind: [Feed]] {
        Dictionary(grouping: feeds, by: \.resolvedKind)
    }

    private var kindSections: [FeedKind] {
        FeedKind.displayOrder.filter { !(feedsByKind[$0] ?? []).isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                if feeds.isEmpty {
                    ContentUnavailableView(
                        "No Feeds",
                        systemImage: "newspaper",
                        description: Text("Add your first RSS feed to get started")
                    )
                    Button("Browse Popular Subscriptions") {
                        showingRecommendedFeeds = true
                        didShowRecommendedFeeds = true
                    }
                } else {
                    ForEach(kindSections, id: \.self) { kind in
                        let sectionFeeds = feedsByKind[kind] ?? []
                        Section {
                            ForEach(sectionFeeds) { feed in
                                NavigationLink {
                                    ArticlesListView(feed: feed)
                                } label: {
                                    FeedRowView(feed: feed)
                                }
                            }
                            .onDelete { offsets in
                                deleteFeeds(sectionFeeds, at: offsets)
                            }
                        } header: {
                            Label(kind.displayName, systemImage: kind.systemImageName)
                        }
                    }
                }
            }
            .transaction { $0.animation = nil }
            .navigationTitle("Feeds")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingAddFeed = true
                        } label: {
                            Label("Add RSS Feed", systemImage: "newspaper")
                        }

                        Button {
                            showingYouTubeSearch = true
                        } label: {
                            Label("Subscribe YouTube", systemImage: "play.rectangle")
                        }

                        Divider()

                        Button {
                            showingRecommendedFeeds = true
                            didShowRecommendedFeeds = true
                        } label: {
                            Label("Popular Subscriptions", systemImage: "sparkles")
                        }

                        Button {
                            showingImportSubscriptions = true
                        } label: {
                            Label("Import from YouTube", systemImage: "arrow.down.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                let feedManager = FeedManager(modelContext: modelContext)
                await feedManager.refreshAllFeeds()
            }
            .task {
                if feeds.isEmpty && !didShowRecommendedFeeds {
                    showingRecommendedFeeds = true
                    didShowRecommendedFeeds = true
                }
            }
            .sheet(isPresented: $showingAddFeed) {
                AddFeedView()
            }
            .sheet(isPresented: $showingYouTubeSearch) {
                YouTubeSearchView()
            }
            .sheet(isPresented: $showingImportSubscriptions) {
                ImportSubscriptionsView()
            }
            .sheet(isPresented: $showingRecommendedFeeds) {
                RecommendedFeedsView()
            }
        }
    }

    private func deleteFeeds(_ feeds: [Feed], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(feeds[index])
        }
        try? modelContext.save()
    }
}

struct FeedRowView: View {
    let feed: Feed

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: feed.iconURL ?? "")) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Image(systemName: feed.resolvedKind.systemImageName)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(.body)
                    .lineLimit(1)

                if let description = feed.feedDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if feed.resolvedKind != .rss {
                Text(feed.resolvedKind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(Capsule())
            }

            if feed.unreadCount > 0 {
                Text("\(feed.unreadCount)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RecommendedFeed: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case rss = "RSS"
        case youtube = "YouTube"
        case podcast = "Podcast"
    }

    let id: String
    let title: String
    let url: String
    let category: String
    let kind: Kind
    let description: String?

    init(
        title: String,
        url: String,
        category: String,
        kind: Kind = .rss,
        description: String? = nil
    ) {
        self.id = url
        self.title = title
        self.url = url
        self.category = category
        self.kind = kind
        self.description = description
    }
}

private enum RecommendedFeedCatalog {
    static let categoryOrder: [String: Int] = [
        "中文": 0,
        "YouTube 中文": 1,
        "YouTube Global": 2,
        "Linux": 3,
        "Programming": 4,
        "DevOps": 5,
        "AI": 6,
        "Tech": 7,
        "Community": 8,
        "Design": 9,
        "Security": 10,
        "Science": 11,
        "Podcast": 12,
    ]

	    static let items: [RecommendedFeed] = [
	        RecommendedFeed(
	            title: "少数派",
	            url: "https://sspai.com/feed",
	            category: "中文",
	            description: "数字生活与效率"
	        ),
	        RecommendedFeed(
	            title: "小众软件",
	            url: "https://www.appinn.com/feed/",
	            category: "中文",
	            description: "精品应用与效率工具"
	        ),
	        RecommendedFeed(
	            title: "阮一峰的网络日志",
	            url: "https://www.ruanyifeng.com/blog/atom.xml",
	            category: "中文",
	            description: "技术、周刊与随笔"
	        ),
	        RecommendedFeed(
	            title: "V2EX",
	            url: "https://www.v2ex.com/index.xml",
	            category: "中文",
	            description: "创意工作者社区"
	        ),
	        RecommendedFeed(
	            title: "酷壳",
	            url: "https://coolshell.cn/feed",
	            category: "中文",
	            description: "技术与思考"
	        ),
	        RecommendedFeed(
	            title: "爱范儿",
	            url: "https://www.ifanr.com/feed",
	            category: "中文",
	            description: "科技与消费电子"
	        ),
	        RecommendedFeed(
	            title: "HelloGitHub",
	            url: "https://hellogithub.com/rss",
	            category: "中文",
	            description: "有趣的开源项目精选"
	        ),
            RecommendedFeed(
                title: "极客湾 Geekerwan",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCNi3K9HUzuTmILZH0iGupkw",
                category: "YouTube 中文",
                kind: .youtube,
                description: "硬件评测与技术科普"
            ),
            RecommendedFeed(
                title: "李永乐老师",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCSQsmKOnRA-2ol6a3M4Rpug",
                category: "YouTube 中文",
                kind: .youtube,
                description: "数学、物理与科普"
            ),
            RecommendedFeed(
                title: "回形针PaperClip",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCg3Ny8s-SJRtP93kH6cMDew",
                category: "YouTube 中文",
                kind: .youtube,
                description: "知识科普"
            ),
            RecommendedFeed(
                title: "小宁子",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCEwYe1cxnI9czwt_2u2hOcA",
                category: "YouTube 中文",
                kind: .youtube,
                description: "数码与科技"
            ),
            RecommendedFeed(
                title: "Veritasium",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCHnyfMqiRRG1u-2MsSQLbXA",
                category: "YouTube Global",
                kind: .youtube,
                description: "Science videos"
            ),
            RecommendedFeed(
                title: "Kurzgesagt – In a Nutshell",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsXVk37bltHxD1rDPwtNM8Q",
                category: "YouTube Global",
                kind: .youtube,
                description: "Science in a nutshell"
            ),
            RecommendedFeed(
                title: "3Blue1Brown",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCYO_jab_esuFRV4b17AJtAw",
                category: "YouTube Global",
                kind: .youtube,
                description: "Math & intuition"
            ),
            RecommendedFeed(
                title: "Fireship",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsBjURrPoezykLs9EqgamOA",
                category: "YouTube Global",
                kind: .youtube,
                description: "Fast-paced dev videos"
            ),
            RecommendedFeed(
                title: "Computerphile",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC9-y-6csu5WGm29I7JiwpnA",
                category: "YouTube Global",
                kind: .youtube,
                description: "Computer science"
            ),
            RecommendedFeed(
                title: "Two Minute Papers",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCbfYPyITQ-7l4upoX8nvctg",
                category: "YouTube Global",
                kind: .youtube,
                description: "AI research highlights"
            ),
            RecommendedFeed(
                title: "The Coding Train",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCvjgXvBlbQiydffZU7m1_aw",
                category: "YouTube Global",
                kind: .youtube,
                description: "Creative coding"
            ),
            RecommendedFeed(
                title: "freeCodeCamp.org",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC8butISFwT-Wl7EV0hUK0BQ",
                category: "YouTube Global",
                kind: .youtube,
                description: "Programming tutorials"
            ),
            RecommendedFeed(
                title: "Google Developers",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC_x5XG1OV2P6uZZ5FSM9Ttw",
                category: "YouTube Global",
                kind: .youtube,
                description: "Developer updates"
            ),
            RecommendedFeed(
                title: "TED",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCAuUUnT6oDeKwE6v1NGQxug",
                category: "YouTube Global",
                kind: .youtube,
                description: "Ideas worth spreading"
            ),
            RecommendedFeed(
                title: "MIT OpenCourseWare",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCEBb1b_L6zDS3xTUrIALZOw",
                category: "YouTube Global",
                kind: .youtube,
                description: "Open courses"
            ),
            RecommendedFeed(
                title: "NASA",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCLA_DiR1FfKNvjuUpBHmylQ",
                category: "YouTube Global",
                kind: .youtube,
                description: "Space & science"
            ),
            RecommendedFeed(
                title: "Linus Tech Tips",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCXuqSBlHAE6Xw-yeJA0Tunw",
                category: "YouTube Global",
                kind: .youtube,
                description: "Tech & hardware"
            ),
            RecommendedFeed(
                title: "MKBHD",
                url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCBJycsmduvYEL83R_U4JriQ",
                category: "YouTube Global",
                kind: .youtube,
                description: "Tech reviews"
            ),
	        RecommendedFeed(
	            title: "Linux Do",
	            url: "https://linux.do/latest.rss",
	            category: "Linux",
	            description: "中文 Linux 社区"
	        ),
        RecommendedFeed(
            title: "Linux.com",
            url: "https://www.linux.com/feed/",
            category: "Linux",
            description: "Linux news"
        ),
        RecommendedFeed(
            title: "It's FOSS",
            url: "https://itsfoss.com/feed/",
            category: "Linux",
            description: "Linux tips & news"
        ),
        RecommendedFeed(
            title: "OMG! Ubuntu",
            url: "https://www.omgubuntu.co.uk/feed",
            category: "Linux",
            description: "Ubuntu news"
        ),
        RecommendedFeed(
            title: "Fedora Magazine",
            url: "https://fedoramagazine.org/feed/",
            category: "Linux",
            description: "Fedora community blog"
        ),
        RecommendedFeed(
            title: "Arch Linux News",
            url: "https://archlinux.org/feeds/news/",
            category: "Linux",
            description: "Arch announcements"
        ),
	        RecommendedFeed(
	            title: "Kernel Releases",
	            url: "https://www.kernel.org/feeds/kdist.xml",
	            category: "Linux",
	            description: "Linux kernel releases"
	        ),
	        RecommendedFeed(
	            title: "LXer",
	            url: "https://lxer.com/module/newswire/headlines.rss",
	            category: "Linux",
	            description: "Linux newswire headlines"
	        ),
	        RecommendedFeed(
	            title: "LWN.net",
	            url: "https://lwn.net/headlines/rss",
	            category: "Linux",
	            description: "Linux and free software news"
	        ),
	        RecommendedFeed(
	            title: "DistroWatch",
	            url: "https://distrowatch.com/news/dwd.xml",
	            category: "Linux",
	            description: "Linux distributions news"
	        ),
	        RecommendedFeed(
	            title: "GitHub Blog",
	            url: "https://github.blog/feed/",
	            category: "Programming",
	            description: "Engineering, open source, and GitHub updates"
	        ),
	        RecommendedFeed(
	            title: "Stack Overflow Blog",
	            url: "https://stackoverflow.blog/feed/",
	            category: "Programming",
	            description: "Engineering and developer culture"
	        ),
	        RecommendedFeed(
	            title: "Martin Fowler",
	            url: "https://martinfowler.com/feed.atom",
	            category: "Programming",
	            description: "Architecture, refactoring, and software design"
	        ),
	        RecommendedFeed(
	            title: "Julia Evans",
	            url: "https://jvns.ca/atom.xml",
	            category: "Programming",
	            description: "Debugging, Linux, and programming"
	        ),
	        RecommendedFeed(
	            title: "Overreacted",
	            url: "https://overreacted.io/rss.xml",
	            category: "Programming",
	            description: "React and engineering essays"
	        ),
	        RecommendedFeed(
	            title: "Google Developers Blog",
	            url: "https://developers.googleblog.com/feeds/posts/default",
	            category: "Programming",
	            description: "Google developer updates"
	        ),
	        RecommendedFeed(
	            title: "Python Insider",
	            url: "https://blog.python.org/feeds/posts/default",
	            category: "Programming",
	            description: "Python release and ecosystem news"
	        ),
	        RecommendedFeed(
	            title: "The Go Blog",
	            url: "https://go.dev/blog/feed.atom",
	            category: "Programming",
	            description: "Go official blog"
	        ),
        RecommendedFeed(
            title: "Rust Blog",
            url: "https://blog.rust-lang.org/feed.xml",
            category: "Programming",
            description: "Rust language updates"
        ),
	        RecommendedFeed(
	            title: "Swift.org",
	            url: "https://swift.org/atom.xml",
	            category: "Programming",
	            description: "Swift language updates"
	        ),
	        RecommendedFeed(
	            title: "Swift by Sundell",
	            url: "https://swiftbysundell.com/feed.rss",
	            category: "Programming",
	            description: "Swift and app development"
	        ),
	        RecommendedFeed(
	            title: "Dropbox Tech",
	            url: "https://dropbox.tech/feed",
	            category: "Programming",
	            description: "Dropbox engineering blog"
	        ),
	        RecommendedFeed(
	            title: "Kubernetes Blog",
	            url: "https://kubernetes.io/feed.xml",
	            category: "DevOps",
            description: "Kubernetes blog & announcements"
        ),
        RecommendedFeed(
            title: "Docker Blog",
            url: "https://www.docker.com/blog/feed/",
            category: "DevOps",
            description: "Docker news & engineering"
        ),
	        RecommendedFeed(
	            title: "Cloudflare Blog",
	            url: "https://blog.cloudflare.com/rss/",
	            category: "DevOps",
	            description: "Networking, security, and performance"
	        ),
	        RecommendedFeed(
	            title: "AWS News Blog",
	            url: "https://aws.amazon.com/blogs/aws/feed/",
	            category: "DevOps",
	            description: "AWS announcements and launches"
	        ),
	        RecommendedFeed(
	            title: "GitLab Blog",
	            url: "https://about.gitlab.com/atom.xml",
	            category: "DevOps",
	            description: "DevOps platform updates"
	        ),
	        RecommendedFeed(
	            title: "HashiCorp Blog",
	            url: "https://www.hashicorp.com/blog/feed.xml",
	            category: "DevOps",
	            description: "Terraform, Vault, and cloud tooling"
	        ),
	        RecommendedFeed(
	            title: "Spotify Engineering",
	            url: "https://engineering.atspotify.com/feed",
	            category: "DevOps",
	            description: "Spotify engineering stories"
	        ),
	        RecommendedFeed(
	            title: "Meta Engineering",
	            url: "https://engineering.fb.com/feed/",
	            category: "DevOps",
	            description: "Meta engineering blog"
	        ),
	        RecommendedFeed(
	            title: "OpenAI Blog",
	            url: "https://openai.com/blog/rss.xml",
            category: "AI",
            description: "OpenAI updates"
        ),
	        RecommendedFeed(
	            title: "Google AI",
	            url: "https://blog.google/technology/ai/rss/",
	            category: "AI",
	            description: "Google AI news"
	        ),
	        RecommendedFeed(
	            title: "Hugging Face",
	            url: "https://huggingface.co/blog/feed.xml",
	            category: "AI",
	            description: "Open-source AI community updates"
	        ),
	        RecommendedFeed(
	            title: "AWS Machine Learning Blog",
	            url: "https://aws.amazon.com/blogs/machine-learning/feed/",
	            category: "AI",
	            description: "Machine learning guides and releases"
	        ),
	        RecommendedFeed(
	            title: "The Gradient",
	            url: "https://thegradient.pub/rss/",
	            category: "AI",
	            description: "AI research and commentary"
	        ),
	        RecommendedFeed(
	            title: "Google Research",
	            url: "https://research.googleblog.com/feeds/posts/default",
	            category: "AI",
	            description: "Research highlights"
	        ),
	        RecommendedFeed(
	            title: "Microsoft Research",
	            url: "https://www.microsoft.com/en-us/research/feed/",
	            category: "AI",
	            description: "Research and AI updates"
	        ),
	        RecommendedFeed(
	            title: "Hacker News",
	            url: "https://hnrss.org/frontpage",
	            category: "Tech",
	            description: "Tech & startups"
	        ),
	        RecommendedFeed(
	            title: "TechCrunch",
	            url: "https://techcrunch.com/feed/",
	            category: "Tech",
	            description: "Startups and technology news"
	        ),
	        RecommendedFeed(
	            title: "The Register",
	            url: "https://www.theregister.com/headlines.atom",
	            category: "Tech",
	            description: "IT industry news"
	        ),
        RecommendedFeed(
            title: "The Verge",
            url: "https://www.theverge.com/rss/index.xml",
            category: "Tech",
            description: "Technology news"
        ),
	        RecommendedFeed(
	            title: "Ars Technica",
	            url: "https://feeds.arstechnica.com/arstechnica/index",
	            category: "Tech",
	            description: "Technology & science"
	        ),
	        RecommendedFeed(
	            title: "WIRED",
	            url: "https://www.wired.com/feed/rss",
	            category: "Tech",
	            description: "Technology and culture"
	        ),
	        RecommendedFeed(
	            title: "Engadget",
	            url: "https://www.engadget.com/rss.xml",
	            category: "Tech",
	            description: "Gadgets and consumer tech"
	        ),
	        RecommendedFeed(
	            title: "9to5Mac",
	            url: "https://9to5mac.com/feed/",
	            category: "Tech",
	            description: "Apple news and rumors"
	        ),
	        RecommendedFeed(
	            title: "MacRumors",
	            url: "https://www.macrumors.com/macrumors.xml",
	            category: "Tech",
	            description: "Apple rumors and news"
	        ),
	        RecommendedFeed(
	            title: "Android Police",
	            url: "https://www.androidpolice.com/feed/",
	            category: "Tech",
	            description: "Android and mobile tech"
	        ),
	        RecommendedFeed(
	            title: "Lobsters",
	            url: "https://lobste.rs/rss",
	            category: "Community",
	            description: "Tech community discussions"
	        ),
	        RecommendedFeed(
	            title: "DEV Community",
	            url: "https://dev.to/feed",
	            category: "Community",
	            description: "Community-driven developer stories"
	        ),
	        RecommendedFeed(
	            title: "Smashing Magazine",
	            url: "https://www.smashingmagazine.com/feed/",
	            category: "Design",
	            description: "UX/UI & front-end"
	        ),
	        RecommendedFeed(
	            title: "A List Apart",
	            url: "https://alistapart.com/main/feed/",
	            category: "Design",
	            description: "Design, development, and web standards"
	        ),
	        RecommendedFeed(
	            title: "CSS-Tricks",
	            url: "https://css-tricks.com/feed/",
	            category: "Design",
	            description: "CSS and front-end tips"
	        ),
	        RecommendedFeed(
	            title: "Nielsen Norman Group",
	            url: "https://www.nngroup.com/feed/rss/",
	            category: "Design",
	            description: "UX research & guidance"
	        ),
	        RecommendedFeed(
	            title: "Krebs on Security",
	            url: "https://krebsonsecurity.com/feed/",
	            category: "Security",
	            description: "Security news & investigations"
	        ),
	        RecommendedFeed(
	            title: "The Hacker News",
	            url: "https://feeds.feedburner.com/TheHackersNews",
	            category: "Security",
	            description: "Cybersecurity news"
	        ),
	        RecommendedFeed(
	            title: "Schneier on Security",
	            url: "https://www.schneier.com/feed/atom/",
	            category: "Security",
	            description: "Security analysis and commentary"
	        ),
	        RecommendedFeed(
	            title: "SANS Internet Storm Center",
	            url: "https://isc.sans.edu/rssfeed.xml",
	            category: "Security",
	            description: "Security diary and alerts"
	        ),
	        RecommendedFeed(
	            title: "BleepingComputer",
	            url: "https://www.bleepingcomputer.com/feed/",
	            category: "Security",
	            description: "Security news and malware reports"
	        ),
	        RecommendedFeed(
	            title: "NASA Breaking News",
	            url: "https://www.nasa.gov/rss/dyn/breaking_news.rss",
	            category: "Science",
	            description: "NASA updates"
	        ),
	        RecommendedFeed(
	            title: "NASA Image of the Day",
	            url: "https://www.nasa.gov/rss/dyn/lg_image_of_the_day.rss",
	            category: "Science",
	            description: "Daily space image"
	        ),
	        RecommendedFeed(
	            title: "Space.com",
	            url: "https://www.space.com/feeds/all",
	            category: "Science",
	            description: "Space news and discoveries"
	        ),
	        RecommendedFeed(
	            title: "The Changelog",
	            url: "https://changelog.com/podcast/feed",
	            category: "Podcast",
            kind: .podcast,
            description: "Software engineering podcast"
        ),
        RecommendedFeed(
            title: "Go Time",
            url: "https://changelog.com/gotime/feed",
            category: "Podcast",
            kind: .podcast,
            description: "Go podcast"
        ),
        RecommendedFeed(
            title: "JS Party",
            url: "https://changelog.com/jsparty/feed",
            category: "Podcast",
            kind: .podcast,
            description: "JavaScript podcast"
        ),
        RecommendedFeed(
            title: "Syntax",
            url: "https://feed.syntax.fm/rss",
            category: "Podcast",
            kind: .podcast,
            description: "Web dev podcast"
        ),
	        RecommendedFeed(
	            title: "Linux Unplugged",
	            url: "https://linuxunplugged.com/rss",
	            category: "Podcast",
	            kind: .podcast,
	            description: "Linux podcast"
	        ),
	        RecommendedFeed(
	            title: "Late Night Linux",
	            url: "https://latenightlinux.com/feed/mp3/",
	            category: "Podcast",
	            kind: .podcast,
	            description: "Linux & open source chat"
	        ),
	        RecommendedFeed(
	            title: "Core Intuition",
	            url: "https://coreint.org/podcast.xml",
	            category: "Podcast",
	            kind: .podcast,
	            description: "Software design & indie dev"
	        ),
	        RecommendedFeed(
	            title: "The Talk Show",
	            url: "https://daringfireball.net/thetalkshow/rss",
	            category: "Podcast",
	            kind: .podcast,
	            description: "Tech talk with John Gruber"
	        ),
	        RecommendedFeed(
	            title: "ShopTalk Show",
	            url: "https://shoptalkshow.com/feed/podcast/",
	            category: "Podcast",
	            kind: .podcast,
	            description: "Front-end web dev podcast"
	        ),
	        RecommendedFeed(
	            title: "Practical AI",
	            url: "https://changelog.com/practicalai/feed",
	            category: "Podcast",
	            kind: .podcast,
	            description: "Applied AI podcast"
	        ),
	        RecommendedFeed(
	            title: "Software Engineering Daily",
	            url: "https://softwareengineeringdaily.com/feed/podcast/",
	            category: "Podcast",
	            kind: .podcast,
	            description: "Daily software engineering interviews"
	        ),
	        RecommendedFeed(
	            title: "Hard Fork",
	            url: "https://feeds.simplecast.com/l2i9YnTd",
	            category: "Podcast",
	            kind: .podcast,
	            description: "Tech & AI from The New York Times"
	        ),
	        RecommendedFeed(
	            title: "The Vergecast",
	            url: "https://feeds.megaphone.fm/vergecast",
	            category: "Podcast",
	            kind: .podcast,
	            description: "The Verge podcast"
	        ),
	        RecommendedFeed(
	            title: "Security Now",
	            url: "https://feeds.twit.tv/sn.xml",
	            category: "Podcast",
	            kind: .podcast,
	            description: "Security news & analysis"
	        ),
	        RecommendedFeed(
	            title: "Python Bytes",
	            url: "https://pythonbytes.fm/episodes/rss",
	            category: "Podcast",
	            kind: .podcast,
	            description: "Python headlines & news"
	        ),
	        RecommendedFeed(
	            title: "Talk Python To Me",
	            url: "https://talkpython.fm/episodes/rss",
	            category: "Podcast",
	            kind: .podcast,
	            description: "Python interviews & stories"
	        ),
		        RecommendedFeed(
		            title: "Darknet Diaries",
		            url: "https://feeds.megaphone.fm/darknetdiaries",
		            category: "Podcast",
		            kind: .podcast,
	            description: "True stories from the dark side of the internet"
	        ),
	        RecommendedFeed(
	            title: "Accidental Tech Podcast",
	            url: "https://atp.fm/rss",
	            category: "Podcast",
	            kind: .podcast,
	            description: "Three nerds discussing tech"
	        ),
	        RecommendedFeed(
	            title: "Under the Radar",
	            url: "https://www.relay.fm/radar/feed",
	            category: "Podcast",
	            kind: .podcast,
	            description: "App development and indie business"
	        ),
	        RecommendedFeed(
	            title: "Lex Fridman Podcast",
	            url: "https://lexfridman.com/feed/podcast/",
	            category: "Podcast",
	            kind: .podcast,
	            description: "AI, science, and long-form conversations"
	        ),
	        RecommendedFeed(
	            title: "Stack Overflow Podcast",
	            url: "https://stackoverflow.blog/podcast/feed/",
	            category: "Podcast",
	            kind: .podcast,
	            description: "Developer stories and tech news"
	        ),
	        RecommendedFeed(
	            title: "Swift by Sundell (Podcast)",
	            url: "https://swiftbysundell.com/podcast/feed.rss",
	            category: "Podcast",
	            kind: .podcast,
	            description: "Swift development interviews"
	        ),
	    ]
	}

struct RecommendedFeedsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var feeds: [Feed]

    @State private var addingId: String?
    @State private var isAddingAll = false
    @State private var error: Error?
    @State private var showingError = false

    private var subscribedURLs: Set<String> {
        Set(feeds.map(\.feedURL))
    }

    private var categorizedItems: [(category: String, items: [RecommendedFeed])] {
        let grouped = Dictionary(grouping: RecommendedFeedCatalog.items, by: \.category)
        return grouped
            .map { (key, value) in (category: key, items: value.sorted { $0.title < $1.title }) }
            .sorted { lhs, rhs in
                let lhsOrder = RecommendedFeedCatalog.categoryOrder[lhs.category] ?? Int.max
                let rhsOrder = RecommendedFeedCatalog.categoryOrder[rhs.category] ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.category < rhs.category
            }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(categorizedItems, id: \.category) { section in
                    Section(section.category) {
                        ForEach(section.items) { item in
                            RecommendedFeedRow(
                                item: item,
                                isAdded: subscribedURLs.contains(item.url),
                                isAdding: addingId == item.id,
                                onAdd: { Task { await add(item) } }
                            )
                        }
                    }
                }
            }
            .transaction { $0.animation = nil }
            .navigationTitle("Popular Subscriptions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await addAll() }
                    } label: {
                        if isAddingAll {
                            ProgressView()
                        } else {
                            Text("Add All")
                        }
                    }
                    .disabled(isAddingAll)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error?.localizedDescription ?? "Failed to add feed")
            }
        }
    }

    @MainActor
    private func add(_ item: RecommendedFeed) async {
        if subscribedURLs.contains(item.url) { return }
        guard addingId == nil else { return }

        addingId = item.id
        defer { addingId = nil }

        do {
            let kindHint: FeedKind? = switch item.kind {
            case .rss: .rss
            case .youtube: .youtube
            case .podcast: .podcast
            }
            let feedManager = FeedManager(modelContext: modelContext)
            _ = try await feedManager.addFeed(url: item.url, kindHint: kindHint)
        } catch {
            self.error = error
            self.showingError = true
        }
    }

    @MainActor
    private func addAll() async {
        guard !isAddingAll else { return }
        isAddingAll = true
        defer { isAddingAll = false }

        let toAdd = RecommendedFeedCatalog.items.filter { !subscribedURLs.contains($0.url) }
        for item in toAdd {
            await add(item)
            if showingError { break }
        }
    }
}

private struct RecommendedFeedRow: View {
    let item: RecommendedFeed
    let isAdded: Bool
    let isAdding: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(item.kind.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.12))
                        .clipShape(Capsule())
                }

                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(item.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isAdded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if isAdding {
                ProgressView()
            } else {
                Button("Add") { onAdd() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FeedsListView()
        .modelContainer(for: [Feed.self, Article.self, Folder.self], inMemory: true)
}
