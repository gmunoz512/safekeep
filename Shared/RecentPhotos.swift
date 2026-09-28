import Photos
import SwiftUI
import UIKit

/// Most recently ADDED photos (photos saved from Messages keep their original capture date,
/// so capture-date order would bury them).
@MainActor
final class RecentPhotosModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var assets: [PHAsset] = []
    @Published var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var loading = false
    @Published var fetchMethod = ""

    let limit = 30
    let caching = PHCachingImageManager()
    static let thumbPixels = CGSize(width: 240, height: 240)
    var log: (String) -> Void = { print($0) }
    private var observing = false
    private var reloadPending = false

    static func describe(_ s: PHAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "Full Access"
        case .limited: return "Limited Access"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "unknown (\(s.rawValue))"
        }
    }

    /// Asks for access if it hasn't been asked yet (works in the app; in the extension it may or may not show a prompt).
    func requestAccess() async {
        let before = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        log("Photos access before request: \(Self.describe(before))")
        let st = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = st
        log("Photos access after request: \(Self.describe(st))")
    }

    func load(reason: String) async {
        var st = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        log("\n=== Recent photos (\(reason)) — Photos access: \(Self.describe(st)) ===")
        if st == .notDetermined {
            log("requesting Photos access…")
            st = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            log("Photos access now: \(Self.describe(st))")
        }
        status = st
        guard st == .authorized || st == .limited else { assets = []; return }
        if !observing { PHPhotoLibrary.shared().register(self); observing = true }
        loading = true
        defer { loading = false }
        let t0 = Date()
        let excluded = Self.ownAlbumAssetIDs()
        log("own album assets excluded: \(excluded.count)")

        // A) User library smart album, no sort descriptors → library order (date added). Take last N, reversed.
        var a: [PHAsset] = []
        var aNote = "A (smartAlbumUserLibrary, no sort, last N reversed): "
        if let lib = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil).firstObject {
            let r = PHAsset.fetchAssets(in: lib, options: nil)
            let (kept, scanned, skipped) = Self.takeRecent(r, limit: limit, excluded: excluded)
            a = kept
            aNote += "total=\(r.count) scanned=\(scanned) skippedOwnCopies=\(skipped) kept=\(kept.count)"
        } else {
            aNote += "user library smart album NOT FOUND"
        }
        log(aNote)

        // B) sort key "addedDate" (undocumented). Guarded so an unsupported key can't crash.
        var b: [PHAsset] = []
        var bNote = "B (PHFetchOptions sort addedDate desc): "
        var rb: PHFetchResult<PHAsset>?
        let exc = SPTryObjC {
            let o = PHFetchOptions()
            o.sortDescriptors = [NSSortDescriptor(key: "addedDate", ascending: false)]
            o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            o.fetchLimit = 200
            let r = PHAsset.fetchAssets(with: o)
            _ = r.count
            _ = r.firstObject
            rb = r
        }
        if let exc {
            bNote += "NOT SUPPORTED — \(exc)"
        } else if let rb {
            var bSkipped = 0
            let exc2 = SPTryObjC {
                rb.enumerateObjects { asset, _, stop in
                    if excluded.contains(asset.localIdentifier) || Self.isOwnCopy(asset) { bSkipped += 1; return }
                    b.append(asset)
                    if b.count >= self.limit { stop.pointee = true }
                }
            }
            bNote += exc2.map { "enumeration failed — \($0)" } ?? "count=\(rb.count) skippedOwnCopies=\(bSkipped) kept=\(b.count)"
        }
        log(bNote)

        // C) Fallback: all images, no sort, last N reversed.
        var c: [PHAsset] = []
        if a.isEmpty && b.isEmpty {
            let o = PHFetchOptions()
            o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let r = PHAsset.fetchAssets(with: o)
            let (kept, scanned, skipped) = Self.takeRecent(r, limit: limit, excluded: excluded)
            c = kept
            log("C (all images, no sort, last N reversed): total=\(r.count) scanned=\(scanned) skipped=\(skipped) kept=\(kept.count)")
        }

        let k = min(8, a.count, b.count)
        if k > 0 {
            let same = Array(a.prefix(k).map(\.localIdentifier)) == Array(b.prefix(k).map(\.localIdentifier))
            log("A vs B first \(k): \(same ? "SAME order" : "DIFFERENT order")")
        }
        let chosen: [PHAsset]
        if !a.isEmpty { chosen = a; fetchMethod = "A: user library, no sort (date added)" }
        else if !b.isEmpty { chosen = b; fetchMethod = "B: addedDate sort" }
        else { chosen = c; fetchMethod = "C: all images, no sort" }
        log("using \(fetchMethod); \(chosen.count) photos in \(String(format: "%.2f", Date().timeIntervalSince(t0))) s")
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        for (i, x) in chosen.prefix(5).enumerated() {
            log("  #\(i) \(x.localIdentifier) created \(x.creationDate.map(df.string(from:)) ?? "nil") \(x.pixelWidth)x\(x.pixelHeight)")
        }
        caching.stopCachingImagesForAllAssets()
        caching.startCachingImages(for: chosen, targetSize: Self.thumbPixels, contentMode: .aspectFill, options: nil)
        assets = chosen
    }

    nonisolated private static func takeRecent(_ r: PHFetchResult<PHAsset>, limit: Int, excluded: Set<String>) -> ([PHAsset], Int, Int) {
        var kept: [PHAsset] = []
        var scanned = 0, skipped = 0
        guard r.count > 0 else { return ([], 0, 0) }
        r.enumerateObjects(options: .reverse) { asset, _, stop in
            scanned += 1
            if scanned > 600 { stop.pointee = true; return }
            guard asset.mediaType == .image else { return }
            if excluded.contains(asset.localIdentifier) || isOwnCopy(asset) { skipped += 1; return }
            kept.append(asset)
            if kept.count >= limit { stop.pointee = true }
        }
        return (kept, scanned, skipped)
    }

    /// The app's own copies are named SoundPhoto_… (and test saves SoundPhotoTest_…).
    nonisolated static func isOwnCopy(_ asset: PHAsset) -> Bool {
        PHAssetResource.assetResources(for: asset).contains { $0.originalFilename.hasPrefix("SoundPhoto") }
    }

    nonisolated static func ownAlbumAssetIDs() -> Set<String> {
        var ids = Set<String>()
        for name in ["Safekeep", "Sound Photos", "Sound Photo Tests"] {
            let o = PHFetchOptions(); o.predicate = NSPredicate(format: "title = %@", name)
            PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: o).enumerateObjects { c, _, _ in
                PHAsset.fetchAssets(in: c, options: nil).enumerateObjects { a, _, _ in ids.insert(a.localIdentifier) }
            }
        }
        return ids
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            guard !self.reloadPending else { return }
            self.reloadPending = true
            try? await Task.sleep(nanoseconds: 800_000_000)
            self.reloadPending = false
            await self.load(reason: "library changed")
        }
    }
}

