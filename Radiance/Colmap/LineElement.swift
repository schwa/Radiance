import Metal
import MetalSprockets
import MetalSprocketsSupport
import simd

struct LineElement: Element {
    let shaderLibrary: ShaderLibrary
    let transform: float4x4
    let vertexBuffer: MTLBuffer
    let vertexCount: Int

    init(transform: float4x4, vertexBuffer: MTLBuffer, vertexCount: Int) throws {
        self.shaderLibrary = try ShaderLibrary(bundle: .main)
        self.transform = transform
        self.vertexBuffer = vertexBuffer
        self.vertexCount = vertexCount
    }

    var body: some Element {
        get throws {
            try RenderPipeline(
                vertexShader: shaderLibrary.lineVertexMain,
                fragmentShader: shaderLibrary.lineFragmentMain
            ) {
                Draw { encoder in
                    encoder.drawPrimitives(primitiveType: .line, vertexStart: 0, vertexCount: vertexCount)
                }
                .vertexBuffer(vertexBuffer, index: 0)
                .vertexValues([transform], index: 1)
            }
            .vertexDescriptor(LineVertex.descriptor)
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
