import Photos
import SwiftUI

/// Main screen (German's mockup): gear, paste card, icon + title, Photos access, how-to carousel.
struct SetupView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var showDebug = false
    @EnvironmentObject private var router: AppRouter
    @State private var clipAudioTypes: [String] = []
    @State private var page = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 20) {
                        gearRow
                        HeroCard(title: "Paste voice note",
                                 subtitle: clipAudioTypes.isEmpty
                                    ? "Copy a voice note in Messages, then tap here"
                                    : "A voice note is on your clipboard. Tap to add it to a photo.") {
                            router.openQuickPaste(reason: "hero card (clipboard audio: \(clipAudioTypes.isEmpty ? "none" : clipAudioTypes.joined(separator: ", ")))")
                        }
                        header
                        permissionCard
                        howToCarousel
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showDebug) { AddSoundView() }
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

    private var gearRow: some View {
        HStack {
            Spacer()
            Button { showDebug = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.primaryText.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.cardTeal.opacity(0.85)))
                    .overlay(Circle().stroke(Theme.secondaryTeal, lineWidth: 1))
            }
            .accessibilityLabel("Settings and debug tools")
        }
        .padding(.top, 8)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 124, height: 124)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.secondaryTeal.opacity(0.6), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
                .padding(.top, 6)
                .padding(.bottom, 4)
            Text("Safekeep")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.primaryText)
            Text("Add a voice note to a photo,\nremember it forever.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.primaryText.opacity(0.92))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
            Text("You only need to open this app once.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: How-to carousel

    private struct HowToPage {
        let title: String
        let detail: String
        let art: HowToArt.Kind
    }

    private let pages: [HowToPage] = [
        .init(title: "Save the photo", detail: "In the chat, hold the photo and tap Save.", art: .savePhoto),
        .init(title: "Copy the voice note", detail: "Hold the voice note and tap Copy.", art: .copyVoice),
        .init(title: "Open Safekeep", detail: "Tap +, then Safekeep, then Add copied voice note.", art: .openSafekeep),
        .init(title: "Tap the photo", detail: "Tap the photo. Done.", art: .tapPhoto),
        .init(title: "Other way", detail: "Save to Voice Memos, then Share → Safekeep.", art: .voiceMemos),
    ]

    private var howToCarousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to use it in Messages")
                .font(.system(.title3).weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                    HStack(alignment: .center, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Theme.deepPetrol)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Theme.softSand))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.title).font(.system(.headline).weight(.semibold)).foregroundStyle(Theme.primaryText)
                                Text(p.detail).font(.system(.subheadline)).foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 6)
                        }
                        Spacer(minLength: 0)
                        HowToArt(kind: p.art)
                            .frame(width: 128, height: 128)
                    }
                    .padding(.horizontal, 2)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 140)
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Theme.softSand : Theme.secondaryTeal)
                        .frame(width: 8, height: 8)
                        .onTapGesture { withAnimation { page = i } }
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Step \(page + 1) of \(pages.count)")
        }
        .themeCard(padding: 20)
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
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.deepPetrol)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Theme.softSand))
                    .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Photos access").font(.system(.title3).weight(.semibold)).foregroundStyle(Theme.primaryText)
                    Text(status == .authorized ? "Full Access" : RecentPhotosModel.describe(status))
                        .font(.system(.subheadline)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            Rectangle().fill(Theme.secondaryTeal).frame(height: 1)
            switch status {
            case .authorized:
                Text("All set. You can close this app and use Safekeep in Messages.")
                    .font(.system(.subheadline)).foregroundStyle(Theme.primaryText.opacity(0.9))
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
                    .font(.system(.subheadline)).foregroundStyle(Theme.primaryText.opacity(0.9))
                Button("Open Settings → Photos → Full Access") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }
                .buttonStyle(PeachButtonStyle())
            }
        }
        .themeCard(padding: 20)
    }
}

/// Small SwiftUI illustrations for the how-to carousel.
struct HowToArt: View {
    enum Kind { case savePhoto, copyVoice, openSafekeep, tapPhoto, voiceMemos }
    let kind: Kind

    var body: some View {
        switch kind {
        case .savePhoto:
            ZStack(alignment: .bottomTrailing) {
                photoTile.frame(width: 104, height: 118).offset(x: -12, y: -6)
                menu([("square.and.arrow.down", "Save", true), ("doc.on.doc", "Copy", false)])
                    .offset(x: 4, y: 4)
            }
        case .copyVoice:
            ZStack(alignment: .bottomTrailing) {
                voiceBubble.offset(x: -16, y: -34)
                menu([("arrowshape.turn.up.left", "Reply", false), ("doc.on.doc", "Copy", true)])
                    .offset(x: 4, y: 4)
            }
        case .openSafekeep:
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.secondaryTeal))
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.secondaryText)
                    Image("Logo").resizable().frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                Text("Add copied voice note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.deepPetrol)
                    .padding(.vertical, 7).padding(.horizontal, 10)
                    .background(Capsule().fill(Theme.softSand))
            }
        case .tapPhoto:
            ZStack {
                LazyVGrid(columns: [GridItem(.fixed(52), spacing: 6), GridItem(.fixed(52), spacing: 6)], spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        photoTile
                            .frame(width: 52, height: 52)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(i == 1 ? Theme.softSand : .clear, lineWidth: 3))
                            .overlay(alignment: .topTrailing) {
                                if i == 1 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(Theme.deepPetrol, Theme.softSand)
                                        .offset(x: 5, y: -5)
                                }
                            }
                            .opacity(i == 1 ? 1 : 0.6)
                    }
                }
            }
        case .voiceMemos:
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.mutedGold)
                    Text("Voice Memos").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.primaryText)
                }
                .padding(.vertical, 8).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.deepPetrol.opacity(0.6)))
                Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                HStack(spacing: 6) {
                    Image("Logo").resizable().frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("Safekeep").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.deepPetrol)
                }
                .padding(.vertical, 5).padding(.horizontal, 9)
                .background(Capsule().fill(Theme.softSand))
            }
        }
    }

    /// A little "photo": sunset sky over teal hills.
    private var photoTile: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(hex: 0xF2C48D), Color(hex: 0xE9A77A), Color(hex: 0x5E8F95)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(hex: 0xFBE3B8)).frame(width: 16, height: 16).offset(x: 14, y: -44)
            Ellipse().fill(Color(hex: 0x2F6E6F)).frame(height: 44).offset(x: -18, y: 18)
            Ellipse().fill(Color(hex: 0x1F5557)).frame(height: 40).offset(x: 24, y: 22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.warmIvory.opacity(0.35), lineWidth: 1))
    }

    private var voiceBubble: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
            Image(systemName: "waveform").font(.system(size: 18, weight: .semibold))
            Text("0:12").font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(Theme.primaryText)
        .padding(.vertical, 9).padding(.horizontal, 12)
        .background(Capsule().fill(Theme.secondaryTeal))
    }

    private func menu(_ items: [(String, String, Bool)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                HStack(spacing: 7) {
                    Image(systemName: it.0).font(.system(size: 10, weight: .semibold))
                    Text(it.1).font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(it.2 ? Theme.deepPetrol : Theme.primaryText)
                .padding(.vertical, 7).padding(.horizontal, 10)
                .background(it.2 ? Theme.softSand : Color.clear)
                if i < items.count - 1 { Rectangle().fill(Theme.secondaryTeal.opacity(0.6)).frame(height: 0.5) }
            }
        }
        .frame(width: 84)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.deepPetrol.opacity(0.92)))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.secondaryTeal, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}
