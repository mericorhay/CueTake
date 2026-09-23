import AVFoundation
import Domain
import Foundation
import Speech

/// Which language someone speaks in a file, heard on the phone.
///
/// Imported footage says nothing about its language, and listening to English with a Turkish
/// recogniser gives half the words, most of them wrong. So the opening stretch is heard once in
/// each likely language, and the recogniser that is surest of what it heard wins. A wrong-language
/// recogniser still writes words, but few, and with low confidence.
public enum SpokenLanguage {
    /// The candidate that heard the sample best, or nil when none heard anything.
    ///
    /// The first candidate is the current guess; another one has to do clearly better to replace it.
    public static func detect(in url: URL, candidates: [String], sampleSeconds: Double = 35) async -> String? {
        let candidates = unique(candidates)
        guard candidates.count > 1 else { return candidates.first }
        guard let audio = try? await SystemSpeechTranscriber.audioFile(for: url),
              let sample = try? await Self.sample(of: audio, seconds: sampleSeconds)
        else { return nil }
        defer { try? FileManager.default.removeItem(at: sample) }

        var scores: [(code: String, score: Double)] = []
        for code in candidates {
            guard let transcript = try? await LegacySpeech.transcribeFile(at: sample, localeIdentifier: code) else { continue }
            scores.append((code, score(transcript.words)))
        }
        guard let best = scores.max(by: { $0.score < $1.score }), best.score > 0 else { return nil }
        let current = scores.first { $0.code == candidates[0] }?.score ?? 0
        // Close calls keep the current guess: switching languages on a coin flip is worse than not.
        return best.score > current * 1.25 ? best.code : candidates[0]
    }

    /// How sure a recogniser was, summed over its words: many words heard confidently scores high.
    static func score(_ words: [TimedWord]) -> Double {
        let confidences = words.compactMap(\.confidence)
        let total = confidences.reduce(0, +)
        // Some results come back without confidences; then the number of words is the evidence.
        return total > 0 ? total : Double(words.count) * 0.3
    }

    /// Candidates by language, first spelling kept, at most four so detection stays quick.
    static func unique(_ codes: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for code in codes where !code.isEmpty {
            let language = Locale(identifier: code).language.languageCode?.identifier ?? code
            guard seen.insert(language).inserted else { continue }
            result.append(code)
        }
        return Array(result.prefix(4))
    }

    /// The opening seconds of an audio file, as a file of their own.
    static func sample(of audioURL: URL, seconds: Double) async throws -> URL {
        let asset = AVURLAsset(url: audioURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw SpeechError.noAudio
        }
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "language-\(UUID().uuidString).m4a", directoryHint: .notDirectory)
        session.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: seconds, preferredTimescale: 600))
        try await session.export(to: destination, as: .m4a)
        return destination
    }
}
