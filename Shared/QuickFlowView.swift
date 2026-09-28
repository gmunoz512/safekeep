import Photos
import SwiftUI

/// Clipboard card → sound ready → recent photos grid. Used by the iMessage extension (and the app's debug screen).
struct QuickFlowView: View {
    @ObservedObject var m: AddSoundModel
    @ObservedObject var recents: RecentPhotosModel
    var columns = 4
    /// Called before anything that needs more room (extension: switch to expanded).
    var onNeedRoom: () -> Void = {}
    /// Extension only: open the containing app (which can read the clipboard) as a fallback.
    var openApp: (() -> Void)? = nil
    @State private var presenter = PresenterHolder()
    @State private var showDocPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            clipboardCard
            if m.busy { busyRow }
            if m.audioURL != nil { soundReadyRow }
            if let sel = m.selectedForSave, m.audioURL == nil { pendingRow(sel) }
            recentSection
        }
    }

    private var pasteButton: some View {
        AudioPasteButton(
            onPaste: { providers in Task { await m.pasteFromControl(providers) } },
            onTouch: { m.pasteButtonTouched() },
            onEnabledChange: { e in m.pasteButtonEnabledChanged(e) }
        )
    }

    private var clipboardCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if m.audioURL == nil {
                if m.clipboardOffer != nil {
                    Label("Voice note copied — tap to use", systemImage: "waveform")
                        .font(Theme.rounded(.headline, .semibold)).foregroundStyle(Theme.cream)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        numbered(1, "In the chat, hold the voice note → Copy")
                        numbered(2, "Come back here and tap Paste")
                    }
                }
                HStack(spacing: 12) {
                    pasteButton.frame(width: 210, height: 52)
                    Button("Paste another way") { onNeedRoom(); Task { await m.pasteAudio() } }
                        .buttonStyle(SoftButtonStyle())
                }
                HStack(spacing: 8) {
                    Button { onNeedRoom(); m.say("Choose audio file tapped"); showDocPicker = true } label: {
                        Label("Choose audio file", systemImage: "folder")
                    }
                    .buttonStyle(SoftButtonStyle())
                    if let openApp {
                        Button { openApp() } label: { Label("Open Safekeep", systemImage: "arrow.up.forward.app") }
                            .buttonStyle(SoftButtonStyle())
                    }
                    Spacer(minLength: 0)
                    if m.clipboardOffer != nil {
                        Button("Not now") { m.dismissClipboardOffer() }
                            .font(Theme.rounded(.footnote)).foregroundStyle(Theme.sage)
                    }
                }
            }
            statusLines
        }
        .themeCard()
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Theme.peach.opacity(m.clipboardOffer != nil && m.audioURL == nil ? 0.8 : 0), lineWidth: 1.5))
        .sheet(isPresented: $showDocPicker) {
            AudioDocPicker(isPresented: $showDocPicker) { url in Task { await m.pickedFile(url) } }
        }
        .onAppear { m.checkClipboard(trigger: "card appeared") }
    }

    private func numbered(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.onPeach)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.peach))
            Text(text).font(Theme.rounded(.subheadline)).foregroundStyle(Theme.cream)
        }
    }

    /// Always-visible status: live clipboard types, paste button state, and the result of the last tap.
    private var statusLines: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(m.clipStatus)
            if let e = m.pasteButtonEnabled, m.audioURL == nil {
                Text(e ? "Paste button: active" : "Paste button: greyed out (iOS reports no audio on the clipboard for Safekeep)")
            }
            if !m.pasteStatus.isEmpty {
                Text(m.pasteStatus).foregroundStyle(m.pasteStatusIsError ? Theme.warning : Theme.cream)
            }
            if m.clipboardUnreadable && m.audioURL == nil {
                Text("Safekeep can't read the clipboard from inside Messages on this iPhone. Use \"Choose audio file\"\(openApp != nil ? ", or \"Open Safekeep\" to paste there" : "").")
                    .foregroundStyle(Theme.warning)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(Theme.sage)
        .textSelection(.enabled)
    }

    private var busyRow: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Theme.peach)
            Text(m.downloadProgress.map { "Downloading photo from iCloud… \(Int($0 * 100))%" } ?? "Working…")
                .font(Theme.rounded(.subheadline)).foregroundStyle(Theme.cream)
        }
    }

    private var soundReadyRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform").font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.onPeach)
                .frame(width: 38, height: 38).background(Circle().fill(Theme.peach))
            VStack(alignment: .leading, spacing: 2) {
                Text("Sound ready: \(String(format: "%.1f", m.audioDuration)) s").font(Theme.rounded(.headline, .semibold)).foregroundStyle(Theme.cream)
                Text(m.selectedForSave == nil ? "Now tap a photo below" : "Saving…").font(Theme.rounded(.caption)).foregroundStyle(Theme.sage)
            }
            Spacer()
            Button { m.togglePlay() } label: {
                Label(m.isPlaying ? "Stop" : "Play", systemImage: m.isPlaying ? "stop.fill" : "play.fill")
            }
            .buttonStyle(SoftButtonStyle())
            Button { m.clearSound() } label: { Image(systemName: "xmark").foregroundStyle(Theme.sage) }
                .buttonStyle(.borderless)
        }
        .themeCard(padding: 12)
    }

    private func pendingRow(_ a: PHAsset) -> some View {
        HStack(spacing: 12) {
            PhotoThumb(asset: a, manager: recents.caching).frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Photo selected — paste the voice note to save").font(Theme.rounded(.subheadline)).foregroundStyle(Theme.cream)
            Spacer()
            Button("Cancel") { m.cancelSelection() }.font(Theme.rounded(.footnote)).foregroundStyle(Theme.peach)
        }
        .themeCard(padding: 12)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent photos").font(Theme.rounded(.headline, .semibold)).foregroundStyle(Theme.cream)
                Spacer()
                Text("newest added first").font(Theme.rounded(.caption2)).foregroundStyle(Theme.sage)
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
