cbuffer SkyboxUniforms : register(b0, space3) {
    float4x4 inverseViewProjection;
    float4 environmentCameraPosition;
    float4 environmentDayZenith;
    float4 environmentDayHorizon;
    float4 environmentNightZenith;
    float4 environmentNightHorizon;
    float4 environmentSunDirectionIntensity;
    float4 environmentSunColor;
    float4 environmentSunShape;
    float4 environmentSunHalo;
    float4 environmentSunGlow;
    float4 environmentHorizonGlowColor;
    float4 environmentHorizonGlow;
    float4 toneMappingSettings;
    float4 toneMappingComparison;
};

struct VertexOutput {
    float2 clip : TEXCOORD0;
    float4 position : SV_Position;
};

VertexOutput vertex_main(uint vertexId : SV_VertexID) {
    const float2 clip = float2(
        vertexId == 1 ? 3.0 : -1.0,
        vertexId == 2 ? 3.0 : -1.0
    );
    VertexOutput output;
    output.clip = clip;
    output.position = float4(clip, 0.0, 1.0);
    return output;
}

float3 environment_radiance(float3 direction) {
    direction = normalize(direction);
    const float upperElevation = pow(saturate(direction.y), 0.72);
    const float lowerElevation = pow(saturate(-direction.y), 0.55);
    const float horizonSoftness = max(environmentHorizonGlow.w * 0.25, 0.0001);
    const float upperHemisphere = smoothstep(
        -horizonSoftness,
        horizonSoftness,
        direction.y
    );
    const float3 dayUpper = lerp(
        environmentDayHorizon.rgb,
        environmentDayZenith.rgb,
        upperElevation
    );
    const float3 dayLower = lerp(
        environmentDayHorizon.rgb * 0.55,
        environmentDayZenith.rgb * 0.08,
        lowerElevation
    );
    const float3 nightUpper = lerp(
        environmentNightHorizon.rgb,
        environmentNightZenith.rgb,
        upperElevation
    );
    const float3 nightLower = lerp(
        environmentNightHorizon.rgb * 0.45,
        environmentNightZenith.rgb * 0.05,
        lowerElevation
    );
    const float3 daySky = lerp(dayLower, dayUpper, upperHemisphere) *
        environmentDayZenith.a;
    const float3 nightSky = lerp(nightLower, nightUpper, upperHemisphere) *
        environmentDayZenith.a;
    const float automaticNight = smoothstep(
        -0.18,
        0.08,
        -environmentSunDirectionIntensity.y
    );
    const float nightBlend = environmentNightHorizon.a >= 0.0
        ? environmentNightHorizon.a
        : automaticNight;
    float3 color = lerp(daySky, nightSky, nightBlend);

    const float3 sunDirection = normalize(environmentSunDirectionIntensity.xyz);
    const float sunDot = dot(direction, sunDirection);
    const float sunDisc = smoothstep(
        cos(environmentSunShape.x + environmentSunShape.y),
        cos(environmentSunShape.x),
        sunDot
    ) * environmentSunDirectionIntensity.w;
    const float sunHalo = smoothstep(
        cos(environmentSunHalo.y + environmentSunHalo.z),
        cos(environmentSunHalo.y),
        sunDot
    ) * environmentSunHalo.x;
    const float sunGlow = smoothstep(
        cos(environmentSunGlow.y + environmentSunGlow.z),
        cos(environmentSunGlow.y),
        sunDot
    ) * environmentSunGlow.x;

    const float horizonBand = pow(
        saturate(1.0 - abs(direction.y) / max(environmentHorizonGlow.y, 0.0001)),
        max(environmentHorizonGlow.z, 0.0001)
    );
    const float2 sunFlat = environmentSunDirectionIntensity.xz;
    const float2 directionFlat = direction.xz;
    float horizonFacing = 0.0;
    if (length(sunFlat) > 0.0001 && length(directionFlat) > 0.0001) {
        horizonFacing = pow(
            saturate(dot(normalize(sunFlat), normalize(directionFlat)) * 0.5 + 0.5),
            max(environmentSunShape.w, 0.0001)
        );
    }

    color += environmentSunColor.rgb * (sunDisc + sunHalo + sunGlow);
    color += environmentHorizonGlowColor.rgb * environmentHorizonGlow.x *
        horizonBand * horizonFacing;
    return max(color, 0.0);
}

float3 tone_map(float3 color) {
    color = max(color, 0.0) * exp2(toneMappingSettings.y);
    if (toneMappingSettings.x < 0.5) color = saturate(color);
    else if (toneMappingSettings.x < 1.5) {
        const float whitePoint = toneMappingSettings.z;
        const float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
        if (luminance > 0.000001) {
            float mappedLuminance;
            if (whitePoint > 0.0) {
                mappedLuminance = luminance *
                    (1.0 + luminance / (whitePoint * whitePoint)) /
                    (1.0 + luminance);
            } else {
                mappedLuminance = luminance / (1.0 + luminance);
            }
            color = saturate(color * (mappedLuminance / luminance));
        } else {
            color = 0.0;
        }
    } else {
        color = saturate((color * (2.51 * color + 0.03)) /
            (color * (2.43 * color + 0.59) + 0.14));
    }
    const float3 low = color * 12.92;
    const float3 high = 1.055 * pow(color, 1.0 / 2.4) - 0.055;
    return float3(
        color.r <= 0.0031308 ? low.r : high.r,
        color.g <= 0.0031308 ? low.g : high.g,
        color.b <= 0.0031308 ? low.b : high.b
    );
}

float4 fragment_main(VertexOutput input) : SV_Target0 {
    const float4 farWorld = mul(
        inverseViewProjection,
        float4(input.clip, 1.0, 1.0)
    );
    const float3 direction = normalize(
        farWorld.xyz / farWorld.w - environmentCameraPosition.xyz
    );
    return float4(tone_map(environment_radiance(direction)), 1.0);
}
