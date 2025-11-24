Shader "Endfield/Brow"
{
    Properties
    {
        _BaseMap ("Base Map", 2D) = "white" {}
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
            "RenderType" = "Opaque"
        }
        LOD 300

        Pass
        {
            Tags{ "LightMode"="UniversalForward" "Queue"="Geometry" "RenderType"="Opaque"}

            ZWrite On
            
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
                float fogCoord          : TEXCOORD1;
                float3 positionWS          : TEXCOORD2;
            };

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap); 

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
                half3 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                return half4(baseColor, 1);
            }

            ENDHLSL
        }

        Pass
        {
            Tags { "LightMode"="SRPDefaultUnLit" "Queue"="Transparent" "RenderType"="Transparent" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS: TEXCOORD1;
            };

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap); 

            float _AngleThreshold;
            half3 _HeadForward;
            
            Varyings vert (Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.vertex);
                float3 viewDir = normalize(GetWorldSpaceViewDir(positionWS));
                o.positionWS = positionWS;
                positionWS += viewDir * 0.1;
                o.positionCS = TransformWorldToHClip(positionWS);
                o.uv = v.uv;
                return o;
            }
            
            half4 frag (Varyings i) : SV_Target
            {
                half3 viewDirWS = normalize(GetWorldSpaceViewDir(i.positionWS));
                half4 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                
                half viewFallOff = saturate(dot(viewDirWS, normalize(_HeadForward)));
                viewFallOff = smoothstep(0.0,1.0,viewFallOff);
                half3 emissionColor = baseColor;
                half4 finalColor = lerp(half4(0.0,0.0,0.0,0.0),half4(emissionColor,1.0),viewFallOff);
                return finalColor;
            }
            ENDHLSL
        }
    }
}
