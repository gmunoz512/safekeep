import AVFoundation
import Photos
import PhotosUI
import SwiftUI

/// Shows one saved asset as a Live Photo. Press and hold to play (with audio).
struct LivePhotoDetail: View {
    let item: SavedAsset
    @State private var livePhoto: PHLivePhoto?
    @State private var status = "Loading…"
    @State private var info = ""
    @State private var lastPlayed = "-"
    @State private var playing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(item.code): \(item.title)").font(.headline)
                ZStack {
                    Color.black.opacity(0.05)
                    if let livePhoto {
                        LivePhotoViewRep(livePhoto: livePhoto, lastPlayed: $lastPlayed, playing: $playing)
                    } else {
                        Text(status).font(.footnote).padding()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 380)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(playing ? "Playing…" : "Press and hold the photo to play.")
                    .font(.subheadline)
                Text("Last playback duration: \(lastPlayed)").font(.subheadline.monospacedDigit())
                Text(info).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                Spacer()
            }
            .padding()
            .navigationTitle("Saved result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Open Photos") { openPhotos() }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            info += "Audio session error: \(error.localizedDescription)\n"
        }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.localIdentifier], options: nil).firstObject else {
            status = "Asset not found in library (deleted, or no Photos access)."
            return
        }
        let df = DateFormatter()
        df.dateStyle = .medium; df.timeStyle = .medium
        info += "id: \(item.localIdentifier)\n"
        info += "created: \(asset.creationDate.map(df.string(from:)) ?? "nil")  hidden: \(asset.isHidden)\n"
        info += "iOS says Live: \(asset.mediaSubtypes.contains(.photoLive))  \(asset.pixelWidth)x\(asset.pixelHeight)\n"
        let opts = PHLivePhotoRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        PHImageManager.default().requestLivePhoto(for: asset, targetSize: PHImageManagerMaximumSize,
                                                  contentMode: .aspectFit, options: opts) { photo, meta in
            DispatchQueue.main.async {
                if let photo {
                    livePhoto = photo
                } else {
                    let err = (meta?[PHImageErrorKey] as? NSError).map { "\($0.domain) \($0.code) \($0.localizedDescription)" } ?? "no Live Photo returned"
                    status = "requestLivePhoto failed: \(err)"
                }
            }
        }
    }
}

func openPhotos() {
    if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
}

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
