struct VertexInput {
    float3 position : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float2 uv : TEXCOORD2;
    float4 color : TEXCOORD3;
};

cbuffer DrawUniforms : register(b0, space1) {
    float4x4 model;
    float4x4 viewProjection;
    float4 materialAlbedo;
};

cbuffer MaterialUniforms : register(b3, space3) {
    float4 materialSurface;
    float4 materialEmission;
    float4 cameraPosition;
};

struct LightData {
    float4 directionIntensity;
    float4 colorType;
    float4 positionReach;
    float4 anglesFalloffSoftness;
    float4 projection;
};

cbuffer LightingUniforms : register(b0, space3) {
    float4 ambientLight;
    float4 lightingSettings;
    LightData lights[16];
};

cbuffer ShadowUniforms : register(b1, space3) {
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
Texture3D<float4> agxLut : register(t1, space2);
SamplerState agxSampler : register(s1, space2);
Texture3D<float4> neutralLut : register(t2, space2);
SamplerState neutralSampler : register(s2, space2);
Texture3D<float4> filmicDesaturationLut : register(t3, space2);
SamplerState filmicDesaturationSampler : register(s3, space2);
Texture2D<float4> filmicLooksLut : register(t4, space2);
SamplerState filmicLooksSampler : register(s4, space2);

struct VertexOutput {
    float3 worldPosition : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float4 color : COLOR0;
    float4 position : SV_Position;
};

VertexOutput vertex_main(VertexInput input) {
    VertexOutput output;
    const float4 world = mul(model, float4(input.position, 1.0));
    output.position = mul(viewProjection, world);
    output.worldPosition = world.xyz;
    output.worldNormal = normalize(mul((float3x3)model, input.normal));
    output.color = input.color * materialAlbedo;
    return output;
}

static const float pbrPi = 3.14159265;

float distribution_ggx(float3 normal, float3 halfDirection, float roughness) {
    const float alpha = roughness * roughness;
    const float alphaSquared = alpha * alpha;
    const float normalHalfDot = saturate(dot(normal, halfDirection));
    const float normalHalfDotSquared = normalHalfDot * normalHalfDot;
    const float denominator = normalHalfDotSquared * (alphaSquared - 1.0) + 1.0;
    return alphaSquared / max(pbrPi * denominator * denominator, 0.00001);
}

float geometry_schlick_ggx(float normalDirectionDot, float roughness) {
    const float r = roughness + 1.0;
    const float k = (r * r) / 8.0;
    return normalDirectionDot
        / max(normalDirectionDot * (1.0 - k) + k, 0.00001);
}

float geometry_smith(
    float3 normal,
    float3 viewDirection,
    float3 lightDirection,
    float roughness
) {
    const float normalViewDot = saturate(dot(normal, viewDirection));
    const float normalLightDot = saturate(dot(normal, lightDirection));
    return geometry_schlick_ggx(normalViewDot, roughness)
        * geometry_schlick_ggx(normalLightDot, roughness);
}

float3 fresnel_schlick(float halfViewDot, float3 reflectance) {
    return reflectance + (1.0 - reflectance) * pow(1.0 - halfViewDot, 5.0);
}

float distance_attenuation(float distanceToLight, float reach, float falloff) {
    if (distanceToLight >= reach) return 0.0;
    const float core = max(reach - falloff, 0.0);
    if (falloff <= 0.00001 || distanceToLight <= core) return 1.0;
    const float amount = saturate((reach - distanceToLight) / falloff);
    return amount * amount * (3.0 - 2.0 * amount);
}

float point_attenuation(LightData light, float distanceToLight) {
    const float radius = max(light.projection.w, 0.0001);
    const float softness = saturate(light.anglesFalloffSoftness.w);
    const float falloff = max(light.anglesFalloffSoftness.z, 0.0);
    if (distanceToLight <= radius) {
        const float ratio = saturate(distanceToLight / radius);
        const float softened = 1.0 - smoothstep(0.0, 1.0, ratio);
        return lerp(1.0, softened, softness);
    }
    if (falloff <= 0.0001) return 0.0;
    const float edgeInfluence = 1.0 - softness;
    const float fade = 1.0 - smoothstep(0.0, falloff, distanceToLight - radius);
    return edgeInfluence * fade;
}

float soften_boundary(float distanceToBoundary, float softness) {
    if (softness <= 0.0001) return distanceToBoundary >= 0.0 ? 1.0 : 0.0;
    return smoothstep(0.0, softness, distanceToBoundary);
}

void projector_basis(float3 forward, out float3 right, out float3 up) {
    const float3 referenceUp = abs(dot(forward, float3(0.0, 1.0, 0.0))) > 0.95
        ? float3(0.0, 0.0, 1.0)
        : float3(0.0, 1.0, 0.0);
    right = normalize(cross(forward, referenceUp));
    up = normalize(cross(right, forward));
}

float projected_attenuation(LightData light, float3 delta) {
    const float3 direction = normalize(light.directionIntensity.xyz);
    const float axial = dot(delta, direction);
    const float kind = light.colorType.w;
    if (kind < 2.5) {
        if (axial <= 0.0) return 0.0;
        const float cone = dot(normalize(delta), direction);
        const float inner = light.anglesFalloffSoftness.x;
        const float outer = light.anglesFalloffSoftness.y;
        return smoothstep(outer, inner, cone);
    }
    const float lengthValue = max(light.projection.z, 0.0001);
    const float softness = max(light.anglesFalloffSoftness.w, 0.0);
    const float falloff = max(light.anglesFalloffSoftness.z, 0.0);
    const float depth = soften_boundary(axial, softness * lengthValue)
        * soften_boundary(lengthValue + falloff - axial, falloff);
    if (kind < 4.5) {
        float3 right;
        float3 up;
        projector_basis(direction, right, up);
        const float halfWidth = max(light.projection.x * 0.5, 0.0001);
        const float halfHeight = max(light.projection.y * 0.5, 0.0001);
        return depth
            * soften_boundary(halfWidth - abs(dot(delta, right)), softness * halfWidth)
            * soften_boundary(halfHeight - abs(dot(delta, up)), softness * halfHeight);
    }
    const float radius = max(light.projection.w, 0.0001);
    const float radial = length(delta - direction * axial);
    return depth * soften_boundary(radius - radial, softness * radius);
}

float3 apply_reinhard(float3 color, float whitePoint) {
    if (whitePoint > 0.0) {
        return (color * (1.0 + color / (whitePoint * whitePoint)))
            / (1.0 + color);
    }
    return color / (1.0 + color);
}

static const float3x3 rec709ToFilmlightEGamut = float3x3(
    0.5593711, 0.3047833, 0.1358456,
    0.0762207, 0.7879718, 0.1358075,
    0.0655267, 0.1645468, 0.7699265
);

static const float3 rec709Luminance = float3(0.2126, 0.7152, 0.0722);

float3 linear_to_srgb(float3 value) {
    value = max(value, 0.0);
    const float3 low = value * 12.92;
    const float3 high = 1.055 * pow(value, 1.0 / 2.4) - 0.055;
    return float3(
        value.r <= 0.0031308 ? low.r : high.r,
        value.g <= 0.0031308 ? low.g : high.g,
        value.b <= 0.0031308 ? low.b : high.b
    );
}

float3 rec1886_to_srgb(float3 value) {
    return linear_to_srgb(pow(max(value, 0.0), 2.4));
}

float3 apply_aces(float3 color) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return linear_to_srgb(saturate(
        (color * (a * color + b)) / (color * (c * color + d) + e)
    ));
}

