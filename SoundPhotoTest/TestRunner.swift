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

    private func say(_ s: String) { log += s + "\n"; print(s) }

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
            let before = PHAsset.fetchAssets(with: nil).count
            let album = try await Self.album()
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
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
        } catch {
            result.error = error.localizedDescription
            say("FAILED before saving: \(error.localizedDescription)")
        }
        return result
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

struct TestError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// Reference box so PhotoKit change blocks can hand back placeholder ids.
final class IDHolder: @unchecked Sendable { var value: String? }
