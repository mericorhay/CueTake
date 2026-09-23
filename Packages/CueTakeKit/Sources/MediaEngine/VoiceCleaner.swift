import AVFoundation
import Domain
import Foundation

/// Cleans the voice inside the footage itself.
///
/// The repair filters used to reach only audio added on top — music, voiceovers — and never the
/// thing that most needs them: the person talking in the clip, recorded on a phone in a room.
///
/// A video file cannot be put through an audio engine directly, so this does it in two cached
/// steps: the recording's sound is copied out to an m4a once, and that is filtered once per
/// combination of switches. The composer then plays the cleaned sound against the original
/// picture. Both files keep the recording's own timeline, so every trim, split and take range
/// still points at the same moment in them. Nothing is written over the original.
public struct VoiceCleaner: Sendable {
    public init() {}

    private func cleanedURL(for recording: Recording, effects: AudioEffects, in directory: URL) -> URL {
        directory.appending(
            path: "\(recording.id.uuidString)-voice-\(AudioEffectRenderer.token(for: effects)).m4a",
            directoryHint: .notDirectory
        )
    }

    /// Whether any recording still has to be processed. For deciding whether to tell the user to
    /// wait — a cached clean costs nothing, and a wait message for nothing is noise.
    public func needsWork(for recordings: [Recording], effects: AudioEffects, in directory: URL) -> Bool {
        guard effects.isActive else { return false }
        return recordings.contains {
            !AudioRenderCache.isUsable(cleanedURL(for: $0, effects: effects, in: directory))
        }
    }

    /// The cleaned voice only if it is already made: for a preview that must not wait for it.
    public func cachedAudio(for recording: Recording, effects: AudioEffects, in directory: URL) -> URL? {
        guard effects.isActive else { return nil }
        let cleaned = cleanedURL(for: recording, effects: effects, in: directory)
        return AudioRenderCache.isUsable(cleaned) ? cleaned : nil
    }

    /// The cleaned voice for a recording, or nil when it cannot be produced — in which case the
    /// composer keeps the original sound rather than dropping it.
    public func cleanedAudio(for recording: Recording, effects: AudioEffects, in directory: URL) async -> URL? {
        guard effects.isActive else { return nil }

        let cleaned = cleanedURL(for: recording, effects: effects, in: directory)
        if AudioRenderCache.isUsable(cleaned) {
            return cleaned
        }

        guard let extracted = await Self.extractedVoice(for: recording, in: directory) else { return nil }

        return await Task.detached(priority: .userInitiated) {
            try? AudioEffectRenderer.render(extracted, to: cleaned, effects: effects)
        }.value
    }

    /// The recording's sound as an m4a, copied out of its video the first time anyone asks.
    static func extractedVoice(for recording: Recording, in directory: URL) async -> URL? {
        let extracted = directory.appending(path: "\(recording.id.uuidString)-voice.m4a", directoryHint: .notDirectory)
        if AudioRenderCache.isUsable(extracted) {
            return extracted
        }
        let source = directory.appending(
            path: (recording.relativePath as NSString).lastPathComponent,
            directoryHint: .notDirectory
        )
        return await extract(from: source, to: extracted) ? extracted : nil
    }

    /// Copies a video's sound out to an m4a. No re-encode of the picture — there is no picture.
    private static func extract(from source: URL, to destination: URL) async -> Bool {
        let partial = AudioRenderCache.partialURL(for: destination)
        defer { try? FileManager.default.removeItem(at: partial) }
        let asset = AVURLAsset(url: source)
        guard (try? await asset.loadTracks(withMediaType: .audio).first) != nil,
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else { return false }
        do {
            try await session.export(to: partial, as: .m4a)
            guard AudioRenderCache.isUsable(partial) else { return false }
            _ = try AudioRenderCache.publish(partial, to: destination)
            return AudioRenderCache.isUsable(destination)
        } catch {
            return false
        }
    }
}
