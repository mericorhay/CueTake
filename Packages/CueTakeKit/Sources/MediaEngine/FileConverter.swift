import AVFoundation
import CoreServices
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns one file into another format.
///
/// Every part of this is already on the phone: ImageIO reads and writes every image format iOS
/// knows, and `AVAssetExportSession` rewrites a container without touching the picture when the
/// codecs already fit. Reaching for a third-party library here would mean shipping a second copy
/// of what the system does, and shipping its bugs.
///
/// One thing worth being honest about: **jpg and jpeg are the same format.** A file that will not
/// open "because it is a .jpeg" needs renaming, not converting, so that case costs a copy and no
/// re-encode at all.
public struct FileConverter: Sendable {
    public init() {}

    public enum Target: String, CaseIterable, Sendable, Hashable {
        case jpg
        case png
        case heic
        case mp4
        case mov
        case m4a

        public var isImage: Bool {
            self == .jpg || self == .png || self == .heic
        }

        public var label: String {
            switch self {
            case .jpg: "JPG"
            case .png: "PNG"
            case .heic: "HEIC"
            case .mp4: "MP4"
            case .mov: "MOV"
            case .m4a: "M4A"
            }
        }

        var imageType: UTType {
            switch self {
            case .png: .png
            case .heic: .heic
            default: .jpeg
            }
        }

        var fileType: AVFileType {
            switch self {
            case .mov: .mov
            case .m4a: .m4a
            default: .mp4
            }
        }
    }

    public enum ConvertError: Error, Hashable, Sendable {
        case unreadable
        case unsupported
        case failed(String)
    }

    /// Converts `source` and returns the new file.
    ///
    /// Written into `directory` under the original name with a new extension, because the name is
    /// the only part of a file anybody recognises.
    public func convert(_ source: URL, to target: Target, in directory: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let name = source.deletingPathExtension().lastPathComponent
        let destination = directory.appending(
            path: "\(name).\(target.rawValue)",
            directoryHint: .notDirectory
        )
        try? FileManager.default.removeItem(at: destination)

        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        if target.isImage {
            try Self.convertImage(source, to: destination, type: target.imageType)
        } else {
            try await Self.convertMedia(source, to: destination, type: target.fileType)
        }
        return destination
    }

    /// What a file can sensibly become. Offering MP4 for a photo is an option that can only fail.
    public static func targets(for source: URL) -> [Target] {
        let type = UTType(filenameExtension: source.pathExtension.lowercased())
        if type?.conforms(to: .image) == true {
            return [.jpg, .png, .heic]
        }
        if type?.conforms(to: .audio) == true {
            return [.m4a]
        }
        if type?.conforms(to: .audiovisualContent) == true {
            return [.mp4, .mov, .m4a]
        }
        return Target.allCases
    }

    private static func convertImage(_ source: URL, to destination: URL, type: UTType) throws {
        guard let reader = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(reader, 0, nil)
        else { throw ConvertError.unreadable }

        guard let writer = CGImageDestinationCreateWithURL(
            destination as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else { throw ConvertError.unsupported }

        // 0.9 rather than 1: the last tenth of JPEG quality is most of the file and none of the
        // picture. Ignored by PNG, which is lossless and has no opinion.
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else {
            throw ConvertError.failed("write")
        }
    }

    private static func convertMedia(_ source: URL, to destination: URL, type: AVFileType) async throws {
        let asset = AVURLAsset(url: source)

        // Passthrough first. Most "convert this to MP4" is a container change — the H.264 inside
        // an MOV is the same H.264 an MP4 wants — and passthrough does it in a second without
        // touching a single frame. Re-encoding is the fallback, not the plan.
        let presets = type == .m4a
            ? [AVAssetExportPresetAppleM4A]
            : [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]

        var lastError: String = "no session"
        for preset in presets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            guard await session.supportedFileTypes.contains(type) else {
                lastError = "format"
                continue
            }
            do {
                try await session.export(to: destination, as: type)
                return
            } catch {
                lastError = error.localizedDescription
                try? FileManager.default.removeItem(at: destination)
            }
        }
        throw ConvertError.failed(lastError)
    }
}
