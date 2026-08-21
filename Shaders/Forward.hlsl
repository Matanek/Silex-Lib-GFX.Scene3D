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

cbuffer DrawUniforms : register(b0, space1) {
    float4x4 viewProjection;
    float4 materialAlbedo;
};

cbuffer MaterialUniforms : register(b0, space3) {
    float4 materialSurface;
    float4 materialEmission;
    float4 cameraPosition;
    float4 materialSettings;
    float4 albedoTransform;
    float4 normalTransform;
    float4 metallicRoughnessTransform;
    float4 occlusionTransform;
    float4 emissionTransform;
    float4 textureRotationsA;
    float4 textureRotationsB;
};

struct LightData {
    float4 directionIntensity;
    float4 colorType;
    float4 positionReach;
    float4 anglesFalloffSoftness;
    float4 projection;
};

cbuffer LightingUniforms : register(b1, space3) {
    float4 ambientLight;
    float4 lightingSettings;
    LightData lights[16];
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
};

cbuffer ShadowUniforms : register(b3, space3) {
    float4 shadowSettings[16];
    float4 shadowSlots[16];
    float4x4 shadowMatrices[16];
    float4 shadowAtlasRects[16];
    float4 pointShadowAtlasRects[96];
    float4 shadowProjectedDepths[16];
    float4 shadowCameraForward;
};

cbuffer ToneMappingUniforms : register(b2, space3) {
    float4 toneMappingSettings;
    float4 toneMappingComparison;
};

Texture2D<float> shadowAtlas : register(t0, space2);
SamplerComparisonState shadowSampler : register(s0, space2);
Texture2D<float4> albedoMap : register(t1, space2);
SamplerState albedoSampler : register(s1, space2);
Texture2D<float4> normalMap : register(t2, space2);
SamplerState normalSampler : register(s2, space2);
Texture2D<float4> metallicRoughnessMap : register(t3, space2);
SamplerState metallicRoughnessSampler : register(s3, space2);
Texture2D<float4> occlusionMap : register(t4, space2);
SamplerState occlusionSampler : register(s4, space2);
Texture2D<float4> emissionMap : register(t5, space2);
SamplerState emissionSampler : register(s5, space2);

struct VertexOutput {
    float3 worldPosition : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float2 uv : TEXCOORD2;
    float4 color : COLOR0;
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
    const float4 world = mul(model, float4(input.position, 1.0));
    output.position = mul(viewProjection, world);
    output.worldPosition = world.xyz;
    output.worldNormal = normalize(mul((float3x3)model, input.normal));
    output.uv = input.uv;
    output.color = input.color * materialAlbedo;
    return output;
}

static const float pbrPi = 3.14159265;

float2 transformed_uv(float2 uv, float4 transform, float rotation) {
    const float2 scaled = uv * transform.zw;
    const float cosine = cos(rotation);
    const float sine = sin(rotation);
    return transform.xy + float2(
        cosine * scaled.x - sine * scaled.y,
        sine * scaled.x + cosine * scaled.y
    );
}

float3 mapped_normal(
    float3 position,
    float3 geometryNormal,
    float2 uv,
    float normalScale
) {
    float3 sampled = normalMap.Sample(normalSampler, uv).xyz * 2.0 - 1.0;
    sampled.xy *= normalScale;
    const float3 positionX = ddx(position);
    const float3 positionY = ddy(position);
    const float2 uvX = ddx(uv);
    const float2 uvY = ddy(uv);
    const float determinant = uvX.x * uvY.y - uvX.y * uvY.x;
    if (abs(determinant) < 0.000001) return geometryNormal;
    const float inverseDeterminant = 1.0 / determinant;
    const float3 tangent = normalize(
        (positionX * uvY.y - positionY * uvX.y) * inverseDeterminant
    );
    const float3 bitangent = normalize(
        (positionY * uvX.x - positionX * uvY.x) * inverseDeterminant
    );
    return normalize(
        tangent * sampled.x + bitangent * sampled.y + geometryNormal * sampled.z
    );
}

