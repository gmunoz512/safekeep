import Photos
import SwiftUI

/// First (and usually only) screen of the app: allow Photos access + how to use it inside Messages.
struct SetupView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var showDebug = false
    @State private var showMatrix = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add a voice note to a photo, right inside Messages.")
                            .font(.title3.weight(.semibold))
                        Text("You only need to open this app once.").foregroundStyle(.secondary)
                    }

                    permissionCard

                    VStack(alignment: .leading, spacing: 14) {
                        Text("How to use it in Messages").font(.headline)
                        step(1, "square.and.arrow.down", "Save the photo", "In the chat, hold the photo and tap Save.")
                        step(2, "doc.on.doc", "Copy the voice note", "Hold the voice message and tap Copy.")
                        step(3, "plus.circle", "Open Safekeep", "Tap + next to the text box, then Safekeep (it may be under More). Tap Paste, then tap the photo. Done.")
                    }

                    Text("A new Live Photo with the sound is saved next to the original, in the album \"Safekeep\". The original is never changed. Press and hold it in Photos to hear it.")
                        .font(.footnote).foregroundStyle(.secondary)

                    Text(Self.buildInfo)
                        .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle("Safekeep")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Add Sound (debug)") { showDebug = true }
                        Button("Test matrix") { showMatrix = true }
                    } label: {
                        Image(systemName: "ladybug").font(.footnote).foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel("Debug tools")
                }
            }
            .navigationDestination(isPresented: $showDebug) { AddSoundView() }
            .navigationDestination(isPresented: $showMatrix) { ContentView().navigationTitle("Test matrix") }
            .onChange(of: scenePhase) { p in
                if p == .active { status = PHPhotoLibrary.authorizationStatus(for: .readWrite) }
            }
        }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: status == .authorized ? "checkmark.circle.fill" : "photo.on.rectangle")
                    .font(.title2)
                    .foregroundStyle(status == .authorized ? Color.green : Color.orange)
                VStack(alignment: .leading) {
                    Text("Photos access").font(.headline)
                    Text(RecentPhotosModel.describe(status)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            switch status {
            case .authorized:
                Text("All set. You can close this app and use Safekeep in Messages.").font(.subheadline)
            case .notDetermined:
                Button {
                    Task { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
                } label: {
                    Text("Allow Photos access").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                Text("Choose \"Allow Full Access\" so your most recently saved photos show up in Messages.")
                    .font(.caption).foregroundStyle(.secondary)
            default:
                Text(status == .limited
                     ? "Only some photos are shared. For newly saved photos to show up, choose Full Access."
                     : "Photos access is off. Turn it on to save sound photos.")
                    .font(.subheadline)
                Button {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                } label: {
                    Text("Open Settings → Photos → Full Access").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func step(_ n: Int, _ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: icon).foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(n). \(title)").font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
