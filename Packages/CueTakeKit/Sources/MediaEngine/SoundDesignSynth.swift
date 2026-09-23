import AVFoundation
import Domain
import Foundation

/// Makes the sound design's sounds on the phone: filtered noise swept for a whoosh, a falling
/// sine for a pop, a bass drop for a hit, frequency modulation for a bell.
///
/// Written by code rather than recorded, so every sound belongs to the app and nothing needs a
/// licence. Each is written once per project as a small WAV beside the footage.
public enum SoundDesignSynth {
    static let sampleRate = 48_000.0

    /// The sound's file in the project's media folder, made the first time it is asked for.
    public static func file(_ kind: SoundCueKind, in mediaDirectory: URL) throws -> URL {
        let url = mediaDirectory.appending(path: kind.fileName, directoryHint: .notDirectory)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return url }

        let samples = Self.samples(kind)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let partial = mediaDirectory.appending(path: kind.fileName + ".partial", directoryHint: .notDirectory)
        try? FileManager.default.removeItem(at: partial)
        do {
            let file = try AVAudioFile(forWriting: partial, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0]
            else { throw CocoaError(.fileWriteUnknown) }
            for (index, sample) in samples.enumerated() { channel[index] = sample }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            try file.write(from: buffer)
        }
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: partial, to: url)
        return url
    }

    /// The sound, peak-normalised to −3 dBFS.
    static func samples(_ kind: SoundCueKind) -> [Float] {
        let count = Int(kind.seconds * sampleRate)
        var noise = Noise(seed: kind.rawValue.unicodeScalars.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1.value) } | 1)
        var raw = [Double](repeating: 0, count: count)
        let sr = sampleRate

        switch kind {
        case .whoosh:
            var filter = BandPass()
            let peak = kind.peak
            for i in 0..<count {
                let t = Double(i) / sr
                let cutoff = t < peak ? 300 * pow(3500.0 / 300, t / peak) : 3500 * pow(900.0 / 3500, min((t - peak) / (kind.seconds - peak), 1))
                let envelope = t < peak ? pow(t / peak, 2) : exp(-(t - peak) * 12)
                raw[i] = filter.run(noise.next(), cutoff: cutoff, damping: 0.6, sampleRate: sr) * envelope
            }

        case .pop:
            var phase = 0.0
            for i in 0..<count {
                let t = Double(i) / sr
                let frequency = 280 + 900 * exp(-t * 55)
                phase += 2 * .pi * frequency / sr
                let body = sin(phase) * exp(-t * 32) * (1 - exp(-t * 2500))
                raw[i] = body + noise.next() * exp(-t * 400) * 0.25
            }

        case .impact:
            var phase = 0.0
            var low = 0.0
            for i in 0..<count {
                let t = Double(i) / sr
                let frequency = 42 + 95 * exp(-t * 16)
                phase += 2 * .pi * frequency / sr
                low += (noise.next() - low) * 0.08
                let value = sin(phase) * exp(-t * 4.5) + low * exp(-t * 30) * 2.2
                raw[i] = tanh(value * 1.6)
            }

        case .ding:
            var carrier = 0.0
            var modulator = 0.0
            var partial = 0.0
            let base = 1318.5
            for i in 0..<count {
                let t = Double(i) / sr
                modulator += 2 * .pi * base * 3.5 / sr
                carrier += 2 * .pi * base / sr
                partial += 2 * .pi * base * 2.76 / sr
                let index = 2.2 * exp(-t * 7)
                let attack = 1 - exp(-t * 900)
                raw[i] = (sin(carrier + index * sin(modulator)) * exp(-t * 3.4) + sin(partial) * 0.22 * exp(-t * 9)) * attack
            }

        case .click:
            var previous = 0.0
            var phase = 0.0
            for i in 0..<count {
                let t = Double(i) / sr
                let white = noise.next()
                let high = white - previous
                previous = white
                phase += 2 * .pi * 2200 / sr
                raw[i] = high * exp(-t * 350) + sin(phase) * exp(-t * 180) * 0.5
            }

        case .riser:
            var filter = BandPass()
            var phase = 0.0
            let peak = kind.peak
            for i in 0..<count {
                let t = Double(i) / sr
                let progress = min(t / peak, 1)
                let cutoff = 200 * pow(5000.0 / 200, progress)
                phase += 2 * .pi * (150 * pow(6.0, progress)) / sr
                let envelope = t < peak ? pow(progress, 2.2) : max(0, 1 - (t - peak) / 0.08)
                raw[i] = (filter.run(noise.next(), cutoff: cutoff, damping: 0.5, sampleRate: sr) + sin(phase) * 0.3) * envelope
            }
        }

        // A few milliseconds of fade at the end, so no sound stops with a click of its own.
        let tail = min(count, Int(0.006 * sr))
        for offset in 0..<tail {
            raw[count - 1 - offset] *= Double(offset) / Double(tail)
        }
        let loudest = raw.map(abs).max() ?? 0
        let scale = loudest > 0 ? 0.708 / loudest : 0
        return raw.map { Float($0 * scale) }
    }

    /// A small, repeatable white noise: the same sound every time it is made.
    struct Noise {
        var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(Int64(bitPattern: state >> 11 << 11)) / Double(Int64.max)
        }
    }

    /// A state-variable band-pass whose centre can move every sample.
    struct BandPass {
        var low = 0.0
        var band = 0.0

        mutating func run(_ input: Double, cutoff: Double, damping: Double, sampleRate: Double) -> Double {
            let f = 2 * sin(.pi * min(cutoff, sampleRate / 6) / sampleRate)
            low += f * band
            let high = input - low - damping * band
            band += f * high
            return band
        }
    }
}
