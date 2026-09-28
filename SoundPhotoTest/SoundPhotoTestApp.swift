import SwiftUI

/// Routes safekeep:// links (from the iMessage extension) to the quick paste screen, on cold and warm launch.
@MainActor
final class AppRouter: ObservableObject {
    @Published var showQuickPaste = false
    @Published var lastLink: String = UserDefaults.standard.string(forKey: "lastLink") ?? "none yet"

    func handle(_ url: URL, via: String) {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        lastLink = "\(url.absoluteString) via \(via) at \(df.string(from: Date()))"
        UserDefaults.standard.set(lastLink, forKey: "lastLink")
        print("[router] " + lastLink)
        guard url.scheme?.lowercased() == "safekeep" else { return }
        if showQuickPaste { return }
        // Present on the next runloop turns so it also works while the app is still finishing a cold launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.showQuickPaste = true }
    }

    /// Audio file picked on the main screen; the quick paste screen loads it instead of pasting.
    @Published var pendingFile: URL?

    func openQuickPaste(reason: String) {
        print("[router] quick paste opened: \(reason)")
        showQuickPaste = true
    }

    func openQuickPaste(file: URL) {
        pendingFile = file
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.showQuickPaste = true }
    }
}

@main
struct SoundPhotoTestApp: App {
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            SetupView()
                .environmentObject(router)
                .onOpenURL { url in router.handle(url, via: "onOpenURL") }
                .fullScreenCover(isPresented: $router.showQuickPaste) {
                    QuickPasteView { router.showQuickPaste = false }
                        .environmentObject(router)
                }
        }
    }
}
