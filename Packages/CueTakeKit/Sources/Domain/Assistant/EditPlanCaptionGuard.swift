import Foundation

extension EditPlan {
    /// Whether an instruction is about the captions' words: the only time the AI may change them.
    ///
    /// Captions are what the creator said, or what they typed to fix it. "Make it more energetic"
    /// used to come back with reworded, merged or deleted captions nobody asked for.
    public static func asksAboutCaptions(_ instruction: String) -> Bool {
        let text = instruction.lowercased()
        let words = [
            // Turkish
            "altyaz", "yazı", "yazıy", "yazıl", "yazım", "metin", "metni", "kelime",
            // English
            "caption", "subtitle", "typo", "spelling", "on-screen text", "on screen text", "transcript",
            // Spanish
            "subtít", "subtit", "texto", "rótulo", "ortograf",
        ]
        return words.contains { text.contains($0) }
    }

    /// The operations that change the captions' words or their timing.
    public static func changesCaptionWords(_ operation: Operation) -> Bool {
        switch operation {
        case .setCaptionText, .captionTiming, .splitCaption, .mergeCaption, .removeCaption, .shiftCaptions: true
        default: false
        }
    }

    /// The plan without its caption-word changes, unless `instruction` asked for them.
    public func keepingCaptions(unlessAskedIn instruction: String) -> EditPlan {
        guard !Self.asksAboutCaptions(instruction) else { return self }
        var kept = self
        kept.operations = operations.filter { !Self.changesCaptionWords($0) }
        return kept
    }
}
