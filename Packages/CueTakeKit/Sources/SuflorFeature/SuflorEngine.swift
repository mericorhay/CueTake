import AVFoundation
import CoreMedia
import CoreVideo
import Domain
import Foundation
import QuartzCore

/// The one clock of the stage, and the floating window's frames.
///
/// A timer off the main actor moves the prompter on and draws each frame as a picture, which the
/// floating window and the stage's preview put on screen. It has to live off the main actor: while another app is in front
/// the main run loop's display link stops, and this timer is what keeps the words moving. The stage
/// on the phone reads the same clock, so the two can never disagree.
nonisolated final class SuflorEngine: @unchecked Sendable {
    nonisolated enum Event: Sendable {
        /// The first play: the stream has begun.
        case started
        case adStarted(Double)
        case adEnded(Double)
        case finished(Double)
    }

    /// The floating window's frame in pixels: 360×480 points at 2x, the shape of a phone held up.
    static let pixelSize = (width: 720, height: 960)
    static let scale: CGFloat = 2
    static let framesPerSecond = 30.0

    let displayLayer = AVSampleBufferDisplayLayer()

    private let lock = NSLock()
    private var clock: SuflorClock
    private var layout: SuflorLayout
    private var wordsPerMinute: Double
    private var kind: SuflorBrief.Kind
    private var text: SuflorChromeText
    private var fonts: SuflorFonts
    private var isDragging = false
    private var adStarted = false
    private var adEnded = false
    private var hasFinished = false
    private var announcedStart = false

    private let queue = DispatchQueue(label: "cuetake.suflor.frames", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var lastTick: CFTimeInterval?
    private var timebase: CMTimebase?
    private var lastTimebaseSync: Double = -10

    /// Called on the frame queue; the owner hops to the main actor.
    var onEvent: (@Sendable (Event) -> Void)?
    /// Each drawn frame, on the frame queue.
    var onFrame: (@Sendable (SuflorFrameImage) -> Void)?
    private var canvas: CGContext?

    init(layout: SuflorLayout, adAt: Double?, holds: Bool, wordsPerMinute: Double, kind: SuflorBrief.Kind, text: SuflorChromeText, fonts: SuflorFonts) {
        self.layout = layout
        self.wordsPerMinute = wordsPerMinute
        self.kind = kind
        self.text = text
        self.fonts = fonts
        clock = SuflorClock(end: Double(layout.end), holdAt: holds ? layout.adTop.map(Double.init) : nil, adAt: adAt, started: false)
        displayLayer.videoGravity = .resizeAspect
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
        if let timebase {
            CMTimebaseSetTime(timebase, time: .zero)
            CMTimebaseSetRate(timebase, rate: 0)
            displayLayer.controlTimebase = timebase
        }
        self.timebase = timebase
    }

    // MARK: - Running

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: 1 / Self.framesPerSecond, leeway: .milliseconds(4))
            source.setEventHandler { [weak self] in self?.step() }
            timer = source
            lastTick = nil
            source.resume()
        }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
        displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: false, completionHandler: nil)
    }

    private func step() {
        let now = CACurrentMediaTime()
        let seconds = lastTick.map { min(0.25, now - $0) } ?? 0
        lastTick = now

        var events: [Event] = []
        let frame: SuflorFrame = lock.withLock {
            let speed = isDragging ? 0 : layout.speed(wordsPerMinute: wordsPerMinute)
            clock.tick(seconds, speed: speed)
            events = noticeCrossings()
            return currentFrame()
        }
        for event in events { onEvent?(event) }
        syncTimebase(frame)
        render(frame)
    }

    /// Ad start, ad end and the finish, each once, from where the reading line has got to.
    private func noticeCrossings() -> [Event] {
        var events: [Event] = []
        if !announcedStart, clock.started {
            announcedStart = true
            events.append(.started)
        }
        let offset = CGFloat(clock.offset)
        let at = max(0, clock.elapsed - SuflorClock.countdown)
        if !adStarted, let top = layout.adTop, offset > top + layout.fontSize {
            adStarted = true
            events.append(.adStarted(at))
        }
        if adStarted, !adEnded, let bottom = layout.adBottom, offset > bottom + layout.fontSize * 0.7 {
            adEnded = true
            events.append(.adEnded(at))
        }
        if !hasFinished, clock.phase == .finished {
            hasFinished = true
            events.append(.finished(at))
        }
        return events
    }

    private func currentFrame() -> SuflorFrame {
        SuflorFrame(clock: clock, layout: layout, kind: kind, text: text, fonts: fonts)
    }

    // MARK: - Reading and steering

    func frame() -> SuflorFrame { lock.withLock { currentFrame() } }

    var isPlaying: Bool { lock.withLock { clock.isPlaying } }

    func setPlaying(_ playing: Bool) {
        lock.withLock { clock.setPlaying(playing) }
    }

    func setDragging(_ dragging: Bool) {
        lock.withLock { isDragging = dragging }
    }

    /// The speaker's finger, in layout points.
    func move(by delta: Double) {
        lock.withLock { clock.move(by: delta) }
    }

    /// A card forward or back; forward at the ad lets it go.
    func skip(forward: Bool) {
        lock.withLock {
            if forward, clock.phase == .holding {
                clock.jump(to: clock.offset + 1)
                return
            }
            if clock.phase == .countdown { clock.elapsed = SuflorClock.countdown }
            clock.jump(to: Double(layout.skip(from: CGFloat(clock.offset), forward: forward)))
        }
    }

    /// The floating window's skip buttons, which the system draws as ten seconds: ten seconds of
    /// reading at the chosen pace, back or forward. Forward at the ad lets it go.
    func nudge(seconds: Double) {
        lock.withLock {
            if seconds > 0, clock.phase == .holding {
                clock.jump(to: clock.offset + 1)
                return
            }
            clock.move(by: layout.speed(wordsPerMinute: wordsPerMinute) * seconds)
        }
    }

    /// Lets the ad go now, wherever the minute is.
    func startAd() {
        lock.withLock {
            guard let top = layout.adTop else { return }
            if clock.phase == .countdown { clock.elapsed = SuflorClock.countdown }
            clock.jump(to: max(clock.offset, Double(top)))
        }
    }

    func setWordsPerMinute(_ value: Double) {
        lock.withLock { wordsPerMinute = value }
    }

    /// New text size: the same card, the same share of it, in the new layout.
    func setLayout(_ new: SuflorLayout, holds: Bool) {
        lock.withLock {
            let position = layout.position(CGFloat(clock.offset), in: new)
            layout = new
            clock.end = Double(new.end)
            clock.holdAt = holds ? new.adTop.map(Double.init) : nil
            clock.offset = min(Double(position), clock.end)
        }
    }

    /// For Picture in Picture's scrubber: the whole flow as time at the chosen pace.
    func timeRange() -> CMTimeRange {
        lock.withLock {
            let speed = max(0.1, layout.speed(wordsPerMinute: wordsPerMinute))
            return CMTimeRange(start: .zero, duration: CMTime(seconds: max(1, clock.end / speed), preferredTimescale: 600))
        }
    }

    // MARK: - Frames

    private func syncTimebase(_ frame: SuflorFrame) {
        guard let timebase else { return }
        let speed = max(0.1, frame.layout.speed(wordsPerMinute: lock.withLock { wordsPerMinute }))
        let rolling = frame.clock.isPlaying && frame.clock.phase == .rolling
        let rate = rolling ? 1.0 : 0.0
        if CMTimebaseGetRate(timebase) != rate || frame.clock.elapsed - lastTimebaseSync > 1 {
            CMTimebaseSetRate(timebase, rate: rate)
            CMTimebaseSetTime(timebase, time: CMTime(seconds: frame.clock.offset / speed, preferredTimescale: 600))
            lastTimebaseSync = frame.clock.elapsed
        }
    }

    /// Draws the frame as a picture. It is not a video frame: the window is a video call's, which
    /// shows views, so nothing here is decoded and nothing is dropped when a camera opens.
    private func render(_ frame: SuflorFrame) {
        guard let onFrame else { return }
        if canvas == nil {
            canvas = CGContext(
                data: nil,
                width: Self.pixelSize.width,
                height: Self.pixelSize.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
            // Bitmaps are y up; the painter works y down in layout points.
            canvas?.translateBy(x: 0, y: CGFloat(Self.pixelSize.height))
            canvas?.scaleBy(x: Self.scale, y: -Self.scale)
        }
        guard let canvas else { return }
        let size = CGSize(width: CGFloat(Self.pixelSize.width) / Self.scale, height: CGFloat(Self.pixelSize.height) / Self.scale)
        canvas.clear(CGRect(origin: .zero, size: size))
        SuflorPainter.drawWindow(canvas, frame: frame, size: size)
        guard let image = canvas.makeImage() else { return }
        onFrame(SuflorFrameImage(image: image))
    }
}

/// A drawn frame on its way to the main actor. A `CGImage` is immutable.
nonisolated struct SuflorFrameImage: @unchecked Sendable {
    let image: CGImage
}
