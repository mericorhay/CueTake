import Foundation

public struct ExportPreset: Hashable, Sendable, Codable {
    public var format: VideoFormat
    public var burnsInCaptions: Bool
    public var destination: ExportDestination
    /// Where a workflow sends the finished file, beyond the phone. Nil sends it nowhere.
    public var delivery: WorkflowDelivery?

    public init(
        format: VideoFormat,
        burnsInCaptions: Bool,
        destination: ExportDestination,
        delivery: WorkflowDelivery? = nil
    ) {
        self.format = format
        self.burnsInCaptions = burnsInCaptions
        self.destination = destination
        self.delivery = delivery
    }

    public static let shortFormVertical = ExportPreset(format: .vertical1080, burnsInCaptions: true, destination: .photoLibrary)

    private enum CodingKeys: String, CodingKey {
        case format, burnsInCaptions, destination, delivery
    }

    /// Every field optional: `{"type": "export", "parameters": {"destination": "files"}}` is a
    /// complete export step, not a broken one.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ExportPreset.shortFormVertical
        format = (try? c.decodeIfPresent(VideoFormat.self, forKey: .format)) ?? fallback.format
        burnsInCaptions = (try? c.decodeIfPresent(Bool.self, forKey: .burnsInCaptions)) ?? fallback.burnsInCaptions
        destination = (try? c.decodeIfPresent(ExportDestination.self, forKey: .destination)) ?? fallback.destination
        delivery = (try? c.decodeIfPresent(WorkflowDelivery.self, forKey: .delivery)) ?? nil
    }
}

public enum ExportDestination: String, Hashable, Sendable, Codable {
    case photoLibrary
    case files
}
