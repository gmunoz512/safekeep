import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Opened via safekeep://paste from the iMessage extension (which can't read the clipboard).
/// Waits until the app is really active, pastes with build 7's working method, shows the result at the top,
/// queues a tapped photo until the sound is ready, saves, then shows the result.
struct QuickPasteView: View {
    let onClose: () -> Void
    @StateObject private var m = AddSoundModel()
    @StateObject private var recents = RecentPhotosModel()
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var autoPasteDone = false
    @State private var pasting = false
    @State private var photosOpenFailed = false
    @State private var viewing: SavedAsset?
    @State private var showLog = false
    @State private var presenter = PresenterHolder()

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let r = m.result {
                        header
                        savedCard(r)
                    } else {
                        header
                        statusCard
                        if let sel = m.selectedForSave, m.audioURL == nil { queuedRow(sel) }
                        photos
                    }
                    if showLog { LogPanel(m: m) }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
        .tint(Theme.peach)
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $viewing) { item in
            SavedPhotoViewer(item: item, log: { m.say($0) }) { viewing = nil }
        }
        .onAppear {
            m.logPrefix = "[app-paste] "
            m.confirmBeforeSave = false
            let model = m
            recents.log = { [weak model] s in model?.say(s) }
            m.say("=== Quick paste screen (opened from Messages) — build \(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?") — \(Date()) ===")
            m.setPasteStatus("Waiting for Safekeep to become active…")
            Task {
                if recents.status == .notDetermined { await recents.requestAccess() }
                await recents.load(reason: "quick paste screen")
            }
            if let file = router.pendingFile {
                router.pendingFile = nil
                autoPasteDone = true   // a chosen file replaces the clipboard paste
                m.say("chosen audio file: \(file.lastPathComponent)")
                Task {
                    await m.pickedFile(file)
                    if m.audioURL != nil { m.setPasteStatus("Voice note ready: \(String(format: "%.1f", m.audioDuration)) s") }
                }
            } else {
                scheduleAutoPaste(reason: "appear")
            }
        }
        .onChange(of: scenePhase) { p in
            m.say("scenePhase → \(p == .active ? "active" : p == .inactive ? "inactive" : "background")")
            scheduleAutoPaste(reason: "scenePhase")
        }
        .onChange(of: m.result) { r in
            if r != nil { m.say("saved → showing Saved card") }
        }
    }

    private var appActive: Bool { UIApplication.shared.applicationState == .active }

    /// The pasteboard isn't reliably readable while the app is still launching/opening from a URL,
    /// so wait for scenePhase == .active AND applicationState == .active, then give it a moment.
    private func scheduleAutoPaste(reason: String) {
        guard !autoPasteDone else { return }
        guard scenePhase == .active, appActive else {
            m.say("auto-paste waiting (\(reason)): scenePhase=\(scenePhase == .active ? "active" : "not active"), applicationState=\(UIApplication.shared.applicationState.rawValue)")
            return
        }
        autoPasteDone = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            Task {
                guard appActive else {
                    m.say("app no longer active; auto-paste postponed")
                    autoPasteDone = false
                    return
                }
                let ok = await paste(trigger: "auto, app active")
                if !ok && UIPasteboard.general.numberOfItems == 0 {
                    // Right after an app switch the clipboard can briefly read as empty: retry once.
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if m.audioURL == nil { _ = await paste(trigger: "auto retry") }
                }
            }
        }
    }

    @discardableResult
    private func paste(trigger: String) async -> Bool {
        guard !pasting else { return false }
        pasting = true
        defer { pasting = false }
        m.say("applicationState=\(UIApplication.shared.applicationState.rawValue) (0 = active)")
        return await m.pasteBuild7(trigger: trigger)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("Logo").resizable().frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Safekeep").font(Theme.rounded(.title3, .bold)).foregroundStyle(Theme.cream)
            Spacer()
            Button(showLog ? "Hide log" : "Log") { showLog.toggle() }.buttonStyle(SoftButtonStyle())
            Button("Close") { onClose() }.buttonStyle(SoftButtonStyle())
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: m.audioURL != nil ? "waveform" : (m.pasteStatusIsError ? "exclamationmark" : "doc.on.clipboard"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.onPeach)
                    .frame(width: 38, height: 38).background(Circle().fill(Theme.peach))
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.audioURL != nil ? "Voice note ready: \(String(format: "%.1f", m.audioDuration)) s"
                         : (m.busy || pasting ? "Pasting voice note…" : "Voice note not attached yet"))
                        .font(Theme.rounded(.headline, .semibold)).foregroundStyle(Theme.cream)
                    Text(m.audioURL != nil ? (m.selectedForSave == nil ? "Now tap a photo below" : "Saving…") : m.pasteStatus)
                        .font(Theme.rounded(.caption))
                        .foregroundStyle(m.pasteStatusIsError && m.audioURL == nil ? Theme.peach : Theme.sage)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                if m.busy || pasting { ProgressView().tint(Theme.peach) }
            }
            if m.audioURL != nil {
                HStack {
                    Button { m.togglePlay() } label: {
                        Label(m.isPlaying ? "Stop" : "Play", systemImage: m.isPlaying ? "stop.fill" : "play.fill")
                    }.buttonStyle(SoftButtonStyle())
                    Button("Paste a different one") { m.clearSound(); Task { await paste(trigger: "manual (replace)") } }
                        .buttonStyle(SoftButtonStyle())
                }
            } else {
                Button { Task { await paste(trigger: "manual button") } } label: {
                    Label("Paste voice note", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(PeachButtonStyle())
                .disabled(pasting || m.busy)
            }
        }
        .themeCard()
    }

    private func queuedRow(_ a: PHAsset) -> some View {
        HStack(spacing: 12) {
            PhotoThumb(asset: a, manager: recents.caching).frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Photo queued — it saves as soon as the voice note is ready")
                .font(Theme.rounded(.subheadline)).foregroundStyle(Theme.cream)
            Spacer()
            Button("Cancel") { m.cancelSelection() }.font(Theme.rounded(.footnote)).foregroundStyle(Theme.peach)
        }
        .themeCard(padding: 12)
    }

    private var photos: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent photos").font(Theme.rounded(.headline, .semibold)).foregroundStyle(Theme.cream)
            RecentPhotosGrid(recents: recents, selectedID: m.selectedForSave?.localIdentifier,
                             disabled: m.busy, columns: 3, presenter: presenter) { asset in
                // tapPhoto: sound ready → save now; otherwise the photo is queued (never saved without sound).
                m.tapPhoto(asset, source: "quick paste grid")
            }
        }
    }

    private func savedCard(_ r: SavedAsset) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            savedTitle
            LivePhotoResultCard(item: r, log: { m.say($0) }) { m.result = nil; m.clearSound() }
            Button { viewing = r } label: {
                Label("View photo", systemImage: "photo")
            }
            .buttonStyle(PeachButtonStyle())
            HStack(spacing: 6) {
                Text("It's in the \"Safekeep\" album.")
                    .font(Theme.rounded(.caption)).foregroundStyle(Theme.sage)
                Button("Open Photos app") { openPhotosApp() }
                    .font(Theme.rounded(.caption, .semibold)).foregroundStyle(Theme.peach)
            }
            if photosOpenFailed {
                Text("iOS wouldn't open Photos from here. Open the Photos app → Albums → \"Safekeep\".")
                    .font(Theme.rounded(.caption)).foregroundStyle(Theme.peach)
            }
            Button("Add another") { m.result = nil; m.clearSound() }.buttonStyle(SoftButtonStyle())
        }
    }

    private var savedTitle: some View {
        Label("Saved ✓", systemImage: "checkmark.circle.fill")
            .font(Theme.rounded(.largeTitle, .bold))
            .foregroundStyle(Theme.cream)
            .labelStyle(.titleOnly)
    }

    private func openPhotosApp() {
        // photos-redirect:// is Photos' own URL scheme: widely used but not documented by Apple.
        guard let url = URL(string: "photos-redirect://") else { photosOpenFailed = true; return }
        UIApplication.shared.open(url) { ok in
            m.say("open photos-redirect:// → \(ok)")
            if !ok { photosOpenFailed = true }
        }
    }
}

