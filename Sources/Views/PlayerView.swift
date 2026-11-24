import AVFoundation
import AVKit
import SwiftUI

struct PlayerScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let target: PlaybackTarget

    @State private var currentEpisodeIndex: Int = 0
    @State private var player: AVPlayer?
    @State private var adBlockLoader: HLSAdBlockLoader?
    @State private var syncObserverToken: Any?
    @State private var subtitleObserverToken: Any?

    @State private var subtitleCues: [SubtitleCue] = []
    @State private var activeSubtitleLabel: String?
    @State private var activeSubtitleText: String?
    @State private var subtitleOffset: Double = 0
    @State private var showSubtitlePicker = false
    @State private var upNextSecondsRemaining: Int?

    private var currentEpisode: EpisodeItem? {
        guard target.detail.episodes.indices.contains(currentEpisodeIndex) else { return nil }
        return target.detail.episodes[currentEpisodeIndex]
    }

    private var nextEpisode: EpisodeItem? {
        let nextIdx = currentEpisodeIndex + 1
        guard target.detail.episodes.indices.contains(nextIdx) else { return nil }
        return target.detail.episodes[nextIdx]
    }

    var body: some View {
        ZStack {
            if let player {
                AVPlayerControllerRepresentable(
                    player: player,
                    hasNextEpisode: nextEpisode != nil,
                    onOpenSubtitles: { showSubtitlePicker = true },
                    onPlayNextEpisode: { advanceToNextEpisode() }
                )
                .ignoresSafeArea()
            } else {
                ProgressView("Starting stream...")
            }

            if let text = activeSubtitleText, !text.isEmpty {
                VStack {
                    Spacer()
                    Text(text)
                        .font(.system(size: 40, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.68))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 72)
                        .padding(.horizontal, 96)
                }
                .allowsHitTesting(false)
            }

            if let remaining = upNextSecondsRemaining, let next = nextEpisode {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            advanceToNextEpisode()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("UP NEXT IN \(remaining)s")
                                    .font(.caption.bold())
                                    .foregroundStyle(.blue)
                                Text(next.title)
                                    .font(.headline)
                                Text("Press Select to play now")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(20)
                        }
                        .padding(.trailing, 64)
                        .padding(.bottom, 120)
                    }
                }
            }
        }
        .onAppear {
            currentEpisodeIndex = target.episodeIndex
            startEpisode(index: target.episodeIndex, startTime: target.startTime)
        }
        .onDisappear {
            teardownPlayer()
        }
        .sheet(isPresented: $showSubtitlePicker) {
            SubtitlePickerView(
                initialQuery: target.detail.title,
                backendTracks: target.detail.subtitles,
                activeCues: $subtitleCues,
                activeLabel: $activeSubtitleLabel,
                subtitleOffset: $subtitleOffset
            )
            .environmentObject(appState)
        }
    }

    private func advanceToNextEpisode() {
        guard let next = nextEpisode else { return }
        teardownPlayer()
        currentEpisodeIndex = next.index
        subtitleCues = []
        activeSubtitleLabel = nil
        activeSubtitleText = nil
        upNextSecondsRemaining = nil
        startEpisode(index: next.index, startTime: 0)
    }

    private func startEpisode(index: Int, startTime: Double) {
        guard target.detail.episodes.indices.contains(index),
              let rawURL = URL(string: target.detail.episodes[index].url) else {
            return
        }

        let asset: AVURLAsset
        if appState.adBlockEnabled {
            let loader = HLSAdBlockLoader()
            let rewritten = HLSAdBlockLoader.rewriteURLForAdBlock(rawURL)
            asset = AVURLAsset(url: rewritten)
            asset.resourceLoader.setDelegate(loader, queue: DispatchQueue(label: "com.local.moontv.adblock"))
            self.adBlockLoader = loader
        } else {
            asset = AVURLAsset(url: rawURL)
        }

        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)

        if startTime > 5 {
            let seekTime = CMTime(seconds: startTime, preferredTimescale: 600)
            avPlayer.seek(to: seekTime)
        }

        let syncInterval = CMTime(seconds: 20, preferredTimescale: 600)
        syncObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: syncInterval, queue: .main) { currentTime in
            let currentSec = currentTime.seconds
            let durationSec = avPlayer.currentItem?.duration.seconds ?? 0
            guard currentSec.isFinite, durationSec.isFinite, durationSec > 0 else { return }
            Task {
                await appState.client.savePlayRecord(
                    source: target.detail.source,
                    sourceName: target.detail.sourceName,
                    videoId: target.detail.id,
                    title: target.detail.title,
                    cover: target.detail.poster,
                    episodeIndex: currentEpisodeIndex,
                    totalEpisodes: target.detail.episodes.count,
                    playTime: currentSec,
                    totalTime: durationSec
                )
            }
        }

        let subInterval = CMTime(seconds: 0.2, preferredTimescale: 600)
        subtitleObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: subInterval, queue: .main) { currentTime in
            let currentSec = currentTime.seconds
            let durationSec = avPlayer.currentItem?.duration.seconds ?? 0

            if !subtitleCues.isEmpty {
                let cue = SubtitleParser.activeCue(in: subtitleCues, at: currentSec, offset: subtitleOffset)
                if activeSubtitleText != cue?.text {
                    activeSubtitleText = cue?.text
                }
            } else if activeSubtitleText != nil {
                activeSubtitleText = nil
            }

            if nextEpisode != nil, currentSec.isFinite, durationSec.isFinite, durationSec > 60 {
                let remaining = Int(ceil(durationSec - currentSec))
                if remaining <= 25 && remaining > 0 {
                    upNextSecondsRemaining = remaining
                } else if remaining <= 0 {
                    advanceToNextEpisode()
                } else if upNextSecondsRemaining != nil {
                    upNextSecondsRemaining = nil
                }
            }
        }

        self.player = avPlayer
        avPlayer.play()
    }

    private func teardownPlayer() {
        if let player {
            let currentSec = player.currentTime().seconds
            let durationSec = player.currentItem?.duration.seconds ?? 0
            if currentSec.isFinite, durationSec.isFinite, durationSec > 0 {
                let epIndex = currentEpisodeIndex
                Task {
                    await appState.client.savePlayRecord(
                        source: target.detail.source,
                        sourceName: target.detail.sourceName,
                        videoId: target.detail.id,
                        title: target.detail.title,
                        cover: target.detail.poster,
                        episodeIndex: epIndex,
                        totalEpisodes: target.detail.episodes.count,
                        playTime: currentSec,
                        totalTime: durationSec
                    )
                    await appState.refreshDashboard()
                }
            }
            if let token = syncObserverToken {
                player.removeTimeObserver(token)
                syncObserverToken = nil
            }
            if let token = subtitleObserverToken {
                player.removeTimeObserver(token)
                subtitleObserverToken = nil
            }
            player.pause()
        }
        adBlockLoader = nil
    }
}

private struct AVPlayerControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer
    let hasNextEpisode: Bool
    let onOpenSubtitles: () -> Void
    let onPlayNextEpisode: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.transportBarCustomMenuItems = buildMenuItems()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
        uiViewController.transportBarCustomMenuItems = buildMenuItems()
    }

    private func buildMenuItems() -> [UIMenuElement] {
        var items: [UIMenuElement] = [
            UIAction(title: "Subtitles", image: UIImage(systemName: "captions.bubble")) { _ in
                onOpenSubtitles()
            }
        ]
        if hasNextEpisode {
            items.append(
                UIAction(title: "Next Episode", image: UIImage(systemName: "forward.end.fill")) { _ in
                    onPlayNextEpisode()
                }
            )
        }
        return items
    }
}
