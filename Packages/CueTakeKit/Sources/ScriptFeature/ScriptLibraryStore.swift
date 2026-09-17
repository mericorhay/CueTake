import Domain
import Foundation
import Observation

/// Scripts kept for reuse and the brand voice the AI writes in, kept on this phone.
@MainActor
@Observable
public final class ScriptLibraryStore {
    private struct Stored: Codable {
        var scripts: [SavedScript]
        var brand: BrandVoice
        var usesBrand: Bool
    }

    public private(set) var scripts: [SavedScript] = []
    public private(set) var brand = BrandVoice()
    /// Whether scripts the AI writes use the brand voice.
    public private(set) var usesBrand = true

    public static let limit = 50
    private let defaults: UserDefaults?
    static let key = "script.library.v1"

    public init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            scripts = stored.scripts
            brand = stored.brand
            usesBrand = stored.usesBrand
        }
    }

    /// The voice to write in, when there is one and it is switched on.
    public var activeBrand: BrandVoice? {
        usesBrand && !brand.isEmpty ? brand : nil
    }

    /// Keeps a script. The same text saved again moves to the top instead of appearing twice.
    @discardableResult
    public func save(_ text: String, title: String? = nil) -> SavedScript? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        var entry = scripts.first { $0.text == clean }
            ?? SavedScript(title: "", text: clean)
        entry.title = (name?.isEmpty == false ? name : nil) ?? (entry.title.isEmpty ? SavedScript.title(for: clean) : entry.title)
        entry.updatedAt = .now
        scripts.removeAll { $0.id == entry.id }
        scripts.insert(entry, at: 0)
        if scripts.count > Self.limit { scripts.removeLast(scripts.count - Self.limit) }
        persist()
        return entry
    }

    /// Marks a script as just used, so the ones in use stay first.
    public func touch(_ id: SavedScript.ID) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        var entry = scripts.remove(at: index)
        entry.updatedAt = .now
        scripts.insert(entry, at: 0)
        persist()
    }

    public func delete(_ id: SavedScript.ID) {
        scripts.removeAll { $0.id == id }
        persist()
    }

    public func setBrand(_ voice: BrandVoice) {
        brand = voice
        persist()
    }

    public func setUsesBrand(_ on: Bool) {
        usesBrand = on
        persist()
    }

    private func persist() {
        guard let defaults else { return }
        let stored = Stored(scripts: scripts, brand: brand, usesBrand: usesBrand)
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

extension Project {
    /// The whole script as one text, a blank line between beats — the shape a pasted script takes.
    public var scriptText: String {
        segments
            .map { $0.script.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
