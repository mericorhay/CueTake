import AVFoundation
import CoreMedia
import CoreVideo
import Domain
import Foundation
import QuartzCore

/// The one clock of the stage, and the floating window's frames.
///
/// A timer off the main actor moves the prompter on and draws each frame into the display layer
/// that Picture in Picture shows. It has to live off the main actor: while another app is in front
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
    private var pool: CVPixelBufferPool?
    private var format: CMVideoFormatDescription?
    private var timebase: CMTimebase?
    private var lastTimebaseSync: Double = -10

    /// Called on the frame queue; the owner hops to the main actor.
    var onEvent: (@Sendable (Event) -> Void)?

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

    private func render(_ frame: SuflorFrame) {
        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        guard renderer.isReadyForMoreMediaData, let pixels = makePixelBuffer() else { return }

        CVPixelBufferLockBaseAddress(pixels, [])
        if let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixels),
            width: Self.pixelSize.width,
            height: Self.pixelSize.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) {
            // Bitmaps are y up; the painter works y down in layout points.
            context.translateBy(x: 0, y: CGFloat(Self.pixelSize.height))
            context.scaleBy(x: Self.scale, y: -Self.scale)
            let size = CGSize(width: CGFloat(Self.pixelSize.width) / Self.scale, height: CGFloat(Self.pixelSize.height) / Self.scale)
            SuflorPainter.drawWindow(context, frame: frame, size: size)
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])

        if format == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescriptionOut: &format)
        }
        guard let format else { return }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(Self.framesPerSecond)),
            presentationTimeStamp: timebase.map { CMTimebaseGetTime($0) } ?? .zero,
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return }
        // Shown the moment it arrives: the frames are live, not a timed movie.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        renderer.enqueue(sample)
    }

    private func makePixelBuffer() -> CVPixelBuffer? {
        if pool == nil {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: Self.pixelSize.width,
                kCVPixelBufferHeightKey: Self.pixelSize.height,
                kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any]() as CFDictionary,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            ]
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return buffer
    }
}
