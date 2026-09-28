import Photos
import SwiftUI
import UIKit

/// Opened via safekeep://paste from the iMessage extension (which can't read the clipboard).
/// Auto-pastes the copied voice note, shows recent photos, tap = save, then heads back to Messages.
struct QuickPasteView: View {
    let onClose: () -> Void
    @StateObject private var m = AddSoundModel()
    @StateObject private var recents = RecentPhotosModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var didAutoPaste = false
    @State private var returning = false
    @State private var showLog = false

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let r = m.result {
                        savedCard(r)
                    } else {
                        QuickFlowView(m: m, recents: recents, columns: 3)
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
            Task {
                if recents.status == .notDetermined { await recents.requestAccess() }
                await recents.load(reason: "quick paste screen")
            }
            autoPasteIfActive()
        }
        .onChange(of: scenePhase) { _ in autoPasteIfActive() }
        .onChange(of: m.result) { r in
            guard r != nil, !returning else { return }
            returning = true
            m.say("saved → returning to Messages in 1.2 s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { backToMessages() }
        }
    }

    private func autoPasteIfActive() {
        guard !didAutoPaste, scenePhase == .active else { return }
        didAutoPaste = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            m.say("auto-paste (direct read; iOS may ask \"Allow Paste\")")
            Task { await m.pasteAudio() }
        }
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

    private func savedCard(_ r: SavedAsset) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Saved to Photos", systemImage: "checkmark.circle.fill")
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
