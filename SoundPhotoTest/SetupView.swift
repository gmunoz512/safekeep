import Photos
import SwiftUI

/// Main screen (matches German's mockup): paste hero card, other ways, how-to, Photos access.
struct SetupView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var showDebug = false
    @State private var showDocPicker = false
    @State private var showVoiceMemosHelp = false
    @EnvironmentObject private var router: AppRouter
    @State private var clipAudioTypes: [String] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 22) {
                        header
                        HeroCard(title: "Paste voice note",
                                 subtitle: clipAudioTypes.isEmpty
                                    ? "Copy a voice note in Messages, then tap here"
                                    : "A voice note is on your clipboard. Tap to add it to a photo.") {
                            router.openQuickPaste(reason: "hero card (clipboard audio: \(clipAudioTypes.isEmpty ? "none" : clipAudioTypes.joined(separator: ", ")))")
                        }
                        otherWaysCard
                        howToCard
                        permissionCard
                        Text("A new Live Photo with the sound is saved next to the original, in the album \"Safekeep\". The original is never changed. Press and hold it in Photos to hear it.")
                            .font(.system(.footnote))
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showDebug = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Theme.cardTeal.opacity(0.7)))
                            .overlay(Circle().stroke(Theme.secondaryTeal, lineWidth: 1))
                    }
                    .accessibilityLabel("Settings and debug tools")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showDebug) { AddSoundView() }
            .sheet(isPresented: $showDocPicker) {
                AudioDocPicker(isPresented: $showDocPicker) { url in router.openQuickPaste(file: url) }
            }
            .sheet(isPresented: $showVoiceMemosHelp) { voiceMemosHelp }
            .onChange(of: scenePhase) { p in
                if p == .active { status = PHPhotoLibrary.authorizationStatus(for: .readWrite); refreshClipboard() }
            }
            .onAppear { refreshClipboard() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refreshClipboard() }
            .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in refreshClipboard() }
        }
        .tint(Theme.softSand)
        .preferredColorScheme(.dark)
    }

    /// Metadata-only check (no paste prompt): does the clipboard hold audio (e.g. a copied voice note)?
    private func refreshClipboard() {
        let types = UIPasteboard.general.types.filter(AddSoundModel.isAudioType)
        if types != clipAudioTypes { clipAudioTypes = types }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            Text("Safekeep")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Theme.primaryText)
            Text("Add a voice note to a photo, remember it forever.")
                .font(.system(.title3))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Text("You only need to open this app once.")
                .font(.system(.footnote))
                .foregroundStyle(Theme.secondaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    private var otherWaysCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Or add it another way").font(.system(.subheadline)).foregroundStyle(Theme.secondaryText)
            HStack(spacing: 12) {
                Button { showDocPicker = true } label: { PillLabel(title: "Choose audio file", icon: "folder") }
                    .buttonStyle(PillButtonStyle())
                Button { showVoiceMemosHelp = true } label: { PillLabel(title: "From Voice Memos", icon: "waveform") }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .themeCard(padding: 16)
    }

    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to use it in Messages").font(.system(.title3).weight(.semibold)).foregroundStyle(Theme.primaryText)
            Text("First save the photo from the chat: hold it → Save.")
                .font(.system(.subheadline)).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            routeTitle("Copy")
            StepList(steps: [
                ("Hold the voice note → Copy", nil),
                ("Tap + → Safekeep → Add copied voice note", nil),
                ("Tap the photo. Done.", nil),
            ])
            routeTitle("Voice Memos")
            StepList(steps: [
                ("Hold the voice note → Save to Voice Memos", nil),
                ("In Voice Memos: open it → ••• → Share → Safekeep", nil),
                ("Tap the photo. Done.", nil),
            ])
        }
        .themeCard(padding: 20)
    }

    private func routeTitle(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.system(.caption).weight(.semibold))
            .tracking(1)
            .foregroundStyle(Theme.softSand)
            .padding(.top, 2)
    }

    private var voiceMemosHelp: some View {
        ZStack {
            Theme.background
            VStack(alignment: .leading, spacing: 20) {
                Text("Add from Voice Memos").font(.system(.title2).weight(.semibold)).foregroundStyle(Theme.primaryText)
                StepList(steps: [
                    ("In Messages, hold the voice note", "Tap Save to Voice Memos."),
                    ("Open Voice Memos", "Tap the recording, then ••• → Share."),
                    ("Choose Safekeep", "It may be under More the first time."),
                    ("Tap the photo", "The Live Photo with the sound is saved. Done."),
                ])
                Spacer()
                Button("Got it") { showVoiceMemosHelp = false }.buttonStyle(PeachButtonStyle())
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    /// Shows which build is installed and which extensions are inside it (debug screen).
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
            HStack(spacing: 16) {
                Image(systemName: status == .authorized ? "checkmark" : "photo.on.rectangle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.deepPetrol)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(status == .authorized ? Theme.secondaryText.opacity(0.9) : Theme.mutedGold))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Photos access").font(.system(.headline).weight(.semibold)).foregroundStyle(Theme.primaryText)
                    Text(status == .authorized ? "Full Access" : RecentPhotosModel.describe(status))
                        .font(.system(.subheadline)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            Rectangle().fill(Theme.secondaryTeal).frame(height: 1)
            switch status {
            case .authorized:
                Text("All set. You can close this app and use Safekeep in Messages.")
                    .font(.system(.subheadline)).foregroundStyle(Theme.secondaryText)
            case .notDetermined:
                Button("Allow Photos access") {
                    Task { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
                }
                .buttonStyle(PeachButtonStyle())
                Text("Choose \"Allow Full Access\" so your most recently saved photos show up.")
                    .font(.system(.caption)).foregroundStyle(Theme.secondaryText)
            default:
                Text(status == .limited
                     ? "Only some photos are shared. For newly saved photos to show up, choose Full Access."
                     : "Photos access is off. Turn it on to save sound photos.")
                    .font(.system(.subheadline)).foregroundStyle(Theme.secondaryText)
                Button("Open Settings → Photos → Full Access") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }
                .buttonStyle(PeachButtonStyle())
            }
        }
        .themeCard(padding: 20)
    }
}
