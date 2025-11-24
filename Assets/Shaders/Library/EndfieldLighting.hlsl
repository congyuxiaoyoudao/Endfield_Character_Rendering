#ifndef ENDFIELD_LIGHTING_INCLUDED
#define ENDFIELD_LIGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Debug/Debugging3D.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/AmbientOcclusion.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DBuffer.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

#if defined(LIGHTMAP_ON)
    #define DECLARE_LIGHTMAP_OR_SH(lmName, shName, index) float2 lmName : TEXCOORD##index
    #define OUTPUT_LIGHTMAP_UV(lightmapUV, lightmapScaleOffset, OUT) OUT.xy = lightmapUV.xy * lightmapScaleOffset.xy + lightmapScaleOffset.zw;
    #define OUTPUT_SH(normalWS, OUT)
#else
    #define DECLARE_LIGHTMAP_OR_SH(lmName, shName, index) half3 shName : TEXCOORD##index
    #define OUTPUT_LIGHTMAP_UV(lightmapUV, lightmapScaleOffset, OUT)
    #define OUTPUT_SH(normalWS, OUT) OUT.xyz = SampleSHVertex(normalWS)
#endif

///////////////////////////////////////////////////////////////////////////////
//                      Lighting Functions                                   //
///////////////////////////////////////////////////////////////////////////////
half3 LightingLambert(half3 lightColor, half3 lightDir, half3 normal)
{
    half NdotL = saturate(dot(normal, lightDir));
    return lightColor * NdotL;
}

half3 LightingSpecular(half3 lightColor, half3 lightDir, half3 normal, half3 viewDir, half4 specular, half smoothness)
{
    float3 halfVec = SafeNormalize(float3(lightDir) + float3(viewDir));
    half NdotH = half(saturate(dot(normal, halfVec)));
    half modifier = pow(NdotH, smoothness);
    // NOTE: In order to fix internal compiler error on mobile platforms, this needs to be float3
    float3 specularReflection = specular.rgb * modifier;
    return lightColor * specularReflection;
}

half DepthRim(half3 normalWS, half2 screenUV, half rimWidth)
{
    float curDepth = SampleSceneDepth(screenUV);
    float linearDepth = LinearEyeDepth(curDepth, _ZBufferParams);

    // here do a trick to sampler a "hull" around mesh pixels
    half3 normalVS = TransformWorldToViewNormal(normalWS, true);
    float2 offset = normalVS.xy * 0.02 * rimWidth;
    float neighborDepth = SampleSceneDepth(screenUV + offset);
    float linearDepth2 = LinearEyeDepth(neighborDepth, _ZBufferParams);
    half depthRim = clamp(0.0,5.0,linearDepth2 - linearDepth);
    return depthRim;
}

half3 LightingPhysicallyBased(BRDFData brdfData, BRDFData brdfDataClearCoat,
    half3 lightColor, half3 lightDirectionWS, half lightAttenuation,
    half3 normalWS, half3 viewDirectionWS,
    half clearCoatMask, bool specularHighlightsOff)
{
    half NdotL = saturate(dot(normalWS, lightDirectionWS));
    half3 radiance = lightColor * (lightAttenuation * NdotL);

    // half2 diffuseRampUV = half2(NdotL, 0);
    // half4 diffuseRamp = SAMPLE_TEXTURE2D(_RampMap, sampler_RampMap, diffuseRampUV).rgba;
    // half3 diffuseColor = lerp(0.0, brdfData.diffuse, diffuseRamp.a);
    //
    // half3 brdf = diffuseColor * diffuseRamp.rgb;
    
    half3 brdf = brdfData.diffuse;

#ifndef _SPECULARHIGHLIGHTS_OFF
    [branch] if (!specularHighlightsOff)
    {
        // TODO: Colorful Specular
        brdf += brdfData.specular * DirectBRDFSpecular(brdfData, normalWS, lightDirectionWS, viewDirectionWS);
        
#if defined(_CLEARCOAT) || defined(_CLEARCOATMAP)
        // Clear coat evaluates the specular a second timw and has some common terms with the base specular.
        // We rely on the compiler to merge these and compute them only once.
        half brdfCoat = kDielectricSpec.r * DirectBRDFSpecular(brdfDataClearCoat, normalWS, lightDirectionWS, viewDirectionWS);

            // Mix clear coat and base layer using khronos glTF recommended formula
            // https://github.com/KhronosGroup/glTF/blob/master/extensions/2.0/Khronos/KHR_materials_clearcoat/README.md
            // Use NoV for direct too instead of LoH as an optimization (NoV is light invariant).
            half NoV = saturate(dot(normalWS, viewDirectionWS));
            // Use slightly simpler fresnelTerm (Pow4 vs Pow5) as a small optimization.
            // It is matching fresnel used in the GI/Env, so should produce a consistent clear coat blend (env vs. direct)
            half coatFresnel = kDielectricSpec.x + kDielectricSpec.a * Pow4(1.0 - NoV);

        brdf = brdf * (1.0 - clearCoatMask * coatFresnel) + brdfCoat * clearCoatMask;
#endif // _CLEARCOAT
    }
#endif // _SPECULARHIGHLIGHTS_OFF

    return brdf * radiance * _DirectLightingIntensity;
}

