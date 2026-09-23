import AVFoundation
import Foundation

/// A recording's sound, made small enough to send to the server listener.
///
/// Speech needs very little: one channel at 16 kHz is what the recogniser works at anyway, and at
/// 32 kbit/s a minute of talking is a quarter of a megabyte instead of the ten of the video it
/// came out of. The upload is the slow part of hearing a recording twice; this makes it seconds.
public enum SpeechAudio {
    public enum SpeechAudioError: Error {
        case noAudio
        case cannotWrite
    }

    /// Writes the compact copy to a temporary file and returns it. The caller removes it.
    @concurrent
    public static func compact(_ source: URL, maximumSeconds: Double? = nil) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw SpeechAudioError.noAudio }

        let destination = FileManager.default.temporaryDirectory
            .appending(path: "speech-\(UUID().uuidString).m4a", directoryHint: .notDirectory)

        let reader = try AVAssetReader(asset: asset)
        if let maximumSeconds {
            reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: maximumSeconds, preferredTimescale: 600))
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw SpeechAudioError.cannotWrite }
        reader.add(output)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw SpeechAudioError.cannotWrite }
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else { throw SpeechAudioError.cannotWrite }
        writer.startSession(atSourceTime: .zero)

        func fail() -> SpeechAudioError {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            return .cannotWrite
        }

        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled { throw fail() }
            var waited = 0
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed || waited > 5000 { throw fail() }
                try? await Task.sleep(for: .milliseconds(2))
                waited += 1
            }
            guard input.append(sample) else { throw fail() }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed, reader.status == .completed else { throw fail() }
        return destination
    }
}
