import Messages
import Photos
import SwiftUI
import UIKit

/// iMessage app (opened from the + drawer in a conversation). Flow: open → Paste → tap photo → saved.
final class MessagesViewController: MSMessagesAppViewController {
    private let model = AddSoundModel()
    private let recents = RecentPhotosModel()
    private let ui = ExtUIState()
    private var host: UIHostingController<ExtensionRootView>?
    private var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        model.logPrefix = "[ext] "
        model.movieMaxSide = 1440
        model.confirmBeforeSave = false
        recents.log = { [weak model = self.model] s in model?.say(s) }
        model.say("=== Safekeep iMessage extension — build \(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?") — \(Date()) ===")
        model.say(Mem.line("viewDidLoad"))
        let root = ExtensionRootView(m: model, recents: recents, ui: ui,
                                     requestExpand: { [weak self] in self?.expandIfNeeded() },
                                     openApp: { [weak self] in self?.openContainingApp() },
                                     insertLog: { [weak self] in self?.insertLogIntoMessage() })
        let h = UIHostingController(rootView: root)
        h.overrideUserInterfaceStyle = .dark
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0x0E / 255, green: 0x4F / 255, blue: 0x57 / 255, alpha: 1)
        h.view.backgroundColor = .clear
        addChild(h)
        h.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(h.view)
        NSLayoutConstraint.activate([
            h.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            h.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            h.view.topAnchor.constraint(equalTo: view.topAnchor),
            h.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        h.didMove(toParent: self)
        host = h
    }

    /// Fallback when the extension can't read the clipboard: the app itself can.
    private func openContainingApp() {
        guard let url = URL(string: "safekeep://paste?from=messages&t=\(Int(Date().timeIntervalSince1970))") else { return }
        model.say("Opening Safekeep app via \(url)…")
        guard let ctx = extensionContext else {
            model.setPasteStatus("Can't open the app: no extension context.", error: true); return
        }
        ctx.open(url) { [weak self] ok in
            Task { @MainActor in
                self?.model.say("open(\(url)) → \(ok)")
                if !ok { self?.model.setPasteStatus("iOS didn't open the Safekeep app from Messages. Open it from the Home Screen instead.", error: true) }
            }
        }
    }

    /// Puts the log into the message field (works even if the clipboard is off-limits for the extension).
    private func insertLogIntoMessage() {
        guard let conv = activeConversation else {
            model.setPasteStatus("No active conversation to put the log into.", error: true); return
        }
        let text = String(model.log.suffix(15000))
        conv.insertText("Safekeep log:\n" + text) { [weak self] err in
            Task { @MainActor in
                if let err { self?.model.setPasteStatus("Couldn't put the log in the message field: \(err.localizedDescription)", error: true) }
                else { self?.model.setPasteStatus("Log put in the message field (\(text.count) chars). Send it to yourself or copy it from there.") }
            }
        }
        requestPresentationStyle(.compact)
    }

    private func expandIfNeeded() {
        if presentationStyle == .compact {
            model.say("requesting expanded presentation")
            requestPresentationStyle(.expanded)
        }
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        ui.compact = presentationStyle == .compact
        model.say("willBecomeActive (style \(presentationStyle == .compact ? "compact" : "expanded"))")
        model.checkClipboard(trigger: "willBecomeActive")
        Task { await recents.load(reason: "extension became active") }
        startTimer()
    }

    override func didResignActive(with conversation: MSConversation) {
        super.didResignActive(with: conversation)
        model.say("didResignActive")
        stopTimer()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        model.checkClipboard(trigger: "viewDidAppear")
    }

    override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.willTransition(to: presentationStyle)
        ui.compact = presentationStyle == .compact
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        model.say("presentation → \(presentationStyle == .compact ? "compact" : presentationStyle == .expanded ? "expanded" : "other")")
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        model.say("MEMORY WARNING — " + Mem.line())
        recents.caching.stopCachingImagesForAllAssets()
    }

    /// The drawer can stay open while you copy in the chat, so re-check the clipboard (metadata only, no prompt).
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.checkClipboard(trigger: "timer") }
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }
}

final class ExtUIState: ObservableObject {
    @Published var compact = true
}

struct ExtensionRootView: View {
    @ObservedObject var m: AddSoundModel
    @ObservedObject var recents: RecentPhotosModel
    @ObservedObject var ui: ExtUIState
    let requestExpand: () -> Void
    let openApp: () -> Void
    let insertLog: () -> Void
    @State private var showLog = false
    @State private var showDocPicker = false

