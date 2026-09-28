import Photos
import SwiftUI

/// Clipboard card → sound ready → recent photos grid. Used by the iMessage extension (and the app's debug screen).
struct QuickFlowView: View {
    @ObservedObject var m: AddSoundModel
    @ObservedObject var recents: RecentPhotosModel
    var columns = 4
    /// Called before anything that needs more room (extension: switch to expanded).
    var onNeedRoom: () -> Void = {}
    @State private var presenter = PresenterHolder()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            clipboardCard
            if m.busy { busyRow }
            if m.audioURL != nil { soundReadyRow }
            if let sel = m.selectedForSave, m.audioURL == nil { pendingRow(sel) }
            recentSection
        }
    }

    private var clipboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if m.clipboardOffer != nil {
                Label("Voice note copied — tap to use", systemImage: "waveform").font(.headline)
                AudioPasteButton { providers in
                    Task { await m.pasteFromControl(providers) }
                }
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
                HStack {
                    Button("Paste another way") { Task { await m.pasteAudio() } }
                    Spacer()
                    Button("Not now") { m.dismissClipboardOffer() }
                }
                .font(.footnote)
            } else if m.audioURL == nil {
                Text("1. In the chat, hold the voice note → Copy").font(.subheadline)
                Text("2. Come back here and tap Paste").font(.subheadline)
                HStack(spacing: 12) {
                    AudioPasteButton { providers in
                        Task { await m.pasteFromControl(providers) }
                    }
                    .frame(width: 210, height: 52)
                    Button("Paste another way") { Task { await m.pasteAudio() } }.font(.footnote)
                }
            }
        }
        .padding(m.clipboardOffer != nil || m.audioURL == nil ? 14 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(m.clipboardOffer != nil ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemBackground)))
    }

    private var busyRow: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(m.downloadProgress.map { "Downloading photo from iCloud… \(Int($0 * 100))%" } ?? "Working…")
                .font(.subheadline)
        }
    }

    private var soundReadyRow: some View {
        HStack {
            Image(systemName: "waveform.circle.fill").font(.title2).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sound ready: \(String(format: "%.1f", m.audioDuration)) s").font(.headline)
                Text(m.selectedForSave == nil ? "Now tap a photo below" : "Saving…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { m.togglePlay() } label: {
                Label(m.isPlaying ? "Stop" : "Play", systemImage: m.isPlaying ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.bordered)
            Button { m.clearSound() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
        }
    }

    private func pendingRow(_ a: PHAsset) -> some View {
        HStack {
            PhotoThumb(asset: a, manager: recents.caching).frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("Photo selected — paste the voice note to save").font(.subheadline)
            Spacer()
            Button("Cancel") { m.cancelSelection() }.font(.footnote)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent photos").font(.headline)
                Spacer()
                Text("newest added first").font(.caption2).foregroundStyle(.secondary)
            }
            RecentPhotosGrid(recents: recents, selectedID: m.selectedForSave?.localIdentifier ?? m.confirmAsset?.localIdentifier,
                             disabled: m.busy, columns: columns, presenter: presenter) { asset in
                onNeedRoom()
                m.tapPhoto(asset, source: "recent grid")
            }
        }
    }
}

/// Small confirm sheet (app debug screen).
struct ConfirmSaveSheet: View {
    let asset: PHAsset
    let duration: Double
    let manager: PHCachingImageManager
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                PhotoThumb(asset: asset, manager: manager).frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add sound to this photo").font(.headline)
                    Text("Sound: \(String(format: "%.1f", duration)) s").font(.subheadline)
                    Text("A new copy is saved; the original stays untouched.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Button(action: onSave) {
                Text("Save sound copy").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel", role: .cancel, action: onCancel)
        }
        .padding()
    }
}

/// Log text + copy/clear (shared by app debug screen and extension).
struct LogPanel: View {
    @ObservedObject var m: AddSoundModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Copy log") { UIPasteboard.general.string = m.log }
                Spacer()
                Button("Clear") { m.clearLog() }
            }
            .font(.footnote)
            Text(m.log)
                .font(.system(.caption2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