float3 apply_reinhard_display(float3 color, float whitePoint) {
    const float luminance = dot(color, rec709Luminance);
    if (luminance <= 0.000001) return 0.0;
    const float mappedLuminance = whitePoint > 0.0
        ? (luminance * (1.0 + luminance / (whitePoint * whitePoint))) / (1.0 + luminance)
        : luminance / (1.0 + luminance);
    return linear_to_srgb(saturate(color * (mappedLuminance / luminance)));
}

float agx_look_contrast(float lookIndex) {
    if (lookIndex < 0.5) return 0.7;
    if (lookIndex < 1.5) return 0.8;
    if (lookIndex < 2.5) return 0.9;
    if (lookIndex < 3.5) return 1.0;
    if (lookIndex < 4.5) return 1.2;
    if (lookIndex < 5.5) return 1.4;
    return 1.57;
}

float agx_look_saturation(float lookIndex) {
    if (lookIndex < 0.5) return 1.15;
    if (lookIndex < 1.5) return 1.1;
    if (lookIndex < 2.5) return 1.05;
    if (lookIndex < 4.5) return 1.0;
    if (lookIndex < 5.5) return 0.95;
    return 0.9;
}

float3 apply_agx_look(float3 logColor, float lookIndex) {
    const float pivot = 0.4;
    const float3 contrasted = (logColor - pivot) * agx_look_contrast(lookIndex) + pivot;
    const float luminance = dot(contrasted, rec709Luminance);
    return luminance + (contrasted - luminance) * agx_look_saturation(lookIndex);
}

