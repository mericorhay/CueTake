import CoreImage
import Domain
import Foundation

/// The grades read from `.cube` files, kept ready between frames.
///
/// A cube is tens of thousands of numbers; parsing one per frame would stall the preview, and
/// parsing one per composition would do it again on every slider tick. So the file is read once
/// and its numbers are held until the project changes.
///
/// What is held is the data, not a filter: frames are composed on several threads at once, and a
/// shared `CIFilter` would have its input image set out from under it. Building the filter from
/// ready bytes costs nothing.
public final class ColorCubes: @unchecked Sendable {
    public static let shared = ColorCubes()

    public struct Ready: Sendable {
        public var size: Int
        public var data: Data
    }

    private let lock = NSLock()
    private var folder: URL?
    private var ready: [String: Ready] = [:]
    /// Files that turned out not to be readable cubes. Remembered so a bad file is not read from
    /// the disk again on every frame of the video it is on.
    private var refused: Set<String> = []

    /// Points at the folder the project keeps its media in. Changing it forgets what was loaded,
    /// because two projects can each have a file called the same thing.
    public func use(folder: URL?) {
        lock.withLock {
            guard self.folder != folder else { return }
            self.folder = folder
            ready.removeAll()
            refused.removeAll()
        }
    }

    /// Forgets one file, for when it has been taken off or replaced in place.
    public func forget(_ file: String) {
        lock.withLock {
            ready[file] = nil
            refused.remove(file)
        }
    }

    func cube(for table: LookUpTable) -> Ready? {
        lock.lock()
        if let made = ready[table.file] {
            lock.unlock()
            return made
        }
        if refused.contains(table.file) {
            lock.unlock()
            return nil
        }
        let root = folder
        lock.unlock()

        guard let root else { return nil }
        let name = table.file.hasPrefix("media/") ? String(table.file.dropFirst("media/".count)) : table.file
        let url = root.appending(path: name, directoryHint: .notDirectory)
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let cube = LookUpTable.parse(text),
              cube.values.count == cube.size * cube.size * cube.size * 4
        else {
            lock.withLock { refused.insert(table.file) }
            return nil
        }
        let made = Ready(size: cube.size, data: cube.values.withUnsafeBufferPointer { Data(buffer: $0) })
        lock.withLock { ready[table.file] = made }
        return made
    }
}
