import AVFoundation
import Foundation

/// One asset per file, kept between builds of the composition.
///
/// The preview is rebuilt on every edit, and each build asked every clip's file for its tracks,
/// size and orientation again. An asset remembers what it has loaded, so on a project of fifty
/// clips reusing it turns fifty file reads per edit into none. A file written again (a reversed or
/// processed copy) is a new asset.
final class AssetCache: @unchecked Sendable {
    static let shared = AssetCache()

    private struct Entry {
        var asset: AVURLAsset
        var stamp: Date?
        var size: Int?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private let limit = 300

    func asset(for url: URL) -> AVURLAsset {
        let key = url.standardizedFileURL.path(percentEncoded: false)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let stamp = values?.contentModificationDate
        let size = values?.fileSize
        return lock.withLock {
            if let entry = entries[key], entry.stamp == stamp, entry.size == size {
                return entry.asset
            }
            if entries.count >= limit { entries.removeAll(keepingCapacity: true) }
            let asset = AVURLAsset(url: url)
            entries[key] = Entry(asset: asset, stamp: stamp, size: size)
            return asset
        }
    }
}