float3 apply_agx(float3 color, float lookIndex) {
    const float minEv = -12.47393;
    const float maxEv = 12.5260688117;
    const float lutSize = 57.0;
    const float3 gamutColor = mul(rec709ToFilmlightEGamut, max(color, 0.0));
    const float3 logColor = (log2(max(gamutColor, 0.000000001)) - minEv) / (maxEv - minEv);
    const float3 lutUv = saturate(apply_agx_look(logColor, lookIndex))
        * ((lutSize - 1.0) / lutSize) + (0.5 / lutSize);
    return rec1886_to_srgb(agxLut.Sample(agxSampler, lutUv).rgb);
}

float3 apply_neutral(float3 color) {
    const float minEv = -9.0;
    const float maxEv = 10.0;
    const float lutSize = 57.0;
    const float3 logColor = (log2(max(color, 0.000000001)) - minEv) / (maxEv - minEv);
    const float3 lutUv = saturate(logColor) * ((lutSize - 1.0) / lutSize) + (0.5 / lutSize);
    return linear_to_srgb(neutralLut.Sample(neutralSampler, lutUv).rgb);
}

float sample_filmic_look(float value, float lookIndex) {
    const float lutSize = 4096.0;
    const float lookCount = 7.0;
    const float2 uv = float2(
        saturate(value) * ((lutSize - 1.0) / lutSize) + (0.5 / lutSize),
        (lookIndex + 0.5) / lookCount
    );
    return filmicLooksLut.Sample(filmicLooksSampler, uv).r;
}

float3 apply_filmic(float3 color, float lookIndex) {
    const float minEv = -12.473931188;
    const float maxEv = 12.526068812;
    const float lutSize = 33.0;
    const float3 logColor = (log2(max(color, 0.000000001)) - minEv) / (maxEv - minEv);
    const float3 uv = saturate(logColor) * ((lutSize - 1.0) / lutSize) + (0.5 / lutSize);
    const float3 filmicLog = saturate(
        filmicDesaturationLut.Sample(filmicDesaturationSampler, uv).rgb / 0.66
    );
    return float3(
        sample_filmic_look(filmicLog.r, lookIndex),
        sample_filmic_look(filmicLog.g, lookIndex),
        sample_filmic_look(filmicLog.b, lookIndex)
    );
}

float3 apply_tone_mapping(float3 color) {
    color = max(color, float3(0.0, 0.0, 0.0)) * exp2(toneMappingSettings.y);
    if (toneMappingSettings.x < 0.5) return saturate(color);
    if (toneMappingSettings.x < 1.5) {
        return apply_reinhard_display(color, toneMappingSettings.z);
    }
    if (toneMappingSettings.x < 2.5) return apply_aces(color);
    if (toneMappingSettings.x < 3.5) return apply_neutral(color);
    if (toneMappingSettings.x < 4.5) {
        return apply_filmic(color, toneMappingSettings.w);
    }
    return apply_agx(color, toneMappingSettings.w);
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
    // Match the 91-degree point-shadow projection. The small guard band keeps
    // caster edges available in both faces at cubemap seams.
    const float guardScale = 0.9826972631;
    return uv * guardScale * 0.5 + 0.5;
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
    float normalLightDot,
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
    const float bias = max(
        shadowSettings[lightIndex].y * (1.0 - normalLightDot),
        shadowSettings[lightIndex].y
    );
    return pcss_shadow(
        uv,
        shadowAtlasRects[projectedFace],
        ndc.z,
        bias,
        texel,
        shadowSlots[lightIndex].w
    );
}

