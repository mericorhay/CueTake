import AVFoundation
import Domain
import Foundation

/// Cleans up a piece of audio before anything else hears it.
///
/// This is filtering, not a learned denoiser, and the comments say so rather than the marketing:
/// a fixed curve cannot separate a voice from a siren. What it can do is take out the two things
/// that actually ruin phone audio — rumble under the voice and hiss above it — and lift the band
/// the consonants live in. That is most of what "reduce noise" buys anyone, at no model, no
/// upload, and no wait.
///
/// The result is cached beside the original under a name derived from the settings, so toggling an
/// effect off and on again costs nothing and the original is never overwritten. Nothing in this
/// app destroys the file the user gave it.
public struct AudioEffectRenderer: Sendable {
    public init() {}

    /// The file that should actually be played for this clip.
    ///
    /// Returns the original untouched when no effect is on, which is the common case and has to
    /// stay free.
    public func source(for clip: AudioClip, in mediaDirectory: URL) async -> URL {
        let original = mediaDirectory.appending(
            path: (clip.relativePath as NSString).lastPathComponent,
            directoryHint: .notDirectory
        )
        guard clip.effects.isActive else { return original }

        let destination = mediaDirectory.appending(
            path: "\(clip.id.uuidString)-\(Self.token(for: clip.effects)).m4a",
            directoryHint: .notDirectory
        )
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            return destination
        }

        let effects = clip.effects
        // Detached because this is seconds of real arithmetic on whoever calls it, and the caller
        // is usually the main actor getting playback ready.
        let rendered = await Task.detached(priority: .userInitiated) {
            try? Self.render(original, to: destination, effects: effects)
        }.value
        return rendered ?? original
    }

    /// The cache name. Changing which effects are on changes the file, so a stale render can never
    /// be mistaken for a fresh one.
    static func token(for effects: AudioEffects) -> String {
        var flags = ""
        flags += effects.noiseReduction ? "n" : ""
        flags += effects.voiceEnhance ? "v" : ""
        flags += effects.deRumble ? "r" : ""
        return flags.isEmpty ? "dry" : flags
    }

    enum RenderError: Error {
        case noBuffer
    }

    /// Offline render through an EQ. Manual rendering mode rather than playback: this runs as fast
    /// as the CPU allows instead of in real time, which is the difference between a two second wait
    /// and a three minute one on a three minute song.
    static func render(_ source: URL, to destination: URL, effects: AudioEffects) throws -> URL {
        try? FileManager.default.removeItem(at: destination)

        let file = try AVAudioFile(forReading: source)
        let format = file.processingFormat

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 4)
        configure(eq, with: effects)

        engine.attach(player)
        engine.attach(eq)
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        player.scheduleFile(file, at: nil)
        try engine.start()
        player.play()

        // AAC in an m4a rather than the source's own format: the source may be an mp3, and nothing
        // on the system writes those. Compressed because an eight minute uncompressed cache entry
        // is a hundred megabytes of someone's phone for no gain anyone can hear.
        let output = try AVAudioFile(
            forWriting: destination,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
            ]
        )

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else {
            engine.stop()
            engine.disableManualRenderingMode()
            throw RenderError.noBuffer
        }

        while engine.manualRenderingSampleTime < file.length {
            let remaining = file.length - engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(min(Int64(buffer.frameCapacity), remaining))
            let status = try engine.renderOffline(frames, to: buffer)
            guard status == .success else { break }
            try output.write(from: buffer)
        }

        player.stop()
        engine.stop()
        engine.disableManualRenderingMode()
        return destination
    }

    /// Four bands, each earning its place.
    ///
    /// Bands that are not asked for are bypassed rather than set flat: a band at zero gain still
    /// has a phase response, and four of them stacked is an audible smear on material that was
    /// supposed to be left alone.
    static func configure(_ eq: AVAudioUnitEQ, with effects: AudioEffects) {
        let bands = eq.bands

        // Handling, traffic, air conditioning. Nothing musical lives at 85 Hz on a phone.
        bands[0].filterType = .highPass
        bands[0].frequency = 85
        bands[0].bypass = !(effects.deRumble || effects.noiseReduction)

        // Mains hum and the boxiness of a small room.
        bands[1].filterType = .parametric
        bands[1].frequency = 180
        bands[1].bandwidth = 1.2
        bands[1].gain = -4
        bands[1].bypass = !effects.noiseReduction

        // Hiss: preamp noise, compression artefacts, the air in a quiet room.
        bands[2].filterType = .highShelf
        bands[2].frequency = 7500
        bands[2].gain = -7
        bands[2].bypass = !effects.noiseReduction

        // Consonants. This is the band that decides whether a voice is understood on a phone
        // speaker in a noisy room, which is where this video is going to be watched.
        bands[3].filterType = .parametric
        bands[3].frequency = 3200
        bands[3].bandwidth = 1.1
        bands[3].gain = 4
        bands[3].bypass = !effects.voiceEnhance

        // Filtering takes energy out; without this, "clean it up" also means "make it quieter",
        // and people read quieter as worse.
        eq.globalGain = effects.noiseReduction ? 2 : 0
    }
}
