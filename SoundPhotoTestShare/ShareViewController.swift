import Photos
import SwiftUI
import UIKit

/// Share sheet "Safekeep": audio file in → recent photos grid → tap photo = saved.
final class ShareViewController: UIViewController {
    private let model = AddSoundModel()
    private let recents = RecentPhotosModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.logPrefix = "[share] "
        model.movieMaxSide = 1440
        model.confirmBeforeSave = false
        recents.log = { [weak model = self.model] s in model?.say(s) }
        model.say("=== Safekeep share extension — build \(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?") — \(Date()) ===")
        model.say(Mem.line("viewDidLoad"))

        overrideUserInterfaceStyle = .dark
        view.backgroundColor = Theme.uiBackground
        let root = ShareRootView(m: model, recents: recents,
                                 done: { [weak self] in self?.finish() },
                                 cancel: { [weak self] in self?.cancel() })
        let h = UIHostingController(rootView: root)
        h.overrideUserInterfaceStyle = .dark
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

        Task { @MainActor in
            await loadSharedAudio()
            if recents.status == .notDetermined { await recents.requestAccess() }
            await recents.load(reason: "share sheet")
        }
    }

    private func loadSharedAudio() async {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        var providers: [NSItemProvider] = []
        for (i, item) in items.enumerated() {
            let atts = item.attachments ?? []
            model.say("input item\(i): \(atts.count) attachment(s), title=\(item.attributedTitle?.string ?? "-"), text=\(item.attributedContentText?.string.prefix(80) ?? "-")")
            for (j, a) in atts.enumerated() { model.say("  attachment\(j): \(a.registeredTypeIdentifiers) name=\(a.suggestedName ?? "-")") }
            providers += atts
        }
        guard !providers.isEmpty else {
            model.setPasteStatus("The share sheet didn't hand over any file.", error: true); return
        }
        model.setPasteStatus("Loading the shared audio…")
        if await model.loadFromProviders(providers, method: "share sheet") { return }
        let types = providers.flatMap(\.registeredTypeIdentifiers)
        model.setPasteStatus("Shared item has no usable audio (\(types.joined(separator: ", "))) — see log", error: true)
    }

    private func finish() {
        model.say("share: done")
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        model.say("share: cancelled")
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        model.say("MEMORY WARNING — " + Mem.line())
        recents.caching.stopCachingImagesForAllAssets()
    }
}

struct ShareRootView: View {
    @ObservedObject var m: AddSoundModel
    @ObservedObject var recents: RecentPhotosModel
    let done: () -> Void
    let cancel: () -> Void
    @State private var showLog = false

    var body: some View {
        ZStack {
            Theme.background
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header.id("top")
                        if let r = m.result {
                            LivePhotoResultCard(item: r, log: { m.say($0) }) { done() }
                        } else {
                            QuickFlowView(m: m, recents: recents, columns: 3, showPasteControls: false)
                        }
                        if showLog { LogPanel(m: m) }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .onChange(of: m.result) { r in
                    if r != nil { withAnimation { proxy.scrollTo("top", anchor: .top) } }
                }
            }
        }
        .tint(Theme.peach)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button("Cancel") { cancel() }.buttonStyle(SoftButtonStyle())
            Spacer()
            Image("Logo").resizable().frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text("Safekeep").font(Theme.rounded(.headline, .bold)).foregroundStyle(Theme.cream)
            Spacer()
            Button(showLog ? "Hide log" : "Log") { showLog.toggle() }.buttonStyle(SoftButtonStyle())
        }
    }
}