half3 LightingPhysicallyBased(BRDFData brdfData, BRDFData brdfDataClearCoat, Light light, half3 normalWS, half3 viewDirectionWS, half clearCoatMask, bool specularHighlightsOff)
{
    return LightingPhysicallyBased(brdfData, brdfDataClearCoat, light.color, light.direction, light.distanceAttenuation * light.shadowAttenuation, normalWS, viewDirectionWS, clearCoatMask, specularHighlightsOff);
}

half sigmoidSharp(half x, half center, half sharpness)
{
    return rcp(pow(100000,(x - center)*(-3*sharpness))+1.0f);
}

// Endfield Skin Lightning
half3 LightningSkin(BRDFData brdfData, Light mainLight, half3 normalWS, half3 viewDirectionWS, float2 screenUV)
{
    // do not apply NdotL for toon face lightning
    half3 radiance = mainLight.color; // now just color

    /// 1. SHADOW ///
    // scene shadow
    half sceneShadow = mainLight.shadowAttenuation;
    sceneShadow = sigmoidSharp(sceneShadow, _SceneShadowCenter, _SceneShadowSharpness); // then moderate 0.1 0.03

    half3 lightDirectionWS = mainLight.direction;
    half NoL = dot(lightDirectionWS, normalWS);
    half lambertShadow = NoL * 0.5 + 0.5;
    // return lambertShadow;
    lambertShadow = sigmoidSharp(lambertShadow, _HalfLambertShadowCenter, _HalfLambertShadowSharpness);// make it smooth 0.1 0.15
    // return sceneShadow;
    // compose final shadow
    half shadow = saturate(min(sceneShadow, lambertShadow));
    // return shadow;
    // before sampling ramp map, shadow should be well adjusted
    half2 diffuseRampUV = half2(shadow, 0.5);
    half4 diffuseRampColor = SAMPLE_TEXTURE2D(_DiffuseRampMap, sampler_DiffuseRampMap, diffuseRampUV);
    // return diffuseRampColor;
    half3 directLightningDiffuse = 0.318 * diffuseRampColor * brdfData.diffuse * radiance;
    
    /// 2. SSS ///
    half alpha = _SSS_Radius;
    half theta = max(0, NoL + alpha) - alpha;
    half normalization_jgt = (2 + alpha) / (2 * (1 + alpha));
    half wrapped_jgt = (pow(((theta + alpha) / (1 + alpha)), 1 + alpha)) * normalization_jgt;
    half3 subsurface_radiance = _SSS_Color * wrapped_jgt * pow(1 - NoL, 3);
    half sss_strength = _SSS_Value * _SSS_Value;
    half3 sss_part = radiance * subsurface_radiance * sss_strength;
    // directLightningDiffuse += sss_part;
    
    /// 3. RIM ///
    half3 rim = DepthRim(normalWS, screenUV, _RimWidth) * _RimIntensity * _RimColor;
    
    half shadowArea = diffuseRampColor.a;
    shadowArea = smoothstep(-0.01, 1.0, shadowArea);
    // shadowArea = clamp(1.0, 0.0, shadowArea);
    // compose final color
    half3 directLightning = (directLightningDiffuse + rim) * shadowArea;
    return directLightning * _DirectLightingIntensity;
}

half3 ComputeAndBlendSphereNormal(half3 headCenter, half3 posWS, half normalWS, half sphereNormalIntensity)
{
    half3 sphereNormal = normalize(posWS - headCenter);
    return NLerp(normalWS, sphereNormal, sphereNormalIntensity);
}

