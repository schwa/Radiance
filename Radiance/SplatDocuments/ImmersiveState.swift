#if os(visionOS)
import Foundation
import GeometryLite3D
import Metal
import MetalSprocketsGaussianSplats
import MetalSprocketsGaussianSplatShaders
import Observation
import simd

@Observable
@MainActor
final class ImmersiveState {
    var isImmersive = false
    var splatCloud: GPUSplatCloud<SparkSplat>? {
        didSet {
            renderState = try? splatCloud.map(SplatImmersiveRenderState.init)
        }
    }
    var renderState: SplatImmersiveRenderState?
    var modelMatrix = simd_float4x4(xRotation: .radians(.pi))
    var scale: Float = 1.0
    var translation: SIMD3<Float> = .zero

    var headPosition: SIMD3<Float> = .zero
    var headForward: SIMD3<Float> = [0, 0, -1]

    static let shared = ImmersiveState()
    private init() {
        // This line intentionally left blank.
    }

    var worldModelMatrix: simd_float4x4 {
        simd_float4x4(translation: translation)
            * simd_float4x4(scale: SIMD3<Float>(repeating: scale))
            * modelMatrix
    }

    func updateHead(cameraMatrix: simd_float4x4) {
        headPosition = SIMD3<Float>(cameraMatrix.columns.3.x, cameraMatrix.columns.3.y, cameraMatrix.columns.3.z)
        headForward = -SIMD3<Float>(cameraMatrix.columns.2.x, cameraMatrix.columns.2.y, cameraMatrix.columns.2.z)
    }

    func recenter(distance: Float = 2.0) {
        // Position the splat in front of the head
        translation = headPosition + headForward * distance
    }
}
#endif
