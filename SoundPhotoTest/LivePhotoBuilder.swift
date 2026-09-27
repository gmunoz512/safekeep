import AVFoundation
import CoreMedia
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import UIKit

struct LivePhotoPair {
    let stillURL: URL
    let movieURL: URL
    let duration: Double
    let identifier: String
}

/// Builds a Live Photo resource pair from bundled test media:
/// - still JPEG with Apple MakerNote key 17 = content identifier
/// - frozen-frame MOV with QuickTime metadata com.apple.quicktime.content.identifier = same value,
///   a timed metadata track com.apple.quicktime.still-image-time, and the voice clip as its audio track.
enum LivePhotoBuilder {

    static func build(identifier: String, maxDuration: Double?, includeStillImageTime: Bool = true,
                      stillIdentifier: String? = nil, heicStill: Bool = false) async throws -> LivePhotoPair {
        guard let photoURL = Bundle.main.url(forResource: "test-photo", withExtension: "jpg"),
              let audioURL = Bundle.main.url(forResource: "test-voice", withExtension: "m4a") else {
            throw TestError("Bundled test media missing.")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("soundphoto-\(identifier)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stillURL = dir.appendingPathComponent(heicStill ? "SoundPhoto.HEIC" : "SoundPhoto.JPG")
        let movieURL = dir.appendingPathComponent("SoundPhoto.MOV")

        let image = try writeStill(from: photoURL, to: stillURL, identifier: stillIdentifier ?? identifier, heic: heicStill)

        let audioAsset = AVURLAsset(url: audioURL)
        var duration = try await audioAsset.load(.duration)
        if let maxDuration {
            duration = CMTimeMinimum(duration, CMTime(seconds: maxDuration, preferredTimescale: 600))
        }
        try await writeMovie(image: image, audio: audioAsset, duration: duration,
                             to: movieURL, identifier: identifier,
                             includeStillImageTime: includeStillImageTime)
        return LivePhotoPair(stillURL: stillURL, movieURL: movieURL,
                             duration: duration.seconds, identifier: identifier)
    }

    // MARK: Still image

    private static func writeStill(from source: URL, to dest: URL, identifier: String, heic: Bool) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw TestError("Could not read bundled photo.")
        }
        var props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]) ?? [:]
        props[kCGImagePropertyMakerAppleDictionary as String] = ["17": identifier]
        props[kCGImageDestinationLossyCompressionQuality as String] = 0.95
        guard let out = CGImageDestinationCreateWithURL(dest as CFURL, (heic ? UTType.heic : UTType.jpeg).identifier as CFString, 1, nil) else {
            throw TestError("Could not create JPEG destination.")
        }
        CGImageDestinationAddImage(out, image, props as CFDictionary)
        guard CGImageDestinationFinalize(out) else { throw TestError("Could not write still image.") }
        return image
    }

    // MARK: Movie

    private static func writeMovie(image: CGImage, audio: AVURLAsset, duration: CMTime,
                                   to url: URL, identifier: String,
                                   includeStillImageTime: Bool) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        // Top-level content identifier (must match the still's MakerNote key 17)
        let idItem = AVMutableMetadataItem()
        idItem.keySpace = .quickTimeMetadata
        idItem.key = "com.apple.quicktime.content.identifier" as NSString
        idItem.value = identifier as NSString
        idItem.dataType = kCMMetadataBaseDataType_UTF8 as String
        writer.metadata = [idItem]

        // Video: same frame for the whole duration
        let width = 1920
        let height = Int((Double(width) * Double(image.height) / Double(image.width) / 2).rounded()) * 2
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        videoInput.expectsMediaDataInRealTime = false
        let pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(videoInput)

        // Timed metadata track: still-image-time
        let spec: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
                "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
                kCMMetadataBaseDataType_SInt8 as String,
        ]
        var metaDesc: CMFormatDescription?
        let st = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [spec] as CFArray, formatDescriptionOut: &metaDesc)
        guard st == noErr, let metaDesc else { throw TestError("Metadata format description failed (\(st)).") }
        let metaInputOpt: AVAssetWriterInput? = includeStillImageTime ? AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: metaDesc) : nil
        let metaAdaptor = metaInputOpt.map { AVAssetWriterInputMetadataAdaptor(assetWriterInput: $0) }
        if let metaInputOpt { writer.add(metaInputOpt) }

        // Audio: voice clip passed through unchanged (AAC)
        guard let audioTrack = try await audio.loadTracks(withMediaType: .audio).first else {
            throw TestError("Bundled audio has no audio track.")
        }
        let audioFormat = try await audioTrack.load(.formatDescriptions).first
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormat)
        audioInput.expectsMediaDataInRealTime = false
        writer.add(audioInput)

        let reader = try AVAssetReader(asset: audio)
        reader.timeRange = CMTimeRange(start: .zero, duration: duration)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        reader.add(readerOutput)

        guard writer.startWriting() else { throw writer.error ?? TestError("startWriting failed.") }
        guard reader.startReading() else { throw reader.error ?? TestError("startReading failed.") }
        writer.startSession(atSourceTime: .zero)

        // still-image-time sample at t=0
        let stillItem = AVMutableMetadataItem()
        stillItem.keySpace = .quickTimeMetadata
        stillItem.key = "com.apple.quicktime.still-image-time" as NSString
        stillItem.value = NSNumber(value: Int8(-1))
        stillItem.dataType = kCMMetadataBaseDataType_SInt8 as String
        let metaGroup = AVTimedMetadataGroup(items: [stillItem],
                                             timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 30)))
        if let metaAdaptor {
            guard metaAdaptor.append(metaGroup) else { throw writer.error ?? TestError("Could not append still-image-time.") }
            metaAdaptor.assetWriterInput.markAsFinished()
        }

        guard let buffer = try makePixelBuffer(image: image, pool: pixelAdaptor.pixelBufferPool,
                                               width: width, height: height) else {
            throw TestError("Could not create pixel buffer.")
        }

        let fps: Int32 = 30
        let frameCount = max(2, Int((duration.seconds * Double(fps)).rounded(.up)))
        let counter = FrameCounter()
        let group = DispatchGroup()

        group.enter()
        videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "video")) {
            while videoInput.isReadyForMoreMediaData {
                if counter.value >= frameCount ||
                    !pixelAdaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(counter.value), timescale: fps)) {
                    videoInput.markAsFinished(); group.leave(); return
                }
                counter.value += 1
            }
        }

        group.enter()
        audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio")) {
            while audioInput.isReadyForMoreMediaData {
                guard let sample = readerOutput.copyNextSampleBuffer(), audioInput.append(sample) else {
                    audioInput.markAsFinished(); group.leave(); return
                }
            }
        }

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) { c.resume() }
        }
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? TestError("Movie writing failed.") }
    }

    private static func makePixelBuffer(image: CGImage, pool: CVPixelBufferPool?,
                                        width: Int, height: Int) throws -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        if let pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) }
        if pb == nil {
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                [kCVPixelBufferCGImageCompatibilityKey: true,
                                 kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &pb)
        }
        guard let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pb
    }

    // MARK: Pre-save self check

    static func verify(_ pair: LivePhotoPair) async throws -> [String] {
        var out: [String] = []
        if let src = CGImageSourceCreateWithURL(pair.stillURL as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
           let apple = props[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] {
            let v = apple["17"] as? String
            out.append("still MakerApple[17] = \(v ?? "missing") \(v == pair.identifier ? "(match)" : "(MISMATCH)")")
        } else {
            out.append("still MakerApple dictionary MISSING")
        }
        let asset = AVURLAsset(url: pair.movieURL)
        let meta = try await asset.load(.metadata)
        var movieID: String?
        for item in meta where item.identifier == .quickTimeMetadataContentIdentifier {
            movieID = try await item.load(.stringValue)
        }
        out.append("movie content.identifier = \(movieID ?? "missing") \(movieID == pair.identifier ? "(match)" : "(MISMATCH)")")
        let v = try await asset.loadTracks(withMediaType: .video).count
        let a = try await asset.loadTracks(withMediaType: .audio).count
        let m = try await asset.loadTracks(withMediaType: .metadata).count
        out.append("movie tracks: video=\(v) audio=\(a) metadata=\(m)")
        return out
    }
}

final class FrameCounter: @unchecked Sendable { var value = 0 }
