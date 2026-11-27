import AVFoundation
import UIKit
import Photos
import PhotosUI
import SwiftUI

/// Activates a playback session that is not silenced by the Ring/Silent switch.
/// PHLivePhotoView still often stays silent when the switch is on (same as the Photos app),
/// so in-app playback also plays the paired movie's audio with AVPlayer.
enum LivePhotoAudio {
    static func activatePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            // Changing category can fail if a session is already active; drop it and retry.
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(.playback, mode: .moviePlayback)
            try? session.setActive(true)
        }
    }

    /// Press-and-hold must beat the enclosing SwiftUI ScrollView, which otherwise
    /// delays/cancels the gesture and leaves only the muted "hint" animation.
    static func allowPressAndHold(in view: UIView) {
        var current: UIView? = view.superview
        while let c = current {
            if let scroll = c as? UIScrollView {
                scroll.canCancelContentTouches = false
                scroll.delaysContentTouches = false
                return
            }
            current = c.superview
        }
    }

    /// Writes the Live Photo's paired movie (the voice track lives here) to a temp file for AVPlayer.
    static func exportPairedMovie(for asset: PHAsset) async -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let video = resources.first(where: { $0.type == .pairedVideo }) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("safekeep-audio-\(UUID().uuidString).MOV")
        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true
        do {
            try await PHAssetResourceManager.default().writeData(for: video, toFile: url, options: opts)
            return url
        } catch {
            return nil
        }
    }
}

/// PHLivePhotoView that keeps audio on and prepares the session as soon as it is on screen.
final class UnmutedLivePhotoView: PHLivePhotoView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        LivePhotoAudio.allowPressAndHold(in: self)
        LivePhotoAudio.activatePlaybackSession()
        if !didHookGesture {
            playbackGestureRecognizer.addTarget(self, action: #selector(prepareSession(_:)))
            didHookGesture = true
        }
    }

    private var didHookGesture = false

    @objc private func prepareSession(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            LivePhotoAudio.activatePlaybackSession()
        }
    }
}

struct LivePhotoViewRep: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    /// Paired movie file from the saved Photos asset. Played with AVPlayer so the voice
    /// is heard even when the Ring/Silent switch is on (PHLivePhotoView often stays mute).
    var audioURL: URL? = nil
    @Binding var lastPlayed: String
    @Binding var playing: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let v = UnmutedLivePhotoView()
        v.contentMode = .scaleAspectFit
        v.isMuted = (audioURL != nil)
        v.delegate = context.coordinator
        return v
    }

    func updateUIView(_ v: PHLivePhotoView, context: Context) {
        context.coordinator.parent = self
        if v.livePhoto !== livePhoto { v.livePhoto = livePhoto }
        // When we have our own player, mute the view so the voice isn't doubled if
        // PHLivePhotoView also plays audio (silent switch off).
        v.isMuted = (audioURL != nil)
    }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        var parent: LivePhotoViewRep
        private var start: Date?
        private var audioPlayer: AVPlayer?
        init(_ p: LivePhotoViewRep) { parent = p }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, willBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            LivePhotoAudio.activatePlaybackSession()
            start = Date()
            // Hint playback is a short bounce and is typically muted. Only full
            // (press-and-hold) playback should show "Playing…" and play the voice.
            parent.playing = (playbackStyle == .full)
            if playbackStyle == .full {
                startPairedAudio()
            }
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            stopPairedAudio()
            let secs = start.map { Date().timeIntervalSince($0) } ?? 0
            parent.playing = false
            parent.lastPlayed = String(format: "%.1f s (%@)", secs, playbackStyle == .full ? "full" : "hint")
        }

        private func startPairedAudio() {
            stopPairedAudio()
            guard let url = parent.audioURL else { return }
            let player = AVPlayer(url: url)
            player.volume = 1
            player.isMuted = false
            player.play()
            audioPlayer = player
        }

        private func stopPairedAudio() {
            audioPlayer?.pause()
            audioPlayer = nil
        }
    }
}

/// Short inline result (used by the iMessage extension): press-and-hold Live Photo preview.
struct LivePhotoResultCard: View {
    let item: SavedAsset
    var log: (String) -> Void = { _ in }
    var onDone: () -> Void
    @State private var livePhoto: PHLivePhoto?
    @State private var audioURL: URL?
    @State private var status = "Loading…"
    @State private var lastPlayed = "-"
    @State private var playing = false
    @State private var isLive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Saved to Photos", systemImage: "checkmark.circle.fill").font(Theme.rounded(.headline, .semibold)).foregroundStyle(Theme.peach)
                Spacer()
                Button("Done", action: onDone).buttonStyle(SoftButtonStyle())
            }
            ZStack {
                Color.black.opacity(0.15)
                if let livePhoto {
                    LivePhotoViewRep(livePhoto: livePhoto, audioURL: audioURL, lastPlayed: $lastPlayed, playing: $playing)
                } else {
                    Text(status).font(Theme.rounded(.footnote)).foregroundStyle(Theme.sage).padding()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(playing ? "Playing…" : "Press and hold the photo to hear it.").font(Theme.rounded(.subheadline)).foregroundStyle(Theme.cream)
            Text("Live Photo: \(isLive ? "yes" : "checking…") · last play: \(lastPlayed) · album \"Safekeep\"")
                .font(Theme.rounded(.caption2)).foregroundStyle(Theme.sage)
        }
        .themeCard()
        .task(id: item.localIdentifier) { await load() }
    }

    private func load() async {
        LivePhotoAudio.activatePlaybackSession()
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.localIdentifier], options: nil).firstObject else {
            status = "Saved asset not found."; log("result: asset not found \(item.localIdentifier)"); return
        }
        isLive = asset.mediaSubtypes.contains(.photoLive)
        let movie = await LivePhotoAudio.exportPairedMovie(for: asset)
        audioURL = movie
        let size = movie.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? NSNumber)?.intValue } ?? 0
        log("result card: \(item.localIdentifier) isLive=\(isLive) pairedMovie=\(movie != nil ? "yes (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))" : "NO")")
        let o = PHLivePhotoRequestOptions()
        o.deliveryMode = .highQualityFormat
        o.isNetworkAccessAllowed = true
        // Screen-sized request (not full size) to keep extension memory down.
        PHImageManager.default().requestLivePhoto(for: asset, targetSize: CGSize(width: 1200, height: 1200),
                                                  contentMode: .aspectFit, options: o) { photo, meta in
            DispatchQueue.main.async {
                if let photo { livePhoto = photo }
                else {
                    status = "Preview unavailable: " + ((meta?[PHImageErrorKey] as? NSError)?.localizedDescription ?? "no Live Photo")
                    log("result card: \(status)")
                }
                log(Mem.line("result preview"))
            }
        }
    }
}
