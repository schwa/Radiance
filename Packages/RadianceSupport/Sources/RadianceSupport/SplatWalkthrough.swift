import Foundation
import simd
import UniformTypeIdentifiers

// A walkable space captured as several splat files (e.g. one per room). The
// camera's containing volume picks which splat is visible. World space is Y-up;
// volume floors are polygons in the XZ plane.
nonisolated public struct SplatWalkthrough: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var splats: [SplatReference]
    public var volumes: [Volume]
    public var crossFade: CrossFade

    public init(splats: [SplatReference] = [], volumes: [Volume] = [], crossFade: CrossFade = CrossFade()) {
        self.version = Self.currentVersion
        self.splats = splats
        self.volumes = volumes
        self.crossFade = crossFade
    }

    public struct SplatReference: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        // Relative to the walkthrough document's directory so the bundle can move as a unit.
        public var path: String
        public var displayName: String?

        public init(path: String, displayName: String? = nil, id: UUID = UUID()) {
            self.id = id
            self.path = path
            self.displayName = displayName
        }

        public func url(relativeTo documentURL: URL) -> URL {
            documentURL.deletingLastPathComponent().appending(path: path)
        }
    }

    // A prism: a floor polygon (XZ) extruded from minHeight to maxHeight (Y).
    public struct Volume: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var name: String?
        public var splatID: UUID
        public var floor: [SIMD2<Float>]
        public var minHeight: Float
        public var maxHeight: Float

        public init(splatID: UUID, floor: [SIMD2<Float>], minHeight: Float, maxHeight: Float, name: String? = nil, id: UUID = UUID()) {
            self.id = id
            self.name = name
            self.splatID = splatID
            self.floor = floor
            self.minHeight = minHeight
            self.maxHeight = maxHeight
        }
    }

    public struct CrossFade: Codable, Sendable, Equatable {
        public enum Easing: String, Codable, Sendable {
            case linear
            case easeInOut = "ease-in-out"
        }

        public var enabled: Bool
        public var duration: Double
        public var easing: Easing?

        public init(enabled: Bool = true, duration: Double = 0.5, easing: Easing? = nil) {
            self.enabled = enabled
            self.duration = duration
            self.easing = easing
        }
    }

    public enum ValidationError: Error, Equatable {
        case unsupportedVersion(Int)
        case duplicateSplatID(UUID)
        case unknownSplat(volume: UUID, splat: UUID)
        case degenerateFloor(volume: UUID)
        case invalidHeightRange(volume: UUID)
        case invalidCrossFadeDuration
    }

    public func validate() throws(ValidationError) {
        guard version <= Self.currentVersion else {
            throw .unsupportedVersion(version)
        }
        var splatIDs = Set<UUID>()
        for splat in splats where !splatIDs.insert(splat.id).inserted {
            throw .duplicateSplatID(splat.id)
        }
        for volume in volumes {
            guard splatIDs.contains(volume.splatID) else {
                throw .unknownSplat(volume: volume.id, splat: volume.splatID)
            }
            guard volume.floor.count >= 3 else {
                throw .degenerateFloor(volume: volume.id)
            }
            guard volume.minHeight < volume.maxHeight else {
                throw .invalidHeightRange(volume: volume.id)
            }
        }
        guard crossFade.duration >= 0 else {
            throw .invalidCrossFadeDuration
        }
    }

    public static func decode(from data: Data) throws -> Self {
        let walkthrough = try JSONDecoder().decode(Self.self, from: data)
        try walkthrough.validate()
        return walkthrough
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public extension UTType {
    /// Splat walkthrough document (`.splatwalkthrough`).
    nonisolated static let splatWalkthrough = UTType(exportedAs: "com.schwa.splatwalkthrough", conformingTo: .json)
}