// Endfield Face Lightning
half3 LightningFaceSDF(BRDFData brdfData, Light mainLight, half4 faceAreaMask, half3 normalWS, half3 viewDirectionWS, half3 posWS, float2 uv)
{
    // do not apply NdotL for toon face lightning
    half3 radiance = mainLight.color; // now just color

    /// 1. SHADOW ///
    half2 sdfUV = uv;
    if(_FlipSDFThreshold < 0.0)
        sdfUV.x = 1 - sdfUV.x;
    half4 sdf = SAMPLE_TEXTURE2D(_SDFMap, sampler_SDFMap, sdfUV);
    half sdfShadow = (sdf.r + sdf.g)/2.0;
    sdfShadow = sigmoidSharp(sdfShadow-_AngleThreshold,  _SDFShadowCenter, _SDFSharpness);
    // scene shadow
    half sceneShadow = mainLight.shadowAttenuation;
    sdfShadow = min(sdfShadow, sceneShadow); // mix first
    sceneShadow = sigmoidSharp(sceneShadow, _SceneShadowCenter, _SceneShadowSharpness); // then moderate 0.0 0.2

    half chinArea = faceAreaMask.g;
    half3 lightDirectionWS = mainLight.direction;
    half faceLambertShadow = dot(lightDirectionWS, normalWS) * 0.5 + 0.5;
    faceLambertShadow = sigmoidSharp(faceLambertShadow, _HalfLambertShadowCenter, _HalfLambertShadowSharpness);// make it smooth 0.5 0.1
    half chinShadow = lerp(1.0, faceLambertShadow, chinArea);

    // compose final shadow
    half shadow = min(sceneShadow, sdfShadow);
    shadow = min(shadow, chinShadow);

    // before sampling ramp map, shadow should be well adjusted
    half2 diffuseRampUV = half2(shadow, 0.5);
    half4 diffuseRampColor = SAMPLE_TEXTURE2D(_DiffuseRampMap, sampler_DiffuseRampMap, diffuseRampUV);

    /// 2. HIGHLIGHT ///
    half lipHLOffset = dot(viewDirectionWS, _HeadRight).x * 0.03;
    half2 lipHLUV = uv + half2(lipHLOffset,0);
    half lipHL = SAMPLE_TEXTURE2D(_LipHighlightMask, sampler_LipHighlightMask, lipHLUV).r;
    lipHL = lipHL * max(0.4, shadow);  // fall off but keep a minimum intensity in shadow
    half3 directLightningDiffuse = 0.318 * diffuseRampColor * brdfData.diffuse * radiance; // here divide by pi

    /// 3. Specular ///
    // here do a trick, do not pass mesh normal for specular calculation
    // instead, we recalculate a sphere normal
    half3 sphereNormalWS = ComputeAndBlendSphereNormal(_HeadCenter, posWS, normalWS, 1.0);
    sphereNormalWS = NLerp(sphereNormalWS, normalWS, chinArea);
    half3 directLightningSpecular = LightingSpecular(mainLight.color, mainLight.direction, sphereNormalWS, viewDirectionWS,
        half4(brdfData.specular,1.0), 0.5);
    directLightningSpecular = smoothstep(0.0, 0.2, directLightningSpecular);
    // return directLightningSpecular;

    /// 4. RIM ///
    half rim = lerp(0, faceAreaMask.a, 1-sdfUV.x>0.5);
    rim -= _AngleThreshold; // back light cutoff
    // uv flipped when _AngleThreshold from 1->0->1, so make it not that abrupt
    rim *= smoothstep(0, 0.2, _AngleThreshold);
    half viewDirFalloff = smoothstep(0.8, 1.0, dot(viewDirectionWS, _HeadForward));
    rim = saturate(rim*viewDirFalloff);

    half shadowArea = diffuseRampColor.a;
    shadowArea = smoothstep(-0.1, 1.0, shadowArea);
    // compose final color
    half3 directLightning = (directLightningDiffuse + directLightningSpecular + rim) * shadowArea +lipHL*3;
    return directLightning * _DirectLightingIntensity;
}

half3 GetEquirectTangent(float3 N)
{
    half3 axis = half3(0.0,1.0,0.0);
    half3 B = normalize(cross(N, axis));
    half3 T_equi = normalize(cross(N, B));
    return T_equi;
}

// Endfield Hair Lightning
half3 LightningHair(BRDFData brdfData, Light mainLight, half4 hairMask, half3 normalWS, half3 viewDirectionWS, float2 uv, float2 screenUV)
{
    // do not apply NdotL for toon face lightning
    half3 radiance = mainLight.color; // now just color

    half NoL = dot(normalWS, mainLight.direction);
    half NoV = saturate(dot(normalWS, viewDirectionWS));
    
    /// 1. SHADOW ///
    half sceneShadow = mainLight.shadowAttenuation;
    sceneShadow = sigmoidSharp(sceneShadow, _SceneShadowCenter, _SceneShadowSharpness); // 0 0.2
    half lambertShadow = NoL * 0.5 + 0.5;
    lambertShadow = sigmoidSharp(lambertShadow, _HalfLambertShadowCenter, _HalfLambertShadowSharpness);// make it smooth 0.5 0.1
    half shadow = min(lambertShadow, sceneShadow);

    // before sampling ramp map, shadow should be well adjusted
    /// 2. DIRECT LIGHTNING ///
    half2 diffuseRampUV = half2(shadow, 0.5);
    half4 diffuseRampColor = SAMPLE_TEXTURE2D(_DiffuseRampMap, sampler_DiffuseRampMap, diffuseRampUV);
    half3 directLightningDiffuse = 0.318 * diffuseRampColor * brdfData.diffuse * radiance; // here divide by pi
    half3 directLightningSpecular = LightingSpecular(mainLight.color, mainLight.direction, normalWS, viewDirectionWS,
            half4(brdfData.specular,1.0), 0.5);
    directLightningSpecular = smoothstep(0.0, 1.2, directLightningSpecular);

    /// 3. ANISOTROPIC HL ///
    half underHairMask = hairMask.r;
    half anisoHLMask = hairMask.g;
    half ao = hairMask.b;
    half anisoHLIntensity = hairMask.a;
    
    half remappedNoV = pow(NoV, 5);
    half viewDirFallOff = sigmoidSharp(remappedNoV, 0.5, 0.1);

    half3 H = normalize(mainLight.direction + viewDirectionWS);
    half3 T = GetEquirectTangent(normalWS); // refer to blender tangent node
    half ToH = dot(T, H);
    half sinTH = sqrt(1 - ToH * ToH);

    half anisoHL = saturate(pow(sinTH,5));
    anisoHL = smoothstep(0.995, 1.01, anisoHL); // this is quite hard to control :(
    anisoHL = min(anisoHL, anisoHLMask) * anisoHLIntensity * viewDirFallOff;
    half3 anisoHLColor = anisoHL * _AnisotropicHLIntensity * _AnisotropicHLColor;

    /// 4. RIM ///
    half3 rim = DepthRim(normalWS, screenUV, _RimWidth) * _RimIntensity * _RimColor;
    
    // global shadow intensity controller
    half shadowArea = diffuseRampColor.a;
    shadowArea = smoothstep(-0.1, 1.0, shadowArea);
    
    // compose final color
    half3 directLightning = (directLightningDiffuse+directLightningSpecular+rim+anisoHLColor)*shadowArea;
    return directLightning * _DirectLightingIntensity;
}

