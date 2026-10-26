#include <metal_stdlib>
using namespace metal;

// Same memory layout as Swift's four UInt32s. BGRA output is SDR, top-left image origin.
struct SplitParameters { uint layout; uint swapEyes; uint flipY; uint unused; };

float4 toLinear(float4 color) {
    float3 low = color.rgb / 12.92f;
    float3 high = pow((color.rgb + 0.055f) / 1.055f, float3(2.4f));
    return float4(select(low, high, color.rgb > 0.04045f), color.a);
}

kernel void splitStereoVideo(texture2d<float, access::sample> source [[texture(0)]],
                             texture2d<float, access::write> left [[texture(1)]],
                             texture2d<float, access::write> right [[texture(2)]],
                             constant SplitParameters &params [[buffer(0)]],
                             uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= left.get_width() || pixel.y >= left.get_height()) return;
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(pixel) + 0.5f) / float2(left.get_width(), left.get_height());
    if (params.flipY) uv.y = 1.0f - uv.y;
    float2 a = uv, b = uv;
    if (params.layout == 1) { a.x *= 0.5f; b.x = a.x + 0.5f; }
    if (params.layout == 2) { a.y *= 0.5f; b.y = a.y + 0.5f; }
    if (params.swapEyes) { float2 temp = a; a = b; b = temp; }
    left.write(toLinear(source.sample(linearSampler, a)), pixel);
    right.write(toLinear(source.sample(linearSampler, b)), pixel);
}
