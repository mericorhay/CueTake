import Foundation
import Testing
@testable import Domain

struct LookUpTableTests {
    /// The smallest real cube: two points an edge, eight rows, red changing fastest.
    private let tiny = """
    # A comment
    TITLE "Tiny"
    LUT_3D_SIZE 2

    0 0 0
    1 0 0
    0 1 0
    1 1 0
    0 0 1
    1 0 1
    0 1 1
    1 1 1
    """

    @Test func readsACubeInTheOrderCoreImageWants() throws {
        let cube = try #require(LookUpTable.parse(tiny))
        #expect(cube.size == 2)
        #expect(cube.values.count == 2 * 2 * 2 * 4)
        // First entry is black, second is red: red varies fastest.
        let first = Array(cube.values.prefix(4))
        let second = Array(cube.values.dropFirst(4).prefix(4))
        #expect(first == [0, 0, 0, 1])
        #expect(second == [1, 0, 0, 1])
        // Every entry is opaque.
        let alphas = stride(from: 3, to: cube.values.count, by: 4).map { cube.values[$0] }
        #expect(alphas.allSatisfy { $0 == 1 })
    }

    @Test func aDomainOtherThanZeroToOneIsScaledIn() throws {
        let scaled = tiny.replacingOccurrences(of: "LUT_3D_SIZE 2", with: "LUT_3D_SIZE 2\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 2 2 2")
        let cube = try #require(LookUpTable.parse(scaled))
        // A row of "1 0 0" in a 0…2 domain is half red, not full red.
        let second = Array(cube.values.dropFirst(4).prefix(4))
        #expect(second == [0.5, 0, 0, 1])
    }

    @Test func aFileThatIsNotACubeIsRefused() {
        #expect(LookUpTable.parse("") == nil)
        #expect(LookUpTable.parse("LUT_1D_SIZE 32\n0 0 0\n1 1 1") == nil)
        // The header promises eight rows and the file has three.
        #expect(LookUpTable.parse("LUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0") == nil)
        // More rows than the header allows: the rest would be read as colours it never set.
        let tooMany = tiny + "\n0.5 0.5 0.5"
        #expect(LookUpTable.parse(tooMany) == nil)
        // A cube nobody could use, and a size that would allocate a gigabyte.
        #expect(LookUpTable.parse("LUT_3D_SIZE 1\n0 0 0") == nil)
        #expect(LookUpTable.parse("LUT_3D_SIZE 512\n0 0 0") == nil)
    }

    @Test func valuesOutsideTheDomainAreBroughtBackIn() throws {
        let wild = """
        LUT_3D_SIZE 2
        -0.4 0 0
        1.8 0 0
        0 1 0
        1 1 0
        0 0 1
        1 0 1
        0 1 1
        1 1 1
        """
        let cube = try #require(LookUpTable.parse(wild))
        #expect(cube.values[0] == 0)
        #expect(cube.values[4] == 1)
    }

    @Test func aGradeIsCarriedWithTheFilterItIsOn() throws {
        var settings = FilterSettings(look: .cinematic)
        settings.lut = LookUpTable(name: "Teal", file: "media/lut-1.cube", size: 33)
        let written = try JSONEncoder().encode(settings)
        let read = try JSONDecoder().decode(FilterSettings.self, from: written)
        #expect(read.lut == settings.lut)
        // Clamping the sliders must not drop it.
        #expect(read.clamped.lut?.name == "Teal")
    }

    @Test func aProjectWrittenBeforeGradesStillReads() throws {
        let old = #"{"look":"vivid","intensity":0.5,"brightness":0,"contrast":0,"saturation":0,"warmth":0,"vignette":0,"sharpness":0}"#
        let read = try JSONDecoder().decode(FilterSettings.self, from: Data(old.utf8))
        #expect(read.look == .vivid)
        #expect(read.lut == nil)
    }
}
