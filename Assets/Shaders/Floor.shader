Shader "Custom/FloorURP"
{
    Properties
    {
        _MagicTex ("Magic Tex", 2D) = "white" {}
        _Color1("Color1", Color) = (1,1,1,1)
        _Color2("Color2", Color) = (1,1,1,1)
        _Min("Remap Min", Float) = 0.5
        _Max("Remap Max", Float) = 2.7
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

            TEXTURE2D(_MagicTex); SAMPLER(sampler_MagicTex); float4 _MagicTex_ST;
            half4 _Color1;
            half4 _Color2;
            half _Min;
            half _Max;

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;

                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _MagicTex);
                o.fogCoord = ComputeFogFactor(o.positionCS.z);
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionWS = positionWS;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // sample mask
                half mask = SAMPLE_TEXTURE2D(_MagicTex, sampler_MagicTex, i.uv).r;
                half3 baseColor = lerp(_Color1, _Color2, mask);

                // do a little trick here
                half r = distance(i.positionWS.xz,half2(0.0,0.0)) / 30;
                half r_remapped = _Min + r * (_Max - _Min);

                // main light
                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half3 finalColor = baseColor * mainLight.shadowAttenuation * mainLight.distanceAttenuation;

                finalColor = saturate(finalColor * r_remapped);
                return half4(finalColor, 1);
            }

            ENDHLSL
        }
    }
}
