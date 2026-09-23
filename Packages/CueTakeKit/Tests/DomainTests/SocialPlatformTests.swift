import Foundation
import Testing
@testable import Domain

/// One video, fitted to each place it goes: the right shape, tall footage filling a shorter frame,
/// captions and titles clear of the platform's buttons, and the project itself untouched.
struct SocialPlatformTests {
    private func project() -> Project {
        let recording = Recording(
            relativePath: "media/a.mov",
            format: .vertical1080,
            camera: .front,
            duration: MediaTime(seconds: 10)
        )
        let take = Take(recordingID: recording.id, sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 10)))
        let segment = Segment(role: .hook, script: "a", estimatedDuration: MediaTime(seconds: 10), takes: [take], selectedTakeID: take.id)
        var project = Project(title: "t", localeIdentifier: "en", segments: [segment], recordings: [recording])
        project.captionStyle.position = CaptionPosition(x: 0.5, y: 0.9)
        project.overlays = [Overlay(content: .text(OverlayText(text: "Hi")), start: .zero, duration: MediaTime(seconds: 2), transform: OverlayTransform(y: 0.95))]
        return project
    }

    @Test func tikTokMovesCaptionsAboveItsButtons() {
        let original = project()
        let fitted = original.adapted(for: .tiktok)
        #expect(fitted.format.aspectRatio == .portrait9x16)
        #expect(fitted.captionStyle.position.y <= 1 - SocialPlatform.tiktok.safeArea.bottom)
        #expect(fitted.overlays[0].transform.y <= 1 - SocialPlatform.tiktok.safeArea.bottom)
        // The project it came from is untouched.
        #expect(original.captionStyle.position.y == 0.9)
    }

    @Test func feedPostCropsTallFootage() {
        let fitted = project().adapted(for: .instagramPost)
        #expect(fitted.format.aspectRatio == .portrait4x5)
        #expect(fitted.format.renderSize == PixelSize(width: 1080, height: 1350))
        #expect(fitted.segments[0].fillsFrame == true)
        // A wide frame keeps tall footage whole, over its blurred copy.
        #expect(project().adapted(for: .youtube).segments[0].fillsFrame == nil)
    }

    @Test func warnsWhatThePlatformWillRefuse() {
        let long = SocialPlatform.instagramStory.warnings(for: project(), duration: 75)
        #expect(long.contains(.tooLong(maximum: 60, over: 15)))
        #expect(SocialPlatform.youtube.warnings(for: project(), duration: 10) == [.letterboxed])
        #expect(SocialPlatform.tiktok.warnings(for: project(), duration: 10).isEmpty)
    }
}
