#include <metal_stdlib>
using namespace metal;
#include <SceneKit/scn_metal>

// Shader code to pass through the vertices as rendered by SceneKit and apply a mask using a fragment shader
// Using Metal to post-process SceneKit rendering is only sparsly documented, see here for documentation and example code:
// - SCNTechnique:
//   https://developer.apple.com/documentation/scenekit/scntechnique
// - Example with Metal shaders:
//   https://github.com/lachlanhurst/SCNTechniqueTest
// - Example with GL shaders that pass in a texture programmatically:
//   https://github.com/kosua20/Technique-iOS

struct custom_vertex_t
{
    float4 position [[attribute(SCNVertexSemanticPosition)]];
};

constexpr sampler s = sampler(coord::normalized, address::repeat, filter::linear);

struct out_vertex_t
{
    float4 position [[position]];
    float2 uv;
    float sinTime;
};

vertex out_vertex_t pass_through_vertex(custom_vertex_t in [[stage_in]],
                                        constant SCNSceneBuffer& scn_frame [[buffer(0)]])
{
    out_vertex_t out;
    out.position = in.position;
    out.uv = float2((in.position.x + 1.0) * 0.5 , (in.position.y + 1.0) * -0.5);
    out.sinTime = scn_frame.sinTime;
    return out;
};

fragment half4 apply_mask_fragment(out_vertex_t vert [[stage_in]],
                            texture2d<float, access::sample> color_sampler [[texture(0)]],
                            texture2d<float, access::sample> mask_sampler [[texture(1)]])
{
    float4 scene_color = color_sampler.sample(s, vert.uv);
    float4 mask_color = mask_sampler.sample(s, vert.uv);

    return half4(0.1 * scene_color + 0.9 * mask_color);
};
