import Foundation

/// A brand template picture, as the model asked for it: which style, every line of it, and its
/// look. Lines it leaves out stay as they were on an edit and empty on a new one.
public struct TemplateRequest: Hashable, Sendable {
    /// A template style: `codeCard`, `coupon`, `priceTag`… (see `slotNames` for its lines).
    public var style: String?
    /// A template's own id, when the model names one.
    public var template: String?
    /// Each line by its slot's name.
    public var texts: [String: String]
    /// `#RRGGBB`.
    public var color: String?
    public var light: Bool?
    /// `display`, `clean` or `mono`.
    public var font: String?
    public var start: Double?
    public var duration: Double?
    public var end: Double?
    public var x: Double?
    public var y: Double?
    public var scale: Double?

    /// Every line a template can have. The model writes them as fields of the step.
    public static let slotNames = [
        "brand", "label", "title", "detail", "code", "price", "oldPrice", "number", "note",
        "date", "place", "cta", "optionA", "optionB", "item1", "item2", "item3",
    ]

    public init(
        style: String? = nil, template: String? = nil, texts: [String: String] = [:], color: String? = nil,
        light: Bool? = nil, font: String? = nil, start: Double? = nil, duration: Double? = nil, end: Double? = nil,
        x: Double? = nil, y: Double? = nil, scale: Double? = nil
    ) {
        self.style = style
        self.template = template
        self.texts = texts
        self.color = color
        self.light = light
        self.font = font
        self.start = start
        self.duration = duration
        self.end = end
        self.x = x
        self.y = y
        self.scale = scale
    }

    var isEmpty: Bool {
        style == nil && template == nil && texts.isEmpty && color == nil && light == nil && font == nil
            && start == nil && duration == nil && end == nil && x == nil && y == nil && scale == nil
    }

    static func read(_ f: PlanFields) -> TemplateRequest {
        var texts: [String: String] = [:]
        for name in slotNames {
            if let value = f.string(name) { texts[name] = value }
        }
        return TemplateRequest(
            style: f.string("style"),
            template: f.string("template"),
            texts: texts,
            color: f.string("color"),
            light: f.flag("light"),
            font: f.string("font"),
            start: f.number("start"),
            duration: f.number("duration"),
            end: f.number("end"),
            x: f.number("x"),
            y: f.number("y"),
            scale: f.number("scale")
        )
    }
}
