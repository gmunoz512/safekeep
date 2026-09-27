import SwiftUI

struct ContentView: View {
    @StateObject private var runner = TestRunner()
    @State private var selected: SavedAsset?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sound Photo PhotoKit Test").font(.headline)

                Button(action: { runner.runAll() }) {
                    Text(runner.isRunning ? "Working…" : "Run All Tests (A–E)")
                        .frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(runner.isRunning)

                Button(action: { runner.runBaseline() }) {
                    Text("Create Sound Photo (baseline only)").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(runner.isRunning)

                Text("Saved Results").font(.headline).padding(.top, 6)
                if runner.saved.isEmpty {
                    Text("Nothing saved yet. Run the tests, or tap 'Find earlier test photos'.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(runner.saved) { item in
                        Button { selected = item } label: {
                            HStack {
                                Text(item.code).font(.headline.monospaced()).frame(width: 28)
                                VStack(alignment: .leading) {
                                    Text(item.title).font(.subheadline).lineLimit(1)
                                    Text(item.savedAt.formatted(date: .abbreviated, time: .standard))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                HStack {
                    Button("Re-check saved") { runner.recheckSaved() }
                    Spacer()
                    Button("Find earlier test photos") { runner.findEarlier() }
                        .disabled(runner.isRunning)
                }
                .font(.footnote)

                HStack {
                    Button("Open Photos app") { openPhotos() }
                    Spacer()
                    Button("Delete test photos", role: .destructive) { runner.deleteSaved() }
                        .disabled(runner.saved.isEmpty)
                }
                .font(.footnote)

                Divider()

                HStack {
                    Button("Copy log") { UIPasteboard.general.string = runner.log }
                    Spacer()
                    Button("Clear") { runner.log = "" }
                }
                .font(.footnote)

                Text(runner.log)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding()
        }
        .sheet(item: $selected) { LivePhotoDetail(item: $0) }
    }
}
