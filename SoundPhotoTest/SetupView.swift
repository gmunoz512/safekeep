import Photos
import SwiftUI

/// First (and usually only) screen of the app: allow Photos access + how to use it inside Messages.
struct SetupView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var showDebug = false
    @State private var showMatrix = false
    @State private var showQuickPaste = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        permissionCard
                        stepsCard
                        Text("A new Live Photo with the sound is saved next to the original, in the album \"Safekeep\". The original is never changed. Press and hold it in Photos to hear it.")
                            .font(Theme.rounded(.footnote))
                            .foregroundStyle(Theme.sage)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Self.buildInfo)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.sage.opacity(0.45))
                            .textSelection(.enabled)
                            .padding(.top, 12)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Add Sound (debug)") { showDebug = true }
                        Button("Test matrix") { showMatrix = true }
                    } label: {
                        Image(systemName: "ladybug").font(.caption2).foregroundStyle(Theme.sage.opacity(0.35))
                    }
                    .accessibilityLabel("Debug tools")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showDebug) { AddSoundView() }
            .navigationDestination(isPresented: $showMatrix) { ContentView().navigationTitle("Test matrix") }
            .onOpenURL { url in
                // safekeep://paste — opened from the iMessage extension when it can't read the clipboard.
                if url.host == "paste" { showQuickPaste = true }
            }
            .fullScreenCover(isPresented: $showQuickPaste) { QuickPasteView { showQuickPaste = false } }
            .onChange(of: scenePhase) { p in
                if p == .active { status = PHPhotoLibrary.authorizationStatus(for: .readWrite) }
            }
        }
        .tint(Theme.peach)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image("Logo")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            Text("Safekeep")
                .font(Theme.rounded(.largeTitle, .bold))
                .foregroundStyle(Theme.cream)
            Text("Add a voice note to a photo, right inside Messages.")
                .font(Theme.rounded(.title3, .medium))
                .foregroundStyle(Theme.cream.opacity(0.92))
                .multilineTextAlignment(.center)
            Text("You only need to open this app once.")
                .font(Theme.rounded(.subheadline))
                .foregroundStyle(Theme.sage)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How to use it in Messages")
                .font(Theme.rounded(.headline, .semibold))
                .foregroundStyle(Theme.cream)
            step(1, "Save the photo", "In the chat, hold the photo and tap Save.")
            step(2, "Copy the voice note", "Hold the voice message and tap Copy.")
            step(3, "Open Safekeep", "Tap + next to the text box, then Safekeep (it may be under More). Tap Paste, then tap the photo. Done.")
        }
        .themeCard(padding: 20)
    }

    /// Shows which build is installed and whether the iMessage extension is inside it (for troubleshooting the + drawer).
    static var buildInfo: String {
        let info = Bundle.main.infoDictionary ?? [:]
        var lines = ["Safekeep \(info["CFBundleShortVersionString"] ?? "?") (build \(info["CFBundleVersion"] ?? "?"))"]
        let dir = Bundle.main.builtInPlugInsURL
        let appexes = (dir.flatMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) } ?? [])
            .filter { $0.pathExtension == "appex" }
        if appexes.isEmpty { lines.append("iMessage extension: NOT FOUND in this install") }
        for u in appexes {
            let b = Bundle(url: u)
            let ext = b?.infoDictionary?["NSExtension"] as? [String: Any]
            lines.append("iMessage extension: \(u.lastPathComponent) · \(b?.bundleIdentifier ?? "?") · \(ext?["NSExtensionPointIdentifier"] ?? "?") · build \(b?.infoDictionary?["CFBundleVersion"] ?? "?")")
        }
        return lines.joined(separator: "\n")
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(status == .authorized ? Theme.peach : Theme.peach.opacity(0.18)).frame(width: 40, height: 40)
                    Image(systemName: status == .authorized ? "checkmark" : "photo.on.rectangle")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(status == .authorized ? Theme.onPeach : Theme.peach)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Photos access").font(Theme.rounded(.headline, .semibold)).foregroundStyle(Theme.cream)
                    Text(RecentPhotosModel.describe(status)).font(Theme.rounded(.subheadline)).foregroundStyle(Theme.sage)
                }
                Spacer()
            }
            switch status {
            case .authorized:
                Text("All set. You can close this app and use Safekeep in Messages.")
                    .font(Theme.rounded(.subheadline)).foregroundStyle(Theme.cream.opacity(0.9))
            case .notDetermined:
                Button("Allow Photos access") {
                    Task { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
                }
                .buttonStyle(PeachButtonStyle())
                Text("Choose \"Allow Full Access\" so your most recently saved photos show up in Messages.")
                    .font(Theme.rounded(.caption)).foregroundStyle(Theme.sage)
            default:
                Text(status == .limited
                     ? "Only some photos are shared. For newly saved photos to show up, choose Full Access."
                     : "Photos access is off. Turn it on to save sound photos.")
                    .font(Theme.rounded(.subheadline)).foregroundStyle(Theme.cream.opacity(0.9))
                Button("Open Settings → Photos → Full Access") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }
                .buttonStyle(PeachButtonStyle())
            }
        }
        .themeCard(padding: 20)
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.onPeach)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.peach))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.rounded(.subheadline, .semibold)).foregroundStyle(Theme.cream)
                Text(detail).font(Theme.rounded(.subheadline)).foregroundStyle(Theme.sage)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
