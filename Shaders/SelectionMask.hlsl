struct VertexInput {
    float3 position : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float2 uv : TEXCOORD2;
    float4 color : TEXCOORD3;
};

cbuffer DrawUniforms : register(b0, space1) {
    float4x4 model;
    float4x4 viewProjection;
    float4 unusedColor;
};

struct VertexOutput {
    float4 position : SV_Position;
};

VertexOutput vertex_main(VertexInput input) {
    VertexOutput output;
    const float4 worldPosition = mul(model, float4(input.position, 1.0));
    output.position = mul(viewProjection, worldPosition);
    return output;
}

float4 fragment_main(VertexOutput input) : SV_Target0 {
    return float4(1.0, 1.0, 1.0, 1.0);
}
