import Foundation

/// Where a video is going, and what that place needs: its shape, how long it may be, and the parts
/// of the frame its own buttons and captions cover.
///
/// People post the same video everywhere and get it wrong in small ways: a feed post cut in half by
/// a 9:16 frame, captions under TikTok's buttons, a Story that stops at a minute. Picking the
/// platform at export fixes all of it on a copy, so the project itself stays as it was edited.
public enum SocialPlatform: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case instagramReels
    case instagramStory
    case instagramPost
    case tiktok
    case youtubeShorts
    case youtube
    case square

    public var id: String { rawValue }

    public var aspectRatio: VideoFormat.AspectRatio {
        switch self {
        case .instagramReels, .instagramStory, .tiktok, .youtubeShorts: .portrait9x16
        case .instagramPost: .portrait4x5
        case .youtube: .landscape16x9
        case .square: .square1x1
        }
    }

    /// The longest video the place takes, in seconds; nil for no practical limit.
    public var maximumSeconds: Double? {
        switch self {
        case .instagramReels: 180
        case .instagramStory: 60
        case .tiktok: 600
        case .youtubeShorts: 180
        case .instagramPost, .youtube, .square: nil
        }
    }

    /// The share of the frame, from each edge, that the app's own interface covers: the like and
    /// share buttons, the caption and username, the progress bar.
    public var safeArea: SafeArea {
        switch self {
        case .instagramReels: SafeArea(top: 0.14, bottom: 0.24, left: 0.05, right: 0.13)
        case .instagramStory: SafeArea(top: 0.14, bottom: 0.2, left: 0.05, right: 0.05)
        case .tiktok: SafeArea(top: 0.13, bottom: 0.26, left: 0.06, right: 0.15)
        case .youtubeShorts: SafeArea(top: 0.12, bottom: 0.24, left: 0.05, right: 0.13)
        case .instagramPost, .square: SafeArea(top: 0.05, bottom: 0.06, left: 0.05, right: 0.05)
        case .youtube: SafeArea(top: 0.06, bottom: 0.12, left: 0.05, right: 0.05)
        }
    }

    public struct SafeArea: Hashable, Sendable {
        public var top: Double
        public var bottom: Double
        public var left: Double
        public var right: Double

        /// A centre height kept inside the area, with a little room for what is drawn around it.
        public func clampY(_ y: Double, margin: Double = 0.05) -> Double {
            let lowest = top + margin
            let highest = 1 - bottom - margin
            guard lowest < highest else { return 0.5 }
            return min(max(y, lowest), highest)
        }
    }

    /// What is worth saying before a video goes there.
    public enum Warning: Hashable, Sendable {
        /// Longer than the place takes, by this many seconds.
        case tooLong(maximum: Double, over: Double)
        /// Footage of another shape: it will sit over a blurred copy of itself.
        case letterboxed
    }

    public func warnings(for project: Project, duration: Double) -> [Warning] {
        var found: [Warning] = []
        if let maximumSeconds, duration > maximumSeconds + 0.5 {
            found.append(.tooLong(maximum: maximumSeconds, over: duration - maximumSeconds))
        }
        let wide = aspectRatio == .landscape16x9
        let footage = project.segments.compactMap { segment -> VideoFormat.AspectRatio? in
            guard let take = segment.selectedTake else { return nil }
            return project.recording(id: take.recordingID)?.format.aspectRatio
        }
        if wide ? footage.contains(.portrait9x16) : (aspectRatio == .portrait9x16 && footage.contains(.landscape16x9)) {
            found.append(.letterboxed)
        }
        return found
    }
}

extension Project {
    /// A copy made for one platform: its shape, tall footage cropped to fill a shorter frame rather
    /// than shrunk over a blur, and captions, titles and pictures moved out from under the
    /// platform's buttons. The project itself is not touched.
    public func adapted(for platform: SocialPlatform) -> Project {
        var copy = self
        copy.format = VideoFormat(aspectRatio: platform.aspectRatio, resolution: format.resolution, frameRate: format.frameRate)

        // 9:16 footage in a 4:5 or square frame: crop the top and bottom, which keeps the face.
        if platform.aspectRatio == .portrait4x5 || platform.aspectRatio == .square1x1 {
            for index in copy.segments.indices where copy.segments[index].fillsFrame == nil {
                guard let take = copy.segments[index].selectedTake,
                      copy.recording(id: take.recordingID)?.format.aspectRatio == .portrait9x16
                else { continue }
                copy.segments[index].fillsFrame = true
            }
        }

        let zone = platform.safeArea
        copy.captionStyle.position.y = zone.clampY(captionStyle.position.y)
        for s in copy.segments.indices {
            for c in copy.segments[s].captions.indices {
                if let position = copy.segments[s].captions[c].position {
                    copy.segments[s].captions[c].position = CaptionPosition(x: position.x, y: zone.clampY(position.y))
                }
            }
        }
        for index in copy.overlays.indices {
            // The brand logo keeps its corner; everything else moves out from under the buttons.
            if case .image(let path, _) = copy.overlays[index].content, path == BrandKit.logoInProject { continue }
            copy.overlays[index].transform.y = zone.clampY(copy.overlays[index].transform.y, margin: 0.08)
        }
        return copy
    }
}