/// Full-screen in-app viewer for the saved Live Photo (there's no public API to open one specific asset in Photos).
struct SavedPhotoViewer: View {
    let item: SavedAsset
    var log: (String) -> Void = { _ in }
    let onClose: () -> Void
    @State private var livePhoto: PHLivePhoto?
    @State private var status = "Loading…"
    @State private var lastPlayed = "-"
    @State private var playing = false
    @State private var shareURLs: [URL] = []
    @State private var showShare = false
    @State private var preparingShare = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let livePhoto {
                LivePhotoViewRep(livePhoto: livePhoto, lastPlayed: $lastPlayed, playing: $playing)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(Theme.peach)
                    Text(status).font(Theme.rounded(.footnote)).foregroundStyle(Theme.sage)
                }
            }
            VStack {
                HStack {
                    Button("Done") { onClose() }.buttonStyle(SoftButtonStyle())
                    Spacer()
                    Button { Task { await prepareShare() } } label: {
                        if preparingShare { ProgressView().tint(Theme.onPeach) }
                        else { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                    .font(Theme.rounded(.subheadline, .semibold))
                    .foregroundStyle(Theme.onPeach)
                    .padding(.vertical, 8).padding(.horizontal, 14)
                    .background(Capsule().fill(Theme.peach))
                    .disabled(preparingShare)
                }
                .padding(.horizontal, 16).padding(.top, 8)
                Spacer()
                Text(playing ? "Playing…" : "Press and hold the photo to hear it")
                    .font(Theme.rounded(.subheadline, .medium))
                    .foregroundStyle(Theme.cream)
                    .padding(.vertical, 8).padding(.horizontal, 16)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: item.localIdentifier) { await load() }
        .sheet(isPresented: $showShare) { ActivitySheet(items: shareURLs) }
    }

    private func load() async {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.localIdentifier], options: nil).firstObject else {
            status = "Saved photo not found."; log("viewer: asset not found"); return
        }
        let o = PHLivePhotoRequestOptions()
        o.deliveryMode = .highQualityFormat
        o.isNetworkAccessAllowed = true
        PHImageManager.default().requestLivePhoto(for: asset, targetSize: PHImageManagerMaximumSize,
                                                  contentMode: .aspectFit, options: o) { photo, meta in
            DispatchQueue.main.async {
                if let photo { livePhoto = photo }
                else if (meta?[PHImageResultIsDegradedKey] as? Bool) != true {
                    status = "Preview unavailable: " + ((meta?[PHImageErrorKey] as? NSError)?.localizedDescription ?? "no Live Photo")
                    log("viewer: \(status)")
                }
            }
        }
    }

    /// Exports the photo + paired movie (same content identifier) so the share sheet can send it as a Live Photo.
    private func prepareShare() async {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.localIdentifier], options: nil).firstObject else { return }
        preparingShare = true
        defer { preparingShare = false }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for r in PHAssetResource.assetResources(for: asset) where r.type == .photo || r.type == .pairedVideo {
            let url = dir.appendingPathComponent(r.originalFilename)
            let o = PHAssetResourceRequestOptions(); o.isNetworkAccessAllowed = true
            do {
                try await PHAssetResourceManager.default().writeData(for: r, toFile: url, options: o)
                urls.append(url)
            } catch { log("viewer share: export \(r.originalFilename) failed: \(error.localizedDescription)") }
        }
        log("viewer share: \(urls.map(\.lastPathComponent))")
        guard !urls.isEmpty else { return }
        shareURLs = urls
        showShare = true
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
