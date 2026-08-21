cbuffer OutlineUniforms : register(b0, space3) {
    float4 outlineColor;
    float4 settings;
};

Texture2D<float> selectionMask : register(t0, space2);
SamplerState selectionSampler : register(s0, space2);

struct VertexOutput {
    float4 position : SV_Position;
};

VertexOutput vertex_main(uint vertexId : SV_VertexID) {
    const float2 clip = float2(
        vertexId == 1 ? 3.0 : -1.0,
        vertexId == 2 ? 3.0 : -1.0
    );
    VertexOutput output;
    output.position = float4(clip, 0.0, 1.0);
    return output;
}

float4 fragment_main(VertexOutput input) : SV_Target0 {
    const float2 texel = settings.xy;
    const float2 uv = input.position.xy * texel;
    const float center = selectionMask.Sample(selectionSampler, uv);
    if (center >= 0.5) { discard; }

    const float2 offset = texel * settings.z;
    float coverage = 0.0;
    coverage = max(coverage, selectionMask.Sample(selectionSampler, uv + float2(-offset.x, 0.0)));
    coverage = max(coverage, selectionMask.Sample(selectionSampler, uv + float2( offset.x, 0.0)));
    coverage = max(coverage, selectionMask.Sample(selectionSampler, uv + float2(0.0, -offset.y)));
    coverage = max(coverage, selectionMask.Sample(selectionSampler, uv + float2(0.0,  offset.y)));
    coverage = max(coverage, selectionMask.Sample(selectionSampler, uv + float2(-offset.x, -offset.y)));
    coverage = max(coverage, selectionMask.Sample(selectionSampler, uv + float2( offset.x, -offset.y)));
    coverage = max(coverage, selectionMask.Sample(selectionSampler, uv + float2(-offset.x,  offset.y)));
    coverage = max(coverage, selectionMask.Sample(selectionSampler, uv + float2( offset.x,  offset.y)));
    if (coverage <= 0.001) { discard; }

    return float4(outlineColor.rgb, outlineColor.a * coverage);
}
