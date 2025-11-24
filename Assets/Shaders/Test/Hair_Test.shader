Shader "Unlit/Hair"
{
    Properties
    {
        _BaseMap ("Base Tex", 2D) = "white" {}
        _BaseColor("Base Color", Color) = (1,1,1,1)
        _NormalMap("Normal Map", 2D) = "bump" {}
        _HLNormalMap("HL Normal Map", 2D) = "bump" {}
        _PBRMask("PBR Mask", 2D) = "white" {}
        _DiffuseRamp("Diffuse Ramp", 2D) = "white" {}
        _MaskMap("Mask Ramp", 2D) = "white" {}
        
        _ShadowColor("Shadow Color", Color) = (0,0,0,1)
        _AnisoHLIntensity("Aniso HL Intensity", Float) = 1.0
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
                float4 tangentOS        : TANGENT;
                float2 uv               : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS       : SV_POSITION;
                float2 uv               : TEXCOORD0;
                float fogCoord          : TEXCOORD1;
                float3 normalWS         : TEXCOORD2;
                float3 positionWS       : TEXCOORD3;
                float4 tangentWS        : TEXCOORD4;
            };

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap); float4 _BaseMap_ST;
            TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);
            TEXTURE2D(_HLNormalMap); SAMPLER(sampler_HLNormalMap);
            TEXTURE2D(_PBRMask); SAMPLER(sampler_PBRMask);
            TEXTURE2D(_DiffuseRamp); SAMPLER(sampler_DiffuseRamp);
            TEXTURE2D(_MaskMap); SAMPLER(sampler_MaskMap);

            half3 _BaseColor;
            half3 _ShadowColor;
            half _AnisoHLIntensity;

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;

                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.fogCoord = ComputeFogFactor(o.positionCS.z);
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS, v.tangentOS);

                o.normalWS = normalInput.normalWS;
                o.tangentWS.xyz = normalize(normalInput.tangentWS);
                o.tangentWS.w = v.tangentOS.w * GetOddNegativeScale();
                return o;
            }
            
            half sigmoidSharp(half x, half center, half sharpness)
            {
                return rcp(pow(100000,(x - center)*(-3*sharpness))+1.0f);
            }

            half3 DecodeNormalFromXY(half2 enc, half scale = half(1.0))
            {
                half3 normal;
                normal.xy = enc * 2.0f - 1.0f;
                normal.z = max(1.0e-16, sqrt(1.0 - saturate(dot(normal.xy, normal.xy))));
                normal.z = normal.z * 0.5 + 0.5;
                normal.xy *= scale;
                return normal;
            }
            
            half3 SampleMixedNormal(float2 uv, TEXTURE2D_PARAM(bumpMap, sampler_bumpMap), half scale = half(1.0))
            {
                half4 n = SAMPLE_TEXTURE2D(bumpMap, sampler_bumpMap, uv);
                return DecodeNormalFromXY(n.rg, scale);
            }

            half3 GetEquirectTangent(float3 N)
            {
                half3 axis = half3(0.0,1.0,0.0);
                half3 B = normalize(cross(N, axis));
                half3 T_equi = normalize(cross(N, B));
                return T_equi;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half4 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                baseColor.rgb *= _BaseColor;
                half alpha = baseColor.a;
                alpha = smoothstep(-0.1,0.55,alpha);
                half mask = SAMPLE_TEXTURE2D(_MaskMap,sampler_MaskMap,i.uv).r;// ST used for outline culling
                
                float3 bitangent = normalize(cross(i.normalWS.xyz, i.tangentWS.xyz));
                half3x3 tbn = half3x3(i.tangentWS.xyz, bitangent.xyz, i.normalWS.xyz);
                half3 normalTS = SampleMixedNormal(i.uv, TEXTURE2D_ARGS(_NormalMap,sampler_NormalMap), 1.0);
                half3 normalWS = normalize(mul(tbn, normalTS));
                
                // get scene shadow
                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half3 lightDirWS = mainLight.direction;

                half3 viewDirWS = normalize(GetWorldSpaceViewDir(i.positionWS));
                half3 H = normalize(lightDirWS + viewDirWS);

                half NoL = saturate(dot(normalWS, lightDirWS));
                half NoV = saturate(dot(normalWS, viewDirWS));
                
                half4 pbr = SAMPLE_TEXTURE2D(_PBRMask, sampler_PBRMask, i.uv);
                half hairAreaMask = pbr.r;
                half ao = pbr.b;
                half highLightOcclusion = pbr.g * pbr.a;
                
                /// HIGHTLIGHT
                half4 highlightNormal = SAMPLE_TEXTURE2D(_HLNormalMap, sampler_HLNormalMap, i.uv);
                half3 highlightNormal1 = DecodeNormalFromXY(highlightNormal.rg, 1.0);
                half3 highlightNormal1WS = normalize(mul(tbn, highlightNormal1));
                half3 highlightNormal2 = DecodeNormalFromXY(highlightNormal.ba, 1.0);
                half3 highlightNormal2WS = normalize(mul(tbn, highlightNormal2));

                // compute hl occlusion
                half remappedNoV = pow(NoV, 5);
                half viewDirFallOff = sigmoidSharp(remappedNoV, 0.5, 0.5);
                highLightOcclusion *= viewDirFallOff;
                
                half3 T = GetEquirectTangent(i.normalWS); // refer to blender tangent node
                half ToH = dot(T, H);
                half sinTH = sqrt(1 - ToH * ToH);
                // half ToV = pow(saturate(dot(T, viewDirWS)),1);

                half anisoHL = saturate(sinTH - 0.1);
                anisoHL = smoothstep(0.89, 0.95, anisoHL);
                // anisoHL = pow(anisoHL, 8);
                anisoHL *= highLightOcclusion;

                /// SHADOW
                half sceneShadow = mainLight.shadowAttenuation;
                sceneShadow = sigmoidSharp(sceneShadow, 0.0, 0.2);
                // NoL = dot(highlightNormal1WS, lightDirWS);
                // return  NoL;
                half lambertShadow = NoL * 0.5 +0.5;
                lambertShadow = sigmoidSharp(lambertShadow, 0.5, 0.2);// make it smooth
                half shadow = min(lambertShadow, sceneShadow);

                half2 diffuseRampUV = half2(shadow, 0.5);
                half4 diffuseRampColor = SAMPLE_TEXTURE2D(_DiffuseRamp,sampler_DiffuseRamp,diffuseRampUV);
                // return diffuseRampColor.a;
                half shadowIntensity = smoothstep(-2.0, 1.0, diffuseRampColor.a);

                half3 directDiffuse = diffuseRampColor * baseColor * mainLight.color * 0.318;
                half3 ambient = half3(0.4,0.4,0.4) * baseColor;

                half3 finalColor = (directDiffuse + ambient + anisoHL*3)*shadowIntensity;
                return half4(finalColor, alpha);
            }

            ENDHLSL
        }
    }
}
