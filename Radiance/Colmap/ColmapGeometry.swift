import Metal
import simd

// MARK: - Point Vertex

struct PointVertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>

    static let descriptor: MTLVertexDescriptor = {
        let desc = MTLVertexDescriptor()
        desc.attributes[0].format = .float3
        desc.attributes[0].offset = 0
        desc.attributes[0].bufferIndex = 0

        desc.attributes[1].format = .float4
        desc.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        desc.attributes[1].bufferIndex = 0

        desc.layouts[0].stride = MemoryLayout<Self>.stride
        desc.layouts[0].stepFunction = .perVertex
        return desc
    }()
}

// MARK: - Line Vertex

struct LineVertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>

    static let descriptor: MTLVertexDescriptor = {
        let desc = MTLVertexDescriptor()
        desc.attributes[0].format = .float3
        desc.attributes[0].offset = 0
        desc.attributes[0].bufferIndex = 0

        desc.attributes[1].format = .float4
        desc.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        desc.attributes[1].bufferIndex = 0

        desc.layouts[0].stride = MemoryLayout<Self>.stride
        desc.layouts[0].stepFunction = .perVertex
        return desc
    }()
}

// MARK: - Geometry Builders

func buildPointVertices(from scene: ColmapScene) -> [PointVertex] {
    scene.points.map { point in
        PointVertex(
            position: point.position,
            color: SIMD4<Float>(
                Float(point.color.x) / 255.0,
                Float(point.color.y) / 255.0,
                Float(point.color.z) / 255.0,
                1.0
            )
        )
    }
}

/// Build camera frustum wireframes as line segments
func buildCameraFrustumVertices(from scene: ColmapScene, frustumScale: Float = 0.5) -> [LineVertex] {
    var vertices: [LineVertex] = []

    for image in scene.images {
        guard let camera = scene.cameras[image.cameraId] else { continue }

        let c2w = image.cameraToWorld

        // Compute frustum corners in camera space
        let fx = Float(camera.params[0])
        let w = Float(camera.width)
        let h = Float(camera.height)

        // Half-extents at unit depth, normalized by focal length
        let halfW = (w / 2) / fx * frustumScale
        let halfH = (h / 2) / fx * frustumScale
        let d = frustumScale // depth

        // Frustum corners in camera space (COLMAP: +Z forward, +X right, +Y down)
        let corners: [SIMD3<Float>] = [
            SIMD3<Float>(-halfW, -halfH, d), // top-left
            SIMD3<Float>(halfW, -halfH, d), // top-right
            SIMD3<Float>(halfW, halfH, d), // bottom-right
            SIMD3<Float>(-halfW, halfH, d) // bottom-left
        ]

        // Transform to world space
        let origin = SIMD3<Float>(c2w.columns.3.x, c2w.columns.3.y, c2w.columns.3.z)
        let worldCorners = corners.map { corner -> SIMD3<Float> in
            let world = c2w * SIMD4<Float>(corner, 1.0)
            return SIMD3<Float>(world.x, world.y, world.z)
        }

        let frustumColor = SIMD4<Float>(1.0, 0.8, 0.0, 1.0) // Yellow

        // Lines from origin to each corner
        for corner in worldCorners {
            vertices.append(LineVertex(position: origin, color: frustumColor))
            vertices.append(LineVertex(position: corner, color: frustumColor))
        }

        // Lines connecting the corners (rectangle at far plane)
        for i in 0..<4 {
            vertices.append(LineVertex(position: worldCorners[i], color: frustumColor))
            vertices.append(LineVertex(position: worldCorners[(i + 1) % 4], color: frustumColor))
        }

        // Camera up indicator (triangle on top edge)
        let upMid = (worldCorners[0] + worldCorners[1]) / 2
        let upDir = simd_normalize(upMid - origin)
        let upTip = upMid + upDir * frustumScale * 0.15
        let upColor = SIMD4<Float>(0.0, 1.0, 0.0, 1.0) // Green for up
        vertices.append(LineVertex(position: worldCorners[0], color: upColor))
        vertices.append(LineVertex(position: upTip, color: upColor))
        vertices.append(LineVertex(position: worldCorners[1], color: upColor))
        vertices.append(LineVertex(position: upTip, color: upColor))
    }

    return vertices
}
