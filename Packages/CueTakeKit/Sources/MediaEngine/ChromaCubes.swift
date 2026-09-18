import CoreGraphics
import CoreImage
import Domain
import Foundation

/// Colour keys as Core Image colour cubes: the whole key — what goes, what stays, the spill
/// taken off — worked out once per setting and then applied to every frame as a table lookup,
/// fast enough for the preview to play it.
public final class ChromaCubes: @unchecked Sendable {
    public static let shared = ChromaCubes()

    /// Points per side. 32 keeps the edge smooth; the table is half a megabyte.
    static let size = 32

    private let lock = NSLock()
    private var cubes: [String: Data] = [:]
    private let space = CGColorSpace(name: CGColorSpace.sRGB)

    /// The frame with the key colour gone, see-through where it was.
    public func apply(_ key: ChromaKey, to image: CIImage) -> CIImage {
        guard let space else { return image }
        return image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": Self.size,
            "inputCubeData": data(for: key),
            "inputColorSpace": space,
        ])
    }

    func data(for key: ChromaKey) -> Data {
        let token = key.token
        if let cached = lock.withLock({ cubes[token] }) { return cached }
        let made = Self.build(key)
        lock.withLock {
            // A handful of keys at most are in use; forget them all rather than grow.
            if cubes.count > 12 { cubes.removeAll() }
            cubes[token] = made
        }
        return made
    }

    /// Red changes fastest, then green, then blue; premultiplied, as Core Image wants it.
    static func build(_ key: ChromaKey) -> Data {
        let n = size
        var values = [Float](repeating: 0, count: n * n * n * 4)
        let step = 1 / Double(n - 1)
        var index = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let out = key.keyed(red: Double(r) * step, green: Double(g) * step, blue: Double(b) * step)
                    values[index] = Float(out.red * out.alpha)
                    values[index + 1] = Float(out.green * out.alpha)
                    values[index + 2] = Float(out.blue * out.alpha)
                    values[index + 3] = Float(out.alpha)
                    index += 4
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
