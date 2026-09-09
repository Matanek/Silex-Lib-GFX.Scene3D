struct VertexInput {
    float2 position : TEXCOORD0;
    float2 uv : TEXCOORD1;
    float4 center : TEXCOORD2;
    float4 right : TEXCOORD3;
    float4 up : TEXCOORD4;
    float4 sizePivot : TEXCOORD5;
    float4 tint : TEXCOORD6;
    float4 uvRegion : TEXCOORD7;
};

cbuffer DrawUniforms : register(b0, space1) {
    float4x4 viewProjection;
};

Texture2D<float4> spriteTexture : register(t0, space2);
SamplerState spriteSampler : register(s0, space2);

struct VertexOutput {
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
    float4 position : SV_Position;
};

VertexOutput vertex_main(VertexInput input) {
    VertexOutput output;
    const float2 local = (input.position - input.sizePivot.zw) *
        input.sizePivot.xy;
    const float3 world = input.center.xyz +
        input.right.xyz * local.x + input.up.xyz * local.y;
    output.position = mul(viewProjection, float4(world, 1.0));
    output.uv = input.uvRegion.xy + input.uv * input.uvRegion.zw;
    output.color = input.tint;
    return output;
}

float4 fragment_main(VertexOutput input) : SV_Target0 {
    return spriteTexture.Sample(spriteSampler, input.uv) * input.color;
}
