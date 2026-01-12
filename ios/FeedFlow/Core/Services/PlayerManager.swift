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
    @Published private(set) var seekableStartTime: TimeInterval = 0
    @Published private(set) var seekableEndTime: TimeInterval = 0
    @Published private(set) var isSeekable: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?

    @Published var playbackMode: PlaybackMode = .video
    @Published var currentVideoId: String?
    @Published var nowPlayingInfo: NowPlayingInfo?
    @Published var nowPlayingFeedKind: FeedKind?

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
                guard let self else { return }
                self.seek(to: self.nowPlayingSeekOffset + event.positionTime)
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

    func loadAndPlay(
        url: URL,
        videoId: String,
        info: NowPlayingInfo,
        feedKind: FeedKind? = nil,
        forceReload: Bool = false
    ) async {
        if let feedKind {
            nowPlayingFeedKind = feedKind
        }

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
        currentTime = 0
        duration = info.duration
        seekableStartTime = 0
        seekableEndTime = info.duration
        isSeekable = info.duration > 0

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
                    self?.updateDurationAndSeekableRangeIfNeeded(from: item)
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
                if let item = self?.player?.currentItem {
                    self?.updateDurationAndSeekableRangeIfNeeded(from: item)
                }
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
        guard let clamped = clampTimeToSeekableRange(time) else {
            play()
            return
        }
        activateAudioSession()
        isPlaying = false
        player.currentItem?.cancelPendingSeeks()
        let tolerance = CMTime(seconds: 1, preferredTimescale: 600)
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.player?.play()
                self.isPlaying = true
                self.currentTime = clamped
                self.updateNowPlayingInfo()
            }
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
        seekableStartTime = 0
        seekableEndTime = 0
        isSeekable = false
        currentVideoId = nil
        nowPlayingInfo = nil
        nowPlayingFeedKind = nil

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        deactivateAudioSession()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        guard let clamped = clampTimeToSeekableRange(time) else { return }
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.currentItem?.cancelPendingSeeks()
        let tolerance = CMTime(seconds: 1, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = clamped
                self.updateNowPlayingProgress()
            }
        }
    }

    func skipForward(seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func skipBackward(seconds: TimeInterval) {
        seek(to: currentTime - seconds)
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        guard let info = nowPlayingInfo else { return }

        let effectiveDuration = nowPlayingDuration > 0 ? nowPlayingDuration : info.duration
        var nowPlayingDict: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyPlaybackDuration: effectiveDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: nowPlayingElapsedTime,
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
        nowPlayingDict[MPMediaItemPropertyPlaybackDuration] = nowPlayingDuration
        nowPlayingDict[MPNowPlayingInfoPropertyElapsedPlaybackTime] = nowPlayingElapsedTime
        nowPlayingDict[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingDict
    }

    private var nowPlayingSeekOffset: TimeInterval {
        guard isSeekable else { return 0 }
        guard seekableEndTime > seekableStartTime else { return 0 }
        return seekableStartTime
    }

    private var nowPlayingDuration: TimeInterval {
        if isSeekable, seekableEndTime > seekableStartTime {
            return seekableEndTime - seekableStartTime
        }
        return duration
    }

    private var nowPlayingElapsedTime: TimeInterval {
        let elapsed = currentTime - nowPlayingSeekOffset
        if nowPlayingDuration > 0 {
            return min(max(elapsed, 0), nowPlayingDuration)
        }
        return max(elapsed, 0)
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

    // MARK: - Seekable Range

    private func updateDurationAndSeekableRangeIfNeeded(from item: AVPlayerItem) {
        let itemDurationSeconds = item.duration.seconds
        let hasFiniteItemDuration =
            itemDurationSeconds.isFinite && !itemDurationSeconds.isNaN && itemDurationSeconds > 0
        if hasFiniteItemDuration {
            duration = itemDurationSeconds
        }

        let ranges = item.seekableTimeRanges.map(\.timeRangeValue)
        if ranges.isEmpty {
            seekableStartTime = 0
            seekableEndTime = duration
            isSeekable = duration > 0
            return
        }

        let itemCurrentTimeSeconds = item.currentTime().seconds
        let fallbackEnd =
            itemCurrentTimeSeconds.isFinite && !itemCurrentTimeSeconds.isNaN
            ? itemCurrentTimeSeconds
            : currentTime

        var start = Double.greatestFiniteMagnitude
        var end = 0.0
        for range in ranges {
            let rangeStart = range.start.seconds
            if rangeStart.isFinite && !rangeStart.isNaN {
                start = min(start, max(rangeStart, 0))
            }

            let rangeEndSeconds = CMTimeRangeGetEnd(range).seconds
            let rangeEnd = rangeEndSeconds.isFinite && !rangeEndSeconds.isNaN
                ? rangeEndSeconds
                : fallbackEnd
            if rangeEnd.isFinite && !rangeEnd.isNaN {
                end = max(end, rangeEnd)
            }
        }

        if start == Double.greatestFiniteMagnitude || end <= 0 {
            seekableStartTime = 0
            seekableEndTime = duration
            isSeekable = duration > 0
            return
        }

        seekableStartTime = start
        seekableEndTime = max(end, start)
        isSeekable = (end - start) > 1
    }

    private func clampTimeToSeekableRange(_ time: TimeInterval) -> TimeInterval? {
        if isSeekable {
            let start = max(0, seekableStartTime)
            let end = max(start, seekableEndTime)
            let safeEnd = end > (start + 0.25) ? (end - 0.25) : end
            return min(max(time, start), safeEnd)
        }

        if duration > 0 {
            return min(max(time, 0), duration)
        }

        return nil
    }
}
