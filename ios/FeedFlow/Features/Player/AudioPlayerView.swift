import SwiftUI

struct AudioPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playerManager = PlayerManager.shared

    var body: some View {
        let title = playerManager.nowPlayingInfo?.title ?? "Now Playing"
        let artist = playerManager.nowPlayingInfo?.artist ?? ""

        ZStack {
            background

            PlayerControlsOverlay(
                title: title,
                channelTitle: artist,
                isPlaying: playerManager.isPlaying,
                currentTime: playerManager.currentTime,
                duration: playerManager.duration,
                seekableStartTime: playerManager.seekableStartTime,
                seekableEndTime: playerManager.seekableEndTime,
                isSeekable: playerManager.isSeekable,
                playbackMode: .audio,
                onPlayPause: { playerManager.togglePlayPause() },
                onSeek: { playerManager.seek(to: $0) },
                onSkipBack: { playerManager.skipBackward(seconds: 15) },
                onSkipForward: { playerManager.skipForward(seconds: 15) },
                onModeToggle: {},
                onDismiss: { dismiss() },
                showsModeToggle: false
            )
        }
        .onAppear {
            playerManager.playbackMode = .audio
        }
    }

    @ViewBuilder
    private var background: some View {
        if let thumbnailUrl = playerManager.nowPlayingInfo?.thumbnailUrl,
           let url = URL(string: thumbnailUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Color.black
            }
            .ignoresSafeArea()
            .blur(radius: 30)
            .overlay(Color.black.opacity(0.35))
        } else {
            LinearGradient(
                colors: [.black, .gray.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    AudioPlayerView()
}

