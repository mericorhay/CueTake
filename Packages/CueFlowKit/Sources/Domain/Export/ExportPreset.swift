import Foundation

public struct ExportPreset: Hashable, Sendable, Codable {
    public var format: VideoFormat
    public var burnsInCaptions: Bool
    public var destination: ExportDestination

    public init(format: VideoFormat, burnsInCaptions: Bool, destination: ExportDestination) {
        self.format = format
        self.burnsInCaptions = burnsInCaptions
        self.destination = destination
    }

    public static let shortFormVertical = ExportPreset(format: .vertical1080, burnsInCaptions: true, destination: .photoLibrary)
}

public enum ExportDestination: String, Hashable, Sendable, Codable {
    case photoLibrary
    case files
}
