import Foundation
import Testing
@testable import Domain

struct ChromaKeyTests {
    @Test func aGreenScreenGoesAndWhatIsInFrontOfItStays() {
        let key = ChromaKey.green
        #expect(key.keyed(red: 0.1, green: 0.85, blue: 0.3).alpha < 0.01)
        #expect(key.keyed(red: 0.2, green: 0.9, blue: 0.3).alpha < 0.01)
        // Skin, grey, white, black and a yellow-green shirt are not the screen.
        #expect(key.keyed(red: 0.8, green: 0.6, blue: 0.5).alpha > 0.99)
        #expect(key.keyed(red: 0.5, green: 0.5, blue: 0.5).alpha > 0.99)
        #expect(key.keyed(red: 1, green: 1, blue: 1).alpha > 0.99)
        #expect(key.keyed(red: 0, green: 0, blue: 0).alpha > 0.99)
        #expect(key.keyed(red: 0.6, green: 0.8, blue: 0.2).alpha > 0.99)
    }

    @Test func aBlueScreenTakesBlueAndLeavesGreen() {
        let key = ChromaKey.blue
        #expect(key.keyed(red: 0.05, green: 0.25, blue: 0.9).alpha < 0.01)
        #expect(key.keyed(red: 0.1, green: 0.85, blue: 0.3).alpha > 0.99)
    }

    @Test func aWiderRangeTakesMoreOfTheShadowOnTheScreen() {
        var narrow = ChromaKey.green
        narrow.tolerance = 0
        var wide = ChromaKey.green
        wide.tolerance = 1
        let shadow = (red: 0.0, green: 0.3, blue: 0.1)
        let kept = narrow.keyed(red: shadow.red, green: shadow.green, blue: shadow.blue).alpha
        let taken = wide.keyed(red: shadow.red, green: shadow.green, blue: shadow.blue).alpha
        #expect(taken < kept)
    }

    @Test func spillTakesTheScreensGlowOffSkin() {
        var full = ChromaKey.green
        full.spill = 1
        var none = ChromaKey.green
        none.spill = 0
        let lit = full.keyed(red: 0.7, green: 0.8, blue: 0.55)
        #expect(abs(lit.green - 0.7) < 0.0001)
        #expect(lit.red == 0.7)
        let untouched = none.keyed(red: 0.7, green: 0.8, blue: 0.55)
        #expect(untouched.green == 0.8)
        // A pixel with no cast keeps its colour.
        let plain = full.keyed(red: 0.8, green: 0.6, blue: 0.5)
        #expect(plain.green == 0.6)
    }

    @Test func settingsAreClampedAndNamedByWhatTheyDo() {
        let wild = ChromaKey(color: .white, tolerance: 4, softness: -1, spill: 2)
        #expect(wild.tolerance == 1)
        #expect(wild.softness == 0)
        #expect(wild.spill == 1)
        var other = ChromaKey.green
        #expect(other.token == ChromaKey.green.token)
        other.tolerance = 0.9
        #expect(other.token != ChromaKey.green.token)
    }

    @Test func backgroundsFromBeforeTheChoiceKeepTheirFileNames() throws {
        // What build 103 wrote, with no cutout in it.
        let json = Data(#"{"style":"blur","strength":0.5,"feather":0.35,"fineEdges":false}"#.utf8)
        let old = try JSONDecoder().decode(BackgroundSettings.self, from: json)
        #expect(old.cutout == .person)
        #expect(old.key == nil)
        #expect(old.token == "blur_s50_f35")
        #expect(BackgroundSettings(style: .black).token == "black_f35")
    }

    @Test func objectAndColourCutoutsRenderFilesOfTheirOwn() throws {
        let person = BackgroundSettings(style: .studio)
        let subject = BackgroundSettings(style: .studio, cutout: .subject)
        let keyed = BackgroundSettings(style: .studio, cutout: .color, key: .green)
        #expect(Set([person.token, subject.token, keyed.token]).count == 3)
        #expect(subject.token.contains("subj"))
        // A keyed colour has no feathered mask; its edge is the key's own.
        #expect(!keyed.usesFeather)
        #expect(!keyed.token.contains("_f"))
        var bluer = keyed
        bluer.key = .blue
        #expect(bluer.token != keyed.token)
        // No key chosen yet is a green screen.
        #expect(BackgroundSettings(style: .black, cutout: .color).effectiveKey == ChromaKey.green)

        let round = try JSONDecoder().decode(BackgroundSettings.self, from: JSONEncoder().encode(keyed))
        #expect(round == keyed)
    }

    @Test func overlaysFromBeforeStayInFront() throws {
        let overlay = Overlay(content: .text(OverlayText(text: "Hi")), start: MediaTime(seconds: 1))
        var data = try JSONEncoder().encode(overlay)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "isBehindPerson")
        data = try JSONSerialization.data(withJSONObject: object)
        let old = try JSONDecoder().decode(Overlay.self, from: data)
        #expect(!old.isBehindPerson)

        var behind = overlay
        behind.isBehindPerson = true
        let round = try JSONDecoder().decode(Overlay.self, from: JSONEncoder().encode(behind))
        #expect(round.isBehindPerson)
    }

    @Test func behindAPersonAFadeIsDrawnAsLight() {
        var overlay = Overlay(content: .text(OverlayText(text: "Hi")), start: MediaTime(seconds: 1), duration: MediaTime(seconds: 2))
        overlay.animation = .fade
        #expect(overlay.visibility(at: 0.9) == 0)
        #expect(overlay.visibility(at: 1) == 0)
        #expect(abs(overlay.visibility(at: 1.125) - 0.5) < 0.001)
        #expect(overlay.visibility(at: 2) == 1)
        #expect(overlay.visibility(at: 3) == 0)
        overlay.animation = .pop
        overlay.transform.opacity = 0.6
        #expect(abs(overlay.visibility(at: 1) - 0.6) < 0.001)
    }

    @Test func aKeyedAddedVideoRoundTrips() throws {
        var layer = VideoLayer(
            recordingID: UUID(),
            title: "screen",
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 3))
        )
        layer.chroma = .blue
        let round = try JSONDecoder().decode(VideoLayer.self, from: JSONEncoder().encode(layer))
        #expect(round.chroma == .blue)
    }
}
