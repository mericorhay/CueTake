import AVFoundation
import Domain
import Foundation

/// The voice of a recording through a sound effect: echo, a hall, a telephone, a robot, a deeper or
/// higher voice.
///
/// Built from the system's own audio units — reverb, delay, distortion, EQ and time-pitch — run
/// offline, as fast as the processor allows. The whole recording is rendered once per setting and
/// kept beside it on the recording's own clock, so any stretch of any clip cut from it can be
/// played from the effect file with the same numbers it would use for the original.
public struct SoundEffectRenderer: Sendable {
    public init() {}

    /// The effect file for a recording, rendering it the first time. Nil when it cannot be made, in
    /// which case the voice plays as recorded.
    ///
    /// - Parameter voice: the sound the effect is applied to — the recording's own, or its cleaned
    ///   copy when voice repair is on.
    public func rendered(
        _ settings: SoundSettings,
        recording: Recording,
        voice: URL,
        voiceToken: String,
        in directory: URL
    ) async -> URL? {
        guard settings.needsRender else { return nil }
        let destination = directory.appending(
            path: "\(recording.id.uuidString)-sfx-\(voiceToken)-\(settings.token).m4a",
            directoryHint: .notDirectory
        )
        if AudioRenderCache.isUsable(destination) {
            return destination
        }
        return await Task.detached(priority: .userInitiated) {
            try? Self.render(voice, to: destination, settings: settings)
        }.value
    }

    enum RenderError: Error {
        case noBuffer
        case stalled
        case failed
    }

    static func render(_ source: URL, to destination: URL, settings: SoundSettings) throws -> URL {
        let partial = AudioRenderCache.partialURL(for: destination)
        defer { try? FileManager.default.removeItem(at: partial) }

        let file = try AVAudioFile(forReading: source)
        let format = file.processingFormat

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let pitch = AVAudioUnitTimePitch()
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        let distortion = AVAudioUnitDistortion()
        let delay = AVAudioUnitDelay()
        let reverb = AVAudioUnitReverb()
        configure(settings, pitch: pitch, eq: eq, distortion: distortion, delay: delay, reverb: reverb)

        // Manual rendering before the graph, as in `AudioEffectRenderer`: connecting while bound to
        // the hardware would build the graph in the hardware's format, and a format mismatch inside
        // the engine is an exception Swift cannot catch.
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        let chain: [AVAudioNode] = [player, pitch, eq, distortion, delay, reverb]
        for node in chain { engine.attach(node) }
        for (from, to) in zip(chain, chain.dropFirst()) {
            engine.connect(from, to: to, format: format)
        }
        engine.connect(reverb, to: engine.mainMixerNode, format: format)

        player.scheduleFile(file, at: nil)
        try engine.start()
        player.play()

        let output = try AVAudioFile(
            forWriting: partial,
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

        var stalledAttempts = 0
        while engine.manualRenderingSampleTime < file.length {
            let remaining = file.length - engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(min(Int64(buffer.frameCapacity), remaining))
            let status = try engine.renderOffline(frames, to: buffer)
            switch status {
            case .success:
                stalledAttempts = 0
                try output.write(from: buffer)
            case .cannotDoInCurrentContext, .insufficientDataFromInputNode:
                stalledAttempts += 1
                guard stalledAttempts < 100 else { throw RenderError.stalled }
            case .error:
                throw RenderError.failed
            @unknown default:
                throw RenderError.failed
            }
        }

        player.stop()
        engine.stop()
        engine.disableManualRenderingMode()
        guard AudioRenderCache.isUsable(partial) else { throw RenderError.failed }
        return try AudioRenderCache.publish(partial, to: destination)
    }

    /// Each preset as a setting of the same six units; the rest are bypassed.
    static func configure(
        _ settings: SoundSettings,
        pitch: AVAudioUnitTimePitch,
        eq: AVAudioUnitEQ,
        distortion: AVAudioUnitDistortion,
        delay: AVAudioUnitDelay,
        reverb: AVAudioUnitReverb
    ) {
        let amount = Float(min(max(settings.amount, 0), 1))
        let wet = amount * 100

        pitch.pitch = Float(settings.pitch * 100)
        pitch.bypass = abs(settings.pitch) < 0.01

        for band in eq.bands { band.bypass = true }
        distortion.bypass = true
        delay.bypass = true
        reverb.bypass = true

        func band(_ index: Int, _ type: AVAudioUnitEQFilterType, _ frequency: Float, gain: Float = 0, width: Float = 1) {
            let band = eq.bands[index]
            band.filterType = type
            band.frequency = frequency
            band.gain = gain
            band.bandwidth = width
            band.bypass = false
        }

        switch settings.preset {
        case .clean, .deep, .chipmunk:
            break
        case .echo:
            delay.bypass = false
            delay.delayTime = 0.28
            delay.feedback = 35
            delay.lowPassCutoff = 6000
            delay.wetDryMix = wet * 0.5
        case .hall:
            reverb.bypass = false
            reverb.loadFactoryPreset(.largeHall)
            reverb.wetDryMix = wet * 0.6
        case .room:
            reverb.bypass = false
            reverb.loadFactoryPreset(.mediumRoom)
            reverb.wetDryMix = wet * 0.45
        case .telephone:
            band(0, .highPass, 400)
            band(1, .lowPass, 3400)
            band(2, .parametric, 1500, gain: 6 * amount, width: 1.2)
            distortion.bypass = false
            distortion.loadFactoryPreset(.multiDecimated1)
            distortion.wetDryMix = wet * 0.25
        case .radio:
            band(0, .highPass, 300)
            band(1, .lowPass, 5000)
            distortion.bypass = false
            distortion.loadFactoryPreset(.speechRadioTower)
            distortion.wetDryMix = wet * 0.6
        case .megaphone:
            band(0, .highPass, 600)
            band(1, .lowPass, 4000)
            band(2, .parametric, 2000, gain: 9 * amount, width: 1)
            distortion.bypass = false
            distortion.loadFactoryPreset(.multiDistortedCubed)
            distortion.wetDryMix = wet * 0.3
        case .robot:
            distortion.bypass = false
            distortion.loadFactoryPreset(.speechAlienChatter)
            distortion.wetDryMix = wet * 0.8
        case .underwater:
            band(0, .lowPass, 600)
            reverb.bypass = false
            reverb.loadFactoryPreset(.plate)
            reverb.wetDryMix = wet * 0.5
        }
    }
}
