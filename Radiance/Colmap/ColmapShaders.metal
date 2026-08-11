#include <metal_stdlib>
using namespace metal;

// MARK: - Point Cloud Shaders

struct PointVertexIn {
    float3 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

struct PointVertexOut {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
};

vertex PointVertexOut pointVertexMain(
    PointVertexIn in [[stage_in]],
    constant float4x4 &transform [[buffer(1)]],
    constant float &pointSize [[buffer(2)]]
) {
    PointVertexOut out;
    out.position = transform * float4(in.position, 1.0);
    out.color = in.color;
    out.pointSize = pointSize;
    return out;
}

fragment float4 pointFragmentMain(
    PointVertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    // Circular points with soft edges
    float dist = length(pointCoord - float2(0.5));
    if (dist > 0.5) {
        discard_fragment();
    }
    float alpha = smoothstep(0.5, 0.35, dist);
    return float4(in.color.rgb, alpha);
}

// MARK: - Line Shaders (for camera frustums)

struct LineVertexIn {
    float3 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

struct LineVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex LineVertexOut lineVertexMain(
    LineVertexIn in [[stage_in]],
    constant float4x4 &transform [[buffer(1)]]
) {
    LineVertexOut out;
    out.position = transform * float4(in.position, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 lineFragmentMain(
    LineVertexOut in [[stage_in]]
) {
    return in.color;
}
