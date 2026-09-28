import Photos
import SwiftUI

/// Debug / full-control screen (the everyday flow lives in the iMessage extension).
struct AddSoundView: View {
    @StateObject private var m = AddSoundModel()
    @StateObject private var recents = RecentPhotosModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPhotoPicker = false
    @State private var showDocPicker = false
    @State private var viewing: SavedAsset?
    @State private var started = false
    @State private var showMatrix = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                QuickFlowView(m: m, recents: recents)
                Divider()
                Text("More options").font(.headline)
                secondaryButtons
                photoSection
                soundSection
                saveSection
                Divider()
                longSection
                Divider()
                LogPanel(m: m)
            }
            .padding()
        }
        .background(Theme.background)
        .tint(Theme.peach)
        .navigationTitle("Add Sound (debug)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Test matrix") { showMatrix = true }
                    Button("Run long-audio check") { Task { await m.longAudioCheck() } }
                    Button("Reload recent photos") { Task { await recents.load(reason: "manual") } }
                    Button("Check clipboard") { m.checkClipboard(trigger: "manual") }
                    Button("Copy log") { UIPasteboard.general.string = m.log }
                    Button("Clear log", role: .destructive) { m.clearLog() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .navigationDestination(isPresented: $showMatrix) { ContentView().navigationTitle("Test matrix") }
        .sheet(item: $viewing) { LivePhotoDetail(item: $0) }
        .sheet(isPresented: Binding(get: { m.confirmAsset != nil }, set: { if !$0 { m.confirmAsset = nil } })) {
            if let a = m.confirmAsset {
                ConfirmSaveSheet(asset: a, duration: m.audioDuration, manager: recents.caching,
                                 onSave: { Task { await m.saveWith(a) } },
                                 onCancel: { m.confirmAsset = nil })
                    .presentationDetents([.height(260)])
            }
        }
        .onChange(of: m.result) { r in if let r { viewing = r } }
        .onChange(of: scenePhase) { p in if p == .active { m.checkClipboard(trigger: "scenePhase active") } }
        .task {
            guard !started else { return }
            started = true
            recents.log = { [weak model = m] s in model?.say(s) }
            m.say("=== Safekeep app (debug screen) — build \(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?") — \(Date()) ===")
            m.checkClipboard(trigger: "launch")
            await recents.load(reason: "launch")
        }
    }

    private var secondaryButtons: some View {
        HStack {
            Button { showPhotoPicker = true } label: {
                Label("Choose from library", systemImage: "photo").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(m.busy)
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker(isPresented: $showPhotoPicker) { id in
                    guard let id, let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
                        Task { await m.picked(id) }; return
                    }
                    m.tapPhoto(a, source: "PHPicker")
                }
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current photo").font(.subheadline.bold())
            if let t = m.thumbnail {
                HStack(alignment: .top) {
                    Image(uiImage: t).resizable().scaledToFit().frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(m.photoInfo).font(.caption)
                        if let p = m.downloadProgress {
                            ProgressView(value: p) { Text("Downloading from iCloud…").font(.caption2) }
                        } else if m.imageData != nil {
                            Text("Full-resolution data loaded").font(.caption2).foregroundStyle(.green)
                        } else if m.busy {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sound").font(.subheadline.bold())
            HStack {
                Button { showDocPicker = true } label: {
                    Label("Choose audio file", systemImage: "folder").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .sheet(isPresented: $showDocPicker) {
                    AudioDocPicker(isPresented: $showDocPicker) { url in Task { await m.pickedFile(url) } }
                }
                Button { Task { await m.toggleRecord() } } label: {
                    Label(m.isRecording ? "Stop" : "Record", systemImage: m.isRecording ? "stop.circle.fill" : "mic")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(m.isRecording ? .red : .accentColor)
            }
            if m.audioURL != nil {
                HStack {
                    Text(m.audioInfo).font(.caption)
                    Spacer()
                    Button { m.togglePlay() } label: {
                        Label(m.isPlaying ? "Stop" : "Play", systemImage: m.isPlaying ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual save").font(.subheadline.bold())
            Button {
                Task { if let r = await m.saveSoundCopy() { viewing = r } }
            } label: {
                Text(m.busy ? "Working…" : "Save sound copy").frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(m.busy || m.imageData == nil || m.audioURL == nil || m.isRecording)
            Text("Creates a NEW Live Photo next to the original (original is never changed) and adds it to the \"Safekeep\" album.")
                .font(.caption2).foregroundStyle(.secondary)
            if let r = m.result {
                HStack {
                    Button("View result") { viewing = r }
                    Spacer()
                    Button("Open Photos") { openPhotos() }
                }
                .font(.subheadline)
            }
        }
    }

    private var longSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Long-audio check").font(.headline)
            Button { Task { await m.longAudioCheck() } } label: {
                Text("Run long-audio check (30 / 60 / 120 / 300 s)").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(m.busy)
            ForEach(m.longResults) { r in
                Button { viewing = r } label: {
                    HStack { Text(r.title); Spacer(); Image(systemName: "chevron.right") }
                }
            }
            if !m.longResults.isEmpty {
                Button("Delete long-audio test photos", role: .destructive) { Task { await m.deleteLongResults() } }
                    .font(.footnote)
            }
        }
    }
}
