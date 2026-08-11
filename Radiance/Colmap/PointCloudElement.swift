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
                    var transform = transform
                    encoder.setVertexBytes(&transform, length: MemoryLayout<float4x4>.stride, index: 1)

                    var size = pointSize
                    encoder.setVertexBytes(&size, length: MemoryLayout<Float>.stride, index: 2)

                    encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                    encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: vertexCount)
                }
            }
            .vertexDescriptor(PointVertex.descriptor)
            .depthCompare(function: .less, enabled: true)
            .renderPipelineDescriptorModifier { descriptor in
                descriptor.colorAttachments[0].isBlendingEnabled = true
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
        }
    }
}
