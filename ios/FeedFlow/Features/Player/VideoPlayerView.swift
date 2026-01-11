import SwiftUI
import AVKit
import UIKit
import os

struct VideoPlayerView: View {
    let videoId: String
    let title: String
    let channelTitle: String
    let thumbnailUrl: String?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var playerManager = PlayerManager.shared

    @State private var isLoading = true
    @State private var error: Error?
    @State private var showingError = false
    @State private var showingDebugCopied = false
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?

    private let apiClient = APIClient.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    // Loading state with thumbnail
                    ZStack {
                        if let thumbnailUrl = thumbnailUrl, let url = URL(string: thumbnailUrl) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                            } placeholder: {
                                Color.black
                            }
                        }

                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        // Back button during loading
                        VStack {
                            HStack {
                                Button {
                                    dismiss()  // Just dismiss, don't stop playback
                                } label: {
                                    Image(systemName: "chevron.down.circle.fill")
                                        .font(.system(size: 30))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .shadow(radius: 4)
                                }
                                .padding(.leading, 16)
                                .padding(.top, 50)
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                } else if let player = playerManager.avPlayer {
                    // Video player
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                showControls.toggle()
                            }
                            scheduleHideControls()
                        }

                    // Always visible back button (minimize to mini player)
                    VStack {
                        HStack {
                            Button {
                                dismiss()  // Just dismiss, playback continues in mini player
                            } label: {
                                Image(systemName: "chevron.down.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .shadow(radius: 4)
                            }
                            .padding(.leading, 16)
                            .padding(.top, 50)
                            Spacer()
                        }
                        Spacer()
                    }

                    // Custom controls overlay
                    if showControls {
                        PlayerControlsOverlay(
                            title: title,
                            channelTitle: channelTitle,
                            isPlaying: playerManager.isPlaying,
                            currentTime: playerManager.currentTime,
                            duration: playerManager.duration,
                            seekableStartTime: playerManager.seekableStartTime,
                            seekableEndTime: playerManager.seekableEndTime,
                            isSeekable: playerManager.isSeekable,
                            playbackMode: playerManager.playbackMode,
                            onPlayPause: { playerManager.togglePlayPause() },
                            onSeek: { playerManager.seek(to: $0) },
                            onSkipBack: { playerManager.skipBackward(seconds: 15) },
                            onSkipForward: { playerManager.skipForward(seconds: 15) },
                            onModeToggle: { togglePlaybackMode() },
                            onDismiss: { dismiss() }
                        )
                        .transition(.opacity)
                    }
                }

                // Error state
                if let error = error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundStyle(.red)
                        Text("Failed to load video")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") {
                            Task { await loadVideo() }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Copy Debug Info") {
                            copyDebugInfo(error: error)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .task(id: videoId) {
            playerManager.playbackMode = .video
            await loadVideo(forceReload: true)
        }
        .onDisappear {
            hideControlsTask?.cancel()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "Unknown error")
        }
        .alert("Copied", isPresented: $showingDebugCopied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Debug info copied to clipboard.")
        }
    }

    private func loadVideo(forceReload: Bool = false) async {
        // If already playing this video, don't reload
        if playerManager.currentVideoId == videoId && playerManager.avPlayer != nil && !forceReload {
            isLoading = false
            scheduleHideControls()
            return
        }

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "enableNetworkDebugLogs") {
            AppLog.player.info(
                "Load video videoId=\(videoId, privacy: .public) mode=\(String(describing: playerManager.playbackMode), privacy: .public) forceReload=\(forceReload, privacy: .public)"
            )
        }
        #endif

        isLoading = true
        error = nil

        do {
            let streamType = playerManager.playbackMode == .audio ? "audio" : "video"
            let streams = try await apiClient.getYouTubeStreamUrls(videoId: videoId, type: streamType)

            let urlString = playerManager.playbackMode == .audio ? streams.audioUrl : streams.videoUrl

            guard let urlString = urlString, let url = URL(string: urlString) else {
                AppLog.player.error(
                    "No playable stream videoId=\(videoId, privacy: .public) mode=\(String(describing: playerManager.playbackMode), privacy: .public) videoUrl=\(streams.videoUrl != nil, privacy: .public) audioUrl=\(streams.audioUrl != nil, privacy: .public)"
                )
                throw NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "No playable stream found"])
            }

            let info = NowPlayingInfo(
                title: title,
                artist: channelTitle,
                thumbnailUrl: thumbnailUrl,
                duration: TimeInterval(streams.duration)
            )

            await playerManager.loadAndPlay(url: url, videoId: videoId, info: info, forceReload: forceReload)
            isLoading = false
            scheduleHideControls()
        } catch {
            AppLog.player.error("Load video failed videoId=\(videoId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            self.error = error
            isLoading = false
        }
    }

    private func togglePlaybackMode() {
        playerManager.playbackMode = playerManager.playbackMode == .video ? .audio : .video
        Task { await loadVideo(forceReload: true) }
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation {
                        showControls = false
                    }
                }
            }
        }
    }

    private func copyDebugInfo(error: Error) {
        let debugInfo = buildDebugInfo(error: error)
        UIPasteboard.general.string = debugInfo
        AppLog.player.info("Copied debug info videoId=\(videoId, privacy: .public)")
        #if DEBUG
        print(debugInfo)
        #endif
        showingDebugCopied = true
    }

    private func buildDebugInfo(error: Error) -> String {
        let date = ISO8601DateFormatter().string(from: Date())

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

        let device = "\(UIDevice.current.model) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"

        let streamProxyToken = UserDefaults.standard.string(forKey: "streamProxyAccessToken") ?? ""
        let tokenStatus = streamProxyToken.isEmpty ? "missing" : "set(len:\(streamProxyToken.count))"

        let mode = playerManager.playbackMode == .audio ? "audio" : "video"
        let streamType = mode

        let baseURL = apiClient.currentBaseURL()
        let streamEndpoint = "\(baseURL)/youtube/stream/\(videoId)?type=\(streamType)"

        return """
        FeedFlow Debug Info
        date=\(date)
        app=\(version) (\(build))
        device=\(device)
        baseURL=\(baseURL)
        streamEndpoint=\(streamEndpoint)
        streamToken=\(tokenStatus)
        videoId=\(videoId)
        mode=\(mode)
        title=\(title)
        channelTitle=\(channelTitle)
        thumbnailUrl=\(thumbnailUrl ?? "nil")
        errorType=\(String(describing: type(of: error)))
        error=\(String(describing: error))
        localizedDescription=\(error.localizedDescription)
        """
    }
}

