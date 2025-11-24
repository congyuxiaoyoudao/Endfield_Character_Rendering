Shader"Custom/Ring"
{
    Properties
    {
        _BaseTex ("Base Tex", 2D) = "white" {}
        
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
                float2 uv               : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS       : SV_POSITION;
                float2 uv               : TEXCOORD0;
                float fogCoord          : TEXCOORD1;
                float3 positionWS          : TEXCOORD2;
            };

            TEXTURE2D(_BaseTex); SAMPLER(sampler_BaseTex);

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
                // sample mask
                half baseColor = SAMPLE_TEXTURE2D(_BaseTex, sampler_BaseTex, i.uv).r;

                // main light
                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half3 finalColor = baseColor * mainLight.shadowAttenuation * mainLight.distanceAttenuation;
                clip(0.1-baseColor);
                return half4(finalColor, 1);
            }

            ENDHLSL
        }
    }
}