// Backwards compatibility
half3 LightingPhysicallyBased(BRDFData brdfData, Light light, half3 normalWS, half3 viewDirectionWS)
{
    #ifdef _SPECULARHIGHLIGHTS_OFF
    bool specularHighlightsOff = true;
#else
    bool specularHighlightsOff = false;
#endif
    const BRDFData noClearCoat = (BRDFData)0;
    return LightingPhysicallyBased(brdfData, noClearCoat, light, normalWS, viewDirectionWS, 0.0, specularHighlightsOff);
}

half3 LightingPhysicallyBased(BRDFData brdfData, half3 lightColor, half3 lightDirectionWS, half lightAttenuation, half3 normalWS, half3 viewDirectionWS)
{
    Light light;
    light.color = lightColor;
    light.direction = lightDirectionWS;
    light.distanceAttenuation = lightAttenuation;
    light.shadowAttenuation   = 1;
    return LightingPhysicallyBased(brdfData, light, normalWS, viewDirectionWS);
}

half3 LightingPhysicallyBased(BRDFData brdfData, Light light, half3 normalWS, half3 viewDirectionWS, bool specularHighlightsOff)
{
    const BRDFData noClearCoat = (BRDFData)0;
    return LightingPhysicallyBased(brdfData, noClearCoat, light, normalWS, viewDirectionWS, 0.0, specularHighlightsOff);
}

half3 LightingPhysicallyBased(BRDFData brdfData, half3 lightColor, half3 lightDirectionWS, half lightAttenuation, half3 normalWS, half3 viewDirectionWS, bool specularHighlightsOff)
{
    Light light;
    light.color = lightColor;
    light.direction = lightDirectionWS;
    light.distanceAttenuation = lightAttenuation;
    light.shadowAttenuation   = 1;
    return LightingPhysicallyBased(brdfData, light, viewDirectionWS, specularHighlightsOff, specularHighlightsOff);
}

half3 VertexLighting(float3 positionWS, half3 normalWS)
{
    half3 vertexLightColor = half3(0.0, 0.0, 0.0);

#ifdef _ADDITIONAL_LIGHTS_VERTEX
    uint lightsCount = GetAdditionalLightsCount();
    uint meshRenderingLayers = GetMeshRenderingLayer();

    LIGHT_LOOP_BEGIN(lightsCount)
        Light light = GetAdditionalLight(lightIndex, positionWS);

#ifdef _LIGHT_LAYERS
    if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
    {
        half3 lightColor = light.color * light.distanceAttenuation;
        vertexLightColor += LightingLambert(lightColor, light.direction, normalWS);
    }

    LIGHT_LOOP_END
#endif

    return vertexLightColor;
}

struct LightingData
{
    half3 giColor;
    half3 mainLightColor;
    half3 additionalLightsColor;
    half3 vertexLightingColor;
    half3 emissionColor;
};

half3 CalculateLightingColor(LightingData lightingData, half3 albedo)
{
    half3 lightingColor = 0;

    if (IsOnlyAOLightingFeatureEnabled())
    {
        return lightingData.giColor; // Contains white + AO
    }

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_GLOBAL_ILLUMINATION))
    {
        lightingColor += lightingData.giColor;
    }

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_MAIN_LIGHT))
    {
        lightingColor += lightingData.mainLightColor;
    }

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_ADDITIONAL_LIGHTS))
    {
        lightingColor += lightingData.additionalLightsColor;
    }

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_VERTEX_LIGHTING))
    {
        lightingColor += lightingData.vertexLightingColor;
    }

    lightingColor *= albedo;

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_EMISSION))
    {
        lightingColor += lightingData.emissionColor;
    }

    return lightingColor;
}

half4 CalculateFinalColor(LightingData lightingData, half alpha)
{
    half3 finalColor = CalculateLightingColor(lightingData, 1);

    return half4(finalColor, alpha);
}

