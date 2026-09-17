import Domain
import Foundation
import MediaEngine

/// Grades brought in from outside: the `.cube` files people buy, or their agency sends them.
extension EditorModel {
    /// Copies a chosen `.cube` file in beside the footage and puts it on one filter.
    ///
    /// Copied rather than referenced: the file the user picked lives in another app's folder,
    /// which may be a download that is cleared, or a cloud file that is not there next week. A
    /// grade is part of the edit, so it travels with the project.
    @discardableResult
    public func useLookUpTable(at url: URL, on effect: TimelineEffect.ID) -> Bool {
        guard let mediaDirectory else { return false }
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        // Read before it is kept: a file that is not a cube should be refused while the user is
        // still looking at the picker, not silently do nothing to the picture later.
        guard let cube = LookUpTable.parse(text) else { return false }

        let name = url.deletingPathExtension().lastPathComponent
        let file = "lut-\(UUID().uuidString).cube"
        let destination = mediaDirectory.appending(path: file, directoryHint: .notDirectory)
        guard (try? text.write(to: destination, atomically: true, encoding: .utf8)) != nil else { return false }

        let table = LookUpTable(name: name.isEmpty ? file : name, file: "media/\(file)", size: cube.size)
        updateFilter(effect) { $0.lut = table }
        return true
    }

    public func removeLookUpTable(from effect: TimelineEffect.ID) {
        guard let file = effectValue(effect)?.filter?.lut?.file else { return }
        updateFilter(effect) { $0.lut = nil }
        ColorCubes.shared.forget(file)
    }

    func effectValue(_ id: TimelineEffect.ID) -> TimelineEffect? {
        project.effects.first { $0.id == id }
    }
}