/// Grabs the hosting view controller (for the limited-library picker) without UIApplication.shared,
/// which isn't available in app extensions.
final class PresenterHolder { weak var vc: UIViewController? }

struct PresenterResolver: UIViewControllerRepresentable {
    let holder: PresenterHolder
    func makeUIViewController(context: Context) -> Resolver { Resolver(holder) }
    func updateUIViewController(_ vc: Resolver, context: Context) {}
    final class Resolver: UIViewController {
        let holder: PresenterHolder
        init(_ h: PresenterHolder) { holder = h; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError() }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            holder.vc = parent
        }
    }
}

struct PhotoThumb: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    @State private var image: UIImage?

    var body: some View {
        Theme.card
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .onAppear(perform: request)
    }

    private func request() {
        guard image == nil else { return }
        let o = PHImageRequestOptions()
        o.deliveryMode = .opportunistic
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = true
        manager.requestImage(for: asset, targetSize: RecentPhotosModel.thumbPixels, contentMode: .aspectFill, options: o) { img, _ in
            if let img { DispatchQueue.main.async { image = img } }
        }
    }
}

struct RecentPhotosGrid: View {
    @ObservedObject var recents: RecentPhotosModel
    var selectedID: String?
    var disabled = false
    var columns = 4
    let presenter: PresenterHolder
    let onTap: (PHAsset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch recents.status {
            case .denied, .restricted:
                Text("No Photos access. Open Settings > Privacy & Security > Photos > Safekeep and choose Full Access (or open Safekeep once).")
                    .font(Theme.rounded(.footnote)).foregroundStyle(Theme.sage)
            case .notDetermined:
                Text("Open Safekeep once to allow Photos access.").font(Theme.rounded(.footnote)).foregroundStyle(Theme.sage)
            default:
                if recents.status == .limited {
                    HStack {
                        Text("Showing only the photos you allowed.").font(Theme.rounded(.caption)).foregroundStyle(Theme.sage)
                        Spacer()
                        Button("Change access") {
                            if let vc = presenter.vc { PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: vc) }
                        }
                        .font(Theme.rounded(.caption, .semibold)).foregroundStyle(Theme.peach)
                    }
                }
                if recents.assets.isEmpty {
                    Text(recents.loading ? "Loading…" : "No photos found.").font(Theme.rounded(.footnote)).foregroundStyle(Theme.sage)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                    ForEach(recents.assets, id: \.localIdentifier) { a in
                        Button { onTap(a) } label: {
                            PhotoThumb(asset: a, manager: recents.caching)
                                .overlay {
                                    if a.localIdentifier == selectedID {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.peach, lineWidth: 4)
                                        Image(systemName: "checkmark.circle.fill").font(.title2)
                                            .foregroundStyle(Theme.onPeach, Theme.peach)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(disabled)
                    }
                }
            }
        }
        .background(PresenterResolver(holder: presenter).frame(width: 0, height: 0))
    }
}
