import SwiftUI

struct MiniPlayerView: View {
    @StateObject private var playerManager = PlayerManager.shared

    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar at top
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * progressRatio)
            }
            .frame(height: 2)

            HStack(spacing: 12) {
                // Thumbnail
                if let thumbnailUrl = playerManager.nowPlayingInfo?.thumbnailUrl,
                   let url = URL(string: thumbnailUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: playerManager.playbackMode == .audio ? "music.note" : "play.rectangle")
                                .foregroundStyle(.secondary)
                        }
                }

                // Title and artist
                VStack(alignment: .leading, spacing: 2) {
                    Text(playerManager.nowPlayingInfo?.title ?? "No title")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let artist = playerManager.nowPlayingInfo?.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Play/Pause button
                Button {
                    playerManager.togglePlayPause()
                } label: {
                    Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }

                // Close button
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    private var progressRatio: Double {
        if playerManager.duration > 0 {
            return min(playerManager.currentTime / playerManager.duration, 1.0)
        }

        guard playerManager.isSeekable else { return 0 }
        let start = playerManager.seekableStartTime
        let end = playerManager.seekableEndTime
        guard end > start else { return 0 }

        let windowDuration = end - start
        let relativeTime = playerManager.currentTime - start
        return min(max(relativeTime / windowDuration, 0), 1)
    }
}

#Preview {
    VStack {
        Spacer()
        MiniPlayerView(
            onTap: {},
            onDismiss: {}
        )
    }
}
