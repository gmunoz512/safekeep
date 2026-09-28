import Foundation
import os

/// A saved asset, persisted across launches so it can be found, re-checked, played, and deleted.
struct SavedAsset: Codable, Identifiable, Hashable {
    let code: String
    let title: String
    let localIdentifier: String
    let savedAt: Date
    var id: String { localIdentifier }
}

struct TestError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// Reference box so PhotoKit change blocks can hand back placeholder ids.
final class IDHolder: @unchecked Sendable { var value: String? }

/// Process memory readings (the iMessage extension has a much lower memory limit than the app).
enum Mem {
    private static var sampledPeak: UInt64 = 0

    static func footprint() -> (current: UInt64, peak: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, 0) }
        return (info.phys_footprint, UInt64(max(0, info.ledger_phys_footprint_peak)))
    }

    static func line(_ label: String = "") -> String {
        let f = footprint()
        sampledPeak = max(sampledPeak, f.current)
        let avail = os_proc_available_memory()
        func mb(_ v: UInt64) -> String { String(format: "%.1f MB", Double(v) / 1_048_576) }
        return "memory\(label.isEmpty ? "" : " [\(label)]"): footprint \(mb(f.current)), peak \(mb(max(f.peak, sampledPeak))), available-to-limit \(avail > 0 ? mb(UInt64(avail)) : "n/a")"
    }
}
