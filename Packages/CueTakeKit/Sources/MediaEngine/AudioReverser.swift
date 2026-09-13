import AVFoundation
import Domain
import Foundation

/// Plays a reversed clip's sound backwards too.
///
/// Reversed clips used to be silent, and the note under the switch said so. Silence was the honest
/// answer while only the pictures were reversed; reversing sound is simpler than reversing video —
/// no decoder state, just samples in the other order — so there was no good reason to stop there.
///
/// Uses the same extracted voice file as `VoiceCleaner`, so a recording's sound is copied out of
/// its video once however many features want it.
struct AudioReverser {
    /// Longer than this and the whole range is not held in memory at once; the clip stays silent
    /// rather than risking the app. Ten minutes of stereo is about 230 MB of samples.
    static let maxSeconds = 600.0

    static func reversedAudio(
        for recording: Recording,
        range: CMTimeRange,
        key: String,
        in directory: URL
    ) async -> URL? {
        guard range.duration.seconds > 0.05, range.duration.seconds <= maxSeconds else { return nil }

        let destination = directory.appending(path: "\(key)-rev-audio.m4a", directoryHint: .notDirectory)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            return destination
        }

        guard let extracted = await VoiceCleaner.extractedVoice(for: recording, in: directory) else { return nil }
        let start = range.start.seconds
        let duration = range.duration.seconds

        return await Task.detached(priority: .userInitiated) {
            try? write(from: extracted, start: start, duration: duration, to: destination)
        }.value
    }

    private static func write(from source: URL, start: Double, duration: Double, to destination: URL) throws -> URL? {
        try? FileManager.default.removeItem(at: destination)

        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let rate = format.sampleRate
        let startFrame = AVAudioFramePosition(start * rate)
        guard startFrame < input.length else { return nil }
        let frames = AVAudioFrameCount(min(duration * rate, Double(input.length - startFrame)))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }

        input.framePosition = startFrame
        try input.read(into: buffer, frameCount: frames)

        let count = Int(buffer.frameLength)
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                let samples = channels[channel]
                var low = 0
                var high = count - 1
                while low < high {
                    let swap = samples[low]
                    samples[low] = samples[high]
                    samples[high] = swap
                    low += 1
                    high -= 1
                }
            }
        }

        // Written inside its own scope so the file is closed — and its header finished — before
        // anything tries to read it back.
        do {
            let output = try AVAudioFile(
                forWriting: destination,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: rate,
                    AVNumberOfChannelsKey: format.channelCount,
                ]
            )
            try output.write(from: buffer)
        }
        return destination
    }
}
