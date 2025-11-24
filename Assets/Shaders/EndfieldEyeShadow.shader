Shader "Endfield/EyeShadow"
{
    Properties
    {
        // textures maps
        _EyeShadowMask ("Eye Shadow Mask", 2D) = "white" {}
        _EyeShadowColor("Eye Shadow Color", Color) = (1.0,1.0,1.0)
    }
    SubShader
    {
        Tags { "Queue"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        Cull Off
        
        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 vertex : POSITION;
                float4 normal: NORMAL;
                float4 tangent : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float4 positionCS : SV_POSITION;
            };

            TEXTURE2D(_EyeShadowMask); SAMPLER(sampler_EyeShadowMask);
            half3 _EyeShadowColor;
            
            Varyings vert (Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.vertex);
                o.uv = v.uv;
                return o;
            }
            
            half4 frag (Varyings i) : SV_Target
            {
                half eyeShadowMask = SAMPLE_TEXTURE2D(_EyeShadowMask, sampler_EyeShadowMask, i.uv).r;
                return float4(_EyeShadowColor, eyeShadowMask);
            }
            ENDHLSL
        }
    }
}