float distribution_ggx(float3 normal, float3 halfDirection, float roughness) {
    const float alpha = roughness * roughness;
    const float alphaSquared = alpha * alpha;
    const float normalHalfDot = saturate(dot(normal, halfDirection));
    const float denominator = normalHalfDot * normalHalfDot *
        (alphaSquared - 1.0) + 1.0;
    return alphaSquared / max(pbrPi * denominator * denominator, 0.00001);
}

float geometry_schlick(float amount, float roughness) {
    const float r = roughness + 1.0;
    const float k = r * r / 8.0;
    return amount / max(amount * (1.0 - k) + k, 0.00001);
}

float3 fresnel_schlick(float amount, float3 reflectance) {
    return reflectance + (1.0 - reflectance) * pow(1.0 - amount, 5.0);
}

float3 fresnel_schlick_roughness(
    float amount,
    float3 reflectance,
    float roughness
) {
    return reflectance + (max(1.0 - roughness, reflectance) - reflectance) *
        pow(1.0 - amount, 5.0);
}

float3 environment_radiance(float3 direction, float roughness) {
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

    const float blur = roughness * roughness;
    const float sunDot = dot(direction, normalize(environmentSunDirectionIntensity.xyz));
    const float sunDisc = smoothstep(
        cos(environmentSunShape.x + environmentSunShape.y + blur * 0.45),
        cos(environmentSunShape.x),
        sunDot
    ) * environmentSunDirectionIntensity.w * (1.0 - blur * 0.75);
    const float sunHalo = smoothstep(
        cos(environmentSunHalo.y + environmentSunHalo.z + blur * 0.65),
        cos(environmentSunHalo.y),
        sunDot
    ) * environmentSunHalo.x * (1.0 - blur * 0.6);
    const float sunGlow = smoothstep(
        cos(environmentSunGlow.y + environmentSunGlow.z + blur * 0.8),
        cos(environmentSunGlow.y),
        sunDot
    ) * environmentSunGlow.x;
    color += environmentSunColor.rgb * (sunDisc + sunHalo + sunGlow);

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
    color += environmentHorizonGlowColor.rgb * environmentHorizonGlow.x *
        horizonBand * horizonFacing;

    const float3 averageSky = lerp(
        environmentDayHorizon.rgb,
        environmentDayZenith.rgb,
        0.45
    ) * environmentDayZenith.a;
    return max(lerp(color, averageSky, blur * 0.55), 0.0);
}

float3 evaluate_environment(
    float3 normal,
    float3 viewDirection,
    float3 albedo,
    float metallic,
    float roughness
) {
    if (environmentSunShape.z < 0.5) return 0.0;
    const float normalView = saturate(dot(normal, viewDirection));
    const float3 reflectance = lerp(0.04, albedo, metallic);
    const float3 fresnel = fresnel_schlick_roughness(
        normalView,
        reflectance,
        roughness
    );
    const float3 diffuseWeight = (1.0 - fresnel) * (1.0 - metallic);
    const float3 diffuse = environment_radiance(normal, 1.0) * albedo *
        diffuseWeight * environmentNightZenith.a;
    const float3 reflection = reflect(-viewDirection, normal);
    const float3 specular = environment_radiance(reflection, roughness) *
        fresnel * environmentSunColor.a;
    return diffuse + specular;
}

void projector_basis(float3 forward, out float3 right, out float3 up) {
    const float3 reference = abs(dot(forward, float3(0.0, 1.0, 0.0))) > 0.95
        ? float3(0.0, 0.0, 1.0)
        : float3(0.0, 1.0, 0.0);
    right = normalize(cross(forward, reference));
    up = normalize(cross(right, forward));
}

float boundary(float distanceToBoundary, float softness) {
    if (softness <= 0.0001) return distanceToBoundary >= 0.0 ? 1.0 : 0.0;
    return smoothstep(0.0, softness, distanceToBoundary);
}

