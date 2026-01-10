import Foundation
import AVFoundation
import MediaPlayer

enum PlaybackMode {
    case video
    case audio
}

struct NowPlayingInfo {
    let title: String
    let artist: String?
    let thumbnailUrl: String?
    let duration: TimeInterval
}

@MainActor
class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?

    @Published var playbackMode: PlaybackMode = .video
    @Published var currentVideoId: String?
    @Published var nowPlayingInfo: NowPlayingInfo?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var playerItemObserver: NSKeyValueObservation?
    private var audioSessionConfigured = false

    // Store playback progress for each video (videoId -> time in seconds)
    private var playbackProgress: [String: TimeInterval] = [:]
    private let progressKey = "VideoPlaybackProgress"

    private init() {
        // Load saved progress from UserDefaults
        if let saved = UserDefaults.standard.dictionary(forKey: progressKey) as? [String: TimeInterval] {
            playbackProgress = saved
        }
        setupRemoteCommands()
    }

    // MARK: - Audio Session

    private func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured else { return }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback)
            audioSessionConfigured = true
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    private func activateAudioSession() {
        configureAudioSessionIfNeeded()
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }

    private func deactivateAudioSession() {
        guard !isPlaying else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }

    // MARK: - Remote Control Commands

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.play()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self?.seek(to: event.positionTime)
            }
            return .success
        }

        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.skipForward(seconds: 15)
            }
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.skipBackward(seconds: 15)
            }
            return .success
        }
    }

    // MARK: - Playback Control

    func loadAndPlay(url: URL, videoId: String, info: NowPlayingInfo, forceReload: Bool = false) async {
        // If already playing this video, just resume
        if currentVideoId == videoId && player != nil && !forceReload {
            if !isPlaying {
                play()
            }
            isLoading = false
            return
        }

        // Save progress of current video before switching
        saveProgress()

        isLoading = true
        error = nil
        currentVideoId = videoId
        nowPlayingInfo = info

        // Stop any existing playback but don't clear currentVideoId yet
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        playerItemObserver = nil
        player = nil

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        // Get saved progress before observing
        let savedProgress = getSavedProgress(for: videoId)

        // Observe player status
        playerItemObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self?.isLoading = false
                    self?.duration = item.duration.seconds.isNaN ? 0 : item.duration.seconds
                    if let progress = savedProgress, progress > 0 {
                        self?.seekAndPlay(to: progress)
                    } else {
                        self?.play()
                    }
                    self?.updateNowPlayingInfo()
                case .failed:
                    self?.isLoading = false
                    self?.error = item.error
                default:
                    break
                }
            }
        }

        // Observe playback progress
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
                self?.updateNowPlayingProgress()
                // Save progress every 5 seconds
                if Int(time.seconds) % 5 == 0 {
                    self?.saveProgress()
                }
            }
        }

        // Observe playback end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.currentTime = 0
                self?.deactivateAudioSession()
            }
        }
    }

    func play() {
        activateAudioSession()
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func seekAndPlay(to time: TimeInterval) {
        guard let player = player else { return }
        activateAudioSession()
        isPlaying = false
        player.seek(
            to: CMTime(seconds: time, preferredTimescale: 600),
            toleranceBefore: CMTime(value: 1, timescale: 600),
            toleranceAfter: CMTime(value: 1, timescale: 600)
        ) { [weak self] _ in
            guard let self else { return }
            self.player?.play()
            self.isPlaying = true
            self.currentTime = time
            self.updateNowPlayingInfo()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
        deactivateAudioSession()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        // Save progress before stopping
        saveProgress()

        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player = nil
        playerItemObserver = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        currentVideoId = nil
        nowPlayingInfo = nil

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        deactivateAudioSession()
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        updateNowPlayingProgress()
    }

    func skipForward(seconds: TimeInterval) {
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }

    func skipBackward(seconds: TimeInterval) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        guard let info = nowPlayingInfo else { return }

        var nowPlayingDict: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]

        if let artist = info.artist {
            nowPlayingDict[MPMediaItemPropertyArtist] = artist
        }

        // Load artwork asynchronously
        if let thumbnailUrlString = info.thumbnailUrl,
           let thumbnailUrl = URL(string: thumbnailUrlString) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: thumbnailUrl),
                   let image = UIImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    await MainActor.run {
                        var updatedDict = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        updatedDict[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedDict
                    }
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingDict
    }

    private func updateNowPlayingProgress() {
        var nowPlayingDict = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        nowPlayingDict[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingDict[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingDict
    }

    // MARK: - AVPlayer Access (for VideoPlayerView)

    var avPlayer: AVPlayer? {
        return player
    }

    // MARK: - Progress Tracking

    func saveProgress() {
        guard let videoId = currentVideoId, currentTime > 5 else { return }
        // Don't save if near the end (within 30 seconds)
        if duration > 0 && currentTime > duration - 30 {
            // Video finished, clear progress
            playbackProgress.removeValue(forKey: videoId)
        } else {
            playbackProgress[videoId] = currentTime
        }
        UserDefaults.standard.set(playbackProgress, forKey: progressKey)
    }

    func getSavedProgress(for videoId: String) -> TimeInterval? {
        return playbackProgress[videoId]
    }

    func clearProgress(for videoId: String) {
        playbackProgress.removeValue(forKey: videoId)
        UserDefaults.standard.set(playbackProgress, forKey: progressKey)
    }
}