half4 CalculateFinalColor(LightingData lightingData, half3 albedo, half alpha, float fogCoord)
{
    #if defined(_FOG_FRAGMENT)
        #if (defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2))
        float viewZ = -fogCoord;
        float nearToFarZ = max(viewZ - _ProjectionParams.y, 0);
        half fogFactor = ComputeFogFactorZ0ToFar(nearToFarZ);
    #else
        half fogFactor = 0;
        #endif
    #else
    half fogFactor = fogCoord;
    #endif
    half3 lightingColor = CalculateLightingColor(lightingData, albedo);
    half3 finalColor = MixFog(lightingColor, fogFactor);

    return half4(finalColor, alpha);
}

LightingData CreateLightingData(InputData inputData, SurfaceData surfaceData)
{
    LightingData lightingData;

    lightingData.giColor = inputData.bakedGI;
    lightingData.emissionColor = surfaceData.emission;
    lightingData.vertexLightingColor = 0;
    lightingData.mainLightColor = 0;
    lightingData.additionalLightsColor = 0;

    return lightingData;
}

half3 CalculateBlinnPhong(Light light, InputData inputData, SurfaceData surfaceData)
{
    half3 attenuatedLightColor = light.color * (light.distanceAttenuation * light.shadowAttenuation);
    half3 lightDiffuseColor = LightingLambert(attenuatedLightColor, light.direction, inputData.normalWS);

    half3 lightSpecularColor = half3(0,0,0);
    #if defined(_SPECGLOSSMAP) || defined(_SPECULAR_COLOR)
    half smoothness = exp2(10 * surfaceData.smoothness + 1);

    lightSpecularColor += LightingSpecular(attenuatedLightColor, light.direction, inputData.normalWS, inputData.viewDirectionWS, half4(surfaceData.specular, 1), smoothness);
    #endif

#if _ALPHAPREMULTIPLY_ON
    return lightDiffuseColor * surfaceData.albedo * surfaceData.alpha + lightSpecularColor;
#else
    return lightDiffuseColor * surfaceData.albedo + lightSpecularColor;
#endif
}

///////////////////////////////////////////////////////////////////////////////
//                      Fragment Functions                                   //
//       Used by ShaderGraph and others builtin renderers                    //
///////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
/// PBR lighting...
////////////////////////////////////////////////////////////////////////////////
half4 UniversalFragmentPBR(InputData inputData, SurfaceData surfaceData)
{
    #if defined(_SPECULARHIGHLIGHTS_OFF)
    bool specularHighlightsOff = true;
    #else
    bool specularHighlightsOff = false;
    #endif
    BRDFData brdfData;
    
    // NOTE: can modify "surfaceData"...
    InitializeBRDFData(surfaceData, brdfData);

    #if defined(DEBUG_DISPLAY)
    half4 debugColor;

    if (CanDebugOverrideOutputColor(inputData, surfaceData, brdfData, debugColor))
    {
        return debugColor;
    }
    #endif

    // Clear-coat calculation...
    BRDFData brdfDataClearCoat = CreateClearCoatBRDFData(surfaceData, brdfData);
    half4 shadowMask = CalculateShadowMask(inputData);
    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
    uint meshRenderingLayers = GetMeshRenderingLayer();
    Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);

    // NOTE: We don't apply AO to the GI here because it's done in the lighting calculation below...
    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI);

    LightingData lightingData = CreateLightingData(inputData, surfaceData);

    lightingData.giColor = GlobalIllumination(brdfData, brdfDataClearCoat, surfaceData.clearCoatMask,
                                              inputData.bakedGI, aoFactor.indirectAmbientOcclusion, inputData.positionWS,
                                              inputData.normalWS, inputData.viewDirectionWS, inputData.normalizedScreenSpaceUV);
#ifdef _LIGHT_LAYERS
    if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
#endif
    {
        
        lightingData.mainLightColor = LightingPhysicallyBased(brdfData, brdfDataClearCoat,
                                                      mainLight,
                                                      inputData.normalWS, inputData.viewDirectionWS,
                                                      surfaceData.clearCoatMask, specularHighlightsOff);
        half2 screenUV = inputData.normalizedScreenSpaceUV;
        half3 rim = DepthRim(inputData.normalWS, screenUV, _RimWidth) * _RimIntensity * _RimColor;
        lightingData.mainLightColor += rim;
        lightingData.giColor *= _GIIntensity;
    }

    #if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();

    #if USE_FORWARD_PLUS
    for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        FORWARD_PLUS_SUBTRACTIVE_LIGHT_CHECK

        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            lightingData.additionalLightsColor += LightingPhysicallyBased(brdfData, brdfDataClearCoat, light,
                                                                          inputData.normalWS, inputData.viewDirectionWS,
                                                                          surfaceData.clearCoatMask, specularHighlightsOff);
        }
    }
    #endif

    LIGHT_LOOP_BEGIN(pixelLightCount)
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            lightingData.additionalLightsColor += LightingPhysicallyBased(brdfData, brdfDataClearCoat, light,
                                                                          inputData.normalWS, inputData.viewDirectionWS,
                                                                          surfaceData.clearCoatMask, specularHighlightsOff);
        }
    LIGHT_LOOP_END
    #endif

    #if defined(_ADDITIONAL_LIGHTS_VERTEX)
    lightingData.vertexLightingColor += inputData.vertexLighting * brdfData.diffuse;
    #endif

