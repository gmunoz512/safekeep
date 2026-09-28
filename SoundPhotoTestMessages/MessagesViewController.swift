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
                                     requestExpand: { [weak self] in self?.expandIfNeeded() })
        let h = UIHostingController(rootView: root)
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
    @State private var showLog = false

    var body: some View {
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
                    QuickFlowView(m: m, recents: recents, columns: 4, onNeedRoom: requestExpand)
                    if showLog { LogPanel(m: m) }
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

    private var header: some View {
        HStack {
            Text("Safekeep").font(.headline)
            Spacer()
            Menu {
                Button(showLog ? "Hide log" : "Show log") { showLog.toggle(); if showLog { requestExpand() } }
                Button("Copy log") { UIPasteboard.general.string = m.log }
                Button("Reload photos") { Task { await recents.load(reason: "manual") } }
                Button("Check clipboard") { m.checkClipboard(trigger: "manual") }
                Button("Clear log", role: .destructive) { m.clearLog() }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recents.status == .notDetermined ? "Safekeep needs access to your photos." : "Open Safekeep once to allow Photos access.")
                .font(.subheadline.weight(.semibold))
            if recents.status == .notDetermined {
                Button("Allow Photos access") {
                    Task { await recents.requestAccess(); await recents.load(reason: "after permission request") }
                }
                .buttonStyle(.borderedProminent)
                Text("If nothing happens, open the Safekeep app once and allow Full Access.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Photos access is off. Open the Safekeep app (or Settings > Privacy & Security > Photos) and choose Full Access.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.12)))
    }
}
