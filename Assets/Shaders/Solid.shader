Shader "Custom/Solid"
{
    Properties
    {
        _BaseTex ("Base Tex", 2D) = "white" {}
        _LineTex ("Line Tex", 2D) = "white" {}
        _GrayScale("Gray Scale", Range(0,1)) = 0.5
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 300

        Pass
        {
            Tags{ "LightMode"="SRPDefaultUnLit" }
            ZWrite On
            ZTest LEqual
            Blend SrcAlpha OneMinusSrcAlpha
         
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS       : POSITION;
                float2 uv               : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS       : SV_POSITION;
                float2 uv               : TEXCOORD0;
                float3 positionWS          : TEXCOORD2;
            };

            TEXTURE2D(_BaseTex); SAMPLER(sampler_BaseTex); float4 _BaseTex_ST;
            TEXTURE2D(_LineTex); SAMPLER(sampler_LineTex);
            half _GrayScale;

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseTex);
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionWS = positionWS;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half3 baseColor = SAMPLE_TEXTURE2D(_BaseTex, sampler_BaseTex, i.uv);

                half worldPosYFade = saturate(i.positionWS.y * 0.1);
                half tone = baseColor * _GrayScale;

                half2 screenUV = 25*GetNormalizedScreenSpaceUV(i.positionCS);
                half lineSample = SAMPLE_TEXTURE2D(_LineTex, sampler_LineTex, screenUV).r;
                half3 finalColor = half3(tone,tone,tone) * lineSample;
                half alpha = smoothstep(0.1,0.18,worldPosYFade);
                
                return half4(finalColor, lineSample*alpha);
            }
            ENDHLSL
        }

        Pass
        {
            Name "SilhouluetteMask"
            Tags{ "LightMode"="SilhouluetteMask" }
         
            ZTest Off
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS       : POSITION;
                float2 uv               : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS       : SV_POSITION;
                float2 uv               : TEXCOORD0;
                float3 positionWS          : TEXCOORD2;
            };

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = v.uv;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionWS = positionWS;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half worldPosYFade = saturate(i.positionWS.y * 0.1);
                half alpha = smoothstep(0.1,0.12,worldPosYFade);
                return alpha;
            }
            ENDHLSL
        }
    }
}
