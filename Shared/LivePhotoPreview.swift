import AVFoundation
import Photos
import PhotosUI
import SwiftUI

struct LivePhotoViewRep: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    @Binding var lastPlayed: String
    @Binding var playing: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let v = PHLivePhotoView()
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
            start = Date()
            parent.playing = true
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
                Label("Saved to Photos", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
                Spacer()
                Button("Done", action: onDone).buttonStyle(.bordered)
            }
            ZStack {
                Color.black.opacity(0.05)
                if let livePhoto {
                    LivePhotoViewRep(livePhoto: livePhoto, lastPlayed: $lastPlayed, playing: $playing)
                } else {
                    Text(status).font(.footnote).padding()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(playing ? "Playing…" : "Press and hold the photo to hear it.").font(.subheadline)
            Text("Live Photo: \(isLive ? "yes" : "checking…") · last play: \(lastPlayed) · album \"Safekeep\"")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(0.08)))
        .task(id: item.localIdentifier) { await load() }
    }

    private func load() async {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
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
