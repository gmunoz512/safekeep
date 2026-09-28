import Photos
import SwiftUI

/// First (and usually only) screen of the app: allow Photos access + how to use it inside Messages.
struct SetupView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var showDebug = false
    @State private var showMatrix = false
    @EnvironmentObject private var router: AppRouter
    @State private var clipAudioTypes: [String] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !clipAudioTypes.isEmpty { pasteCard }
                        header
                        permissionCard
                        stepsCard
                        Text("A new Live Photo with the sound is saved next to the original, in the album \"Safekeep\". The original is never changed. Press and hold it in Photos to hear it.")
                            .font(Theme.rounded(.footnote))
                            .foregroundStyle(Theme.sage)
                            .fixedSize(horizontal: false, vertical: true)
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
            .onChange(of: scenePhase) { p in
                if p == .active { status = PHPhotoLibrary.authorizationStatus(for: .readWrite); refreshClipboard() }
            }
            .onAppear { refreshClipboard() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refreshClipboard() }
            .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in refreshClipboard() }
        }
        .tint(Theme.peach)
        .preferredColorScheme(.dark)
    }

    /// Metadata-only check (no paste prompt): does the clipboard hold audio (e.g. a copied voice note)?
    private func refreshClipboard() {
        let types = UIPasteboard.general.types.filter(AddSoundModel.isAudioType)
        if types != clipAudioTypes { clipAudioTypes = types }
    }

    private var pasteCard: some View {
        Button { router.openQuickPaste(reason: "setup paste card (\(clipAudioTypes.joined(separator: ", ")))") } label: {
            HStack(spacing: 14) {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.peach)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.onPeach))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Paste voice note").font(Theme.rounded(.title3, .bold))
                    Text("A voice note is on your clipboard. Tap to add it to a photo.")
                        .font(Theme.rounded(.subheadline))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Theme.onPeach)
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.peach))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
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
            Text("Add a voice note to a photo, remember it forever.")
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
            tip
            optionCard("Option A — Copy", icon: "doc.on.doc", steps: [
                ("In Messages, hold the voice note → Copy.", nil),
                ("Tap + → Safekeep → Add copied voice note.", nil),
                ("Tap the photo. Done.", nil),
            ])
            optionCard("Option B — Voice Memos", icon: "waveform", steps: [
                ("Hold the voice note → Save to Voice Memos.", nil),
                ("In Voice Memos, open it → ••• → Share → Safekeep.", nil),
                ("Tap the photo. Done.", nil),
            ])
        }
    }

    private var tip: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "photo.badge.arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.peach)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.peach.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text("First, save the photo").font(Theme.rounded(.subheadline, .semibold)).foregroundStyle(Theme.cream)
                Text("Save the photo from the chat first: hold it → Save.")
                    .font(Theme.rounded(.subheadline)).foregroundStyle(Theme.sage)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
    }

    private func optionCard(_ title: String, icon: String, steps: [(String, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(Theme.rounded(.headline, .semibold))
                .foregroundStyle(Theme.cream)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, st in
                step(i + 1, st.0, st.1)
            }
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
        if appexes.isEmpty { lines.append("Extensions: NOT FOUND in this install") }
        for u in appexes {
            let b = Bundle(url: u)
            let ext = b?.infoDictionary?["NSExtension"] as? [String: Any]
            let kind = u.lastPathComponent.contains("Share") ? "Share extension" : "iMessage extension"
            lines.append("\(kind): \(u.lastPathComponent) · \(b?.bundleIdentifier ?? "?") · \(ext?["NSExtensionPointIdentifier"] ?? "?") · build \(b?.infoDictionary?["CFBundleVersion"] ?? "?")")
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

    private func step(_ n: Int, _ title: String, _ detail: String?) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text("\(n)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.onPeach)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.peach))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.rounded(.subheadline, .medium)).foregroundStyle(Theme.cream)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(Theme.rounded(.subheadline)).foregroundStyle(Theme.sage)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
