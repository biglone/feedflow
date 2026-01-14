import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @StateObject private var authManager = AuthManager.shared
    @State private var isSyncing = false
    @State private var lastSyncTime: Date?
    @AppStorage("refreshInterval") private var refreshInterval: Int = 30
    @AppStorage("markAsReadOnScroll") private var markAsReadOnScroll: Bool = false
    @AppStorage("openLinksInApp") private var openLinksInApp: Bool = true
    @AppStorage("fontSize") private var fontSize: Double = 17
    @AppStorage("apiBaseURLOverride") private var apiBaseURLOverride: String = ""
    @AppStorage("youTubeStreamBaseURL") private var youTubeStreamBaseURL: String = ""
    #if DEBUG
    @AppStorage("useLocalAPI") private var useLocalAPI: Bool = false
    @AppStorage("enableNetworkDebugLogs") private var enableNetworkDebugLogs: Bool = false
    #endif

    @State private var showingAccountSheet = false
    @State private var showingExportSheet = false
    @State private var showingImportSheet = false
    @State private var showingClearDataAlert = false
    @State private var showingLogoutAlert = false

    @State private var exportDocument = OPMLDocument(text: "")
    @State private var exportFilename = "feedflow-subscriptions.opml"

    @State private var isImportingOPML = false
    @State private var importProgress = 0
    @State private var importTotal = 0
    @State private var importTask: Task<Void, Never>?

    @State private var showingOPMLAlert = false
    @State private var opmlAlertTitle = "OPML"
    @State private var opmlAlertMessage = ""

    private enum BackendPreset: String, CaseIterable, Identifiable {
        case `default`
        case vercel
        #if DEBUG
        case local
        #endif

        var id: String { rawValue }

        var title: String {
            switch self {
            case .default:
                return "Default"
            case .vercel:
                return "Vercel"
            #if DEBUG
            case .local:
                return "Local"
            #endif
            }
        }
    }

    private var backendPresetBinding: Binding<BackendPreset> {
        Binding(
            get: { inferBackendPreset() },
            set: { applyBackendPreset($0) }
        )
    }

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                // Account Section
                Section("Account") {
                    if authManager.isLoggedIn, let user = authManager.currentUser {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title)
                                .foregroundStyle(Color.accentColor)

                            VStack(alignment: .leading) {
                                Text(user.email)
                                    .foregroundStyle(.primary)
                                Text("Signed in")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button(role: .destructive) {
                            showingLogoutAlert = true
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        Button {
                            showingAccountSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading) {
                                    Text("Sign In")
                                        .foregroundStyle(.primary)
                                    Text("Sync your feeds across devices")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Sync Section (only when logged in)
                if authManager.isLoggedIn {
                    Section("Sync") {
                        Button {
                            Task {
                                await syncWithCloud()
                            }
                        } label: {
                            HStack {
                                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                if isSyncing {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isSyncing)

                        if let lastSync = lastSyncTime {
                            HStack {
                                Text("Last Synced")
                                Spacer()
                                Text(lastSync, style: .relative)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Reading Section
                Section("Reading") {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(fontSize))pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $fontSize, in: 12...24, step: 1)

                    Toggle("Mark as Read on Scroll", isOn: $markAsReadOnScroll)

                    Toggle("Open Links in App", isOn: $openLinksInApp)
                }

                // Refresh Section
                Section("Refresh") {
                    Picker("Refresh Interval", selection: $refreshInterval) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("Manual only").tag(0)
                    }
                }

                // Server Section
                Section("Backend") {
                    Picker("Server", selection: backendPresetBinding) {
                        ForEach(BackendPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Use Vercel if YouTube playback fails on your local server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Data Section
                Section("Data") {
                    Button {
                        prepareOPMLExport()
                    } label: {
                        Label("Export OPML", systemImage: "square.and.arrow.up")
                    }
                    .disabled(feeds.isEmpty || isImportingOPML)

                    Button {
                        showingImportSheet = true
                    } label: {
                        Label("Import OPML", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isImportingOPML)

                    Button(role: .destructive) {
                        showingClearDataAlert = true
                    } label: {
                        Label("Clear All Data", systemImage: "trash")
                    }
                }

                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersionString)
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/feedflow")!) {
                        HStack {
                            Text("Source Code")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Link(destination: URL(string: "mailto:support@feedflow.app")!) {
                        HStack {
                            Text("Contact Support")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                #if DEBUG
                // Developer Section for switching API endpoints
                Section("Developer") {
                    Toggle("Use Local API Server", isOn: $useLocalAPI)
                    Text("Connect to http://172.16.1.16:3000/api instead of the deployed backend.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Current API: \(APIClient.shared.currentBaseURL())")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("API Base URL override (e.g. feedflow-silk.vercel.app)", text: $apiBaseURLOverride)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Text("YouTube stream base: \(APIClient.shared.currentYouTubeStreamBaseURL())")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("YouTube stream URL override (e.g. feedflow-silk.vercel.app)", text: $youTubeStreamBaseURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Use Vercel (feedflow-silk.vercel.app)") {
                        useLocalAPI = false
                        apiBaseURLOverride = "https://feedflow-silk.vercel.app/api"
                        youTubeStreamBaseURL = "https://feedflow-silk.vercel.app/api"
                    }

                    Button("Reset Overrides", role: .destructive) {
                        apiBaseURLOverride = ""
                        youTubeStreamBaseURL = ""
                    }
                    .disabled(apiBaseURLOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && youTubeStreamBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Toggle("Enable Network Debug Logs", isOn: $enableNetworkDebugLogs)
                    Text("Print request/response logs to the Xcode console (and Console.app).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #endif
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingAccountSheet) {
                AccountView()
            }
            .fileExporter(
                isPresented: $showingExportSheet,
                document: exportDocument,
                contentType: .feedFlowOPML,
                defaultFilename: exportFilename
            ) { result in
                if case .failure(let error) = result, !isUserCancelled(error) {
                    opmlAlertTitle = "Export Failed"
                    opmlAlertMessage = error.localizedDescription
                    showingOPMLAlert = true
                }
            }
            .fileImporter(
                isPresented: $showingImportSheet,
                allowedContentTypes: [.feedFlowOPML, .xml, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importTask?.cancel()
                    importTask = Task { await importOPML(from: url) }
                case .failure(let error):
                    if !isUserCancelled(error) {
                        opmlAlertTitle = "Import Failed"
                        opmlAlertMessage = error.localizedDescription
                        showingOPMLAlert = true
                    }
                }
            }
            .alert("Clear All Data", isPresented: $showingClearDataAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    clearAllData()
                }
            } message: {
                Text("This will delete all feeds and articles. This action cannot be undone.")
            }
            .alert("Sign Out", isPresented: $showingLogoutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    authManager.logout()
                    lastSyncTime = nil
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert(opmlAlertTitle, isPresented: $showingOPMLAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(opmlAlertMessage)
            }
            .overlay {
                if isImportingOPML {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView(value: Double(importProgress), total: Double(max(importTotal, 1)))
                                .frame(width: 240)
                            Text("Importing \(importProgress)/\(importTotal)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Cancel") {
                                importTask?.cancel()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(16)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 12)
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
        lastSyncTime = feedManager.lastSyncTime
    }

    private func clearAllData() {
        do {
            try modelContext.delete(model: Article.self)
            try modelContext.delete(model: Feed.self)
            try modelContext.delete(model: Folder.self)
            try modelContext.save()
        } catch {
            print("Failed to clear data: \(error)")
        }
    }

    private func prepareOPMLExport() {
        let items = feeds.compactMap { feed -> OPMLService.Item? in
            guard let url = OPMLService.normalizeURLString(feed.feedURL) else { return nil }
            let categories = feed.folder.map { [$0.name] } ?? []
            return OPMLService.Item(
                title: feed.title,
                xmlUrl: url,
                htmlUrl: feed.siteURL,
                kind: feed.kind,
                categories: categories
            )
        }

        exportDocument = OPMLDocument(text: OPMLService.generate(items: items))
        exportFilename = "feedflow-subscriptions-\(dateStampForFilename()).opml"
        showingExportSheet = true
    }

    @MainActor
    private func importOPML(from url: URL) async {
        isImportingOPML = true
        importProgress = 0
        importTotal = 0
        defer {
            isImportingOPML = false
            importTask = nil
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let parsedItems = try OPMLService.parse(data: data)

            var seen = Set(feeds.compactMap { OPMLService.normalizeURLString($0.feedURL) })
            let feedManager = FeedManager(modelContext: modelContext)

            let normalizedItems: [OPMLService.Item] = parsedItems.compactMap { item in
                guard let normalized = OPMLService.normalizeURLString(item.xmlUrl) else { return nil }
                return OPMLService.Item(
                    title: item.title,
                    xmlUrl: normalized,
                    htmlUrl: item.htmlUrl,
                    kind: item.kind,
                    categories: item.categories
                )
            }

            importTotal = normalizedItems.count

            var imported = 0
            var skipped = 0
            var failed = 0

            for item in normalizedItems {
                if Task.isCancelled {
                    break
                }

                if seen.contains(item.xmlUrl) {
                    skipped += 1
                    importProgress += 1
                    continue
                }
                seen.insert(item.xmlUrl)

                do {
                    let kindHint = item.kind.flatMap { FeedKind(rawValue: $0) }
                    _ = try await feedManager.addFeed(url: item.xmlUrl, kindHint: kindHint)
                    imported += 1
                } catch {
                    if isDuplicateFeedError(error) {
                        skipped += 1
                    } else {
                        failed += 1
                    }
                }

                importProgress += 1
            }

            let cancelled = Task.isCancelled
            opmlAlertTitle = cancelled ? "Import Cancelled" : "Import Complete"
            opmlAlertMessage = "Imported \(imported), skipped \(skipped), failed \(failed)."
            showingOPMLAlert = true
        } catch {
            if Task.isCancelled { return }
            opmlAlertTitle = "Import Failed"
            opmlAlertMessage = error.localizedDescription
            showingOPMLAlert = true
        }
    }

    private func dateStampForFilename(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private func isDuplicateFeedError(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }
        if case .serverError(let message) = apiError {
            let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.contains("feed already exists") || normalized.contains("already exists")
        }
        return false
    }

    private func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.Code.userCancelled.rawValue
    }

    private func inferBackendPreset() -> BackendPreset {
        let base = APIClient.shared.currentBaseURL().lowercased()

        if base.contains("feedflow-silk.vercel.app") {
            return .vercel
        }

        #if DEBUG
        if base.contains("172.16.1.16:3000") {
            return .local
        }
        #endif

        return .default
    }

    private func applyBackendPreset(_ preset: BackendPreset) {
        switch preset {
        case .default:
            apiBaseURLOverride = ""
            youTubeStreamBaseURL = ""
            #if DEBUG
            useLocalAPI = false
            #endif
        case .vercel:
            apiBaseURLOverride = "https://feedflow-silk.vercel.app/api"
            youTubeStreamBaseURL = "https://feedflow-silk.vercel.app/api"
            #if DEBUG
            useLocalAPI = false
            #endif
        #if DEBUG
        case .local:
            apiBaseURLOverride = "http://172.16.1.16:3000/api"
            youTubeStreamBaseURL = "http://172.16.1.16:3000/api"
            useLocalAPI = false
        #endif
        }
    }
}

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authManager = AuthManager.shared

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var isSignUp = false
    @State private var error: Error?
    @State private var showingError = false

    private var isEmailValid: Bool {
        let emailRegex = /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/
            .ignoresCase()
        return email.wholeMatch(of: emailRegex) != nil
    }

    private var isFormValid: Bool {
        if isSignUp {
            return isEmailValid && password.count >= 8 && password == confirmPassword
        } else {
            return isEmailValid && !password.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)

                    if isSignUp {
                        SecureField("Confirm Password", text: $confirmPassword)
                            .textContentType(.newPassword)
                    }
                } footer: {
                    if isSignUp {
                        Text("Password must be at least 8 characters")
                    }
                }

                Section {
                    Button {
                        Task {
                            await authenticate()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!isFormValid || isLoading)
                }

                Section {
                    Button {
                        withAnimation {
                            isSignUp.toggle()
                            confirmPassword = ""
                        }
                    } label: {
                        Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(isSignUp ? "Create Account" : "Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error?.localizedDescription ?? "An unknown error occurred")
            }
            .interactiveDismissDisabled(isLoading)
        }
    }

    private func authenticate() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if isSignUp {
                try await authManager.register(email: email, password: password)
            } else {
                try await authManager.login(email: email, password: password)
            }
            dismiss()
        } catch {
            self.error = error
            self.showingError = true
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Feed.self, Article.self, Folder.self], inMemory: true)
}
