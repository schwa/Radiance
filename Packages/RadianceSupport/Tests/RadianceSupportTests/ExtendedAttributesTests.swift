import Foundation
@testable import RadianceSupport
import Testing

struct ExtendedAttributesTests {
    private static let name = "com.schwa.radiance.test"

    private func makeFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "xattr-\(UUID().uuidString).txt")
        try Data("splat".utf8).write(to: url)
        return url
    }

    @Test func missingAttributeIsNil() throws {
        let url = try makeFile()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try ExtendedAttributes.data(named: Self.name, at: url) == nil)
    }

    @Test func writeThenRead() throws {
        let url = try makeFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let payload = Data(#"{"verticalAngleOfView": 60}"#.utf8)
        try ExtendedAttributes.setData(payload, named: Self.name, at: url)
        #expect(try ExtendedAttributes.data(named: Self.name, at: url) == payload)
    }

    @Test func overwriteReplacesValue() throws {
        let url = try makeFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try ExtendedAttributes.setData(Data("first, longer value".utf8), named: Self.name, at: url)
        try ExtendedAttributes.setData(Data("second".utf8), named: Self.name, at: url)
        #expect(try ExtendedAttributes.data(named: Self.name, at: url) == Data("second".utf8))
    }

    @Test func removeDeletesAndIsIdempotent() throws {
        let url = try makeFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try ExtendedAttributes.setData(Data("x".utf8), named: Self.name, at: url)
        try ExtendedAttributes.remove(named: Self.name, at: url)
        try ExtendedAttributes.remove(named: Self.name, at: url)
        #expect(try ExtendedAttributes.data(named: Self.name, at: url) == nil)
    }

    @Test func missingFileThrows() {
        let url = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString)")
        #expect(throws: (any Error).self) {
            try ExtendedAttributes.data(named: Self.name, at: url)
        }
    }
}