#if REAL_IS_HALF
    // Clamp any half.inf+ to HALF_MAX
    return min(CalculateFinalColor(lightingData, surfaceData.alpha), HALF_MAX);
#else
    return CalculateFinalColor(lightingData, surfaceData.alpha);
#endif
}

half4 UniversalFragmentSkin(InputData inputData, SurfaceData surfaceData)
{
    #if defined(_SPECULARHIGHLIGHTS_OFF)
    bool specularHighlightsOff = true;
    #else
    bool specularHighlightsOff = false;
    #endif
    BRDFData brdfData;
    
    // NOTE: can modify "surfaceData"...
    InitializeBRDFData(surfaceData, brdfData);

    #if defined(DEBUG_DISPLAY)
    half4 debugColor;

    if (CanDebugOverrideOutputColor(inputData, surfaceData, brdfData, debugColor))
    {
        return debugColor;
    }
    #endif

    // Clear-coat calculation...
    BRDFData brdfDataClearCoat = CreateClearCoatBRDFData(surfaceData, brdfData);
    half4 shadowMask = CalculateShadowMask(inputData);
    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
    uint meshRenderingLayers = GetMeshRenderingLayer();
    Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);

    // NOTE: We don't apply AO to the GI here because it's done in the lighting calculation below...
    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI);

    LightingData lightingData = CreateLightingData(inputData, surfaceData);
    aoFactor.indirectAmbientOcclusion = smoothstep(-1.5, 1.8, aoFactor.indirectAmbientOcclusion);
    // lightingData.giColor = GlobalIllumination(brdfData, brdfDataClearCoat, surfaceData.clearCoatMask,
    //                                           inputData.bakedGI, aoFactor.indirectAmbientOcclusion, inputData.positionWS,
    //                                           inputData.normalWS, inputData.viewDirectionWS, inputData.normalizedScreenSpaceUV);
    lightingData.giColor = inputData.bakedGI * brdfData.diffuse * aoFactor.indirectAmbientOcclusion;

#ifdef _LIGHT_LAYERS
    if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
#endif
    {
        lightingData.mainLightColor = LightningSkin(brdfData, mainLight,
                                                      inputData.normalWS, inputData.viewDirectionWS,
                                                      inputData.normalizedScreenSpaceUV);
        lightingData.giColor *= _GIIntensity;
    }

    #if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();

    #if USE_FORWARD_PLUS
    for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        FORWARD_PLUS_SUBTRACTIVE_LIGHT_CHECK

        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            lightingData.additionalLightsColor += LightingPhysicallyBased(brdfData, brdfDataClearCoat, light,
                                                                          inputData.normalWS, inputData.viewDirectionWS,
                                                                          surfaceData.clearCoatMask, specularHighlightsOff);
        }
    }
    #endif

    LIGHT_LOOP_BEGIN(pixelLightCount)
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            lightingData.additionalLightsColor += LightingPhysicallyBased(brdfData, brdfDataClearCoat, light,
                                                                          inputData.normalWS, inputData.viewDirectionWS,
                                                                          surfaceData.clearCoatMask, specularHighlightsOff);
        }
    LIGHT_LOOP_END
    #endif
    // lightingData.mainLightColor = float3(0,0,0);
    // lightingData.giColor = float3(0,0,0);
    
    #if defined(_ADDITIONAL_LIGHTS_VERTEX)
    lightingData.vertexLightingColor += inputData.vertexLighting * brdfData.diffuse;
    #endif

#if REAL_IS_HALF
    // Clamp any half.inf+ to HALF_MAX
    return min(CalculateFinalColor(lightingData, surfaceData.alpha), HALF_MAX);
#else
    return CalculateFinalColor(lightingData, surfaceData.alpha);
#endif
}

