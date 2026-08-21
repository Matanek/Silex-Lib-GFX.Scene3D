struct VertexInput {
    float2 position : TEXCOORD0;
    float2 uv : TEXCOORD1;
};

cbuffer DrawUniforms : register(b0, space1) {
    float4x4 model;
    float4x4 view;
    float4x4 projection;
    float4 sizePivot;
    float4 tint;
    float4 settings;
    float4 uvRegion;
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
    const float2 local2D = (input.position - sizePivot.zw) * sizePivot.xy;
    float3 worldPosition;
    if (settings.y < 0.5) {
        worldPosition = mul(model, float4(local2D, settings.x, 1.0)).xyz;
    } else {
        const float3 center = mul(model, float4(0.0, 0.0, 0.0, 1.0)).xyz;
        float3 right = normalize(float3(view[0][0], view[0][1], view[0][2]));
        float3 up = normalize(float3(view[1][0], view[1][1], view[1][2]));
        if (settings.y > 1.5) {
            right.y = 0.0;
            right = normalize(right);
            up = float3(0.0, 1.0, 0.0);
        }
        worldPosition = center + right * local2D.x + up * local2D.y;
    }
    output.position = mul(projection, mul(view, float4(worldPosition, 1.0)));
    output.uv = uvRegion.xy + input.uv * uvRegion.zw;
    output.color = tint;
    return output;
}

float4 fragment_main(VertexOutput input) : SV_Target0 {
    return spriteTexture.Sample(spriteSampler, input.uv) * input.color;
}
