struct VertexInput {
    float3 position : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float2 uv : TEXCOORD2;
    float4 color : TEXCOORD3;
    float4 modelColumn0 : TEXCOORD4;
    float4 modelColumn1 : TEXCOORD5;
    float4 modelColumn2 : TEXCOORD6;
    float4 modelColumn3 : TEXCOORD7;
};

cbuffer PointShadowUniforms : register(b0, space1) {
    float4x4 viewProjection;
};

cbuffer PointShadowFragmentUniforms : register(b0, space3) {
    float4 lightPositionRange;
};

struct VertexOutput {
    float3 worldPosition : TEXCOORD0;
    float4 position : SV_Position;
};

VertexOutput vertex_main(VertexInput input) {
    const float4x4 model = transpose(float4x4(
        input.modelColumn0,
        input.modelColumn1,
        input.modelColumn2,
        input.modelColumn3
    ));
    const float4 localPosition = float4(input.position, 1.0);
    const float4 worldPosition = mul(model, localPosition);
    VertexOutput output;
    output.position = mul(viewProjection, worldPosition);
    output.worldPosition = worldPosition.xyz;
    return output;
}

struct FragmentOutput {
    float depth : SV_Depth;
};

FragmentOutput fragment_main(VertexOutput input) {
    const float range = max(lightPositionRange.w, 0.0001);
    const float depth = saturate(length(input.worldPosition - lightPositionRange.xyz) / range - 0.00008);
    FragmentOutput output;
    output.depth = depth;
    return output;
}
