Shader "Custom/Skybox"
{
    Properties
    {
		[HDR]_Top("Top", Color) = (1,1,1,0)
		[HDR]_Bottom("Bottom", Color) = (0,0,0,0)
		_mult("mult", Float) = 1
		_pwer("pwer", Float) = 1
		[Toggle(_SCREENSPACE_ON)] _Screenspace("Screen space", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Queue" "RenderPipeline"="UniversalPipeline" }
        LOD 100
        HLSLINCLUDE

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        struct appdata
        {
            float4 positionOS : POSITION;
            float4 color : COLOR;
        };

        struct v2f
        {
            float4 positionCS : SV_POSITION;
			float4 positionOS : TEXCOORD0;
			float4 screenPos : TEXCOORD1;
        };

        CBUFFER_START(UnityPerMaterial)
            float4 _Bottom,_Top;
            float _mult,_pwer;
        CBUFFER_END

        ENDHLSL

        Pass
        {

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma shader_feature_local _SCREENSPACE_ON

            v2f vert (appdata v)
            {
                v2f o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
				o.screenPos = ComputeScreenPos(o.positionCS);     
				o.positionOS = v.positionOS; 
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                float4 screenPos = i.screenPos;
                float2 screenPosNorm = screenPos.xy / screenPos.w;

                #ifdef _SCREENSPACE_ON
                    float staticSwitch = screenPosNorm.y;
                #else
                    float staticSwitch = i.positionOS.y;
                #endif

                half4 col = lerp(_Bottom,_Top, pow(saturate(staticSwitch * _mult),_pwer));

                return col;
            }
            ENDHLSL
        }
    }
}