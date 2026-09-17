import Domain
import Observation
import SwiftUI

/// Teleprompter state, matching the design's prompter panel exactly.
///
/// Geometry is stored as percentages of the camera frame, like the design, so the panel keeps its
/// place when the device rotates or the preview size changes.
/// Knows nothing about audio: StudioFeature feeds `speakerDidReach` from speech tracking.
@MainActor
@Observable
public final class TeleprompterModel {
    /// How the current position is painted onto the script.
    public enum HighlightMode: String, CaseIterable, Sendable {
        /// Current word inverted on accent, look-ahead words washed lime.
        case word = "Word"
        /// A moving window of readable lines.
        case line = "Line"
        /// Everything already spoken turns accent.
        case karaoke = "Karaoke"
    }

    public enum Alignment: String, CaseIterable, Sendable {
        case left = "Left"
        case center = "Center"
    }

    public enum SettingsTab: String, CaseIterable, Sendable {
        case layout = "Layout"
        case flow = "Flow"
    }

    public enum Preset: String, CaseIterable, Sendable {
        case compact = "Compact"
        case band = "Band"
        case full = "Full"
        case corner = "Corner"
        /// Set automatically once the user drags or resizes the panel.
        case custom = "Custom"
    }

    /// Panel rectangle in percent of the frame, as in the design.
    public struct Frame: Hashable, Sendable, Codable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    // Verbatim from the design's PRESETS table.
    static let portraitPresets: [Preset: Frame] = [
        .compact: Frame(x: 28, y: 60, width: 44, height: 18),
        .band: Frame(x: 5, y: 56, width: 90, height: 26),
        .full: Frame(x: 5, y: 16, width: 90, height: 62),
        .corner: Frame(x: 54, y: 12, width: 42, height: 26),
    ]

    static let landscapePresets: [Preset: Frame] = [
        .compact: Frame(x: 34, y: 56, width: 32, height: 30),
        .band: Frame(x: 8, y: 58, width: 84, height: 32),
        .full: Frame(x: 6, y: 12, width: 88, height: 68),
        .corner: Frame(x: 58, y: 10, width: 38, height: 42),
    ]

    public private(set) var segments: [Segment] = []
    public private(set) var position: ScriptPosition?

    public var frame = Frame(x: 5, y: 56, width: 90, height: 26)
    public var preset: Preset = .band
    public var isDragging = false
    public var isLandscape = false

    /// Text size in points. The design shipped a 14–34 slider, but every teleprompter guide puts
    /// the floor for comfortable reading-to-camera around 36 — the old ceiling was below the point
    /// where the feature starts working. Pinching the panel drives this directly.
    public static let textSizeRange: ClosedRange<Double> = 14...64
    public var textSize: Double = 20
    /// Panel opacity, 10–100. The panel fill is `opacity / 145`, as in the design.
    public var opacity: Double = 78
    /// Scroll speed, 0–100, displayed as 0.6×–1.6×.
    public var speed: Double = 50
    /// Words highlighted ahead of the current one, 0–4.
    public var lookAhead: Int = 1
    public var mode: HighlightMode = .word
    public var alignment: Alignment = .left
    public var isMirrored = false
    public var settingsTab: SettingsTab = .layout
    public var isSettingsOpen = false
    public var isPaused = false
    /// Where the line being read sits in the panel, from the top: 0.15–0.6.
    public static let readingLineRange: ClosedRange<Double> = 0.15...0.6
    public var readingLine: Double = 0.3
    /// Says so when the reader runs well ahead of or behind a natural pace.
    public var coachesPace = true
    /// Seconds between pressing record and rolling, to get back into frame. 0 rolls at once.
    public static let countdownChoices = [0, 3, 5, 10]
    public var countdown = 3

    /// Words a minute, measured from the reader's voice. Nil until there is enough to say.
    public var pace: Double?
    /// A natural pace for the script's language.
    public var targetPace: Double = 150
    /// Seconds of reading left, at the measured pace or the target one.
    public var remaining: Double?
    /// How far through the whole script the reader is, 0–1.
    public var progress: Double = 0

    private let defaults: UserDefaults?
    static let preferencesKey = "teleprompter.preferences.v1"

