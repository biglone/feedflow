import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var authManager = AuthManager.shared
    @State private var isSyncing = false
    @State private var lastSyncTime: Date?
    @AppStorage("refreshInterval") private var refreshInterval: Int = 30
    @AppStorage("markAsReadOnScroll") private var markAsReadOnScroll: Bool = false
    @AppStorage("openLinksInApp") private var openLinksInApp: Bool = true
    @AppStorage("fontSize") private var fontSize: Double = 17
    #if DEBUG
    @AppStorage("useLocalAPI") private var useLocalAPI: Bool = false
    @AppStorage("enableNetworkDebugLogs") private var enableNetworkDebugLogs: Bool = false
    #endif

    @State private var showingAccountSheet = false
    @State private var showingExportSheet = false
    @State private var showingImportSheet = false
    @State private var showingClearDataAlert = false
    @State private var showingLogoutAlert = false

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

                // Data Section
                Section("Data") {
                    Button {
                        showingExportSheet = true
                    } label: {
                        Label("Export OPML", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingImportSheet = true
                    } label: {
                        Label("Import OPML", systemImage: "square.and.arrow.down")
                    }

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
