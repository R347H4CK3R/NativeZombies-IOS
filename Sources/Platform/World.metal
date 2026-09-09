#include <metal_stdlib>
using namespace metal;
struct Vertex { float4 position; float4 color; float4 materialUV; };
struct Camera { float4 eye; float4 right; float4 up; float4 forward; float4 params; };
struct Raster { float4 position [[position]]; float4 color; float distance; float2 uv; uint material [[flat]]; };
vertex Raster worldVertex(uint id [[vertex_id]], const device Vertex* vertices [[buffer(0)]], constant Camera& camera [[buffer(1)]]) {
    Vertex v = vertices[id];
    float3 d = v.position.xyz-camera.eye.xyz;
    float depth = dot(d, camera.forward.xyz);
    Raster out;
    out.position = float4(dot(d,camera.right.xyz)*camera.params.y/camera.params.x,
                         dot(d,camera.up.xyz)*camera.params.y,
                         depth*60.0/59.95-3.0/59.95, depth);
    out.color = v.color;
    out.uv = v.materialUV.xy;
    out.material = uint(v.materialUV.z);
    out.distance = length(d);
    return out;
}
fragment float4 worldFragment(Raster in [[stage_in]], texture2d_array<float> materials [[texture(0)]]) {
    constexpr sampler linearSampler(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
    float3 surface = materials.sample(linearSampler,in.uv,in.material).rgb;
    float fog = clamp((in.distance-4.0)/24.0, 0.0, 0.84);
    float3 color = mix(in.color.rgb*surface, float3(0.026,0.038,0.053), fog);
    return float4(color,1.0);
}
