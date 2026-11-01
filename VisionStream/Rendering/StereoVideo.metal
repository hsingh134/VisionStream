#include <metal_stdlib>
using namespace metal;

float4 linearVideoColor(float4 c, uint colorMode) {
    if (colorMode == 1) {
        // D65 Display P3 -> D65 linear sRGB. Keep negative/out-of-gamut and
        // extended highlights; the compositor owns final display mapping.
        return float4(float3(1.224940176f*c.r-0.224940176f*c.g,
                            -0.042056955f*c.r+1.042056955f*c.g,
                            -0.019637555f*c.r-0.078636046f*c.g+1.098273600f*c.b),c.a);
    }
    if (colorMode == 2) {
        float3 low=c.rgb/12.92f;
        float3 high=pow(max((c.rgb+0.055f)/1.055f,0.0f),float3(2.4f));
        return float4(select(low,high,c.rgb>0.04045f),c.a);
    }
    return c;
}

// Known-linear half-float frames take the fast hardware-filtered path.
// Untagged SDR fallback linearizes *before* interpolation, without a full-frame
// CPU copy or an extra intermediate GPU image. Never sample across eye borders.
float4 sampleVideoEye(texture2d<float, access::sample> source, float2 uv,
                      uint eye, constant uint4 &flags, uint colorMode) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    if (flags.z) uv.y = 1.0f - uv.y;
    float2 scale(1.0f), offset(0.0f);
    if (flags.x == 1) { scale.x = 0.5f; offset.x = eye * 0.5f; }
    if (flags.x == 2) { scale.y = 0.5f; offset.y = eye * 0.5f; }
    float2 inset = 0.5f / float2(source.get_width(), source.get_height());
    float2 mapped=clamp(uv*scale+offset,offset+inset,offset+scale-inset);
    if (colorMode != 2) return linearVideoColor(source.sample(s,mapped),colorMode);
    float2 dimensions(source.get_width(),source.get_height());
    uint2 limit=uint2((offset+scale)*dimensions)-1;
    float2 p=clamp(mapped*dimensions-0.5f,offset*dimensions,float2(limit));
    uint2 a=uint2(floor(p));
    uint2 b=min(a+1,limit);float2 f=fract(p);
    return mix(mix(linearVideoColor(source.read(a),2),linearVideoColor(source.read(uint2(b.x,a.y)),2),f.x),
               mix(linearVideoColor(source.read(uint2(a.x,b.y)),2),linearVideoColor(source.read(b),2),f.x),f.y);
}

float4 prepareVideoEye(texture2d<float, access::sample> source, float2 uv, float2 step,
                       uint eye, constant uint4 &flags, uint colorMode) {
    float4 c = sampleVideoEye(source, uv, eye, flags, colorMode);
    // Preserve border gradients instead of sharpening the clamped image edge.
    if (flags.w != 1 || any(uv < step) || any(uv > 1.0f-step)) return c;
    float4 l = sampleVideoEye(source, uv - float2(step.x,0), eye, flags, colorMode);
    float4 r = sampleVideoEye(source, uv + float2(step.x,0), eye, flags, colorMode);
    float4 u = sampleVideoEye(source, uv - float2(0,step.y), eye, flags, colorMode);
    float4 d = sampleVideoEye(source, uv + float2(0,step.y), eye, flags, colorMode);
    float3 lo = min(c.rgb,min(min(l.rgb,r.rgb),min(u.rgb,d.rgb)));
    float3 hi = max(c.rgb,max(max(l.rgb,r.rgb),max(u.rgb,d.rgb)));
    constexpr float3 weights(0.2126f,0.7152f,0.0722f);
    float contrast = dot(hi-lo,weights);
    float edge = max(abs(dot(r.rgb-l.rgb,weights)),abs(dot(d.rgb-u.rgb,weights)));
    float coherence = edge / max(contrast,0.00001f);
    float amount = 0.12f * smoothstep(0.002f,0.04f,contrast) * smoothstep(0.2f,0.7f,coherence);
    float3 result = clamp(c.rgb + amount * (c.rgb - (l.rgb+r.rgb+u.rgb+d.rgb)*0.25f),lo,hi);
    return float4(result,c.a); // No clipping to SDR white; preserve extended values.
}

kernel void prepareVideoFrame(texture2d<float, access::sample> source [[texture(0)]],
                              texture2d<float, access::write> left [[texture(1)]],
                              texture2d<float, access::write> right [[texture(2)]],
                              constant uint4 &flags [[buffer(0)]],
                              constant uint &colorMode [[buffer(1)]],
                              uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= left.get_width() || pixel.y >= left.get_height()) return;
    float2 step = 1.0f / float2(left.get_width(),left.get_height());
    float2 uv = (float2(pixel)+0.5f)*step;
    uint first = flags.y && flags.x != 0 ? 1 : 0;
    left.write(prepareVideoEye(source,uv,step,first,flags,colorMode),pixel);
    // Monoscopic eyes share one RealityKit resource: no duplicate GPU write.
    if (flags.x != 0) right.write(prepareVideoEye(source,uv,step,1-first,flags,colorMode),pixel);
}

// Same memory layout as Swift's four UInt32s. BGRA output is SDR, top-left image origin.
// Retained for the reproducible pre-0.16 benchmark, not the production renderer.
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
