cbuffer GridUniforms : register(b0, space1) {
    float4x4 inverseViewProjection;
    float4x4 viewProjection;
    float4 minorColor;
    float4 majorColor;
    float4 xAxisColor;
    float4 zAxisColor;
    float4 settings;
    float4 fadeSettings;
};

struct VertexOutput {
    float3 nearPoint : TEXCOORD0;
    float3 farPoint : TEXCOORD1;
    float4 position : SV_Position;
};

float3 unproject(float2 clip, float depth) {
    float4 world = mul(inverseViewProjection, float4(clip, depth, 1.0));
    return world.xyz / world.w;
}

VertexOutput vertex_main(uint vertexId : SV_VertexID) {
    float2 clip = float2(
        vertexId == 1 ? 3.0 : -1.0,
        vertexId == 2 ? 3.0 : -1.0
    );
    VertexOutput output;
    output.nearPoint = unproject(clip, 0.0);
    output.farPoint = unproject(clip, 1.0);
    output.position = float4(clip, 0.0, 1.0);
    return output;
}

float line_coverage(float coordinate, float spacing, float width) {
    float scaled = coordinate / spacing;
    float distanceToLine = abs(frac(scaled - 0.5) - 0.5);
    float footprint = max(fwidth(scaled), 0.000001);
    float pixelDistance = distanceToLine / footprint;
    return 1.0 - smoothstep(width * 0.5, width * 0.5 + 1.0, pixelDistance);
}

float axis_coverage(float coordinate, float width) {
    float footprint = max(fwidth(coordinate), 0.000001);
    float pixelDistance = abs(coordinate) / footprint;
    return 1.0 - smoothstep(width * 0.5, width * 0.5 + 1.0, pixelDistance);
}

struct FragmentOutput {
    float4 color : SV_Target0;
    float depth : SV_Depth;
};

FragmentOutput fragment_main(VertexOutput input) {
    float denominator = input.farPoint.y - input.nearPoint.y;
    if (abs(denominator) < 0.000001) discard;
    float distanceAlongRay = -input.nearPoint.y / denominator;
    if (distanceAlongRay < 0.0 || distanceAlongRay > 1.0) discard;

    float3 world = input.nearPoint + distanceAlongRay * (input.farPoint - input.nearPoint);
    float2 plane = world.xz;
    float worldPerPixel = max(length(ddx(plane)), length(ddy(plane)));
    float continuousLevel = clamp(
        log(max(worldPerPixel * 12.0 / settings.x, 0.000001)) / log(settings.y),
        -8.0,
        8.0
    );
    float level = floor(continuousLevel);
    float transition = frac(continuousLevel);
    float minorSpacing = settings.x * pow(settings.y, level);
    float majorSpacing = minorSpacing * settings.y;
    float coarseSpacing = majorSpacing * settings.y;
    float minor = max(
        line_coverage(world.x, minorSpacing, settings.z),
        line_coverage(world.z, minorSpacing, settings.z)
    );
    float major = max(
        line_coverage(world.x, majorSpacing, settings.z),
        line_coverage(world.z, majorSpacing, settings.z)
    );
    float coarse = max(
        line_coverage(world.x, coarseSpacing, settings.z),
        line_coverage(world.z, coarseSpacing, settings.z)
    );

    float minorWeight = minor * (1.0 - transition);
    float4 middleColor = lerp(majorColor, minorColor, transition);
    float3 gridColor = minorColor.rgb;
    float gridAlpha = minorColor.a * minorWeight;
    gridColor = lerp(gridColor, middleColor.rgb, major);
    gridAlpha = max(gridAlpha, middleColor.a * major);
    float coarseWeight = coarse * transition;
    gridColor = lerp(gridColor, majorColor.rgb, coarseWeight);
    gridAlpha = max(gridAlpha, majorColor.a * coarseWeight);
    float4 color = float4(gridColor, gridAlpha);

    float xAxis = axis_coverage(world.z, settings.w);
    float zAxis = axis_coverage(world.x, settings.w);
    color = lerp(color, xAxisColor, xAxis);
    color = lerp(color, zAxisColor, zAxis);
    color.a = max(color.a, max(xAxis * xAxisColor.a, zAxis * zAxisColor.a));

    color.a *= 1.0 - smoothstep(
        fadeSettings.x * 0.65,
        fadeSettings.x,
        length(world - input.nearPoint)
    );
    if (color.a <= 0.001) discard;

    float4 clip = mul(viewProjection, float4(world, 1.0));
    FragmentOutput output;
    output.color = color;
    output.depth = clip.z / clip.w;
    return output;
}
