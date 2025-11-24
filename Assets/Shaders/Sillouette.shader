Shader "Custom/Sillouette"
{
    Properties
    {
        _BaseTex ("Base Tex", 2D) = "white" {}
        [HDR]_Top("Top", Color) = (1,1,1,0)
		[HDR]_Bottom("Bottom", Color) = (0,0,0,0)
		_mult("mult", Float) = 1
		_pwer("pwer", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent+50" }
        LOD 300

        Pass
        {
            Tags{ "LightMode"="SRPDefaultUnLit" }
            ZWrite Off
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
            TEXTURE2D(_SilhouluetteMask); SAMPLER(sampler_SilhouluetteMask);
            float4 _Bottom,_Top;
            float _mult,_pwer;

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv.xy = TRANSFORM_TEX(v.uv, _BaseTex);
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionWS = positionWS;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half mask = SAMPLE_TEXTURE2D(_BaseTex, sampler_BaseTex, i.uv).r;
                half2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);
                half alpha = SAMPLE_TEXTURE2D(_SilhouluetteMask, sampler_SilhouluetteMask, screenUV).r;

                half3 color = lerp(_Bottom,_Top, pow(saturate(i.positionWS.y * _mult),_pwer));
                return half4(color, (1-mask) * alpha);
            }

            ENDHLSL
        }
    }
}