float distance_attenuation(float distanceToLight, float reach, float falloff) {
    if (distanceToLight >= reach) return 0.0;
    const float core = max(reach - falloff, 0.0);
    if (falloff <= 0.0001 || distanceToLight <= core) return 1.0;
    const float amount = saturate((reach - distanceToLight) / falloff);
    return amount * amount * (3.0 - 2.0 * amount);
}

float projector_attenuation(LightData light, float3 delta) {
    const float3 direction = normalize(light.directionIntensity.xyz);
    const float axial = dot(delta, direction);
    const float kind = light.colorType.w;
    if (kind < 2.5) {
        if (axial <= 0.0) return 0.0;
        const float cone = dot(normalize(delta), direction);
        return smoothstep(
            light.anglesFalloffSoftness.y,
            light.anglesFalloffSoftness.x,
            cone
        );
    }
    const float lengthValue = max(light.projection.z, 0.0001);
    const float softness = max(light.anglesFalloffSoftness.w, 0.0);
    const float falloff = max(light.anglesFalloffSoftness.z, 0.0);
    const float depth = boundary(axial, softness * lengthValue) *
        boundary(lengthValue + falloff - axial, falloff);
    float3 right;
    float3 up;
    projector_basis(direction, right, up);
    if (kind < 4.5) {
        const float halfWidth = max(light.projection.x * 0.5, 0.0001);
        const float halfHeight = max(light.projection.y * 0.5, 0.0001);
        return depth *
            boundary(halfWidth - abs(dot(delta, right)), softness * halfWidth) *
            boundary(halfHeight - abs(dot(delta, up)), softness * halfHeight);
    }
    const float radius = max(light.projection.w, 0.0001);
    const float radial = length(delta - direction * axial);
    return depth * boundary(radius - radial, softness * radius);
}

int point_shadow_face(float3 direction) {
    const float3 absoluteDirection = abs(direction);
    if (absoluteDirection.x >= absoluteDirection.y && absoluteDirection.x >= absoluteDirection.z) {
        return direction.x >= 0.0 ? 0 : 1;
    }
    if (absoluteDirection.y >= absoluteDirection.x && absoluteDirection.y >= absoluteDirection.z) {
        return direction.y >= 0.0 ? 2 : 3;
    }
    return direction.z >= 0.0 ? 4 : 5;
}

float2 point_shadow_uv_for_face(float3 direction, int face) {
    const float3 sampleDirection = normalize(direction);
    const float3 absoluteDirection = abs(sampleDirection);
    float2 uv = float2(0.0, 0.0);
    if (face == 0) uv = float2(-sampleDirection.z, -sampleDirection.y) / absoluteDirection.x;
    if (face == 1) uv = float2(sampleDirection.z, -sampleDirection.y) / absoluteDirection.x;
    if (face == 2) uv = float2(sampleDirection.x, sampleDirection.z) / absoluteDirection.y;
    if (face == 3) uv = float2(sampleDirection.x, -sampleDirection.z) / absoluteDirection.y;
    if (face == 4) uv = float2(sampleDirection.x, -sampleDirection.y) / absoluteDirection.z;
    if (face == 5) uv = float2(-sampleDirection.x, -sampleDirection.y) / absoluteDirection.z;
    return uv * 0.9826972631 * 0.5 + 0.5;
}

float atlas_shadow_compare(
    float2 uv,
    float4 rect,
    float localTexel,
    float receiverDepth
) {
    const float2 atlasTexel = float2(localTexel * rect.x, localTexel * rect.y);
    const float2 atlasMin = rect.zw + atlasTexel * 0.5;
    const float2 atlasMax = rect.zw + rect.xy - atlasTexel * 0.5;
    const float2 atlasUv = uv * rect.xy + rect.zw;
    return shadowAtlas.SampleCmpLevelZero(
        shadowSampler,
        clamp(atlasUv, atlasMin, atlasMax),
        receiverDepth
    );
}

