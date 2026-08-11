import Foundation
import simd

// MARK: - Data Types

struct ColmapPoint: Sendable {
    let id: UInt64
    let position: SIMD3<Float>
    let color: SIMD3<UInt8>
    let error: Double
}

struct ColmapCamera: Sendable {
    let id: UInt32
    let modelId: UInt32
    let width: UInt64
    let height: UInt64
    let params: [Double] // fx, cx, cy, k for SIMPLE_RADIAL
}

struct ColmapImage: Sendable {
    let id: UInt32
    let quaternion: simd_quatf // w, x, y, z
    let translation: SIMD3<Float>
    let cameraId: UInt32
    let name: String

    /// Camera-to-world transform (the camera's pose in world space)
    var cameraToWorld: float4x4 {
        // COLMAP stores world-to-camera: R * X_world + t = X_camera
        // So camera center in world = -R^T * t
        let rotation = float4x4(quaternion.inverse)
        let center = -quaternion.inverse.act(translation)
        var transform = rotation
        transform.columns.3 = SIMD4<Float>(center, 1)
        return transform
    }
}

struct ColmapScene: Sendable {
    let points: [ColmapPoint]
    let cameras: [UInt32: ColmapCamera]
    let images: [ColmapImage]

    /// Bounding box of points only
    var pointsBoundingBox: (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard let first = points.first else {
            return (min: .zero, max: .zero)
        }
        var minP = first.position
        var maxP = first.position
        for point in points {
            minP = simd_min(minP, point.position)
            maxP = simd_max(maxP, point.position)
        }
        return (min: minP, max: maxP)
    }

    /// Bounding box including points and camera positions
    var boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>) {
        var bb = pointsBoundingBox
        for image in images {
            let c2w = image.cameraToWorld
            let camPos = SIMD3<Float>(c2w.columns.3.x, c2w.columns.3.y, c2w.columns.3.z)
            bb.min = simd_min(bb.min, camPos)
            bb.max = simd_max(bb.max, camPos)
        }
        return bb
    }

    var center: SIMD3<Float> {
        let bb = boundingBox
        return (bb.min + bb.max) / 2
    }
}

// MARK: - Parser

enum ColmapParser {
    static func load(directory: URL) throws -> ColmapScene {
        let points = try parsePoints3D(url: directory.appendingPathComponent("points3D.bin"))
        let cameras = try parseCameras(url: directory.appendingPathComponent("cameras.bin"))
        let images = try parseImages(url: directory.appendingPathComponent("images.bin"))
        return ColmapScene(points: points, cameras: cameras, images: images)
    }

    static func parsePoints3D(url: URL) throws -> [ColmapPoint] {
        let data = try Data(contentsOf: url)
        var offset = 0

        func read<T>(_: T.Type) -> T {
            let value = data[offset..<offset + MemoryLayout<T>.size].withUnsafeBytes { $0.loadUnaligned(as: T.self) }
            offset += MemoryLayout<T>.size
            return value
        }

        let numPoints: UInt64 = read(UInt64.self)
        var points: [ColmapPoint] = []
        points.reserveCapacity(Int(numPoints))

        for _ in 0..<numPoints {
            let pointId: UInt64 = read(UInt64.self)
            let x: Double = read(Double.self)
            let y: Double = read(Double.self)
            let z: Double = read(Double.self)
            let r: UInt8 = read(UInt8.self)
            let g: UInt8 = read(UInt8.self)
            let b: UInt8 = read(UInt8.self)
            let error: Double = read(Double.self)
            let trackLength: UInt64 = read(UInt64.self)
            offset += Int(trackLength) * 8 // skip track entries

            points.append(ColmapPoint(
                id: pointId,
                position: SIMD3<Float>(Float(x), Float(y), Float(z)),
                color: SIMD3<UInt8>(r, g, b),
                error: error
            ))
        }
        return points
    }

    static func parseCameras(url: URL) throws -> [UInt32: ColmapCamera] {
        let data = try Data(contentsOf: url)
        var offset = 0

        func read<T>(_: T.Type) -> T {
            let value = data[offset..<offset + MemoryLayout<T>.size].withUnsafeBytes { $0.loadUnaligned(as: T.self) }
            offset += MemoryLayout<T>.size
            return value
        }

        let numCameras: UInt64 = read(UInt64.self)
        var cameras: [UInt32: ColmapCamera] = [:]

        let numParamsForModel: [UInt32: Int] = [0: 3, 1: 4, 2: 4, 3: 5, 4: 8]

        for _ in 0..<numCameras {
            let cameraId: UInt32 = read(UInt32.self)
            let modelId: UInt32 = read(UInt32.self)
            let width: UInt64 = read(UInt64.self)
            let height: UInt64 = read(UInt64.self)
            let numParams = numParamsForModel[modelId] ?? 4
            var params: [Double] = []
            for _ in 0..<numParams {
                params.append(read(Double.self))
            }
            cameras[cameraId] = ColmapCamera(id: cameraId, modelId: modelId, width: width, height: height, params: params)
        }
        return cameras
    }

    static func parseImages(url: URL) throws -> [ColmapImage] {
        let data = try Data(contentsOf: url)
        var offset = 0

        func read<T>(_: T.Type) -> T {
            let value = data[offset..<offset + MemoryLayout<T>.size].withUnsafeBytes { $0.loadUnaligned(as: T.self) }
            offset += MemoryLayout<T>.size
            return value
        }

        let numImages: UInt64 = read(UInt64.self)
        var images: [ColmapImage] = []

        for _ in 0..<numImages {
            let imageId: UInt32 = read(UInt32.self)
            let qw: Double = read(Double.self)
            let qx: Double = read(Double.self)
            let qy: Double = read(Double.self)
            let qz: Double = read(Double.self)
            let tx: Double = read(Double.self)
            let ty: Double = read(Double.self)
            let tz: Double = read(Double.self)
            let cameraId: UInt32 = read(UInt32.self)

            // Read null-terminated name
            var nameBytes: [UInt8] = []
            while offset < data.count {
                let byte: UInt8 = read(UInt8.self)
                if byte == 0 { break }
                nameBytes.append(byte)
            }
            let name = String(bytes: nameBytes, encoding: .utf8) ?? ""

            let numPoints2D: UInt64 = read(UInt64.self)
            offset += Int(numPoints2D) * 24 // skip 2D points

            images.append(ColmapImage(
                id: imageId,
                quaternion: simd_quatf(ix: Float(qx), iy: Float(qy), iz: Float(qz), r: Float(qw)),
                translation: SIMD3<Float>(Float(tx), Float(ty), Float(tz)),
                cameraId: cameraId,
                name: name
            ))
        }
        return images
    }
}
