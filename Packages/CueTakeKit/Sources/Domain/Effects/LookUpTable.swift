import Foundation

/// A colour grade bought or downloaded as a `.cube` file, the format every grading tool writes.
///
/// The built-in looks are made from the system's own filters, which is why they are free and
/// adjustable — but a look somebody has bought, or that their agency hands them, only exists as a
/// table of colours. This reads that table; the picture is graded with it in MediaEngine.
public struct LookUpTable: Hashable, Sendable, Codable {
    /// What to call it on screen: the file's own name, without the extension.
    public var name: String
    /// The file beside the footage, e.g. "media/lut-teal.cube".
    public var file: String
    /// Entries along one edge of the cube. 33 is the usual; 17 and 65 are both seen.
    public var size: Int

    public init(name: String, file: String, size: Int) {
        self.name = name
        self.file = file
        self.size = size
    }

    /// The largest cube worth loading: 65³ is a megabyte of floats and already more resolution
    /// than a video frame can show. Anything larger is a mistake or an attack.
    public static let largestSize = 65

    /// A parsed cube, in the layout Core Image wants: red varying fastest, then green, then blue,
    /// four floats an entry with the alpha always 1.
    public struct Cube: Hashable, Sendable {
        public var size: Int
        public var values: [Float]

        public init(size: Int, values: [Float]) {
            self.size = size
            self.values = values
        }
    }

    /// Reads a `.cube` file. Returns nil rather than a half-built cube: a grade that is wrong in
    /// the middle is worse than one that never arrived, because nobody would know to look.
    public static func parse(_ text: String) -> Cube? {
        var size = 0
        var lower: [Float] = [0, 0, 0]
        var upper: [Float] = [1, 1, 1]
        var values: [Float] = []
        var rows = 0

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let first = parts.first else { continue }

            switch first.uppercased() {
            case "LUT_3D_SIZE":
                guard parts.count >= 2, let read = Int(parts[1]), read >= 2, read <= largestSize else { return nil }
                size = read
                values.reserveCapacity(read * read * read * 4)
            case "LUT_1D_SIZE":
                // A one-dimensional table is a curve, not a grade. Refusing is honest; pretending
                // it is a cube would tint the picture in a way the file never asked for.
                return nil
            case "DOMAIN_MIN":
                guard parts.count >= 4, let edge = floats(parts.dropFirst()) else { return nil }
                lower = edge
            case "DOMAIN_MAX":
                guard parts.count >= 4, let edge = floats(parts.dropFirst()) else { return nil }
                upper = edge
            case "TITLE", "LUT_3D_INPUT_RANGE":
                continue
            default:
                // Anything else has to be a row of three numbers, or the file is not a cube.
                guard size > 0, parts.count >= 3, let row = floats(parts.prefix(3)) else { continue }
                rows += 1
                guard rows <= size * size * size else { return nil }
                for channel in 0..<3 {
                    let span = upper[channel] - lower[channel]
                    let scaled = span > 0 ? (row[channel] - lower[channel]) / span : row[channel]
                    values.append(min(max(scaled, 0), 1))
                }
                values.append(1)
            }
        }

        guard size >= 2, rows == size * size * size else { return nil }
        return Cube(size: size, values: values)
    }

    private static func floats(_ parts: some Sequence<String>) -> [Float]? {
        var result: [Float] = []
        for part in parts {
            guard let value = Float(part), value.isFinite else { return nil }
            result.append(value)
        }
        return result.count == 3 ? result : nil
    }
}
