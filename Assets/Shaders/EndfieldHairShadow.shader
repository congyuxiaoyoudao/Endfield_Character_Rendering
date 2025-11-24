Shader "Endfield/HairShadow"
{
    Properties
    {
        _DepthDiffThreshold("Depth Diff Threshold", Range(0,1)) = 1.0
        _ShadowOffset("Shadow Offset", Vector) = (1.0,1.0,1.0)
        
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline"}
        LOD 300

        Pass
        {
            Name "HairShadow"
            Tags{ "LightMode"="SRPDefaultUnlit" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZTest LEqual
            Cull Back
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            struct Attributes
            {
                float3 positionOS       : POSITION;
                float2 uv               : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS       : SV_POSITION;
                float2 uv               : TEXCOORD0;
                float3 positionWS          : TEXCOORD2;
            };

            half _DepthDiffThreshold;
            half3 _ShadowOffset;
            
            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;
                Light mainLight = GetMainLight();
                o.uv = v.uv;
                v.positionOS -= _ShadowOffset;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                positionWS.xyz -= mainLight.direction.xyz * 0.001;
                float3 positionVS = TransformWorldToView(positionWS);
                o.positionCS = TransformWViewToHClip(positionVS);
                o.positionWS = positionWS;
                // o.positionCS = TransformWorldToHClip(positionWS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);
                half curDepth = i.positionCS.z / i.positionCS.w;
                half sceneDepth = SampleSceneDepth(screenUV);
                half linearDepth = LinearEyeDepth(sceneDepth, _ZBufferParams);
                half depthDiff = linearDepth - LinearEyeDepth(curDepth, _ZBufferParams);
                depthDiff = saturate(depthDiff/1000);

                half3 sceneColor = SampleSceneColor(screenUV).rgb;
                clip(0.96-i.uv.y);
                half alpha = depthDiff<_DepthDiffThreshold ? 1.0 : 0.0;
                float3 color = float3(0.5,0.5,0.5) * sceneColor;
                return half4(color, 1.0);
            }

            ENDHLSL
        }
    }
}
