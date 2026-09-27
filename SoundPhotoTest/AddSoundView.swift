import SwiftUI

struct AddSoundView: View {
    @StateObject private var m = AddSoundModel()
    @State private var showPhotoPicker = false
    @State private var showDocPicker = false
    @State private var viewing: SavedAsset?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    photoSection
                    Divider()
                    soundSection
                    Divider()
                    saveSection
                    Divider()
                    longSection
                    Divider()
                    logSection
                }
                .padding()
            }
            .navigationTitle("Add Sound to Photo")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink("Test matrix") { ContentView().navigationTitle("Test matrix") }
                }
            }
            .sheet(item: $viewing) { LivePhotoDetail(item: $0) }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1. Photo").font(.headline)
            Button { showPhotoPicker = true } label: {
                Label(m.photoAsset == nil ? "Choose photo" : "Choose another photo", systemImage: "photo")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(m.busy)
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker(isPresented: $showPhotoPicker) { id in Task { await m.picked(id) } }
            }
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
            Text("2. Sound").font(.headline)
            Button { Task { await m.pasteAudio() } } label: {
                Label("Paste voice message", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
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
            Text("3. Save").font(.headline)
            Button {
                Task { if let r = await m.saveSoundCopy() { viewing = r } }
            } label: {
                Text(m.busy ? "Working…" : "Save sound copy").frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(m.busy || m.imageData == nil || m.audioURL == nil || m.isRecording)
            Text("Creates a NEW Live Photo next to the original (original is never changed) and adds it to the \"Sound Photos\" album.")
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

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Copy log") { UIPasteboard.general.string = m.log }
                Spacer()
                Button("Clear") { m.log = "" }
            }
            .font(.footnote)
            Text(m.log)
                .font(.system(.caption2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
