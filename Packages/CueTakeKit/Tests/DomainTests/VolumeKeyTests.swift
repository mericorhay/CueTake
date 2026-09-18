import Foundation
import Testing
@testable import Domain

struct VolumeKeyTests {
    private func song(seconds: Double = 20) -> AudioClip {
        AudioClip(
            name: "song",
            relativePath: "media/song.m4a",
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: seconds))
        )
    }

    @Test func theCurveIsFlatWhereNobodyDrew() {
        var clip = song()
        #expect(clip.automation(at: 5) == 1)
        clip.setVolumeKey(at: 4, level: 0.4)
        clip.setVolumeKey(at: 8, level: 1.2)
        #expect(abs(clip.automation(at: 0) - 0.4) < 0.0001)
        #expect(abs(clip.automation(at: 6) - 0.8) < 0.0001)
        #expect(abs(clip.automation(at: 19) - 1.2) < 0.0001)
    }

    @Test func aKeyBesideAnotherMovesItInsteadOfAddingOne() {
        var clip = song()
        clip.setVolumeKey(at: 5, level: 0.5)
        clip.setVolumeKey(at: 5.02, level: 0.9)
        let keys = clip.orderedVolumeKeys
        #expect(keys.count == 1)
        #expect(abs((keys.first?.level ?? 0) - 0.9) < 0.0001)
    }

    @Test func levelsAndTimesStayInside() {
        var clip = song(seconds: 10)
        clip.setVolumeKey(at: 40, level: 9)
        clip.setVolumeKey(at: -3, level: -1)
        let keys = clip.orderedVolumeKeys
        let times = keys.map { $0.time }
        let levels = keys.map { $0.level }
        #expect(times == [0, 10])
        #expect(levels == [0, 2])
    }

    @Test func removingTheLastKeyLeavesNoCurveAtAll() {
        var clip = song()
        clip.setVolumeKey(at: 5, level: 0.5)
        #expect(!clip.removeVolumeKey(near: 12))
        #expect(clip.removeVolumeKey(near: 5.1))
        #expect(clip.volumeKeys == nil)
    }

    @Test func shiftingDropsKeysThatFallOffTheClip() {
        var clip = song(seconds: 10)
        clip.setVolumeKey(at: 1, level: 0.5)
        clip.setVolumeKey(at: 6, level: 0.8)
        clip.shiftVolumeKeys(by: -3)
        let times = clip.orderedVolumeKeys.map { $0.time }
        #expect(times == [3])
    }

    @Test func aProjectWrittenBeforeKeysStillReads() throws {
        let clip = song()
        var written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as? [String: Any] ?? [:]
        written["volumeKeys"] = nil
        let data = try JSONSerialization.data(withJSONObject: written)
        let read = try JSONDecoder().decode(AudioClip.self, from: data)
        #expect(read.volumeKeys == nil)
        #expect(read.automation(at: 3) == 1)
    }

    @Test func aCopyHasItsOwnKeys() {
        var clip = song()
        clip.setVolumeKey(at: 2, level: 0.3)
        let copy = clip.copyWithNewIdentity()
        let mine = clip.orderedVolumeKeys.map { $0.id }
        let theirs = copy.orderedVolumeKeys.map { $0.id }
        #expect(copy.orderedVolumeKeys.count == 1)
        #expect(Set(mine).isDisjoint(with: theirs))
    }
}
