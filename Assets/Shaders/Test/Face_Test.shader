Shader "Unlit/Face"
{
    Properties
    {
        _BaseMap ("Base Tex", 2D) = "white" {}
        _BaseColor("Base Color", Color) = (1,1,1,1)
        _SDFMap("SDF", 2D) = "white" {}
        _CustomMask("Custom Mask", 2D) = "white" {}
        _LipHighlightMask("Lip HL Mask", 2D) = "white" {}
        _DiffuseRampMap("Diffuse Ramp Map", 2D) = "white" {}
        _ShadowColor("Shadow Color", Color) = (0,0,0,1)
        _LipHLColor("Lip HL Color", Color) = (1,1,1,1)
        _SSSTint("SSS Tint", Color) = (1,1,1,1)
        
        [HideInInspector] _FlipSDFThreshold("Flip SDF Threshold", Float) = 0.0
        [HideInInspector] _AngleThreshold("Angle Threshold", Float) = 0.0
        [HideInInspector] _HeadRight("Head Right Vector", Vector) = (0.0,0.0,0.0)
        [HideInInspector] _HeadForward("Head Forward Vector", Vector) = (0.0,0.0,0.0)
        
        _StepSharpness("Step Sharpness", Range(0.1,10)) = 5.0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 300

        Pass
        {
            Name "ForwardLit"
            Tags{ "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS       : POSITION;
                float3 normalOS         : NORMAL;
                float2 uv               : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS       : SV_POSITION;
                float2 uv               : TEXCOORD0;
                float fogCoord          : TEXCOORD1;
                float3 normalWS          : TEXCOORD2;
                float3 positionWS          : TEXCOORD3;
            };

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap); float4 _BaseMap_ST;
            TEXTURE2D(_SDFMap); SAMPLER(sampler_SDFMap);
            TEXTURE2D(_CustomMask); SAMPLER(sampler_CustomMask);
            TEXTURE2D(_LipHighlightMask); SAMPLER(sampler_LipHighlightMask);
            TEXTURE2D(_DiffuseRampMap); SAMPLER(sampler_DiffuseRampMap);

            half3 _BaseColor;
            half3 _ShadowColor;
            half3 _SSSTint;
            half _FlipSDFThreshold;
            half _AngleThreshold;
            half _StepSharpness;
            half3 _LipHLColor;
            half3 _HeadRight;
            half3 _HeadForward;

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;

                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.fogCoord = ComputeFogFactor(o.positionCS.z);
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.positionWS = positionWS;
                o.normalWS = normalWS;
                return o;
            }
            
            half sigmoidSharp(half x, half center, half sharpness)
            {
                return rcp(pow(100000,(x - center)*(-3*sharpness))+1.0f);
            }
            
            half4 frag(Varyings i) : SV_Target
            {
                half3 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                baseColor *= _BaseColor;
                
                /// SHADOW ///
                half2 sdfUV = i.uv;
                if(_FlipSDFThreshold < 0.0)
                    sdfUV.x = 1 - sdfUV.x;
                half3 sdf = SAMPLE_TEXTURE2D(_SDFMap, sampler_SDFMap, sdfUV);
                half sdfShadow = (sdf.r + sdf.g)/2.0;
                sdfShadow = sigmoidSharp(sdfShadow-_AngleThreshold, 0.1, _StepSharpness);

                // get scene shadow
                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half3 lightDir = mainLight.direction;
                half sceneShadow = mainLight.shadowAttenuation;
                sdfShadow = min(sdfShadow, sceneShadow);
                // make it more smooth...
                sceneShadow = sigmoidSharp(sceneShadow, 0.0, 0.2);

                half4 customMask = SAMPLE_TEXTURE2D(_CustomMask, sampler_CustomMask, i.uv);
                half chinArea = customMask.g;

                half faceLambertShadow = dot(lightDir, i.normalWS) * 0.5 + 0.5;
                faceLambertShadow = sigmoidSharp(faceLambertShadow, 0.5, 0.1);// make it smooth
                half chinShadow = lerp(1.0, faceLambertShadow, chinArea);

                // Compose final shadow
                half shadow = min(sceneShadow, sdfShadow);
                shadow = min(shadow, chinShadow);

                /// HIGHLIGHT ///
                half3 viewDir = normalize(GetWorldSpaceViewDir(i.positionWS));
                
                half lipHLOffset = dot(viewDir, _HeadRight).x * 0.03;
                half2 lipHLUV = i.uv + half2(lipHLOffset,0);
                half lipHL = SAMPLE_TEXTURE2D(_LipHighlightMask, sampler_LipHighlightMask, lipHLUV).r;
                lipHL = lipHL * max(0.4, shadow);  // fall off but keep a minimum intensity in shadow
                
                /// RIM ///
                half rim =  lerp(0, customMask.a, 1-sdfUV.x>0.5);
                rim -= _AngleThreshold; // back light cutoff
                // uv flipped when _AngleThreshold from 1->0->1, so make it not that abrupt
                rim *= smoothstep(0, 0.2, _AngleThreshold);
                half viewDirFalloff = smoothstep(0.8, 1.0, dot(viewDir, _HeadForward));
                rim = saturate(rim*viewDirFalloff); 

                half sssMask = customMask.r; // also trick here :)
                sssMask = smoothstep(0, 1.0, pow(sssMask, 2));
                half3 sssColor = lerp(float3(1.0,1.0,1.0), _SSSTint, sssMask);
                sssColor = lerp(float3(1.0,1.0,1.0), sssColor, viewDirFalloff) * baseColor;
                baseColor = lerp(baseColor, sssColor, shadow);
                /// AMBIENT ///
                half3 ambient = half3(0.5,0.5,0.5) * baseColor;

                half2 diffuseRampUV = half2(shadow, 0.5);
                half4 diffuseRampColor = SAMPLE_TEXTURE2D(_DiffuseRampMap, sampler_DiffuseRampMap, diffuseRampUV);
                half3 finalColor = baseColor*lerp(_ShadowColor, mainLight.color, shadow) + ambient;
                finalColor = finalColor + lipHL.rrr*8 + rim;
                
                return half4(finalColor, 1);
            }

            ENDHLSL
        }
    }
}
