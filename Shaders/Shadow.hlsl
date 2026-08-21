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

struct VertexOutput {
    float4 position : SV_Position;
};

VertexOutput vertex_main(VertexInput input) {
    VertexOutput output;
    const float4x4 model = transpose(float4x4(
        input.modelColumn0,
        input.modelColumn1,
        input.modelColumn2,
        input.modelColumn3
    ));
    output.position = mul(viewProjection, mul(model, float4(input.position, 1.0)));
    return output;
}

void fragment_main() {
}
