import Metal
import MetalSprockets
import MetalSprocketsSupport
import simd

struct PointCloudElement: Element {
    let shaderLibrary: ShaderLibrary
    let transform: float4x4
    let vertexBuffer: MTLBuffer
    let vertexCount: Int
    let pointSize: Float

    init(transform: float4x4, vertexBuffer: MTLBuffer, vertexCount: Int, pointSize: Float = 4.0) throws {
        self.shaderLibrary = try ShaderLibrary(bundle: .main)
        self.transform = transform
        self.vertexBuffer = vertexBuffer
        self.vertexCount = vertexCount
        self.pointSize = pointSize
    }

    var body: some Element {
        get throws {
            try RenderPipeline(
                vertexShader: shaderLibrary.pointVertexMain,
                fragmentShader: shaderLibrary.pointFragmentMain
            ) {
                Draw { encoder in
                    encoder.drawPrimitives(primitiveType: .point, vertexStart: 0, vertexCount: vertexCount)
                }
                .vertexBuffer(vertexBuffer, index: 0)
                .vertexValues([transform], index: 1)
                .vertexValues([pointSize], index: 2)
            }
            .vertexDescriptor(PointVertex.descriptor)
            .depthCompare(function: .less, enabled: true)
            .renderPipelineDescriptorTransformer { descriptor in
                descriptor.colorAttachments[0].blendingState = .enabled
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
        }
    }
}
