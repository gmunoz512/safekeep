import SwiftUI

struct ContentView: View {
    @StateObject private var runner = TestRunner()

    var body: some View {
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

            HStack {
                Button("Copy log") { UIPasteboard.general.string = runner.log }
                Spacer()
                Button("Clear") { runner.log = "" }
            }
            .font(.footnote)

            ScrollView {
                Text(runner.log)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }
}
