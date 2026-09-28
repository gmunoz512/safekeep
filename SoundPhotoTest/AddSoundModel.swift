import AVFoundation
import CoreLocation
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers

/// "Add Sound to Photo": pick a real photo + a sound, save a NEW Live Photo copy next to the original.
@MainActor
final class AddSoundModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var log = ""
    @Published var busy = false
    @Published var photoAsset: PHAsset?
    @Published var photoInfo = ""
    @Published var thumbnail: UIImage?
    @Published var imageData: Data?
    @Published var downloadProgress: Double?
    @Published var audioURL: URL?
    @Published var audioDuration: Double = 0
    @Published var audioInfo = ""
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var result: SavedAsset?
    @Published var longResults: [SavedAsset] = []

    // Quick flow (clipboard card + recent photos + one-tap save)
    /// Set when audio is on the clipboard and that clipboard (changeCount) hasn't been used/dismissed yet.
    @Published var clipboardOffer: Int?
    @Published var clipboardTypesSummary = ""
    /// Live clipboard status (types only, no prompt), shown in the card.
    @Published var clipStatus = "Clipboard: not checked yet"
    /// Result of the last paste tap, shown in the card so no tap is ever silent.
    @Published var pasteStatus = ""
    @Published var pasteStatusIsError = false
    /// Set when a direct read returns nothing at all: the process likely can't see the clipboard.
    @Published var clipboardUnreadable = false
    @Published var pasteButtonEnabled: Bool?
    /// Photo tapped in the grid while no sound was ready: saved automatically once the sound arrives.
    @Published var selectedForSave: PHAsset?
    /// Photo waiting for the "Save sound copy" confirmation.
    @Published var confirmAsset: PHAsset?

    /// "[ext] " in the iMessage extension.
    var logPrefix = ""
    /// Longest side of the Live Photo movie frame (smaller in the extension to stay under its memory limit).
    var movieMaxSide = 1920
    /// App (debug screen): show a confirm sheet. Extension: tap photo = save.
    var confirmBeforeSave = true
    private var lastCheckedChangeCount = -1
    private var loadTask: Task<Void, Never>?

    private var recorder: AVAudioRecorder?
    private var recordURL: URL?
    private var player: AVAudioPlayer?

    static let albumName = "Safekeep"
    static let testAlbumName = "Sound Photo Tests"

    nonisolated static let knownAudioTypes = [
        "public.audio", "public.mpeg-4-audio", "com.apple.m4a-audio", "com.apple.coreaudio-format",
        "public.mp3", "org.xiph.opus", "org.xiph.ogg-audio", "com.microsoft.waveform-audio",
        "public.aiff-audio", "public.aifc-audio", "public.amr-audio", "org.xiph.flac",
        "com.apple.protected-mpeg-4-audio",
    ]

    func say(_ s: String) {
        let line = logPrefix.isEmpty ? s : s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : logPrefix + $0 }.joined(separator: "\n")
        log += line + "\n"
        print(line)
        Self.appendToLogFile(line + "\n")
    }

    /// Also written to a file in this process's Documents folder (app and extension each keep their own).
    nonisolated static var logFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("SoundPhotoLog.txt")
    }

    nonisolated private static func appendToLogFile(_ s: String) {
        guard let data = s.data(using: .utf8) else { return }
        let url = logFileURL
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    func clearLog() {
        log = ""
        try? FileManager.default.removeItem(at: Self.logFileURL)
    }

    nonisolated private static func tmp(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("audio-\(UUID().uuidString).\(ext)")
    }

    /// Types the UIPasteControl accepts (Messages voice notes are com.apple.coreaudio-format).
    nonisolated static let pasteTypeIdentifiers = knownAudioTypes + ["public.aac-audio", "com.apple.messages.audioMessage"]

    nonisolated static func isAudioType(_ id: String) -> Bool {
        if knownAudioTypes.contains(id) { return true }
        return UTType(id)?.conforms(to: .audio) ?? false
    }

    // MARK: 0. Clipboard detection (no paste prompt: only types / changeCount / has* are read)

    private static let handledKey = "handledClipboard.v1"

    /// Boot time rounded to a minute, so a stored changeCount is only trusted within the same boot.
    private static var bootStamp: Int { Int((Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime) / 60) }

    private var handledChangeCount: Int? {
        get {
            guard let d = UserDefaults.standard.dictionary(forKey: Self.handledKey),
                  let cc = d["cc"] as? Int, let boot = d["boot"] as? Int, abs(boot - Self.bootStamp) <= 1 else { return nil }
            return cc
        }
        set {
            if let newValue { UserDefaults.standard.set(["cc": newValue, "boot": Self.bootStamp], forKey: Self.handledKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.handledKey) }
        }
    }

    func checkClipboard(trigger: String) {
        let pb = UIPasteboard.general
        let cc = pb.changeCount
        let types = pb.types                       // metadata only: does not trigger the paste prompt
        let audio = types.filter(Self.isAudioType)
        let containsAudio = pb.contains(pasteboardTypes: Self.knownAudioTypes)
        let voiceMarker = types.contains("com.apple.messages.audioMessage")
        let handled = handledChangeCount
        let detected = !audio.isEmpty || containsAudio || voiceMarker
        let changed = cc != lastCheckedChangeCount
        if changed || trigger == "launch" {
            say("[clipboard check · \(trigger) · \(Date().formatted(date: .omitted, time: .standard))] changeCount=\(cc) handled=\(handled.map { String($0) } ?? "none") items=\(pb.numberOfItems) types=\(types) audioTypes=\(audio) contains(audio)=\(containsAudio) voiceMessageMarker=\(voiceMarker) hasStrings=\(pb.hasStrings) hasURLs=\(pb.hasURLs) hasImages=\(pb.hasImages)")
        }
        lastCheckedChangeCount = cc
        let shown = types.count > 4 ? Array(types.prefix(4)) + ["+\(types.count - 4) more"] : types
        clipStatus = "Clipboard: #\(cc) · \(pb.numberOfItems) item(s) · \(types.isEmpty ? "no types visible" : shown.joined(separator: ", "))"
            + (cc == 0 && types.isEmpty ? " (change #0: clipboard looks blocked for Safekeep here)" : "")
        clipboardTypesSummary = audio.first ?? (voiceMarker ? "com.apple.messages.audioMessage" : "")
        if detected && cc != handled {
            if clipboardOffer != cc { say("  → audio detected, showing paste card (changeCount \(cc))") }
            clipboardOffer = cc
        } else {
            if clipboardOffer != nil { say("  → hiding paste card (\(detected ? "clipboard already used" : "no audio on clipboard"))") }
            clipboardOffer = nil
        }
    }

    func dismissClipboardOffer() {
        let cc = UIPasteboard.general.changeCount
        handledChangeCount = cc
        clipboardOffer = nil
        say("Paste card dismissed (changeCount \(cc) won't be offered again).")
    }

    private func markClipboardUsed() {
        let cc = UIPasteboard.general.changeCount
        handledChangeCount = cc
        clipboardOffer = nil
        say("clipboard changeCount \(cc) marked as used.")
    }

    private var lastTouch = Date.distantPast

    func pasteButtonTouched() {
        guard Date().timeIntervalSince(lastTouch) > 0.5 else { return }
        lastTouch = Date()
        let pb = UIPasteboard.general
        let enabled = pasteButtonEnabled.map { $0 ? "active" : "greyed out" } ?? "unknown"
        setPasteStatus("Paste button tapped (\(enabled)); clipboard #\(pb.changeCount), \(pb.numberOfItems) item(s), types \(pb.types.isEmpty ? "none" : pb.types.joined(separator: ", ")). Waiting for iOS to hand over the items…",
                       error: pasteButtonEnabled == false)
        let at = lastTouch
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.lastTouch == at && self.pasteStatus.hasPrefix("Paste button tapped") {
                self.setPasteStatus("iOS delivered nothing to the Paste button (it was \(enabled)). Try \"Paste another way\" or \"Choose audio file\".", error: true)
            }
        }
    }

    func pasteButtonEnabledChanged(_ e: Bool) {
        guard pasteButtonEnabled != e else { return }
        pasteButtonEnabled = e
        say("Paste button is now \(e ? "active" : "greyed out") (clipboard #\(UIPasteboard.general.changeCount))")
    }

    func setPasteStatus(_ text: String, error: Bool = false) {
        pasteStatus = text
        pasteStatusIsError = error
        say("[status] " + text)
    }

    /// Items handed over by the UIPasteControl (no system prompt).
    func pasteFromControl(_ providers: [NSItemProvider]) async {
        say("\n=== Paste via UIPasteControl — \(Date()) ===")
        say("paste method: UIPasteControl (no prompt), \(providers.count) item provider(s)")
        say(Mem.line())
        let types = providers.flatMap(\.registeredTypeIdentifiers)
        setPasteStatus("Paste button gave \(providers.count) item(s): \(types.isEmpty ? "no types" : types.joined(separator: ", "))", error: providers.isEmpty)
        guard !providers.isEmpty else { return }
        if await loadFromProviders(providers, method: "paste button") { return }
        setPasteStatus("Paste button: items had no usable audio (\(types.joined(separator: ", "))). Try \"Choose audio file\".", error: true)
    }

    /// Tries every provider: audio types first (data → file → in-place), then public.file-url / public.url.
    /// Returns true when a sound was loaded and processed.
    func loadFromProviders(_ providers: [NSItemProvider], method: String) async -> Bool {
        let preferred = ["com.apple.coreaudio-format", "public.audio"]
        for (i, p) in providers.enumerated() {
            let reg = p.registeredTypeIdentifiers
            say("  provider\(i) types: \(reg)")
            var candidates: [String] = reg.filter(Self.isAudioType)
            for t in preferred where !candidates.contains(t) && p.hasItemConformingToTypeIdentifier(t) { candidates.append(t) }
            for t in candidates {
                for mode in ["data", "file", "in-place"] {
                    setPasteStatus("Loading \(t) (\(mode))…")
                    let (url, note) = await Self.load(p, type: t, mode: mode)
                    say("  \(t) \(mode): \(note)")
                    if let url {
                        markClipboardUsed()
                        setPasteStatus("Got audio via \(method) (\(t), \(mode)). Converting…")
                        await process(url, source: "\(method) (\(t), \(mode))")
                        if audioURL != nil { setPasteStatus("Sound ready: \(String(format: "%.1f", audioDuration)) s — now tap a photo") }
                        else { setPasteStatus("Got \(t) but conversion failed — see log", error: true) }
                        return true
                    }
                }
            }
            for t in ["public.file-url", "public.url"] where p.hasItemConformingToTypeIdentifier(t) {
                setPasteStatus("Loading \(t)…")
                let (u, note) = await Self.loadURLItem(p, type: t)
                say("  \(t): \(note)")
                guard let u, u.isFileURL else { continue }
                let dest = Self.tmp(u.pathExtension.isEmpty ? "audio" : u.pathExtension)
                let access = u.startAccessingSecurityScopedResource()
                defer { if access { u.stopAccessingSecurityScopedResource() } }
                do {
                    try FileManager.default.copyItem(at: u, to: dest)
                    markClipboardUsed()
                    await process(dest, source: "\(method) (\(t))")
                    if audioURL != nil { setPasteStatus("Sound ready: \(String(format: "%.1f", audioDuration)) s — now tap a photo"); return true }
                } catch {
                    say("  copy from \(u.path) failed: \(error.localizedDescription)")
                    setPasteStatus("Can't read the voice note file (\(u.lastPathComponent)): \(error.localizedDescription)", error: true)
                }
            }
        }
        return false
    }

    nonisolated private static func ext(for type: String, url: URL? = nil) -> String {
        if let e = url?.pathExtension, !e.isEmpty { return e }
        if type == "com.apple.coreaudio-format" { return "caf" }
        return UTType(type)?.preferredFilenameExtension ?? "audio"
    }

    /// One provider load in the given mode. Always returns a human-readable note.
    nonisolated static func load(_ p: NSItemProvider, type: String, mode: String) async -> (URL?, String) {
        await withCheckedContinuation { (c: CheckedContinuation<(URL?, String), Never>) in
            switch mode {
            case "data":
                _ = p.loadDataRepresentation(forTypeIdentifier: type) { data, err in
                    guard let data, !data.isEmpty else { c.resume(returning: (nil, "no data (\(err?.localizedDescription ?? "nil"))")); return }
                    let dest = tmp(ext(for: type))
                    do { try data.write(to: dest); c.resume(returning: (dest, "\(data.count) bytes")) }
                    catch { c.resume(returning: (nil, "write failed: \(error.localizedDescription)")) }
                }
            case "file":
                _ = p.loadFileRepresentation(forTypeIdentifier: type) { url, err in
                    guard let url else { c.resume(returning: (nil, "no file (\(err?.localizedDescription ?? "nil"))")); return }
                    let dest = tmp(ext(for: type, url: url))
                    do { try FileManager.default.copyItem(at: url, to: dest); c.resume(returning: (dest, "file \(url.lastPathComponent)")) }
                    catch { c.resume(returning: (nil, "copy failed: \(error.localizedDescription)")) }
                }
            default:
                p.loadInPlaceFileRepresentation(forTypeIdentifier: type) { url, inPlace, err in
                    guard let url else { c.resume(returning: (nil, "no in-place file (\(err?.localizedDescription ?? "nil"))")); return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let dest = tmp(ext(for: type, url: url))
                    do { try FileManager.default.copyItem(at: url, to: dest); c.resume(returning: (dest, "in-place=\(inPlace) \(url.lastPathComponent)")) }
                    catch { c.resume(returning: (nil, "copy failed: \(error.localizedDescription)")) }
                }
            }
        }
    }

    nonisolated static func loadURLItem(_ p: NSItemProvider, type: String) async -> (URL?, String) {
        await withCheckedContinuation { (c: CheckedContinuation<(URL?, String), Never>) in
            p.loadItem(forTypeIdentifier: type, options: nil) { item, err in
                if let u = item as? URL { c.resume(returning: (u, "URL \(u.absoluteString.prefix(120))")) }
                else if let d = item as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) { c.resume(returning: (u, "URL(data) \(u.absoluteString.prefix(120))")) }
                else if let s = item as? String, let u = URL(string: s) { c.resume(returning: (u, "URL(string) \(s.prefix(120))")) }
                else { c.resume(returning: (nil, "no URL (\(item.map { String(describing: Swift.type(of: $0)) } ?? "nil"), \(err?.localizedDescription ?? "no error"))")) }
            }
        }
    }

    // MARK: Quick flow: recent photo tapped / chosen

    func tapPhoto(_ asset: PHAsset, source: String) {
        say("\n=== Photo tapped (\(source)) — \(asset.localIdentifier) ===")
        if audioURL != nil {
            if confirmBeforeSave {
                say("sound is ready → confirm sheet")
                confirmAsset = asset
            } else {
                say("sound is ready → saving right away (no confirm step)")
                Task { await self.saveWith(asset) }
                return
            }
        } else {
            say("no sound yet → photo selected; it will be saved as soon as a sound arrives")
            selectedForSave = asset
        }
        // Preload full-resolution data now so the save is quick.
        if photoAsset?.localIdentifier != asset.localIdentifier || imageData == nil {
            let id = asset.localIdentifier
            loadTask = Task { await self.picked(id) }
        }
    }

    func cancelSelection() {
        if selectedForSave != nil { say("Photo selection cleared.") }
        selectedForSave = nil
    }

    /// Runs the existing save for the given photo (loading its data first if needed).
    @discardableResult
    func saveWith(_ asset: PHAsset) async -> SavedAsset? {
        confirmAsset = nil
        selectedForSave = nil
        say("One-tap save for \(asset.localIdentifier)")
        await loadTask?.value
        loadTask = nil
        if photoAsset?.localIdentifier != asset.localIdentifier || imageData == nil {
            await picked(asset.localIdentifier)
        }
        guard photoAsset?.localIdentifier == asset.localIdentifier, imageData != nil else {
            say("Photo data not available; not saved."); return nil
        }
        return await saveSoundCopy()
    }

    private func soundArrived() {
        guard let a = selectedForSave else { return }
        say("Sound arrived with a photo already selected → saving now")
        Task { await self.saveWith(a) }
    }

    func clearSound() {
        stopPlayback()
        audioURL = nil
        audioDuration = 0
        audioInfo = ""
        say("Sound cleared.")
    }

    // MARK: 1. Photo

    func picked(_ assetID: String?) async {
        say("\n=== Photo chosen — \(Date()) ===")
        say(Mem.line("before photo load"))
        guard let assetID else {
            say("Picker returned no asset identifier (shouldn't happen with the shared library)."); return
        }
        say("assetIdentifier: \(assetID)")
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        say("Photos authorization: \(status == .authorized ? "authorized" : status == .limited ? "limited" : "not granted (\(status.rawValue))")")
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            say("Could not fetch the asset. Give the app Full Access to Photos (Settings > Privacy > Photos).")
            return
        }
        photoAsset = asset
        imageData = nil
        result = nil
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        say("creationDate: \(asset.creationDate.map(df.string(from:)) ?? "nil")")
        say("location: \(asset.location.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" } ?? "nil")")
        say("size: \(asset.pixelWidth)x\(asset.pixelHeight)  live=\(asset.mediaSubtypes.contains(.photoLive))  subtypes raw=\(asset.mediaSubtypes.rawValue)")
        for r in PHAssetResource.assetResources(for: asset) {
            say("  resource type=\(r.type.rawValue) uti=\(r.uniformTypeIdentifier) name=\(r.originalFilename)")
        }
        photoInfo = "\(asset.pixelWidth)×\(asset.pixelHeight) · \(asset.creationDate.map(df.string(from:)) ?? "no date")"

        let topts = PHImageRequestOptions()
        topts.deliveryMode = .opportunistic
        topts.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 600, height: 600),
                                              contentMode: .aspectFit, options: topts) { [weak self] img, _ in
            DispatchQueue.main.async { if let img { self?.thumbnail = img } }
        }

        busy = true
        defer { busy = false; downloadProgress = nil }
        let opts = PHImageRequestOptions()
        opts.version = .current
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        opts.progressHandler = { [weak self] p, err, _, _ in
            DispatchQueue.main.async {
                self?.downloadProgress = p
                if let err { self?.say("iCloud download error: \(err.localizedDescription)") }
            }
        }
        say("Loading full-resolution image data (version .current, network allowed)…")
        let loaded: (Data?, String?, CGImagePropertyOrientation, [AnyHashable: Any]?) = await withCheckedContinuation { c in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, uti, orient, info in
                c.resume(returning: (data, uti, orient, info))
            }
        }
        let (data, uti, orient, info) = loaded
        if let err = info?[PHImageErrorKey] as? NSError { say("image data error: \(err.domain) \(err.code) \(err.localizedDescription)") }
        say("inCloud=\(info?[PHImageResultIsInCloudKey] as? Bool ?? false) degraded=\(info?[PHImageResultIsDegradedKey] as? Bool ?? false)")
        guard let data else { say("No image data returned."); return }
        imageData = data
        say("image data: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)) uti=\(uti ?? "?") orientation=\(orient.rawValue)")
        if let src = CGImageSourceCreateWithData(data as CFData, nil),
           let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            let exif = p[kCGImagePropertyExifDictionary as String] as? [String: Any]
            let maker = p[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any]
            say(Mem.line("after photo load"))
            say("image source: type=\(CGImageSourceGetType(src) as String? ?? "?") \(p[kCGImagePropertyPixelWidth as String] ?? "?")x\(p[kCGImagePropertyPixelHeight as String] ?? "?") DateTimeOriginal=\(exif?[kCGImagePropertyExifDateTimeOriginal as String] ?? "none") GPS=\(p[kCGImagePropertyGPSDictionary as String] != nil) MakerApple17=\(maker?["17"] ?? "none")")
        }
    }

    // MARK: 2. Sound

    /// Fallback: read the pasteboard directly (may prompt "Allow Paste"). Every step reports into the card.
    func pasteAudio() async {
        say("\n=== Paste another way (direct read) — \(Date()) ===")
        say("paste method: direct UIPasteboard read (fallback; may show the system paste prompt)")
        let pb = UIPasteboard.general
        let cc = pb.changeCount, n = pb.numberOfItems, types = pb.types
        say("pasteboard: changeCount=\(cc) numberOfItems=\(n) types=\(types) hasStrings=\(pb.hasStrings) hasURLs=\(pb.hasURLs)")
        setPasteStatus("Reading clipboard: #\(cc), \(n) item(s), types \(types.isEmpty ? "none" : types.joined(separator: ", "))")
        if n == 0 && types.isEmpty {
            clipboardUnreadable = true
            setPasteStatus("Safekeep can't see anything on the clipboard (0 items, change #\(cc)). iOS may not let apps inside Messages read the clipboard. Use \"Choose audio file\" or \"Open Safekeep app\".", error: true)
            return
        }
        clipboardUnreadable = false
        for (i, item) in pb.items.enumerated() {
            for (k, v) in item {
                let d: String
                if let data = v as? Data { d = "Data \(data.count) bytes" }
                else if let s = v as? String { d = "String \"\(s.prefix(120))\"" }
                else if let u = v as? URL { d = "URL \(u)" }
                else { d = String(describing: type(of: v)) }
                say("  item\(i) [\(k)]: \(d)")
            }
        }
        if await loadFromProviders(pb.itemProviders, method: "direct read") { return }
        for t in types where Self.isAudioType(t) {
            if let data = pb.data(forPasteboardType: t), !data.isEmpty {
                let url = Self.tmp(Self.ext(for: t))
                do {
                    try data.write(to: url)
                    say("Wrote \(data.count) bytes of \(t) to \(url.lastPathComponent)")
                    markClipboardUsed()
                    await process(url, source: "paste data (\(t))")
                    if audioURL != nil { setPasteStatus("Sound ready: \(String(format: "%.1f", audioDuration)) s — now tap a photo"); return }
                } catch { say("write failed: \(error.localizedDescription)") }
            } else {
                say("  data(forPasteboardType: \(t)) returned nothing")
            }
        }
        for u in pb.urls ?? [] where u.isFileURL {
            say("Pasteboard has file URL \(u.path)")
            let dest = Self.tmp(u.pathExtension.isEmpty ? "audio" : u.pathExtension)
            if (try? FileManager.default.copyItem(at: u, to: dest)) != nil {
                markClipboardUsed()
                await process(dest, source: "paste file URL")
                if audioURL != nil { setPasteStatus("Sound ready: \(String(format: "%.1f", audioDuration)) s — now tap a photo"); return }
            } else {
                say("  can't copy \(u.path) (no access from this process)")
            }
        }
        say("RESULT: no audio found on the pasteboard.")
        setPasteStatus("Clipboard has \(n) item(s) (\(types.joined(separator: ", "))) but no readable audio. Try \"Choose audio file\".", error: true)
    }

    /// Exactly build 7's working paste path (app only): item provider with an audio type →
    /// loadFileRepresentation → process; then raw pasteboard data; then a file URL. No early bail-outs.
    /// Returns true when a sound is ready.
    @discardableResult
    func pasteBuild7(trigger: String) async -> Bool {
        say("\n=== Paste voice message (build-7 method, \(trigger)) — \(Date()) ===")
        let pb = UIPasteboard.general
        say("pasteboard: changeCount=\(pb.changeCount) numberOfItems=\(pb.numberOfItems)")
        let types = pb.types
        say("pasteboard types: \(types)")
        let typeList = types.isEmpty ? "none" : types.joined(separator: ", ")
        setPasteStatus("Reading clipboard… (#\(pb.changeCount), \(pb.numberOfItems) item(s): \(typeList))")
        let readItems = pb.items   // the actual read (may show iOS's "Allow Paste" prompt)
        say("items actually read: \(readItems.count)")
        for (i, item) in readItems.enumerated() {
            for (k, v) in item {
                let d: String
                if let data = v as? Data { d = "Data \(data.count) bytes" }
                else if let s = v as? String { d = "String \"\(s.prefix(120))\"" }
                else if let u = v as? URL { d = "URL \(u)" }
                else { d = String(describing: type(of: v)) }
                say("  item\(i) [\(k)]: \(d)")
            }
        }
        let providers = pb.itemProviders
        for (i, p) in providers.enumerated() { say("  provider\(i) types: \(p.registeredTypeIdentifiers)") }
        // 1) item providers with an audio type (build 7: this is what worked for com.apple.coreaudio-format)
        for p in providers {
            if let t = p.registeredTypeIdentifiers.first(where: Self.isAudioType) {
                say("Trying provider file representation for \(t)…")
                setPasteStatus("Loading voice note (\(t))…")
                if let url = await Self.loadFile(p, type: t) {
                    say("Got file from provider: \(url.lastPathComponent)")
                    await process(url, source: "paste (\(t))")
                    return finishPaste(typeList)
                } else {
                    say("  provider file representation for \(t) returned nothing")
                }
            }
        }
        // 2) raw data for any audio type on the pasteboard
        for t in types where Self.isAudioType(t) {
            if let data = pb.data(forPasteboardType: t) {
                let url = Self.tmp(Self.ext(for: t))
                do {
                    try data.write(to: url)
                    say("Wrote \(data.count) bytes of \(t) to \(url.lastPathComponent)")
                    await process(url, source: "paste data (\(t))")
                    return finishPaste(typeList)
                } catch { say("write failed: \(error.localizedDescription)") }
            }
        }
        // 3) a file URL pointing at audio
        if let u = pb.url, u.isFileURL {
            say("Pasteboard has file URL \(u.lastPathComponent)")
            let dest = Self.tmp(u.pathExtension.isEmpty ? "audio" : u.pathExtension)
            if (try? FileManager.default.copyItem(at: u, to: dest)) != nil {
                await process(dest, source: "paste file URL")
                return finishPaste(typeList)
            }
        }
        say("RESULT: no audio found on the pasteboard.")
        if pb.numberOfItems > 0 && readItems.isEmpty {
            setPasteStatus("iOS didn't hand over the clipboard (\(pb.numberOfItems) item(s): \(typeList)) — was the paste prompt answered \"Don't Allow\"? Settings > Apps > Safekeep > Paste from Other Apps > Allow.", error: true)
        } else if pb.numberOfItems == 0 {
            setPasteStatus("Clipboard is empty (0 items, #\(pb.changeCount)). In Messages, hold the voice note → Copy, then tap Paste voice note.", error: true)
        } else {
            setPasteStatus("No voice note on the clipboard. It has: \(typeList). Copy the voice note again, then tap Paste voice note.", error: true)
        }
        return false
    }

    private func finishPaste(_ typeList: String) -> Bool {
        if audioURL != nil {
            setPasteStatus("Voice note ready: \(String(format: "%.1f", audioDuration)) s")
            return true
        }
        setPasteStatus("Got audio from the clipboard (\(typeList)) but it couldn't be converted — see log", error: true)
        return false
    }

    nonisolated private static func loadFile(_ p: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { (c: CheckedContinuation<URL?, Never>) in
            p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard let url else { c.resume(returning: nil); return }
                let ext = url.pathExtension.isEmpty ? (UTType(type)?.preferredFilenameExtension ?? "audio") : url.pathExtension
                let dest = tmp(ext)
                do { try FileManager.default.copyItem(at: url, to: dest); c.resume(returning: dest) }
                catch { c.resume(returning: nil) }
            }
        }
    }

    func pickedFile(_ url: URL) async {
        say("\n=== Audio file chosen — \(Date()) ===")
        setPasteStatus("Loading \(url.lastPathComponent)…")
        let dest = Self.tmp(url.pathExtension.isEmpty ? "audio" : url.pathExtension)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            await process(dest, source: "file \(url.lastPathComponent)")
            if audioURL != nil { setPasteStatus("Sound ready: \(String(format: "%.1f", audioDuration)) s — now tap a photo") }
            else { setPasteStatus("That file couldn't be used as audio — see log", error: true) }
        } catch {
            say("copy failed: \(error.localizedDescription)")
            setPasteStatus("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)", error: true)
        }
    }

    func toggleRecord() async {
        let session = AVAudioSession.sharedInstance()
        if isRecording, let recorder {
            recorder.stop()
            isRecording = false
            self.recorder = nil
            try? session.setCategory(.playback, mode: .default)
            say("Recording stopped.")
            if let recordURL { await process(recordURL, source: "recording") }
            return
        }
        say("\n=== Record — \(Date()) ===")
        let granted: Bool = await withCheckedContinuation { c in
            session.requestRecordPermission { c.resume(returning: $0) }
        }
        guard granted else { say("Microphone permission denied (Settings > Privacy > Microphone)."); return }
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = Self.tmp("m4a")
            let r = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            guard r.record() else { say("record() returned false"); return }
            recorder = r
            recordURL = url
            isRecording = true
            say("Recording… tap Stop when done.")
        } catch {
            say("Recorder error: \(error.localizedDescription)")
        }
    }

    /// Inspect, convert to AAC if needed, and make it the current sound.
    func process(_ url: URL, source: String) async {
        stopPlayback()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        say("audio in: \(url.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))) from \(source)")
        var info = await Self.inspect(url)
        say("  playable=\(info.playable) tracks=\(info.tracks) format=\(info.format) \(info.detail) duration=\(String(format: "%.2f", info.duration)) s")
        var final = url
        if !(info.playable && info.tracks > 0 && info.isAAC) {
            say("  not AAC/playable → converting to AAC m4a…")
            if let out = await convert(url) {
                final = out
                info = await Self.inspect(out)
                say("  converted: playable=\(info.playable) format=\(info.format) \(info.detail) duration=\(String(format: "%.2f", info.duration)) s")
            } else {
                say("  CONVERSION FAILED — this audio can't be used.")
                return
            }
        }
        guard info.duration > 0 else { say("  audio has zero duration."); return }
        audioURL = final
        audioDuration = info.duration
        audioInfo = "\(source) · \(info.format) · \(String(format: "%.1f", info.duration)) s"
        say("Sound ready: \(String(format: "%.2f", info.duration)) s (\(Self.bucket(info.duration)))")
        soundArrived()
    }

    struct AudioInfo { var playable = false; var tracks = 0; var format = "?"; var detail = ""; var isAAC = false; var duration = 0.0 }

    static func inspect(_ url: URL) async -> AudioInfo {
        var i = AudioInfo()
        let asset = AVURLAsset(url: url)
        i.playable = (try? await asset.load(.isPlayable)) ?? false
        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        i.tracks = tracks.count
        i.duration = ((try? await asset.load(.duration)) ?? .zero).seconds
        if i.duration.isNaN { i.duration = 0 }
        if let t = tracks.first, let fd = (try? await t.load(.formatDescriptions))?.first {
            let st = CMFormatDescriptionGetMediaSubType(fd)
            i.format = fourCC(st)
            i.isAAC = st == kAudioFormatMPEG4AAC
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
                i.detail = "\(Int(asbd.mSampleRate)) Hz, \(asbd.mChannelsPerFrame) ch"
            }
        }
        return i
    }

    static func fourCC(_ v: FourCharCode) -> String {
        let bytes = [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
        let s = String(bytes: bytes, encoding: .ascii) ?? "?"
        return "'\(s)'"
    }

    static func bucket(_ d: Double) -> String { d > 60 ? ">60 s" : d > 30 ? ">30 s" : "≤30 s" }

    private func convert(_ url: URL) async -> URL? {
        // Try 1: AVAssetExportSession (AppleM4A)
        let asset = AVURLAsset(url: url)
        if let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) {
            let out = Self.tmp("m4a")
            ex.outputURL = out
            ex.outputFileType = .m4a
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                ex.exportAsynchronously { c.resume() }
            }
            if ex.status == .completed { say("  AVAssetExportSession: OK"); return out }
            say("  AVAssetExportSession failed: status=\(ex.status.rawValue) \(ex.error.map { ($0 as NSError).domain + " " + String(($0 as NSError).code) + " " + $0.localizedDescription } ?? "")")
        } else {
            say("  AVAssetExportSession: not available for this file")
        }
        // Try 2: AVAudioFile decode → AAC encode
        do {
            let out = try Self.transcodeWithAudioFile(url)
            say("  AVAudioFile transcode: OK")
            return out
        } catch {
            let ns = error as NSError
            say("  AVAudioFile transcode failed: \(ns.domain) \(ns.code) \(ns.localizedDescription)")
            return nil
        }
    }

    private static func transcodeWithAudioFile(_ url: URL) throws -> URL {
        let input = try AVAudioFile(forReading: url)
        let fmt = input.processingFormat
        let out = tmp("m4a")
        try autoreleasepool {
            let output = try AVAudioFile(forWriting: out, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: min(fmt.sampleRate, 48000),
                AVNumberOfChannelsKey: min(fmt.channelCount, 2),
                AVEncoderBitRateKey: 128000,
            ], commonFormat: fmt.commonFormat, interleaved: fmt.isInterleaved)
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 32768) else { throw TestError("buffer alloc failed") }
            while input.framePosition < input.length {
                try input.read(into: buf)
                if buf.frameLength == 0 { break }
                try output.write(from: buf)
            }
        }
        return out
    }

    func togglePlay() {
        if isPlaying { stopPlayback(); return }
        guard let audioURL else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: audioURL)
            p.delegate = self
            p.play()
            player = p
            isPlaying = true
        } catch {
            say("Playback error: \(error.localizedDescription)")
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }

    // MARK: 3. Save sound copy

    func saveSoundCopy() async -> SavedAsset? {
        guard let asset = photoAsset, let data = imageData, let audio = audioURL else {
            say("Choose a photo and a sound first."); return nil
        }
        busy = true
        defer { busy = false }
        stopPlayback()
        say("\n=== Save sound copy — \(Date()) ===")
        say("photo: \(asset.localIdentifier)  sound: \(audio.lastPathComponent) \(String(format: "%.2f", audioDuration)) s  movie max side: \(movieMaxSide)")
        say(Mem.line("before build"))
        let baseDate = asset.creationDate ?? Date()
        let newDate = baseDate.addingTimeInterval(1)
        let loc = asset.location
        let saved = await buildAndSave(imageData: data, audioURL: audio, creationDate: newDate, location: loc,
                                       albumName: Self.albumName, code: "S", title: "Sound copy",
                                       filenameBase: "SoundPhoto_\(Int(Date().timeIntervalSince1970))")
        if let saved { result = saved }
        say("Original untouched: \(asset.localIdentifier)")
        return saved
    }

    /// Shared by the real-photo save and the long-audio check.
    private func buildAndSave(imageData: Data, audioURL: URL, creationDate: Date, location: CLLocation?,
                              albumName: String, code: String, title: String, filenameBase: String) async -> SavedAsset? {
        let id = UUID().uuidString
        let duration = await Self.inspect(audioURL).duration
        say("audio: \(String(format: "%.2f", duration)) s (\(Self.bucket(duration)))")
        let pair: LivePhotoPair
        do {
            let (p, notes) = try await LivePhotoBuilder.buildFromOriginal(imageData: imageData, audioURL: audioURL,
                                                                         identifier: id, creationDate: creationDate,
                                                                         maxMovieSide: movieMaxSide)
            pair = p
            for n in notes { say("  \(n)") }
            say("  built still \(Self.fileSize(p.stillURL)) + movie \(Self.fileSize(p.movieURL)) (\(String(format: "%.2f", p.duration)) s)")
            let mv = AVURLAsset(url: p.movieURL)
            let at = (try? await mv.loadTracks(withMediaType: .audio)) ?? []
            let vt = (try? await mv.loadTracks(withMediaType: .video)) ?? []
            let md = (try? await mv.load(.duration)).map(CMTimeGetSeconds) ?? 0
            var atDur = 0.0
            if let t = at.first, let r = try? await t.load(.timeRange) { atDur = CMTimeGetSeconds(r.duration) }
            say("  movie check: audio tracks=\(at.count) (audio \(String(format: "%.2f", atDur)) s), video tracks=\(vt.count), movie \(String(format: "%.2f", md)) s")
            if at.isEmpty || atDur <= 0 {
                say("  ABORT: the Live Photo movie has no audio — not saving.")
                setPasteStatus("Not saved: the built movie had no audio track — see log", error: true)
                return nil
            }
        } catch {
            say("BUILD FAILED (\(Self.bucket(duration))): \(error.localizedDescription)")
            return nil
        }
        let album = try? await Self.ensureAlbum(albumName)
        say("album \"\(albumName)\": \(album == nil ? "unavailable" : "ok")")
        let holder = IDHolder()
        let albumAdd = IDHolder()
        let stillExt = pair.stillURL.pathExtension.uppercased()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.creationDate = creationDate
                req.location = location
                let po = PHAssetResourceCreationOptions()
                po.originalFilename = "\(filenameBase).\(stillExt)"
                req.addResource(with: .photo, fileURL: pair.stillURL, options: po)
                let vo = PHAssetResourceCreationOptions()
                vo.originalFilename = "\(filenameBase).MOV"
                req.addResource(with: .pairedVideo, fileURL: pair.movieURL, options: vo)
                if let ph = req.placeholderForCreatedAsset {
                    holder.value = ph.localIdentifier
                    if let album, let add = PHAssetCollectionChangeRequest(for: album) {
                        add.addAssets([ph] as NSArray)
                        albumAdd.value = "requested"
                    }
                }
            }
            say("SAVE: SUCCESS (audio \(String(format: "%.1f", duration)) s, \(Self.bucket(duration)))")
        } catch {
            let ns = error as NSError
            say("SAVE FAILED (audio \(String(format: "%.1f", duration)) s, \(Self.bucket(duration))): domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription)")
            if !ns.userInfo.isEmpty { say("  userInfo: \(ns.userInfo)") }
            return nil
        }
        guard let newID = holder.value,
              let a = PHAsset.fetchAssets(withLocalIdentifiers: [newID], options: nil).firstObject else {
            say("Saved but could not read back."); return nil
        }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        say("new localIdentifier: \(newID)")
        say("isLive: \(a.mediaSubtypes.contains(.photoLive) ? "YES" : "NO")  size: \(a.pixelWidth)x\(a.pixelHeight)")
        say("creationDate: \(a.creationDate.map(df.string(from:)) ?? "nil")  location: \(a.location.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" } ?? "nil")")
        say(Mem.line("after save"))
        let res = PHAssetResource.assetResources(for: a)
        say("pairedVideo (sound movie) in saved asset: \(res.contains { $0.type == .pairedVideo } ? "YES" : "NO")")
        say("resources: \(PHAssetResource.assetResources(for: a).map { "\($0.type.rawValue):\($0.originalFilename)" }.joined(separator: ", "))")
        if let album {
            let o = PHFetchOptions(); o.predicate = NSPredicate(format: "localIdentifier == %@", newID)
            say("album add: \(albumAdd.value ?? "not attempted") → in album: \(PHAsset.fetchAssets(in: album, options: o).count > 0 ? "YES" : "NO")")
        }
        return SavedAsset(code: code, title: title, localIdentifier: newID, savedAt: Date())
    }

    static func ensureAlbum(_ name: String) async throws -> PHAssetCollection? {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "title = %@", name)
        if let found = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: opts).firstObject {
            return found
        }
        let holder = IDHolder()
        try await PHPhotoLibrary.shared().performChanges {
            holder.value = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                .placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let id = holder.value else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }

    static func fileSize(_ url: URL) -> String {
        let b = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }

    // MARK: 5. Long-audio check

    /// Saves the bundled test photo with looped voice audio of increasing lengths to find a limit.
    func longAudioCheck(lengths: [Double] = [30, 60, 120, 300]) async {
        busy = true
        defer { busy = false }
        say("\n=== Long-audio check — \(Date()) ===")
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { say("No Photos access."); return }
        guard let photoURL = Bundle.main.url(forResource: "test-photo", withExtension: "jpg"),
              let voiceURL = Bundle.main.url(forResource: "test-voice", withExtension: "m4a"),
              let photoData = try? Data(contentsOf: photoURL) else { say("bundled media missing"); return }
        var summary: [String] = []
        for len in lengths {
            say("\n--- \(Int(len)) s ---")
            guard let audio = await makeLoopedAudio(voiceURL, seconds: len) else {
                summary.append("\(Int(len)) s: audio build failed"); continue
            }
            let r = await buildAndSave(imageData: photoData, audioURL: audio, creationDate: Date(), location: nil,
                                       albumName: Self.testAlbumName, code: "L", title: "Long audio \(Int(len)) s",
                                       filenameBase: "SoundPhotoTest_L\(Int(len))")
            if let r {
                longResults.append(r)
                let live = PHAsset.fetchAssets(withLocalIdentifiers: [r.localIdentifier], options: nil).firstObject?
                    .mediaSubtypes.contains(.photoLive) ?? false
                summary.append("\(Int(len)) s: saved, live=\(live ? "YES" : "NO")")
            } else {
                summary.append("\(Int(len)) s: FAILED (see above)")
            }
        }
        say("\n=== Long-audio summary ===")
        for s in summary { say(s) }
        say("Open each in 'Long-audio results' (or Photos > album \"\(Self.testAlbumName)\") and press-and-hold: note seconds actually played.")
    }

    private func makeLoopedAudio(_ src: URL, seconds: Double) async -> URL? {
        do {
            let asset = AVURLAsset(url: src)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
            let d = try await asset.load(.duration)
            let comp = AVMutableComposition()
            guard let ct = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
            let target = CMTime(seconds: seconds, preferredTimescale: 600)
            var t = CMTime.zero
            while t < target {
                let seg = CMTimeMinimum(d, target - t)
                try ct.insertTimeRange(CMTimeRange(start: .zero, duration: seg), of: track, at: t)
                t = t + seg
            }
            guard let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetAppleM4A) else { return nil }
            let out = Self.tmp("m4a")
            ex.outputURL = out
            ex.outputFileType = .m4a
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                ex.exportAsynchronously { c.resume() }
            }
            guard ex.status == .completed else {
                say("looped audio export failed: \(ex.error?.localizedDescription ?? "status \(ex.status.rawValue)")"); return nil
            }
            return out
        } catch {
            say("looped audio error: \(error.localizedDescription)"); return nil
        }
    }

    func deleteLongResults() async {
        let ids = longResults.map(\.localIdentifier)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else { longResults = []; return }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets) }
            say("Deleted \(assets.count) long-audio test photos.")
            longResults = []
        } catch {
            say("Delete not done: \(error.localizedDescription)")
        }
    }
}
