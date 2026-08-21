struct VertexInput {
    float3 position : TEXCOORD0;
    float4 color : TEXCOORD1;
};

cbuffer GizmoUniforms : register(b0, space1) {
    float4x4 viewProjection;
};

struct VertexOutput {
    float4 color : COLOR0;
    float4 position : SV_Position;
};

VertexOutput vertex_main(VertexInput input) {
    VertexOutput output;
    output.position = mul(viewProjection, float4(input.position, 1.0));
    output.color = input.color;
    return output;
}

float4 fragment_main(VertexOutput input) : SV_Target0 {
    return input.color;
}
