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

cbuffer ShadowDrawUniforms : register(b0, space1) {
    float4x4 viewProjection;
};

cbuffer PointShadowFragmentUniforms : register(b0, space3) {
    float4 lightPositionRange;
};

cbuffer CanvasShadowUniforms : register(b1, space3) {
    float4 canvasShadowSettings;
};

Texture2D<float4> canvasTexture : register(t1, space2);
SamplerState canvasSampler : register(s1, space2);

struct VertexOutput {
    float3 worldPosition : TEXCOORD0;
    float2 uv : TEXCOORD1;
    float4 position : SV_Position;
};

VertexOutput vertex_main(VertexInput input) {
    const float4x4 model = transpose(float4x4(
        input.modelColumn0,
        input.modelColumn1,
        input.modelColumn2,
        input.modelColumn3
    ));
    const float4 world = mul(model, float4(input.position, 1.0));
    VertexOutput output;
    output.position = mul(viewProjection, world);
    output.worldPosition = world.xyz;
    output.uv = input.uv;
    return output;
}

struct FragmentOutput { float depth : SV_Depth; };

FragmentOutput fragment_main(VertexOutput input) {
    clip(canvasTexture.Sample(canvasSampler, input.uv).a - canvasShadowSettings.x);
    const float range = max(lightPositionRange.w, 0.0001);
    FragmentOutput output;
    output.depth = saturate(
        length(input.worldPosition - lightPositionRange.xyz) / range
    );
    return output;
}