float atlas_shadow_depth(float2 uv, float4 rect, float localTexel) {
    const float2 atlasTexel = float2(localTexel * rect.x, localTexel * rect.y);
    const float2 atlasMin = rect.zw + atlasTexel * 0.5;
    const float2 atlasMax = rect.zw + rect.xy - atlasTexel * 0.5;
    const float2 atlasUv = clamp(uv * rect.xy + rect.zw, atlasMin, atlasMax);
    uint width;
    uint height;
    shadowAtlas.GetDimensions(width, height);
    const int2 lastPixel = int2(width - 1, height - 1);
    const int2 pixel = clamp(
        int2(atlasUv * float2(width, height)),
        int2(0, 0),
        lastPixel
    );
    return shadowAtlas.Load(int3(pixel, 0));
}

static const float2 shadowPoissonDisk[16] = {
    float2(-0.94201624, -0.39906216), float2( 0.94558609, -0.76890725),
    float2(-0.09418410, -0.92938870), float2( 0.34495938,  0.29387760),
    float2(-0.91588581,  0.45771432), float2(-0.81544232, -0.87912464),
    float2(-0.38277543,  0.27676845), float2( 0.97484398,  0.75648379),
    float2( 0.44323325, -0.97511554), float2( 0.53742981, -0.47373420),
    float2(-0.26496911, -0.41893023), float2( 0.79197514,  0.19090188),
    float2(-0.24188840,  0.99706507), float2(-0.81409955,  0.91437590),
    float2( 0.19984126,  0.78641367), float2( 0.14383161, -0.14100790)
};

float poisson_pcf_shadow(
    float2 uv,
    float4 rect,
    float receiverDepth,
    float texel,
    float radius
) {
    float visibility = 0.0;
    [unroll]
    for (int sampleIndex = 0; sampleIndex < 16; ++sampleIndex) {
        visibility += atlas_shadow_compare(
            uv + shadowPoissonDisk[sampleIndex] * radius,
            rect,
            texel,
            receiverDepth
        );
    }
    return visibility * (1.0 / 16.0);
}

float pcf_shadow(float2 uv, float4 rect, float receiverDepth, float texel, float softness) {
    if (softness <= 0.0001) {
        return atlas_shadow_compare(uv, rect, texel, receiverDepth);
    }
    return poisson_pcf_shadow(
        uv, rect, receiverDepth, texel, texel * (0.75 + softness * 1.5)
    );
}

float pcss_shadow(
    float2 uv,
    float4 rect,
    float receiverDepth,
    float bias,
    float texel,
    float softness
) {
    if (softness <= 0.0001) {
        return atlas_shadow_compare(uv, rect, texel, receiverDepth - bias);
    }
    const float2 edgeDistance = min(uv, float2(1.0, 1.0) - uv);
    const float safeRadius = min(edgeDistance.x, edgeDistance.y);
    const float lightSize = 1.5;
    const float searchRadius = min(
        lightSize * texel * softness * 0.5,
        safeRadius
    );
    static const float2 blockerOffsets[8] = {
        float2(-0.5, -0.5), float2( 0.5, -0.5),
        float2(-0.5,  0.5), float2( 0.5,  0.5),
        float2(-1.0,  0.0), float2( 1.0,  0.0),
        float2( 0.0, -1.0), float2( 0.0,  1.0)
    };
    float blockerDepth = 0.0;
    float blockerCount = 0.0;
    [unroll]
    for (int sampleIndex = 0; sampleIndex < 8; ++sampleIndex) {
        const float depth = atlas_shadow_depth(
            uv + blockerOffsets[sampleIndex] * searchRadius,
            rect,
            texel
        );
        if (depth < receiverDepth - bias) {
            blockerDepth += depth;
            blockerCount += 1.0;
        }
    }
    if (blockerCount < 0.5) return 1.0;
    const float averageBlocker = blockerDepth / blockerCount;
    const float penumbra = (receiverDepth - averageBlocker) * lightSize
        / max(averageBlocker, 0.001);
    const float filterRadius = min(
        max(penumbra * texel * softness, texel),
        safeRadius
    );
    return poisson_pcf_shadow(
        uv,
        rect,
        receiverDepth - bias,
        texel,
        filterRadius
    );
}