half4 UniversalFragmentFaceSDF(InputData inputData, SurfaceData surfaceData, float2 uv)
{
    #if defined(_SPECULARHIGHLIGHTS_OFF)
    bool specularHighlightsOff = true;
    #else
    bool specularHighlightsOff = false;
    #endif
    BRDFData brdfData;

    // modify albedo
    half4 faceAreaMask = SAMPLE_TEXTURE2D(_CustomMask,sampler_CustomMask, uv);
    half faceFrontArea = faceAreaMask.r;
    faceFrontArea = pow(faceFrontArea, 2.0); // broaden a bit
    faceFrontArea = smoothstep(0.0,1.0,faceFrontArea);
    half3 faceRamp = lerp(float3(1.0,1.0,1.0), _FaceSideColor, faceFrontArea);
    surfaceData.albedo = faceRamp * surfaceData.albedo;

    // NOTE: can modify "surfaceData"...
    InitializeBRDFData(surfaceData, brdfData);

    #if defined(DEBUG_DISPLAY)
    half4 debugColor;

    if (CanDebugOverrideOutputColor(inputData, surfaceData, brdfData, debugColor))
    {
        return debugColor;
    }
    #endif

    // Clear-coat calculation...
    BRDFData brdfDataClearCoat = CreateClearCoatBRDFData(surfaceData, brdfData);
    half4 shadowMask = CalculateShadowMask(inputData);
    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
    half chinArea = faceAreaMask.g;
    chinArea = pow(chinArea, 2.0);
    aoFactor.indirectAmbientOcclusion = lerp(1-chinArea, aoFactor.indirectAmbientOcclusion, 0.4);
    aoFactor.indirectAmbientOcclusion = smoothstep(-2.0,1.0,1 - chinArea);
 
    uint meshRenderingLayers = GetMeshRenderingLayer();
    Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);

    // NOTE: We don't apply AO to the GI here because it's done in the lighting calculation below...
    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI);

    LightingData lightingData = CreateLightingData(inputData, surfaceData);

    
    lightingData.giColor = GlobalIllumination(brdfData, brdfDataClearCoat, surfaceData.clearCoatMask,
                                              inputData.bakedGI, aoFactor.indirectAmbientOcclusion, inputData.positionWS,
                                              inputData.normalWS, inputData.viewDirectionWS, inputData.normalizedScreenSpaceUV);
    // TODO: now just assign a constantColor
    // lightingData.giColor = inputData.bakedGI * float3(0.5,0.5,0.5) * brdfData.diffuse;
    // lightingData.giColor = 0;
#ifdef _LIGHT_LAYERS
    if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
#endif
    {
        lightingData.mainLightColor = LightningFaceSDF(brdfData, mainLight, faceAreaMask,
                                                       inputData.normalWS, inputData.viewDirectionWS,
                                                       inputData.positionWS, uv);
        lightingData.giColor *= _GIIntensity;
    }
    // No additional lights for face sdf
#if REAL_IS_HALF
    // Clamp any half.inf+ to HALF_MAX
    return min(CalculateFinalColor(lightingData, surfaceData.alpha), HALF_MAX);
#else
    return CalculateFinalColor(lightingData, surfaceData.alpha);
#endif
}

half4 UniversalFragmentHair(InputData inputData, SurfaceData surfaceData, float2 uv)
{
    #if defined(_SPECULARHIGHLIGHTS_OFF)
    bool specularHighlightsOff = true;
    #else
    bool specularHighlightsOff = false;
    #endif
    BRDFData brdfData;
    
    // NOTE: can modify "surfaceData"...
    InitializeBRDFData(surfaceData, brdfData);

    #if defined(DEBUG_DISPLAY)
    half4 debugColor;

    if (CanDebugOverrideOutputColor(inputData, surfaceData, brdfData, debugColor))
    {
        return debugColor;
    }
    #endif

    // Clear-coat calculation...
    BRDFData brdfDataClearCoat = CreateClearCoatBRDFData(surfaceData, brdfData);
    half4 shadowMask = CalculateShadowMask(inputData);
    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
    
    uint meshRenderingLayers = GetMeshRenderingLayer();
    Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);

    // NOTE: We don't apply AO to the GI here because it's done in the lighting calculation below...
    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI);

    LightingData lightingData = CreateLightingData(inputData, surfaceData);

    lightingData.giColor = GlobalIllumination(brdfData, brdfDataClearCoat, surfaceData.clearCoatMask,
                                              inputData.bakedGI, aoFactor.indirectAmbientOcclusion, inputData.positionWS,
                                              inputData.normalWS, inputData.viewDirectionWS, inputData.normalizedScreenSpaceUV);
#ifdef _LIGHT_LAYERS
    if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
#endif
    {
        half4 hairMask = SAMPLE_TEXTURE2D(_PMaskMap, sampler_PMaskMap, uv);
        lightingData.mainLightColor = LightningHair(brdfData, mainLight, hairMask,
                                                    inputData.normalWS, inputData.viewDirectionWS,
                                                    uv, inputData.normalizedScreenSpaceUV);
        lightingData.giColor *= _GIIntensity;
    }

    #if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();

    #if USE_FORWARD_PLUS
    for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        FORWARD_PLUS_SUBTRACTIVE_LIGHT_CHECK

        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            lightingData.additionalLightsColor += LightingPhysicallyBased(brdfData, brdfDataClearCoat, light,
                                                                          inputData.normalWS, inputData.viewDirectionWS,
                                                                          surfaceData.clearCoatMask, specularHighlightsOff);
        }
    }
    #endif

    LIGHT_LOOP_BEGIN(pixelLightCount)
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            lightingData.additionalLightsColor += LightingPhysicallyBased(brdfData, brdfDataClearCoat, light,
                                                                          inputData.normalWS, inputData.viewDirectionWS,
                                                                          surfaceData.clearCoatMask, specularHighlightsOff);
        }
    LIGHT_LOOP_END
    #endif

    lightingData.additionalLightsColor = float3(0.0,0.0,0.0);
    // lightingData.giColor = float3(0.0,0.0,0.0);
    
    #if defined(_ADDITIONAL_LIGHTS_VERTEX)
    lightingData.vertexLightingColor += inputData.vertexLighting * brdfData.diffuse;
    #endif