    /// - Parameter defaults: where the reader's settings are kept between takes. Nil keeps nothing.
    public init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.preferencesKey),
           let saved = try? JSONDecoder().decode(Preferences.self, from: data) {
            restore(saved)
        }
    }

    // MARK: - Preferences

    /// Everything the reader chooses, kept between takes and launches.
    public struct Preferences: Hashable, Sendable, Codable {
        public var textSize: Double
        public var opacity: Double
        public var speed: Double
        public var lookAhead: Int
        public var mode: String
        public var alignment: String
        public var isMirrored: Bool
        public var preset: String
        public var portrait: Frame?
        public var landscape: Frame?
        public var readingLine: Double
        public var coachesPace: Bool
        public var countdown: Int?
    }

    @ObservationIgnored private var portraitFrame: Frame?
    @ObservationIgnored private var landscapeFrame: Frame?

    public var preferences: Preferences {
        Preferences(
            textSize: textSize,
            opacity: opacity,
            speed: speed,
            lookAhead: lookAhead,
            mode: mode.rawValue,
            alignment: alignment.rawValue,
            isMirrored: isMirrored,
            preset: preset.rawValue,
            portrait: isLandscape ? portraitFrame : frame,
            landscape: isLandscape ? frame : landscapeFrame,
            readingLine: readingLine,
            coachesPace: coachesPace,
            countdown: countdown
        )
    }

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// Writes the settings down, a moment after the last change: a slider being dragged changes
    /// them sixty times a second, and each write is a trip to disk.
    public func save() {
        guard defaults != nil, !isDragging else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    private func write() {
        guard let defaults else { return }
        if isLandscape {
            landscapeFrame = frame
        } else {
            portraitFrame = frame
        }
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: Self.preferencesKey)
        }
    }

    private func restore(_ saved: Preferences) {
        setTextSize(saved.textSize)
        opacity = min(max(10, saved.opacity), 100)
        speed = min(max(0, saved.speed), 100)
        lookAhead = min(max(0, saved.lookAhead), 4)
        mode = HighlightMode(rawValue: saved.mode) ?? mode
        alignment = Alignment(rawValue: saved.alignment) ?? alignment
        isMirrored = saved.isMirrored
        readingLine = min(max(Self.readingLineRange.lowerBound, saved.readingLine), Self.readingLineRange.upperBound)
        coachesPace = saved.coachesPace
        countdown = min(max(saved.countdown ?? 3, 0), 30)
        portraitFrame = saved.portrait
        landscapeFrame = saved.landscape
        let savedPreset = Preset(rawValue: saved.preset) ?? .band
        if savedPreset == .custom, let custom = saved.portrait {
            preset = .custom
            frame = custom
        } else {
            apply(savedPreset)
        }
    }

    /// The pace as a verdict, when there is one worth showing.
    public var paceVerdict: PaceMeter.Verdict? {
        guard coachesPace, let pace else { return nil }
        return PaceMeter.verdict(pace, target: targetPace)
    }

    public func load(_ segments: [Segment]) {
        self.segments = segments
        position = nil
    }

    // MARK: - Position

    public func speakerDidReach(_ position: ScriptPosition) {
        guard !isPaused else { return }
        self.position = position
    }

    /// Manual input always wins over automatic following.
    public func userDidMove(to position: ScriptPosition) {
        self.position = position
    }

    /// Index of the word being spoken in the current segment, or nil when not tracking.
    public var activeWordIndex: Int? {
        position?.wordIndex
    }

    public var currentSegment: Segment? {
        guard let position else { return segments.first }
        return segments.first { $0.id == position.segmentID } ?? segments.first
    }

    public var nextSegment: Segment? {
        guard let current = currentSegment,
              let index = segments.firstIndex(where: { $0.id == current.id }),
              segments.indices.contains(index + 1)
        else { return nil }
        return segments[index + 1]
    }

    // MARK: - Layout

    var presets: [Preset: Frame] {
        isLandscape ? Self.landscapePresets : Self.portraitPresets
    }

    public func apply(_ preset: Preset) {
        guard let frame = presets[preset] else { return }
        self.preset = preset
        self.frame = frame
        isDragging = false
    }

    /// Keeps the current preset's shape when the device rotates.
    public func setLandscape(_ landscape: Bool) {
        guard landscape != isLandscape else { return }
        isLandscape = landscape
        // A panel placed by hand comes back where it was put for this orientation.
        if preset == .custom, let placed = landscape ? landscapeFrame : portraitFrame {
            frame = placed
            return
        }
        let target = presets[preset] ?? presets[.band]
        if let target { frame = target }
    }

    /// Clamped so a pinch can be thrown at it without bounds checks at the call site.
    public func setTextSize(_ value: Double) {
        textSize = min(max(Self.textSizeRange.lowerBound, value), Self.textSizeRange.upperBound)
    }

    /// Stops the script following the speaker without touching what is on screen, so the reader
    /// can hold a line while they ad-lib and pick it up again afterwards.
    public func togglePause() {
        isPaused.toggle()
    }

    public func cyclePreset() {
        let order: [Preset] = [.compact, .band, .full, .corner]
        let index = order.firstIndex(of: preset).map { $0 + 1 } ?? 0
        apply(order[index % order.count])
    }

    /// Drag, in percent of the frame. Clamped exactly as the design clamps it.
    public func move(byX dx: Double, y dy: Double, from origin: Frame) {
        preset = .custom
        frame.x = min(max(2, origin.x + dx), 98 - origin.width)
        frame.y = min(max(6, origin.y + dy), 93 - origin.height)
    }

    public func resize(byX dx: Double, y dy: Double, from origin: Frame) {
        preset = .custom
        frame.width = min(max(26, origin.width + dx), 98 - origin.x)
        frame.height = min(max(12, origin.height + dy), 93 - origin.y)
    }

    // MARK: - Derived display values

    /// Panel fill opacity. The design divides the 10–100 setting by 145.
    public var panelFillOpacity: Double { opacity / 145 }

    public var speedLabel: String { String(format: "%.1f×", 0.6 + speed / 100) }

    /// Per-word appearance for the current segment.
    public func wordStyles(accent: Color, ink: Color, inkInverse: Color, lime: Color) -> [WordStyle] {
        guard let segment = currentSegment else { return [] }
        return Self.wordStyles(
            script: segment.script,
            active: activeWordIndex,
            mode: mode,
            lookAhead: lookAhead,
            accent: accent,
            ink: ink,
            inkInverse: inkInverse,
            lime: lime
        )
    }

    /// Per-word appearance for any script, so every screen that prompts paints it the same way.
    public static func wordStyles(
        script: String,
        active activeIndex: Int?,
        mode: HighlightMode,
        lookAhead: Int,
        accent: Color,
        ink: Color,
        inkInverse: Color,
        lime: Color
    ) -> [WordStyle] {
        let words = ScriptText.words(in: script).map { ScriptText.emphasis($0) }
        let active = activeIndex ?? -1

        return words.enumerated().map { index, word in
            let text = word.text
            switch mode {
            case .karaoke:
                return WordStyle(
                    id: index,
                    text: text,
                    color: index <= active ? accent : ink,
                    background: .clear,
                    opacity: index <= active ? 1 : 0.4,
                    isActive: index == active,
                    isEmphasized: word.isEmphasized
                )
            case .line:
                let near = abs(index - active) <= 6
                return WordStyle(
                    id: index,
                    text: text,
                    color: ink,
                    background: .clear,
                    opacity: active < 0 ? 0.85 : (near ? 1 : 0.22),
                    isActive: index == active,
                    isEmphasized: word.isEmphasized
                )
            case .word:
                let isHot = active >= 0 && index > active && index <= active + lookAhead
                return WordStyle(
                    id: index,
                    text: text,
                    color: index == active ? inkInverse : ink,
                    background: index == active ? accent : (isHot ? lime.opacity(0.16) : .clear),
                    opacity: index < active ? 0.3 : 1,
                    isActive: index == active,
                    isEmphasized: word.isEmphasized
                )
            }
        }
    }

    public struct WordStyle: Identifiable {
        /// The word's index. It used to be a fresh `UUID` per call, which gave every word a new
        /// identity on every body evaluation: `ForEach` rebuilt the entire script each frame and
        /// restarted every highlight animation mid-flight.
        public let id: Int
        public var text: String
        public var color: Color
        public var background: Color
        public var opacity: Double
        /// The word being spoken. Drawn slightly larger, because this is the one thing on screen
        /// the reader's eye is tracking continuously.
        public var isActive: Bool = false
        /// Written as `*word*`: drawn heavier so the reader stresses it.
        public var isEmphasized: Bool = false
    }
}