float point_face_shadow(
    float3 direction,
    int face,
    int firstFace,
    float receiverDepth,
    float texel,
    float softness
) {
    return pcf_shadow(
        point_shadow_uv_for_face(direction, face),
        pointShadowAtlasRects[firstFace + face],
        receiverDepth,
        texel,
        softness
    );
}

float projected_face_shadow(
    int lightIndex,
    int projectedFace,
    float3 offsetPosition,
    float slope,
    float texel,
    out bool valid
) {
    valid = false;
    const float4 clip = mul(
        shadowMatrices[projectedFace],
        float4(offsetPosition, 1.0)
    );
    if (clip.w <= 0.0001) return 1.0;
    const float3 ndc = clip.xyz / clip.w;
    const float2 uv = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0
        || ndc.z < 0.0 || ndc.z > 1.0) return 1.0;
    valid = true;
    const float bias = shadowSettings[lightIndex].y * (0.25 + slope * 0.75);
    return pcss_shadow(
        uv,
        shadowAtlasRects[projectedFace],
        ndc.z,
        bias,
        texel,
        shadowSlots[lightIndex].w
    );
}

float shadow_visibility(
    int lightIndex,
    float3 worldPosition,
    float3 normal,
    float3 lightDirection
) {
    const float4 settings = shadowSettings[lightIndex];
    if (settings.x < 0.5) return 1.0;
    const int firstFace = (int)shadowSlots[lightIndex].x;
    const float texel = max(settings.z, 0.00001);
    const float normalLightDot = saturate(dot(normal, lightDirection));
    const float slope = 1.0 - normalLightDot;
    const float3 offsetPosition = worldPosition + normal * settings.w * slope;
    if (settings.x > 1.5) {
        const float3 toFragment = offsetPosition - lights[lightIndex].positionReach.xyz;
        const float distanceToLight = length(toFragment);
        const float range = max(lights[lightIndex].positionReach.w, 0.0001);
        if (distanceToLight <= 0.0001 || distanceToLight >= range) return 1.0;
        const float bias = max(
            settings.y * (0.2 + slope * 0.8),
            texel * 0.75 / max(normalLightDot, 0.35)
        );
        const float receiverDepth = distanceToLight / range - bias;
        const float softness = shadowSlots[lightIndex].w;
        const float3 absoluteDirection = abs(toFragment);
        const float dominant = max(
            absoluteDirection.x,
            max(absoluteDirection.y, absoluteDirection.z)
        );
        const float seamWidth = min(
            texel * max(1.0, 1.0 + softness * 2.0) * 8.0,
            0.05
        );
        const float adjacentThreshold = dominant * (1.0 - seamWidth);
        const int dominantFace = point_shadow_face(toFragment);
        float visibility = point_face_shadow(
            toFragment,
            dominantFace,
            firstFace,
            receiverDepth,
            texel,
            softness
        );
        // Both samples come from the valid 91-degree overlap. Preserve an
        // occluder reported by either face; choosing the brightest sample
        // leaks light as a thin line along cubemap seams.
        if (dominantFace != 0 && dominantFace != 1
            && absoluteDirection.x >= adjacentThreshold) {
            const int face = toFragment.x >= 0.0 ? 0 : 1;
            visibility = min(visibility, point_face_shadow(
                toFragment, face, firstFace, receiverDepth, texel, softness
            ));
        }
        if (dominantFace != 2 && dominantFace != 3
            && absoluteDirection.y >= adjacentThreshold) {
            const int face = toFragment.y >= 0.0 ? 2 : 3;
            visibility = min(visibility, point_face_shadow(
                toFragment, face, firstFace, receiverDepth, texel, softness
            ));
        }
        if (dominantFace != 4 && dominantFace != 5
            && absoluteDirection.z >= adjacentThreshold) {
            const int face = toFragment.z >= 0.0 ? 4 : 5;
            visibility = min(visibility, point_face_shadow(
                toFragment, face, firstFace, receiverDepth, texel, softness
            ));
        }
        return visibility;
    }
    int projectedFace = firstFace;
    const int faceCount = (int)shadowSlots[lightIndex].y;
    const bool cascaded = shadowSlots[lightIndex].z < 0.5 && faceCount > 1;
    float viewDepth = 0.0;
    if (cascaded) {
        viewDepth = dot(
            offsetPosition - cameraPosition.xyz,
            shadowCameraForward.xyz
        );
        [unroll]
        for (int cascade = 0; cascade < 3; ++cascade) {
            if (cascade + 1 < faceCount
                && viewDepth > shadowProjectedDepths[projectedFace].y) {
                projectedFace++;
            }
        }
    }
    bool primaryValid;
    float visibility = projected_face_shadow(
        lightIndex, projectedFace, offsetPosition, slope, texel, primaryValid
    );
    if (cascaded && projectedFace + 1 < firstFace + faceCount) {
        const float2 split = shadowProjectedDepths[projectedFace].xy;
        const float blendWidth = max((split.y - split.x) * 0.08, 0.0001);
        const float blendStart = split.y - blendWidth;
        if (viewDepth > blendStart) {
            bool nextValid;
            const float nextVisibility = projected_face_shadow(
                lightIndex,
                projectedFace + 1,
                offsetPosition,
                slope,
                texel,
                nextValid
            );
            if (nextValid) {
                const float blend = smoothstep(
                    blendStart, split.y, viewDepth
                );
                visibility = lerp(visibility, nextVisibility, blend);
            }
        }
    }
    return visibility;
}

