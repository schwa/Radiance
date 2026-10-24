import Foundation
@testable import RadianceSupport
import Testing

struct SplatWalkthroughTests {
    private func sample() -> SplatWalkthrough {
        let kitchen = SplatWalkthrough.SplatReference(path: "kitchen.spz")
        let hall = SplatWalkthrough.SplatReference(path: "rooms/hall.ply", displayName: "Hall")
        return SplatWalkthrough(
            splats: [kitchen, hall],
            volumes: [
                .init(splatID: kitchen.id, floor: [[0, 0], [4, 0], [4, 3], [0, 3]], minHeight: 0, maxHeight: 2.5, name: "Kitchen"),
                .init(splatID: hall.id, floor: [[4, 0], [8, 0], [6, 3]], minHeight: -0.5, maxHeight: 3)
            ],
            crossFade: .init(enabled: true, duration: 0.75, easing: .easeInOut)
        )
    }

    @Test func roundTrips() throws {
        let walkthrough = sample()
        let decoded = try SplatWalkthrough.decode(from: walkthrough.encoded())
        #expect(decoded == walkthrough)
        #expect(decoded.version == SplatWalkthrough.currentVersion)
    }

    @Test func resolvesSplatPathsRelativeToDocument() {
        let reference = SplatWalkthrough.SplatReference(path: "rooms/hall.ply")
        let url = reference.url(relativeTo: URL(filePath: "/tmp/house/house.splatwalkthrough"))
        #expect(url.path == "/tmp/house/rooms/hall.ply")
    }

    @Test func easingIsOptional() throws {
        var walkthrough = sample()
        walkthrough.crossFade = .init(enabled: false, duration: 0)
        let decoded = try SplatWalkthrough.decode(from: walkthrough.encoded())
        #expect(decoded.crossFade.easing == nil)
        #expect(decoded.crossFade.enabled == false)
    }

    @Test func rejectsNewerVersion() throws {
        var walkthrough = sample()
        walkthrough.version = SplatWalkthrough.currentVersion + 1
        #expect(throws: SplatWalkthrough.ValidationError.unsupportedVersion(walkthrough.version)) {
            try SplatWalkthrough.decode(from: walkthrough.encoded())
        }
    }

    @Test func rejectsVolumeWithUnknownSplat() {
        var walkthrough = sample()
        let missing = UUID()
        walkthrough.volumes[0].splatID = missing
        #expect(throws: SplatWalkthrough.ValidationError.unknownSplat(volume: walkthrough.volumes[0].id, splat: missing)) {
            try walkthrough.validate()
        }
    }

    @Test func rejectsDegenerateFloorAndHeights() {
        var walkthrough = sample()
        walkthrough.volumes[0].floor = [[0, 0], [1, 0]]
        #expect(throws: SplatWalkthrough.ValidationError.degenerateFloor(volume: walkthrough.volumes[0].id)) {
            try walkthrough.validate()
        }
        walkthrough = sample()
        walkthrough.volumes[1].maxHeight = walkthrough.volumes[1].minHeight
        #expect(throws: SplatWalkthrough.ValidationError.invalidHeightRange(volume: walkthrough.volumes[1].id)) {
            try walkthrough.validate()
        }
    }

    @Test func rejectsDuplicateSplatIDs() {
        var walkthrough = sample()
        walkthrough.splats[1].id = walkthrough.splats[0].id
        #expect(throws: SplatWalkthrough.ValidationError.duplicateSplatID(walkthrough.splats[0].id)) {
            try walkthrough.validate()
        }
    }
}
