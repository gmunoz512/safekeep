import Foundation
import Photos
import UIKit

/// One experiment = one asset saved to Photos.
struct TestVariant {
    let code: String
    let title: String
    let expectation: String
    var maxDuration: Double? = nil
    var includeStillImageTime = true
    var mismatchIdentifiers = false
    var heicStill = false
}


struct VariantResult {
    let variant: TestVariant
    var saved = false
    var isLive = false
    var assetID = "-"
    var resources = "-"
    var error: String?
}

@MainActor
final class TestRunner: ObservableObject {
    @Published var log = ""
    @Published var isRunning = false
    @Published var saved: [SavedAsset] = []

    private static let savedKey = "savedAssets.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.savedKey),
           let list = try? JSONDecoder().decode([SavedAsset].self, from: data) {
            saved = list
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.savedKey)
        }
    }

    private func remember(_ a: SavedAsset) {
        saved.removeAll { $0.localIdentifier == a.localIdentifier }
        saved.append(a)
        persist()
    }

    static let albumName = "Sound Photo Tests"

    static let variants: [TestVariant] = [
        TestVariant(code: "A", title: "Baseline: JPEG + 8.8 s voice video",
                    expectation: "Main test. LIVE, still image, full voice."),
        TestVariant(code: "B", title: "3 s clip (normal Live Photo length)",
                    expectation: "Tells us whether length matters.", maxDuration: 3.0),
        TestVariant(code: "C", title: "No still-image-time marker",
                    expectation: "Tells us whether that marker is required.", includeStillImageTime: false),
        TestVariant(code: "D", title: "HEIC still + 8.8 s voice video",
                    expectation: "Same as A but with the iPhone camera's photo format.", heicStill: true),
        TestVariant(code: "E", title: "CONTROL: mismatched pairing IDs",
                    expectation: "Should be REJECTED or NOT live. If it goes live, IDs don't matter.",
                    mismatchIdentifiers: true),
    ]

    func say(_ s: String) { log += s + "\n"; print(s) }

    func runAll() { start(Self.variants) }
    func runBaseline() { start([Self.variants[0]]) }

    private func start(_ list: [TestVariant]) {
        isRunning = true
        Task {
            defer { isRunning = false }
            await run(list)
        }
    }

    private func run(_ list: [TestVariant]) async {
        say("=== Sound Photo PhotoKit test — \(Date()) ===")
        say("iOS \(UIDevice.current.systemVersion), \(UIDevice.current.model)")
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        say("Photos authorization: \(Self.name(status))")
        guard status == .authorized || status == .limited else {
            say("STOP: Photos access not granted. Allow it in Settings > Privacy > Photos."); return
        }
        if status == .limited { say("NOTE: limited access. Choose Full Access for reliable read-back.") }

        var results: [VariantResult] = []
        for v in list {
            results.append(await runOne(v))
        }

        say("\n=== SUMMARY (app read-back; still check each one in Photos) ===")
        say("code | saved | iOS says Live | resources | error")
        for r in results {
            say("\(r.variant.code) | \(r.saved ? "yes" : "NO") | \(r.isLive ? "YES" : "no") | \(r.resources) | \(r.error ?? "-")")
        }
        say("\nIn Photos, open the album \"\(Self.albumName)\". Items were saved in order A → \(list.last?.code ?? "A"); A is the oldest.")
        say("For each: LIVE badge? press-and-hold plays? image still? voice audible? seconds played? works after reopening Photos?")
        say("=== end ===\n")
    }

    private func runOne(_ v: TestVariant) async -> VariantResult {
        var result = VariantResult(variant: v)
        say("\n--- \(v.code): \(v.title) ---")
        say("Expectation: \(v.expectation)")
        do {
            let identifier = UUID().uuidString
            let stillID = v.mismatchIdentifiers ? UUID().uuidString : nil
            let pair = try await LivePhotoBuilder.build(identifier: identifier, maxDuration: v.maxDuration,
                                                        includeStillImageTime: v.includeStillImageTime,
                                                        stillIdentifier: stillID, heicStill: v.heicStill)
            say("Built \(pair.stillURL.lastPathComponent) (\(Self.size(pair.stillURL))) + \(pair.movieURL.lastPathComponent) (\(Self.size(pair.movieURL)), \(String(format: "%.2f", pair.duration)) s)")
            for c in try await LivePhotoBuilder.verify(pair) { say("  check: \(c)") }

            let holder = IDHolder()
            let albumAdd = IDHolder()
            let before = PHAsset.fetchAssets(with: nil).count
            let album = try await Self.album()
            if let album {
                say("album: \"\(album.localizedTitle ?? "?")\" id=\(album.localIdentifier) count before=\(PHAsset.fetchAssets(in: album, options: nil).count)")
            } else {
                say("album: could not find or create")
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.creationDate = Date()
                    request.location = nil
                    let po = PHAssetResourceCreationOptions()
                    po.originalFilename = "SoundPhotoTest_\(v.code).\(v.heicStill ? "HEIC" : "JPG")"
                    request.addResource(with: .photo, fileURL: pair.stillURL, options: po)
                    let vo = PHAssetResourceCreationOptions()
                    vo.originalFilename = "SoundPhotoTest_\(v.code).MOV"
                    request.addResource(with: .pairedVideo, fileURL: pair.movieURL, options: vo)
                    if let ph = request.placeholderForCreatedAsset {
                        holder.value = ph.localIdentifier
                        if let album, let add = PHAssetCollectionChangeRequest(for: album) {
                            add.addAssets([ph] as NSArray)
                            albumAdd.value = "requested"
                        } else {
                            albumAdd.value = album == nil ? "no album" : "change request nil"
                        }
                    }
                }
                say("performChanges: SUCCESS")
            } catch {
                let ns = error as NSError
                say("performChanges: ERROR domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription)")
                if !ns.userInfo.isEmpty { say("  userInfo: \(ns.userInfo)") }
                result.error = "PhotoKit \(ns.domain) \(ns.code)"
                return result
            }
            result.saved = true
            let after = PHAsset.fetchAssets(with: nil).count
            say("New assets in library: \(after - before)")
            guard let id = holder.value,
                  let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
                result.error = "saved but not readable"; say("Could not read back the asset."); return result
            }
            result.assetID = id
            result.isLive = asset.mediaSubtypes.contains(.photoLive)
            let res = PHAssetResource.assetResources(for: asset).map { Self.name($0.type) }
            result.resources = res.joined(separator: "+")
            say("localIdentifier: \(id)")
            say("mediaType: \(asset.mediaType == .image ? "image" : "other(\(asset.mediaType.rawValue))"), \(asset.pixelWidth)x\(asset.pixelHeight)")
            say("iOS classifies as Live Photo: \(result.isLive ? "YES" : "NO")")
            say("stored resources: \(result.resources)")
            say("album add in change block: \(albumAdd.value ?? "not attempted")")
            remember(SavedAsset(code: v.code, title: v.title, localIdentifier: id, savedAt: Date()))
            say("persisted localIdentifier for \(v.code)")
            describe(asset, album: album)
        } catch {
            result.error = error.localizedDescription
            say("FAILED before saving: \(error.localizedDescription)")
        }
        return result
    }

    /// Logs where Photos thinks the asset lives and how it is dated.
    func describe(_ asset: PHAsset, album: PHAssetCollection?) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        say("  creationDate: \(asset.creationDate.map(df.string(from:)) ?? "nil")")
        say("  modificationDate: \(asset.modificationDate.map(df.string(from:)) ?? "nil")")
        say("  isHidden: \(asset.isHidden)  isFavorite: \(asset.isFavorite)")
        say("  sourceType: \(Self.name(asset.sourceType))")
        say("  burstIdentifier: \(asset.burstIdentifier ?? "nil")  representsBurst: \(asset.representsBurst)")
        say("  mediaSubtypes raw: \(asset.mediaSubtypes.rawValue)  live=\(asset.mediaSubtypes.contains(.photoLive))  size=\(asset.pixelWidth)x\(asset.pixelHeight)")
        say("  location: \(asset.location.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" } ?? "nil")")
        var names: [String] = []
        for type in [PHAssetCollectionType.album, .smartAlbum] {
            let cols = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: type, options: nil)
            cols.enumerateObjects { c, _, _ in
                names.append("\(type == .album ? "album" : "smart"):\(c.localizedTitle ?? "?")")
            }
        }
        say("  in collections: \(names.isEmpty ? "NONE" : names.joined(separator: ", "))")
        if let album {
            let all = PHAsset.fetchAssets(in: album, options: nil)
            let opts = PHFetchOptions()
            opts.predicate = NSPredicate(format: "localIdentifier == %@", asset.localIdentifier)
            let inAlbum = PHAsset.fetchAssets(in: album, options: opts).count > 0
            say("  album add succeeded: \(inAlbum ? "YES" : "NO")  album total count: \(all.count)")
        }
        // Where would it appear in the main library (newest first)?
        let lib = PHFetchOptions()
        lib.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        lib.fetchLimit = 50
        let recent = PHAsset.fetchAssets(with: .image, options: lib)
        let idx = recent.index(of: asset)
        say("  position among newest 50 images in Library: \(idx == NSNotFound ? "not in newest 50" : "#\(idx + 1)")")
    }

    /// Re-logs diagnostics for every persisted asset (works across launches).
    func recheckSaved() {
        Task {
            say("\n=== Re-check saved assets — \(Date()) ===")
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            say("Photos authorization: \(Self.name(status))")
            let album = Self.existingAlbum()
            if let album { say("album \"\(Self.albumName)\" count: \(PHAsset.fetchAssets(in: album, options: nil).count)") }
            else { say("album \"\(Self.albumName)\" not found") }
            if saved.isEmpty { say("No saved assets recorded. Run the tests or tap 'Find earlier test photos'.") }
            for s in saved {
                say("\n\(s.code): \(s.localIdentifier)")
                if let a = PHAsset.fetchAssets(withLocalIdentifiers: [s.localIdentifier], options: nil).firstObject {
                    describe(a, album: album)
                } else {
                    say("  NOT FOUND in library (deleted?)")
                }
            }
            say("=== end ===\n")
        }
    }

    /// Scans recently modified Live Photos for resources named SoundPhotoTest_* (finds assets saved by older builds).
    func findEarlier() {
        isRunning = true
        Task {
            defer { isRunning = false }
            say("\n=== Find earlier test photos — \(Date()) ===")
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized || status == .limited else { say("No Photos access."); return }
            let opts = PHFetchOptions()
            opts.includeHiddenAssets = true
            opts.predicate = NSPredicate(format: "modificationDate > %@", Date().addingTimeInterval(-14 * 86400) as NSDate)
            let found = PHAsset.fetchAssets(with: .image, options: opts)
            say("Checking \(found.count) images modified in the last 14 days…")
            var hits: [(PHAsset, String)] = []
            found.enumerateObjects { a, _, _ in
                let names = PHAssetResource.assetResources(for: a).map(\.originalFilename)
                if let n = names.first(where: { $0.hasPrefix("SoundPhotoTest_") }) { hits.append((a, n)) }
            }
            say("Found \(hits.count) test assets.")
            let album = Self.existingAlbum()
            for (a, n) in hits {
                let code = String(n.dropFirst("SoundPhotoTest_".count).prefix(1))
                say("\n\(code) (\(n)): \(a.localIdentifier)")
                describe(a, album: album)
                if !saved.contains(where: { $0.localIdentifier == a.localIdentifier }) {
                    remember(SavedAsset(code: code, title: "found: \(n)", localIdentifier: a.localIdentifier,
                                        savedAt: a.creationDate ?? Date()))
                }
            }
            say("=== end ===\n")
        }
    }

    /// Deletes every persisted test asset. iOS shows its own confirmation.
    func deleteSaved() {
        let ids = saved.map(\.localIdentifier)
        guard !ids.isEmpty else { say("Nothing to delete."); return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else {
            say("None of the \(ids.count) saved assets still exist; clearing list.")
            saved = []; persist(); return
        }
        Task {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(assets)
                }
                say("Deleted \(assets.count) test assets (they stay in Recently Deleted for 30 days).")
                saved = []; persist()
            } catch {
                let ns = error as NSError
                say("Delete not done: domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription)")
            }
        }
    }

    static func existingAlbum() -> PHAssetCollection? {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "title = %@", albumName)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: opts).firstObject
    }

    private static func name(_ t: PHAssetSourceType) -> String {
        var parts: [String] = []
        if t.contains(.typeUserLibrary) { parts.append("userLibrary") }
        if t.contains(.typeCloudShared) { parts.append("cloudShared") }
        if t.contains(.typeiTunesSynced) { parts.append("iTunesSynced") }
        return parts.isEmpty ? "raw(\(t.rawValue))" : parts.joined(separator: "+") + " (raw \(t.rawValue))"
    }

    /// Finds or creates the test album so results are easy to find in Photos.
    private static func album() async throws -> PHAssetCollection? {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "title = %@", albumName)
        if let found = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: opts).firstObject {
            return found
        }
        let holder = IDHolder()
        try await PHPhotoLibrary.shared().performChanges {
            holder.value = PHAssetCollectionChangeRequest
                .creationRequestForAssetCollection(withTitle: albumName)
                .placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let id = holder.value else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }

    private static func size(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func name(_ s: PHAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "authorized"
        case .limited: return "limited"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown(\(s.rawValue))"
        }
    }

    private static func name(_ t: PHAssetResourceType) -> String {
        switch t {
        case .photo: return "photo"
        case .pairedVideo: return "pairedVideo"
        case .fullSizePhoto: return "fullSizePhoto"
        case .fullSizePairedVideo: return "fullSizePairedVideo"
        case .video: return "video"
        case .adjustmentData: return "adjustmentData"
        default: return "type\(t.rawValue)"
        }
    }
}