    var body: some View {
        ZStack {
        Theme.background
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header.id("top")
                    if let r = m.result {
                        LivePhotoResultCard(item: r, log: { m.say($0) }) { m.result = nil }
                    }
                    if recents.status == .notDetermined || recents.status == .denied || recents.status == .restricted {
                        permissionCard
                    }
                    addCard
                    QuickFlowView(m: m, recents: recents, columns: 4, onNeedRoom: requestExpand, showPasteControls: false)
                    if showLog { logSection }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .onChange(of: m.result) { r in
                if r != nil { requestExpand(); withAnimation { proxy.scrollTo("top", anchor: .top) } }
            }
            .onChange(of: m.busy) { b in
                if b { withAnimation { proxy.scrollTo("top", anchor: .top) } }
            }
        }
        }
        .tint(Theme.peach)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("Logo").resizable().frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text("Safekeep").font(Theme.rounded(.title3, .bold)).foregroundStyle(Theme.cream)
            Spacer()
            Button(showLog ? "Hide log" : "Log") {
                showLog.toggle()
                if showLog { requestExpand() }
            }
            .buttonStyle(SoftButtonStyle())
        }
    }

    /// Paste and drag are blocked for Messages extensions, so the main action hands off to the app.
    private var addCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if m.audioURL == nil {
                Button { openApp() } label: {
                    Label("Add copied voice note", systemImage: "waveform")
                }
                .buttonStyle(PeachButtonStyle())
                Text("Hold the voice note → Copy, then tap here")
                    .font(Theme.rounded(.subheadline, .medium)).foregroundStyle(Theme.cream)
                Text("Or: Save to Voice Memos → Share → Safekeep")
                    .font(Theme.rounded(.caption)).foregroundStyle(Theme.sage)
                Button { requestExpand(); m.say("Choose audio file tapped"); showDocPicker = true } label: {
                    Label("Choose audio file", systemImage: "folder")
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
        .themeCard()
        .sheet(isPresented: $showDocPicker) {
            AudioDocPicker(isPresented: $showDocPicker) { url in Task { await m.pickedFile(url) } }
        }
    }

    /// Log is always reachable with plain buttons (no menu).
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics (paste is blocked by iOS inside Messages)")
                .font(Theme.rounded(.caption, .semibold)).foregroundStyle(Theme.sage)
            Text([m.clipStatus, m.pasteButtonEnabled.map { $0 ? "Paste button: active" : "Paste button: greyed out" } ?? "", m.pasteStatus]
                    .filter { !$0.isEmpty }.joined(separator: "\n"))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.sage)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                AudioPasteButton(
                    onPaste: { providers in Task { await m.pasteFromControl(providers) } },
                    onTouch: { m.pasteButtonTouched() },
                    onEnabledChange: { e in m.pasteButtonEnabledChanged(e) }
                ).frame(width: 150, height: 40)
                Button("Paste another way") { Task { await m.pasteAudio() } }
            }
            .buttonStyle(SoftButtonStyle())
            HStack(spacing: 10) {
                Button("Copy log (replaces clipboard)") { copyLog() }
                Button("Put log in message") { insertLog() }
                Spacer()
            }
            .buttonStyle(SoftButtonStyle())
            HStack(spacing: 10) {
                Button("Reload photos") { Task { await recents.load(reason: "manual") } }
                Button("Check clipboard") { m.checkClipboard(trigger: "manual") }
                Spacer()
                Button("Clear log", role: .destructive) { m.clearLog() }
            }
            .buttonStyle(SoftButtonStyle())
                ScrollView {
                    Text(m.log)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.cream.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(6)
                }
                .frame(height: 260)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.2)))
        }
    }

    private func copyLog() {
        let pb = UIPasteboard.general
        let before = pb.changeCount
        pb.string = m.log
        let after = pb.changeCount
        if after != before {
            m.setPasteStatus("Log copied (\(m.log.count) chars).")
        } else {
            m.setPasteStatus("Copy log didn't reach the clipboard (change # stayed \(before)) — iOS blocks the clipboard here. Use \"Put log in message\".", error: true)
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recents.status == .notDetermined ? "Safekeep needs access to your photos." : "Open Safekeep once to allow Photos access.")
                .font(Theme.rounded(.subheadline, .semibold)).foregroundStyle(Theme.cream)
            if recents.status == .notDetermined {
                Button("Allow Photos access") {
                    Task { await recents.requestAccess(); await recents.load(reason: "after permission request") }
                }
                .buttonStyle(PeachButtonStyle())
                Text("If nothing happens, open the Safekeep app once and allow Full Access.")
                    .font(Theme.rounded(.caption)).foregroundStyle(Theme.sage)
            } else {
                Text("Photos access is off. Open the Safekeep app (or Settings > Privacy & Security > Photos) and choose Full Access.")
                    .font(Theme.rounded(.caption)).foregroundStyle(Theme.sage)
            }
        }
        .themeCard()
    }
}
