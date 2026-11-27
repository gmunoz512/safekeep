import AVFoundation
import UIKit
import Photos
import PhotosUI
import SwiftUI

/// Activates a playback session that is not silenced by the Ring/Silent switch.
/// PHLivePhotoView will otherwise follow the default session (silenced when the switch is on),
/// which matches "Playing…" with no sound.
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
}

/// PHLivePhotoView that keeps audio on and prepares the session as soon as it is on screen.
final class UnmutedLivePhotoView: PHLivePhotoView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        isMuted = false
        LivePhotoAudio.allowPressAndHold(in: self)
        LivePhotoAudio.activatePlaybackSession()
    }
}

struct LivePhotoViewRep: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    @Binding var lastPlayed: String
    @Binding var playing: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let v = UnmutedLivePhotoView()
        v.contentMode = .scaleAspectFit
        v.isMuted = false
        v.delegate = context.coordinator
        return v
    }

    func updateUIView(_ v: PHLivePhotoView, context: Context) {
        context.coordinator.parent = self
        if v.livePhoto !== livePhoto { v.livePhoto = livePhoto }
        v.isMuted = false
    }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        var parent: LivePhotoViewRep
        private var start: Date?
        init(_ p: LivePhotoViewRep) { parent = p }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, willBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            LivePhotoAudio.activatePlaybackSession()
            livePhotoView.isMuted = false
            start = Date()
            // Hint playback is a short bounce and is typically muted. Only full
            // (press-and-hold) playback should show "Playing…".
            parent.playing = (playbackStyle == .full)
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            let secs = start.map { Date().timeIntervalSince($0) } ?? 0
            parent.playing = false
            parent.lastPlayed = String(format: "%.1f s (%@)", secs, playbackStyle == .full ? "full" : "hint")
        }
    }
}

/// Short inline result (used by the iMessage extension): press-and-hold Live Photo preview.
struct LivePhotoResultCard: View {
    let item: SavedAsset
    var log: (String) -> Void = { _ in }
    var onDone: () -> Void
    @State private var livePhoto: PHLivePhoto?
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
                    LivePhotoViewRep(livePhoto: livePhoto, lastPlayed: $lastPlayed, playing: $playing)
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
        log("result card: \(item.localIdentifier) isLive=\(isLive)")
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