struct PlayerControlsOverlay: View {
    let title: String
    let channelTitle: String
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let seekableStartTime: TimeInterval
    let seekableEndTime: TimeInterval
    let isSeekable: Bool
    let playbackMode: PlaybackMode
    let onPlayPause: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onSkipBack: () -> Void
    let onSkipForward: () -> Void
    let onModeToggle: () -> Void
    let onDismiss: () -> Void

    @State private var isScrubbing = false
    @State private var scrubValue: TimeInterval = 0

    var body: some View {
        let effectiveSeekStart = seekableStartTime
        let effectiveSeekEnd = seekableEndTime > seekableStartTime
            ? seekableEndTime
            : (seekableStartTime + max(duration, 1))
        let seekWindowDuration = max(effectiveSeekEnd - effectiveSeekStart, 1)
        let displayedCurrentTime = max(0, min(currentTime - effectiveSeekStart, seekWindowDuration))

        ZStack {
            // Gradient background
            LinearGradient(
                colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                // Top bar
                HStack {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(channelTitle)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }

                    Spacer()

                    // Audio/Video mode toggle
                    Button {
                        onModeToggle()
                    } label: {
                        Image(systemName: playbackMode == .audio ? "speaker.wave.2" : "play.rectangle")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .padding()

                Spacer()

                // Center controls
                HStack(spacing: 50) {
                    Button {
                        onSkipBack()
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title)
                            .foregroundStyle(.white)
                    }

                    Button {
                        onPlayPause()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 70))
                            .foregroundStyle(.white)
                    }

                    Button {
                        onSkipForward()
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }

                Spacer()

                // Progress bar
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { isScrubbing ? scrubValue : displayedCurrentTime },
                            set: { scrubValue = $0 }
                        ),
                        in: 0...seekWindowDuration
                    ) { editing in
                        isScrubbing = editing
                        if editing {
                            scrubValue = displayedCurrentTime
                        } else {
                            onSeek(effectiveSeekStart + scrubValue)
                        }
                    }
                    )
                    .tint(.white)
                    .disabled(!isSeekable)

                    HStack {
                        Text(formatTime(isScrubbing ? scrubValue : displayedCurrentTime))
                            .font(.caption)
                            .foregroundStyle(.gray)
                        Spacer()
                        Text(formatTime(seekWindowDuration))
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && !time.isInfinite else { return "0:00" }
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    VideoPlayerView(
        videoId: "dQw4w9WgXcQ",
        title: "Test Video",
        channelTitle: "Test Channel",
        thumbnailUrl: nil
    )
}
