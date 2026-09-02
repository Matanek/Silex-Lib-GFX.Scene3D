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

cbuffer CanvasShadowUniforms : register(b0, space3) {
    float4 canvasShadowSettings;
};

Texture2D<float4> canvasTexture : register(t1, space2);
SamplerState canvasSampler : register(s1, space2);

struct VertexOutput {
    float2 uv : TEXCOORD0;
    float4 position : SV_Position;
};

VertexOutput vertex_main(VertexInput input) {
    const float4x4 model = transpose(float4x4(
        input.modelColumn0,
        input.modelColumn1,
        input.modelColumn2,
        input.modelColumn3
    ));
    VertexOutput output;
    output.position = mul(viewProjection, mul(model, float4(input.position, 1.0)));
    output.uv = input.uv;
    return output;
}

void fragment_main(VertexOutput input) {
    clip(canvasTexture.Sample(canvasSampler, input.uv).a - canvasShadowSettings.x);
}