#if REAL_IS_HALF
    // Clamp any half.inf+ to HALF_MAX
    return min(CalculateFinalColor(lightingData, surfaceData.alpha), HALF_MAX);
#else
    return CalculateFinalColor(lightingData, surfaceData.alpha);
#endif
}

// Deprecated: Use the version which takes "SurfaceData" instead of passing all of these arguments...
half4 UniversalFragmentPBR(InputData inputData, half3 albedo, half metallic, half3 specular,
    half smoothness, half occlusion, half3 emission, half alpha)
{
    SurfaceData surfaceData;

    surfaceData.albedo = albedo;
    surfaceData.specular = specular;
    surfaceData.metallic = metallic;
    surfaceData.smoothness = smoothness;
    surfaceData.normalTS = half3(0, 0, 1);
    surfaceData.emission = emission;
    surfaceData.occlusion = occlusion;
    surfaceData.alpha = alpha;
    surfaceData.clearCoatMask = 0;
    surfaceData.clearCoatSmoothness = 1;

    return UniversalFragmentPBR(inputData, surfaceData);
}

////////////////////////////////////////////////////////////////////////////////
/// Phong lighting...
////////////////////////////////////////////////////////////////////////////////
half4 UniversalFragmentBlinnPhong(InputData inputData, SurfaceData surfaceData)
{
    #if defined(DEBUG_DISPLAY)
    half4 debugColor;

    if (CanDebugOverrideOutputColor(inputData, surfaceData, debugColor))
    {
        return debugColor;
    }
    #endif

    uint meshRenderingLayers = GetMeshRenderingLayer();
    half4 shadowMask = CalculateShadowMask(inputData);
    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
    Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);

    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI, aoFactor);

    inputData.bakedGI *= surfaceData.albedo;

    LightingData lightingData = CreateLightingData(inputData, surfaceData);
#ifdef _LIGHT_LAYERS
    if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
#endif
    {
        lightingData.mainLightColor += CalculateBlinnPhong(mainLight, inputData, surfaceData);
    }

    #if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();

    #if USE_FORWARD_PLUS
    for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        FORWARD_PLUS_SUBTRACTIVE_LIGHT_CHECK

        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            lightingData.additionalLightsColor += CalculateBlinnPhong(light, inputData, surfaceData);
        }
    }
    #endif

    LIGHT_LOOP_BEGIN(pixelLightCount)
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            lightingData.additionalLightsColor += CalculateBlinnPhong(light, inputData, surfaceData);
        }
    LIGHT_LOOP_END
    #endif

    #if defined(_ADDITIONAL_LIGHTS_VERTEX)
    lightingData.vertexLightingColor += inputData.vertexLighting * surfaceData.albedo;
    #endif

    return CalculateFinalColor(lightingData, surfaceData.alpha);
}

// Deprecated: Use the version which takes "SurfaceData" instead of passing all of these arguments...
half4 UniversalFragmentBlinnPhong(InputData inputData, half3 diffuse, half4 specularGloss, half smoothness, half3 emission, half alpha, half3 normalTS)
{
    SurfaceData surfaceData;

    surfaceData.albedo = diffuse;
    surfaceData.alpha = alpha;
    surfaceData.emission = emission;
    surfaceData.metallic = 0;
    surfaceData.occlusion = 1;
    surfaceData.smoothness = smoothness;
    surfaceData.specular = specularGloss.rgb;
    surfaceData.clearCoatMask = 0;
    surfaceData.clearCoatSmoothness = 1;
    surfaceData.normalTS = normalTS;

    return UniversalFragmentBlinnPhong(inputData, surfaceData);
}

////////////////////////////////////////////////////////////////////////////////
/// Unlit
////////////////////////////////////////////////////////////////////////////////
half4 UniversalFragmentBakedLit(InputData inputData, SurfaceData surfaceData)
{
    #if defined(DEBUG_DISPLAY)
    half4 debugColor;

    if (CanDebugOverrideOutputColor(inputData, surfaceData, debugColor))
    {
        return debugColor;
    }
    #endif

    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
    LightingData lightingData = CreateLightingData(inputData, surfaceData);

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_AMBIENT_OCCLUSION))
    {
        lightingData.giColor *= aoFactor.indirectAmbientOcclusion;
    }

    return CalculateFinalColor(lightingData, surfaceData.albedo, surfaceData.alpha, inputData.fogCoord);
}

// Deprecated: Use the version which takes "SurfaceData" instead of passing all of these arguments...
half4 UniversalFragmentBakedLit(InputData inputData, half3 color, half alpha, half3 normalTS)
{
    SurfaceData surfaceData;

    surfaceData.albedo = color;
    surfaceData.alpha = alpha;
    surfaceData.emission = half3(0, 0, 0);
    surfaceData.metallic = 0;
    surfaceData.occlusion = 1;
    surfaceData.smoothness = 1;
    surfaceData.specular = half3(0, 0, 0);
    surfaceData.clearCoatMask = 0;
    surfaceData.clearCoatSmoothness = 1;
    surfaceData.normalTS = normalTS;

    return UniversalFragmentBakedLit(inputData, surfaceData);
}

#endif