float shadow_visibility(int lightIndex, float3 worldPosition, float3 normal, float3 lightDirection) {
    const float4 settings = shadowSettings[lightIndex];
    if (settings.x < 0.5) return 1.0;
    const int firstFace = (int)shadowSlots[lightIndex].x;
    const float3 offsetPosition = worldPosition + normal * settings.w;
    const float texel = max(settings.z, 0.00001);
    const float normalLightDot = saturate(dot(normal, lightDirection));
    if (settings.x > 1.5) {
        const float3 toFragment = offsetPosition - lights[lightIndex].positionReach.xyz;
        const float distanceToLight = length(toFragment);
        const float range = max(lights[lightIndex].positionReach.w, 0.0001);
        if (distanceToLight <= 0.0001 || distanceToLight >= range) return 1.0;
        // Point faces share the atlas, so their effective texel size is larger
        // than a full-resolution projected shadow. Cover the PCF footprint and
        // increase the receiver bias for grazing light angles.
        const float bias = max(
            max(settings.y * (1.0 - normalLightDot), settings.y * 0.2),
            texel * 4.0 / max(normalLightDot, 0.25)
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
        lightIndex,
        projectedFace,
        offsetPosition,
        normalLightDot,
        texel,
        primaryValid
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
                normalLightDot,
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

float4 fragment_main(VertexOutput input) : SV_Target0 {
    const float3 normal = normalize(input.worldNormal);
    const float metallic = saturate(materialSurface.x);
    const float roughness = clamp(materialSurface.y, 0.04, 1.0);
    const float occlusion = saturate(materialSurface.z);
    const float3 albedo = input.color.rgb;
    const float3 viewDirection = normalize(cameraPosition.xyz - input.worldPosition);
    const float normalViewDot = saturate(dot(normal, viewDirection));
    const float3 reflectance = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);
    float3 direct = float3(0.0, 0.0, 0.0);
    const int lightCount = min((int)lightingSettings.x, 16);
    for (int index = 0; index < lightCount; ++index) {
        const LightData light = lights[index];
        const float kind = light.colorType.w;
        float3 toLight;
        float attenuation = 1.0;
        if (kind < 0.5) {
            toLight = -normalize(light.directionIntensity.xyz);
        } else {
            const float3 delta = light.positionReach.xyz - input.worldPosition;
            const float distanceToLight = length(delta);
            if (distanceToLight <= 0.00001) continue;
            toLight = delta / distanceToLight;
            if (kind < 1.5) {
                attenuation = point_attenuation(light, distanceToLight);
            } else if (kind < 3.5) {
                attenuation = distance_attenuation(
                    distanceToLight,
                    light.positionReach.w,
                    light.anglesFalloffSoftness.z
                ) * projected_attenuation(light, -delta);
            } else {
                attenuation = projected_attenuation(light, -delta);
            }
        }
        const float normalLightDot = saturate(dot(normal, toLight));
        const float3 halfDirection = normalize(viewDirection + toLight);
        const float distribution = distribution_ggx(normal, halfDirection, roughness);
        const float geometry = geometry_smith(normal, viewDirection, toLight, roughness);
        const float3 fresnel = fresnel_schlick(
            saturate(dot(halfDirection, viewDirection)),
            reflectance
        );
        const float3 specular = distribution * geometry * fresnel
            / max(4.0 * normalViewDot * normalLightDot, 0.00001);
        const float3 diffuseEnergy = (1.0 - fresnel) * (1.0 - metallic);
        const float visibility = shadow_visibility(index, input.worldPosition, normal, toLight);
        const float3 radiance = light.colorType.rgb
            * light.directionIntensity.w
            * attenuation
            * visibility;
        direct += (diffuseEnergy * albedo / pbrPi + specular)
            * radiance
            * normalLightDot;
    }
    const float3 ambient = ambientLight.rgb * ambientLight.a * albedo * occlusion;
    const float3 linearColor = max(
        ambient + direct + materialEmission.rgb * materialEmission.a,
        float3(0.0, 0.0, 0.0)
    );
    float3 color = apply_tone_mapping(linearColor);
    if (
        toneMappingComparison.y > 0.5
        && input.position.x / max(toneMappingComparison.w, 1.0)
            < toneMappingComparison.z
    ) {
        color = saturate(linearColor * exp2(toneMappingComparison.x));
    }
    return float4(color, input.color.a);
}
