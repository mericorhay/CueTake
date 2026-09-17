import Foundation
import Testing
@testable import Domain

struct BrandKitTests {
    private func project(segments count: Int = 3, seconds: Double = 4) -> Project {
        let recording = Recording(relativePath: "a.mov", format: .vertical1080, camera: .back, duration: MediaTime(seconds: 60))
        let made = (0..<count).map { index -> Segment in
            let take = Take(
                recordingID: recording.id,
                sourceRange: MediaTimeRange(start: MediaTime(seconds: Double(index) * seconds), duration: MediaTime(seconds: seconds)),
                status: .ready
            )
            return Segment(role: .mainPoint, script: "", takes: [take], selectedTakeID: take.id)
        }
        return Project(title: "Kahve Lab", localeIdentifier: "tr-TR", segments: made, recordings: [recording])
    }

    @Test func thePaintGoesOnCaptionsAndTitlesOnly() {
        var made = project()
        made.captionStyle = CaptionStyle.preset("boxed")
        made.overlays = [
            Overlay(content: .text(OverlayText(text: "Merhaba", color: .white, background: .black)), start: .zero),
            Overlay(content: .image(relativePath: "photo.png", aspect: 1), start: .zero),
        ]
        let kit = BrandKit(
            primary: RGBAColor(red: 0.1, green: 0.8, blue: 0.4),
            secondary: RGBAColor(red: 0.2, green: 0.2, blue: 0.2),
            ink: RGBAColor(red: 0.95, green: 0.95, blue: 1),
            fontName: "JetBrainsMono-Medium"
        )
        made.apply(kit)

        #expect(made.captionStyle.textColor == kit.ink)
        #expect(made.captionStyle.keywordColor == kit.primary)
        #expect(made.captionStyle.fontName == "JetBrainsMono-Medium")
        guard case .text(let text) = made.overlays[0].content else {
            Issue.record("the title should still be a title")
            return
        }
        #expect(text.color == kit.ink)
        #expect(text.background == kit.secondary)
        #expect(text.fontName == "JetBrainsMono-Medium")
        // The picture overlay is the user's own and is left alone.
        guard case .image(let path, _) = made.overlays[1].content else {
            Issue.record("the picture should still be a picture")
            return
        }
        #expect(path == "photo.png")
    }

    @Test func theLogoGoesInItsCornerAndComesOutAgain() {
        var made = project()
        var kit = BrandKit(logoFile: "logo.png", logoAspect: 2)
        kit.watermark = BrandKit.Watermark(isOn: true, corner: .bottomTrailing, width: 0.2, opacity: 0.6)
        made.setWatermark(kit, aspect: 2, totalSeconds: 12)

        #expect(made.hasWatermark)
        guard let logo = made.overlays.first(where: { if case .image = $0.content { return true } else { return false } }) else {
            Issue.record("the logo should be on the video")
            return
        }
        #expect(logo.transform.x > 0.5)
        #expect(logo.transform.y > 0.5)
        #expect(abs(logo.transform.opacity - 0.6) < 0.001)
        #expect(abs(logo.duration.seconds - 12) < 0.001)

        // Applied again: one logo, not two.
        made.setWatermark(kit, aspect: 2, totalSeconds: 12)
        #expect(made.overlays.count == 1)

        kit.watermark.isOn = false
        made.setWatermark(kit, aspect: 2, totalSeconds: 12)
        #expect(!made.hasWatermark)
        #expect(made.overlays.isEmpty)
    }

    @Test func aTemplateIsTakenFromAProjectAndPutOnAnother() {
        var source = project()
        source.format = VideoFormat(aspectRatio: .landscape16x9, resolution: .uhd4K)
        source.captionStyle = CaptionStyle.preset("neon", position: CaptionPosition(x: 0.5, y: 0.7))
        let total = source.segments.reduce(0) { $0 + $1.barWeight }
        source.effects = [
            TimelineEffect(start: .zero, duration: MediaTime(seconds: total), kind: .filter(FilterSettings(look: .cinematic))),
            // A graded moment is not the video's look.
            TimelineEffect(start: MediaTime(seconds: 1), duration: MediaTime(seconds: 1), kind: .filter(FilterSettings(look: .noir))),
        ]
        for index in source.segments.indices.dropLast() {
            source.setTransition(after: source.segments[index].id, kind: .crossfade, duration: 0.4)
        }

        let template = VideoTemplate(name: "Seri", from: source)
        #expect(template.captionPreset == "neon")
        #expect(template.look?.look == .cinematic)
        #expect(template.transition == .crossfade)
        #expect(template.format.aspectRatio == .landscape16x9)

        var target = project()
        target.setTransition(after: target.segments[0].id, kind: .fadeBlack)
        let words = target.segments.map(\.script)
        target.apply(template, brand: BrandKit(primary: RGBAColor(red: 1, green: 0, blue: 0)))

        #expect(target.format.resolution == .uhd4K)
        #expect(target.captionStyle.presetID == "neon")
        #expect(abs(target.captionStyle.position.y - 0.7) < 0.001)
        let grades = target.effects.filter { $0.filter != nil }
        #expect(grades.count == 1)
        #expect(grades.first?.filter?.look == .cinematic)
        // The chosen transition stays; the empty cut takes the template's.
        let kinds = Set(target.transitions.map(\.kind))
        #expect(target.transitions.count == 2)
        #expect(kinds == [.fadeBlack, .crossfade])
        // The brand came with it, and the words were never touched.
        #expect(target.captionStyle.keywordColor == RGBAColor(red: 1, green: 0, blue: 0))
        #expect(target.segments.map(\.script) == words)
    }

    @Test func aTemplateWithoutOneRuleKeepsNone() {
        var mixed = project()
        mixed.setTransition(after: mixed.segments[0].id, kind: .crossfade)
        mixed.setTransition(after: mixed.segments[1].id, kind: .fadeWhite)
        let template = VideoTemplate(name: "t", from: mixed)
        #expect(template.transition == nil)
        #expect(template.look == nil)
        #expect(VideoTemplate.name(for: mixed) == "Kahve Lab")
    }
}