float3 evaluate_light(
    int lightIndex,
    LightData light,
    float3 position,
    float3 normal,
    float3 viewDirection,
    float3 albedo,
    float metallic,
    float roughness
) {
    float3 lightDirection;
    float attenuation = 1.0;
    const float kind = light.colorType.w;
    if (kind < 0.5) {
        lightDirection = normalize(-light.directionIntensity.xyz);
    } else {
        const float3 delta = light.positionReach.xyz - position;
        const float distanceToLight = length(delta);
        if (distanceToLight <= 0.0001) return 0.0;
        lightDirection = delta / distanceToLight;
        if (kind < 1.5) {
            const float radius = max(light.projection.w, 0.0001);
            const float fade = max(light.anglesFalloffSoftness.z, 0.0001);
            attenuation = 1.0 - smoothstep(radius, radius + fade, distanceToLight);
        } else if (kind < 2.5) {
            attenuation = distance_attenuation(
                distanceToLight,
                light.positionReach.w,
                light.anglesFalloffSoftness.z
            ) * projector_attenuation(light, -delta);
        } else {
            attenuation = projector_attenuation(light, -delta);
        }
    }
    const float normalLight = saturate(dot(normal, lightDirection));
    if (normalLight <= 0.0 || attenuation <= 0.0) return 0.0;
    const float3 halfDirection = normalize(viewDirection + lightDirection);
    const float3 reflectance = lerp(0.04, albedo, metallic);
    const float distribution = distribution_ggx(normal, halfDirection, roughness);
    const float geometry = geometry_schlick(saturate(dot(normal, viewDirection)), roughness) *
        geometry_schlick(normalLight, roughness);
    const float3 fresnel = fresnel_schlick(
        saturate(dot(halfDirection, viewDirection)),
        reflectance
    );
    const float3 specular = distribution * geometry * fresnel /
        max(4.0 * saturate(dot(normal, viewDirection)) * normalLight, 0.0001);
    const float3 diffuse = (1.0 - fresnel) * (1.0 - metallic) * albedo / pbrPi;
    const float visibility = shadow_visibility(
        lightIndex,
        position,
        normal,
        lightDirection
    );
    return (diffuse + specular) * light.colorType.rgb *
        light.directionIntensity.w * normalLight * attenuation * visibility;
}

