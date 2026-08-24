#if os(visionOS)
import CompositorServices
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsGaussianSplats
import MetalSprocketsGaussianSplatShaders
import MetalSprocketsSupport
import MetalSprocketsUI
import simd

struct ImmersiveGPUSortElement: Element, @unchecked Sendable {
    let content: SplatImmersiveGPUSortElement

    init(context: ImmersiveContext, splatCloud: GPUSplatCloud<SparkSplat>, modelMatrix: simd_float4x4, renderState: SplatImmersiveRenderState) throws {
        ImmersiveState.shared.updateHead(cameraMatrix: context.viewMatrix(eye: 0).inverse)
        content = try SplatImmersiveGPUSortElement(
            context: context,
            splatCloud: splatCloud,
            modelMatrix: modelMatrix,
            renderState: renderState
        )
    }

    nonisolated var body: some Element {
        content
    }
}
#endif
