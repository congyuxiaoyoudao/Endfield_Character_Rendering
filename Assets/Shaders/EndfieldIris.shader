Shader "Endfield/Iris"
{
    Properties
    {
        // textures maps
        _IrisMap ("Iris", 2D) = "white" {}
        _MatCap ("MatCap", 2D) = "white" {}
        _EmissionIntensity("Emission Intensity", Float) = 1.0
        
        [Header(Base Render)]
        [KeywordEnum(None, Parallax, Physical)] _Refraction("Refraction Mode", Float) = 0
        [Toggle(_USEMATCAP)]_UseMatCap("Use MatCap?", Float) = 0
        
        [Header(Parallax Settings)]
        _ParallaxScale("ParallaxScale",Range(-1,1)) = 0.01
        [Header(Physical Refraction Settings)]
        _IOR("IOR",Range(1,3)) = 1.5
        _OffsetScale("OffsetScale",Range(-1,1))=1
        [HideInInspector] _AngleThreshold("Angle Threshold", Float)=0.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        ZWrite On
        Cull Off
        
        Pass
        {
            Tags { "RenderType"="Opaque" "LightMode"="UniversalForward" }
            
            HLSLPROGRAM
            #pragma shader_feature _USEMATCAP
            #pragma shader_feature _REFRACTION_NONE _REFRACTION_PARALLAX _REFRACTION_PHYSICAL
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
                float4 vertColor : COLOR;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float3 normalWS:TEXCOORD1;
                float4 vertexColor:TEXCOORD2;
                float4 positionCS : SV_POSITION;
                float3 positionWS: TEXCOORD3;
                float3 tangentDir : TEXCOORD4;
                float3 bitangentDir : TEXCOORD5;
            };

            // params
            TEXTURE2D(_IrisMap); SAMPLER(sampler_IrisMap); float4 _IrisMap_ST;
            TEXTURE2D(_MatCap); SAMPLER(sampler_MatCap);

            float _ParallaxScale;
            float _IOR;
            float _OffsetScale;
            float _AngleThreshold;
            float _EmissionIntensity;
            half3 _HeadForward;
            
            Varyings vert (Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.vertex);
                o.positionWS = positionWS;
                o.positionCS = TransformWorldToHClip(positionWS);
                
                o.uv = TRANSFORM_TEX(v.uv, _IrisMap);
                o.vertexColor = v.vertColor;
                o.normalWS = TransformObjectToWorldNormal(v.normal);
                o.tangentDir = normalize(mul(unity_ObjectToWorld,float4(v.tangent.xyz,0.0)).xyz);
                o.bitangentDir = normalize(cross(o.normalWS,o.tangentDir)*v.tangent.w);
                return o;
            }
            
            half4 frag (Varyings i) : SV_Target
            {
                // prepare vectors
                Light mainLight = GetMainLight();
                float3 mainLightDir = normalize(mainLight.direction);
                float3 viewDir = normalize(GetWorldSpaceViewDir(i.positionWS));
                float3 halfDir = normalize(mainLightDir + viewDir);
                float3 normalWS = normalize(i.normalWS);

                
                float2 irisUV = i.uv;
                float3x3 TBN = float3x3(i.tangentDir,i.bitangentDir,i.normalWS); // Tangent transform matrix

#ifdef _REFRACTION_PARALLAX
                float3 viewDirTS = mul(TBN, viewDir);
                float2 offset = viewDirTS.xy/viewDirTS.z; // do the z division for projection
                //offset.y = -offset.y; // in unity, the y axis is inverted
                irisUV -= _ParallaxScale * offset;
#elif defined(_REFRACTION_PHYSICAL)
                // model of eye cornea and aqueous humor
                float height = saturate( 1.0 - 18.4 * 0.1 * 0.1 );
                
                // compute refraction vector
                float n = 1.0 / _IOR;
                float w = n * dot( normalWS, viewDir ); // eta * cos theta_i
                float k = sqrt( 1.0 + ( w - n ) * ( w + n ) ); // sqrt(1-eta^2(1-cos theta^2_i)) 
                float3 refractedDirWS = n * viewDir - ( w - k ) * normalWS;

                float cosAlpha = dot(float3(0.0,0.0,1.0), refractedDirWS);// use (0,0,1) as temp forward vector
                float dist = height / cosAlpha;
                float3 offsetWS = dist * refractedDirWS;
                float2 offsetTS = mul(TBN,offsetWS);
                irisUV -= _OffsetScale * offsetTS; // in unity y axis is inverted
#endif
                
                // sample the texture
                half4 baseColor = SAMPLE_TEXTURE2D(_IrisMap, sampler_IrisMap, irisUV);
                half3 diffuse = baseColor * (2-_AngleThreshold);
                half3 finalColor = diffuse * _EmissionIntensity;
#ifdef _USEMATCAP
                half3 cameraRight = normalize(cross(half3(0.0,1.0,0.0), viewDir));
                half3 cameraUp = normalize(cross(viewDir, cameraRight));
                half u = 0.5 + dot(normalWS, cameraRight) * 0.5;
                half v = 0.5 + dot(normalWS, cameraUp) * 0.5;
                half2 matCapUV = half2(u,v);
                half3 matcapColor = SAMPLE_TEXTURE2D(_MatCap, sampler_MatCap, matCapUV).rgb;
                finalColor += matcapColor * baseColor;
#endif
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Tags {"Queue"="Transparent" "LightMode" = "SRPDefaultUnLit"}
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            
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

            // params
            TEXTURE2D(_IrisMap); SAMPLER(sampler_IrisMap); float4 _IrisMap_ST;

            float _AngleThreshold;
            float _EmissionIntensity;
            half3 _HeadForward;
            
            Varyings vert (Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.vertex);
                float3 viewDir = normalize(GetWorldSpaceViewDir(positionWS));
                o.positionWS = positionWS;
                positionWS += viewDir * 0.1;
                o.positionCS = TransformWorldToHClip(positionWS);
                o.uv = TRANSFORM_TEX(v.uv, _IrisMap);
                return o;
            }
            
            half4 frag (Varyings i) : SV_Target
            {
                // prepare vectors
                float2 irisUV = i.uv;
                half3 viewDirWS = normalize(GetWorldSpaceViewDir(i.positionWS));
                // sample the texture
                half4 baseColor = SAMPLE_TEXTURE2D(_IrisMap, sampler_IrisMap, irisUV);
                half3 diffuse = baseColor * (2-_AngleThreshold);
                
                half viewFallOff = saturate(dot(viewDirWS, normalize(_HeadForward)));
                viewFallOff = smoothstep(0.0,1.0,viewFallOff);
                half3 emissionColor = diffuse * _EmissionIntensity;
                half4 finalColor = lerp(half4(0.0,0.0,0.0,0.0),half4(emissionColor,1.0),viewFallOff);
                return finalColor;
            }
            ENDHLSL
        }
    }
}
