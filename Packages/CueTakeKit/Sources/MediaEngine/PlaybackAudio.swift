import AVFoundation

/// Makes the phone's speaker play what the app plays.
///
/// Nothing in the app ever set the audio session, so playback ran under the system default — the
/// "solo ambient" category, which the ring/silent switch mutes — or under whatever the camera left
/// behind after recording, which routes sound to the earpiece. Either way the editor's preview
/// played in silence. Every video app plays through the silent switch; this is how.
public enum PlaybackAudio {
    public static func activate() {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback || session.mode != .moviePlayback {
            try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        }
        try? session.setActive(true)
    }
}
