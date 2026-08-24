import Foundation
import GeometryLite3D
import Metal
import MetalSprocketsGaussianSplats
import MetalSprocketsGaussianSplatShaders
import MetalSprocketsSupport
import simd
import Splats
import UniformTypeIdentifiers

struct SplatCloudDescriptor: Sendable {
    var url: URL
    var contentType: UTType?
    var fileSize: Int
    var splatCount: Int = 0
    var shDegree: UInt8 = 0

    var bytesPerSplat: Double {
        guard splatCount > 0 else {
            return 0
        }
        return Double(fileSize) / Double(splatCount)
    }

    var hasSphericalHarmonics: Bool {
        shDegree > 0
    }

    var fileTypeDescription: String {
        contentType?.localizedDescription ?? "Unknown"
    }

    init(url: URL) throws {
        self.url = url

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        fileSize = attributes[.size] as? Int ?? 0

        contentType = UTType(filenameExtension: url.pathExtension)

        switch contentType {
        case .spz:
            let reader = try SPZReader(url: url)
            splatCount = reader.splatCount
            shDegree = reader.shDegree

        case .ply:
            let reader = try PLYSplatReader(url: url)
            splatCount = reader.splatCount
            shDegree = reader.shDegree

        case .antimatter15Splat:
            let reader = try Antimatter15Reader(url: url)
            splatCount = reader.splatCount
            shDegree = 0

        case .sog:
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw SplatLoaderError.unsupportedFormat(url.pathExtension)
            }
            let result = try SplatLoader.read(device: device, url: url)
            splatCount = result.count
            shDegree = result.shDegree

        default:
            splatCount = 0
            shDegree = 0
        }
    }

    @concurrent
    func computeBounds() async throws -> BoundingBox {
        var bounds = BoundingBox.empty
        switch contentType {
        case .spz:
            let reader = try SPZReader(url: url)
            try reader.read { _, extendedSplat in
                bounds.expand(by: extendedSplat.genericSplat.position)
            }

        case .ply:
            let reader = try PLYSplatReader(url: url)
            try reader.read { _, extendedSplat in
                bounds.expand(by: extendedSplat.genericSplat.position)
            }

        case .antimatter15Splat:
            let reader = try Antimatter15Reader(url: url)
            try reader.read { _, extendedSplat in
                bounds.expand(by: extendedSplat.genericSplat.position)
            }

        case .sog:
            break

        default:
            break
        }
        return bounds
    }
}

#if !arch(x86_64)
import Metal
import MetalSprocketsGaussianSplatShaders
import MetalSprocketsSupport

extension SplatCloudDescriptor {
    nonisolated func loadGPUSplatCloud(modelTransform: simd_float4x4 = .identity) throws -> GPUSplatCloud<SparkSplat> {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "SplatCloudDescriptor", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Metal device available"])
        }

        return GPUSplatCloud(try SplatLoader.read(device: device, url: url), modelTransform: modelTransform)
    }
}
#endif
