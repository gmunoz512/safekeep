import Photos
import SwiftUI
import UIKit

/// Opened via safekeep://paste from the iMessage extension (which can't read the clipboard).
/// Waits until the app is really active, pastes with build 7's working method, shows the result at the top,
/// queues a tapped photo until the sound is ready, saves, then heads back to Messages.
struct QuickPasteView: View {
    let onClose: () -> Void
    @StateObject private var m = AddSoundModel()
    @StateObject private var recents = RecentPhotosModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var autoPasteDone = false
    @State private var pasting = false
    @State private var returning = false
    @State private var showLog = false
    @State private var presenter = PresenterHolder()

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let r = m.result {
                        savedCard(r)
                    } else {
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
            scheduleAutoPaste(reason: "appear")
        }
        .onChange(of: scenePhase) { p in
            m.say("scenePhase → \(p == .active ? "active" : p == .inactive ? "inactive" : "background")")
            scheduleAutoPaste(reason: "scenePhase")
        }
        .onChange(of: m.result) { r in
            guard r != nil, !returning else { return }
            returning = true
            m.say("saved → returning to Messages in 1.5 s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { backToMessages() }
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
        VStack(alignment: .leading, spacing: 14) {
            Label("Saved with the voice note", systemImage: "checkmark.circle.fill")
                .font(Theme.rounded(.title3, .semibold)).foregroundStyle(Theme.peach)
            Text("Returning to Messages… (or tap \"◀ Messages\" at the top left)")
                .font(Theme.rounded(.subheadline)).foregroundStyle(Theme.cream)
            Button("Back to Messages") { backToMessages() }.buttonStyle(PeachButtonStyle())
            Button("Add another") { m.result = nil; returning = false; m.clearSound() }.buttonStyle(SoftButtonStyle())
        }
        .themeCard()
    }

    private func backToMessages() {
        let urls = ["messages://", "sms:"].compactMap(URL.init(string:))
        func tryOpen(_ i: Int) {
            guard i < urls.count else { m.say("couldn't open Messages; use ◀ Messages"); return }
            UIApplication.shared.open(urls[i]) { ok in
                m.say("open \(urls[i]) → \(ok)")
                if !ok { tryOpen(i + 1) }
            }
        }
        tryOpen(0)
    }
}