float3 tone_map(float3 color) {
    color = max(color, 0.0) * exp2(toneMappingSettings.y);
    if (toneMappingSettings.x < 0.5) return saturate(color);
    if (toneMappingSettings.x < 1.5) {
        const float whitePoint = toneMappingSettings.z;
        const float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
        if (luminance <= 0.000001) return 0.0;
        float mappedLuminance;
        if (whitePoint > 0.0) {
            mappedLuminance = (luminance *
                (1.0 + luminance / (whitePoint * whitePoint))) /
                (1.0 + luminance);
        } else {
            mappedLuminance = luminance / (1.0 + luminance);
        }
        color = saturate(color * (mappedLuminance / luminance));
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

float4 fragment_main(VertexOutput input, bool frontFace : SV_IsFrontFace) : SV_Target0 {
    const float2 albedoUv = transformed_uv(
        input.uv,
        albedoTransform,
        textureRotationsA.x
    );
    const float4 sampledAlbedo = albedoMap.Sample(albedoSampler, albedoUv);
    const float4 surfaceColor = input.color * sampledAlbedo;
    const float alphaMode = materialSettings.x;
    if (alphaMode > 0.5 && alphaMode < 1.5) {
        clip(surfaceColor.a - materialSettings.y);
    }
    float alpha = surfaceColor.a;
    if (alphaMode < 1.5) alpha = 1.0;
    float3 geometryNormal = normalize(input.worldNormal);
    const bool doubleSided = fmod(materialSettings.w, 2.0) > 0.5;
    if (doubleSided && !frontFace) geometryNormal = -geometryNormal;
    const float2 normalUv = transformed_uv(
        input.uv,
        normalTransform,
        textureRotationsA.y
    );
    const float3 normal = mapped_normal(
        input.worldPosition,
        geometryNormal,
        normalUv,
        materialSettings.z
    );
    const float3 viewDirection = normalize(cameraPosition.xyz - input.worldPosition);
    const float2 metallicRoughnessUv = transformed_uv(
        input.uv,
        metallicRoughnessTransform,
        textureRotationsA.z
    );
    const float4 sampledMetallicRoughness = metallicRoughnessMap.Sample(
        metallicRoughnessSampler,
        metallicRoughnessUv
    );
    const float metallic = saturate(materialSurface.x * sampledMetallicRoughness.b);
    const float roughness = clamp(
        materialSurface.y * sampledMetallicRoughness.g,
        0.04,
        1.0
    );
    const float2 occlusionUv = transformed_uv(
        input.uv,
        occlusionTransform,
        textureRotationsA.w
    );
    const float sampledOcclusion = occlusionMap.Sample(
        occlusionSampler,
        occlusionUv
    ).r;
    const float occlusion = saturate(
        1.0 + materialSurface.z * (sampledOcclusion - 1.0)
    );
    const float3 albedo = surfaceColor.rgb;
    const bool unlit = materialSettings.w > 1.5;
    if (unlit) return float4(tone_map(albedo), alpha);
    const float3 reflectance = lerp(0.04, albedo, metallic);
    const float3 ambientMaterial = albedo * (1.0 - metallic) +
        reflectance * (1.0 - roughness * 0.5);
    float3 color = ambientMaterial * ambientLight.rgb * ambientLight.a * occlusion;
    color += evaluate_environment(
        normal,
        viewDirection,
        albedo,
        metallic,
        roughness
    ) * occlusion;
    const int count = min((int)lightingSettings.x, 16);
    for (int index = 0; index < count; ++index) {
        color += evaluate_light(
            index,
            lights[index],
            input.worldPosition,
            normal,
            viewDirection,
            albedo,
            metallic,
            roughness
        );
    }
    const float2 emissionUv = transformed_uv(
        input.uv,
        emissionTransform,
        textureRotationsB.x
    );
    const float3 sampledEmission = emissionMap.Sample(emissionSampler, emissionUv).rgb;
    color += materialEmission.rgb * sampledEmission * materialSurface.w;
    return float4(tone_map(color), alpha);
}
