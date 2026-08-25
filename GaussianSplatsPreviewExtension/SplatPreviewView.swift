#if !arch(x86_64)
import GeometryLite3D
import Interaction3D
import Metal
import MetalSprockets
import MetalSprocketsGaussianSplats
import MetalSprocketsGaussianSplatShaders
import MetalSprocketsUI
import simd
import SwiftUI

struct SplatPreviewView: View {
    let splatCloud: GPUSplatCloud<SparkSplat>
    let sortResources: GPUSortResources

    @State private var cameraMatrix = simd_float4x4(translation: [0, 0, 5])
    private let modelMatrix = simd_float4x4(xRotation: .radians(.pi))
    private let projection = PerspectiveProjection(
        verticalAngleOfView: .degrees(90),
        depthMode: .standard(zClip: 0.01 ... 1_000)
    )

    init(splatCloud: GPUSplatCloud<SparkSplat>) throws {
        self.splatCloud = splatCloud
        let device = MTLCreateSystemDefaultDevice()!
        self.sortResources = try GPUSortResources(device: device, capacity: splatCloud.count)
    }

    var body: some View {
        RenderView { _, drawableSize in
            let projectionMatrix = projection.projectionMatrix(for: drawableSize)
            try GPUSortedSplatRenderPipeline(
                splatCloud: splatCloud,
                projectionMatrix: projectionMatrix,
                modelMatrix: modelMatrix,
                cameraMatrix: cameraMatrix,
                drawableSize: SIMD2<Float>(drawableSize),
                resources: sortResources
            )
        }
        .metalColorPixelFormat(.bgra8Unorm_srgb)
        .metalClearColor(.init(red: 0, green: 0, blue: 0, alpha: 1))
        .interactiveCamera(cameraMatrix: $cameraMatrix, mode: .turntable())
    }
}
#endif
