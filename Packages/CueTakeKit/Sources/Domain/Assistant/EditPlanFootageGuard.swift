import Foundation

extension EditPlan {
    /// Whether an instruction asks for footage to go: cut, shorten, pauses, fillers.
    ///
    /// The footage is the creator's. "Make it more energetic" used to come back with every pause
    /// trimmed, and a 2:57 video came out 2:08 without anyone asking for it. Only a request that
    /// talks about cutting may take anything out. Words are matched from their start, so "herkes"
    /// is not "kes" and "clean the audio" is not a cut.
    public static func asksToCut(_ instruction: String) -> Bool {
        let text = instruction.lowercased()
        let stems = [
            // Turkish
            "kes", "kısalt", "kırp", "boşluk", "sessiz", "duraksa", "duraklama", "ııı", "eee", "doldurma",
            "gereksiz", "sil", "çıkar", "sıkılaştır",
            // English
            "cut", "trim", "shorten", "shorter", "pause", "silence", "filler", "tighten", "remove", "delete",
            "gap",
            // Spanish
            "cort", "recort", "acort", "pausa", "silencio", "muletilla", "quita", "elimina", "hueco",
        ]
        let words = text.split { !$0.isLetter }
        if words.contains(where: { word in stems.contains { word.hasPrefix($0) } }) { return true }
        // Whole words only: "umut" is not "um".
        if words.contains(where: { ["um", "ums", "uh", "uhs"].contains(String($0)) }) { return true }
        return text.contains("dead air")
    }

    /// The operations that take footage out of the video.
    public static func removesFootage(_ operation: Operation) -> Bool {
        switch operation {
        case .cut, .removeWords, .trimPauses, .trimClip, .deleteClip: true
        default: false
        }
    }

    /// The plan without footage cuts, unless `instruction` asked for them.
    public func keepingFootage(unlessAskedIn instruction: String) -> EditPlan {
        guard !Self.asksToCut(instruction) else { return self }
        var kept = self
        kept.operations = operations.filter { !Self.removesFootage($0) }
        return kept
    }
}
