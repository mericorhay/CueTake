import Domain
import Foundation

extension EditorModel {
    /// The plan without the operations that would add again what the video already has.
    ///
    /// The AI works in two passes, and the second is shown the video after the first and told not
    /// to repeat itself. Weaker models did anyway: the same title twice over the same seconds, the
    /// same look laid on the same stretch again. The same happened when "Try again" re-ran a
    /// request that had already landed. A title or a look that is already there is not added twice.
    ///
    /// Nor are the captions: text that says what is being said, where captions already show it,
    /// is a second set of captions stacked on the first. A short quote as a title now and then is
    /// kept; sentences, or more quotes than one every fifteen seconds, are not.
    func withoutRepeats(_ plan: EditPlan) -> EditPlan {
        var kept = plan
        let cues = project.captionCues
        var quotes = project.overlays.filter { overlay in
            guard case .text(let existing) = overlay.content else { return false }
            return Self.repeatsSpeech(existing.text, from: overlay.start.seconds, length: overlay.duration.seconds, cues: cues)
        }.count
        let quoteLimit = max(1, Int(duration / 15))
        kept.operations = plan.operations.filter { operation in
            if repeatsWhatIsThere(operation) { return false }
            if case .addText(let patch) = operation, let text = patch.text {
                let start = patch.start ?? 0
                let length = patch.duration ?? max(0.5, (patch.end ?? start + 2) - start)
                if Self.repeatsSpeech(text, from: start, length: length, cues: cues) {
                    guard Self.plain(text).split(separator: " ").count <= 6, quotes < quoteLimit else { return false }
                    quotes += 1
                }
            }
            return true
        }
        return kept
    }

    private func repeatsWhatIsThere(_ operation: EditPlan.Operation) -> Bool {
        switch operation {
        case .addText(let patch):
            guard let text = patch.text.map(Self.plain), !text.isEmpty else { return false }
            let start = patch.start ?? 0
            return project.overlays.contains { overlay in
                guard case .text(let existing) = overlay.content, Self.plain(existing.text) == text else { return false }
                let from = overlay.start.seconds
                let to = from + overlay.duration.seconds
                return abs(from - start) < 1.5 || (start >= from && start < to)
            }
        case .setFilter(let request):
            guard let look = request.look?.lowercased(), let from = request.from else { return false }
            let to = max(request.to ?? from, from + 0.1)
            return project.effects.contains { effect in
                guard let filter = effect.filter, filter.look.rawValue.lowercased() == look else { return false }
                return effect.start.seconds < to && from < effect.end
            }
        default:
            return false
        }
    }

    /// Whether a text mostly says the words the captions show around that moment.
    static func repeatsSpeech(_ text: String, from start: Double, length: Double, cues: [PlacedCue]) -> Bool {
        let words = Set(plain(text).split(separator: " "))
        guard words.count >= 2 else { return false }
        let near = cues.filter { $0.range.start.seconds < start + length + 1.5 && start - 1.5 < $0.range.end.seconds }
        guard !near.isEmpty else { return false }
        let spoken = Set(near.flatMap { plain($0.text).split(separator: " ") })
        let shared = words.filter { spoken.contains($0) }.count
        return Double(shared) / Double(words.count) >= 0.6
    }

    /// Text compared the way a person would: case, spacing and punctuation aside.
    static func plain(_ text: String) -> String {
        text.lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(separator: " ")
            .joined(separator: " ")
    }
}
