import Domain
import Foundation

extension EditorModel {
    /// The plan without the operations that would add again what the video already has.
    ///
    /// The AI works in two passes, and the second is shown the video after the first and told not
    /// to repeat itself. Weaker models did anyway: the same title twice over the same seconds, the
    /// same look laid on the same stretch again. The same happened when "Try again" re-ran a
    /// request that had already landed. A title or a look that is already there is not added twice.
    func withoutRepeats(_ plan: EditPlan) -> EditPlan {
        var kept = plan
        kept.operations = plan.operations.filter { !repeatsWhatIsThere($0) }
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

    /// Text compared the way a person would: case, spacing and punctuation aside.
    private static func plain(_ text: String) -> String {
        text.lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(separator: " ")
            .joined(separator: " ")
    }
}
