#if os(iOS) || os(macOS)
import GeometryLite3D
import Interaction3D
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsGaussianSplats
import MetalSprocketsGaussianSplatsDebug
import MetalSprocketsGaussianSplatShaders
import MetalSprocketsUI
import simd
import Splats
import SwiftUI

// MARK: - Multi-Cloud Render View

/// Renders each cloud through the shared GPU-sorted pipeline, in draw order.
/// Clouds are sorted independently on the GPU; there is no global cross-cloud
/// ordering.
struct MultiCloudRenderView: View {
    let clouds: [GPUSplatCloud<SparkSplat>]

    let cameraMatrix: simd_float4x4
    let sceneTransform: simd_float4x4
    let verticalAngleOfView: Double
    let nearClip: Double
    let farClip: Double
    let useSphericalHarmonics: Bool
    let gridColor: Color
    let showGrid: Bool
    let showAxes: Bool
    let backgroundColor: [Float]
    var cullBoundingBox: BoundingBox3D?

    // Debug rendering
    var debugParams: DebugParams?

    // FPS tracking callback
    var onFrame: (() -> Void)?
    var onDrawableSizeChange: ((CGSize) -> Void)?

    @State private var resources: [GPUSortResources] = []

    private var clearColor: MTLClearColor {
        guard backgroundColor.count == 4 else {
            return MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        }
        return MTLClearColor(
            red: Double(backgroundColor[0]),
            green: Double(backgroundColor[1]),
            blue: Double(backgroundColor[2]),
            alpha: Double(backgroundColor[3])
        )
    }

    var body: some View {
        let resolvedGridColor = gridColor.resolve(in: .init())
        let gridColorVector = SIMD4<Float>(Float(resolvedGridColor.red), Float(resolvedGridColor.green), Float(resolvedGridColor.blue), Float(resolvedGridColor.opacity))

        RenderView { _, drawableSize in
            let projection = PerspectiveProjection(verticalAngleOfView: .degrees(Float(verticalAngleOfView)), depthMode: .standard(zClip: Float(nearClip) ... Float(farClip)))
            let projectionMatrix = projection.projectionMatrix(for: drawableSize)
            let drawableSizeVector = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))

            let showGuides = showGrid || showAxes
            if showGuides {
                SceneGuidesRenderPass(projectionMatrix: projectionMatrix, cameraMatrix: cameraMatrix, drawableSize: drawableSizeVector, gridColor: showGrid ? gridColorVector : nil, showAxes: showAxes)
            }

            if resources.count == clouds.count {
                ForEach(Array(clouds.enumerated()), id: \.offset) { index, cloud in
                    // The first cloud clears (or loads over the guides);
                    // later clouds composite over earlier ones.
                    let loadAction: MTLLoadAction? = index == 0 ? (showGuides ? .load : nil) : .load
                    if let debugParams {
                        try GPUSortedSplatDebugRenderPipeline(
                            splatCloud: cloud,
                            projectionMatrix: projectionMatrix,
                            modelMatrix: sceneTransform,
                            cameraMatrix: cameraMatrix,
                            drawableSize: drawableSizeVector,
                            debugParams: debugParams,
                            resources: resources[index]
                        )
                        .renderPassDescriptorModifier { descriptor in
                            if let loadAction {
                                descriptor.colorAttachments[0].loadAction = loadAction
                            }
                        }
                    } else {
                        try GuidedSplatRenderPass(
                            splatCloud: cloud,
                            projectionMatrix: projectionMatrix,
                            modelMatrix: sceneTransform,
                            cameraMatrix: cameraMatrix,
                            drawableSize: drawableSizeVector,
                            useSphericalHarmonics: useSphericalHarmonics,
                            colorLoadAction: loadAction,
                            boxes: [],
                            resources: resources[index],
                            boundingBox: cullBoundingBox
                        )
                    }
                }
            }
        }
        .metalColorPixelFormat(.bgra8Unorm_srgb)
        .metalClearColor(clearColor)
        .frameRatePreference()
        .onFrameTimingChange { _ in
            onFrame?()
        }
        .onDrawableSizeChange { size in
            onDrawableSizeChange?(size)
        }
        .task(id: clouds.count) {
            updateResources()
        }
    }

    private func updateResources() {
        guard let device = clouds.first?.splats.unsafeMTLBuffer.device else {
            resources = []
            return
        }
        guard resources.count != clouds.count else {
            return
        }
        resources = clouds.compactMap { cloud in
            try? GPUSortResources(device: device, capacity: cloud.count)
        }
    }
}
#endif
