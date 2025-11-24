#ifndef ENDFIELD_OUTLINE_PASS_INCLUDED
#define ENDFIELD_OUTLINE_PASS_INCLUDED

struct Attributes
{
    float4 positionOS : POSITION;
    float2 uv : TEXCOORD0;
    float4 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float3 smoothedNormal : TEXCOORD7;
    float4 color : COLOR;
};

struct Varyings
{
    float2 uv : TEXCOORD0;
    float3 positionWS : TEXCOORD2;
    float4 positionCS : SV_POSITION;
};

Varyings OutlinePassVertex(Attributes input)
{
    Varyings output = (Varyings)0;
    VertexPositionInputs vertexPositionInput = GetVertexPositionInputs(input.positionOS);
    VertexNormalInputs VertexNormalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    float3 positionWS = vertexPositionInput.positionWS;
    
    #ifdef _OUTLINE_ON
        // CameraFade
        float3 front = (float3(0.0, 1.0, 0.00));
        half3 V = GetWorldSpaceNormalizeViewDir(positionWS);
        V = TransformWorldToObject(V);
        // half view_fade = saturate(dot(V, front));
        //
        // half cameradistance = distance(GetCameraPositionWS(), positionWS);
        //
        // half camerafade = 1 - smoothstep(0, 1, 1 - (cameradistance - 0) / max(_OutlineWidthFadeDistance, 0.001));
        //
        // half cameraScale = lerp(1, 3, camerafade);
        //
        //
        //
        // half outline_scale = lerp(1, input.color.x, view_fade) * 1 ;
        // // half outline_scale =input.color.a * cameraScale ;
        float3 smoothedNormalTS = input.smoothedNormal * 2.0f - 1.0f;

        float3 tangentWS   = VertexNormalInputs.tangentWS;
        float3 bitangentWS = VertexNormalInputs.bitangentWS * input.tangentOS.w;
        float3 normalWS    = VertexNormalInputs.normalWS;
        float3x3 tbn = float3x3(tangentWS, bitangentWS, normalWS);
    
        float3 smoothedNormalWS = normalize(mul(smoothedNormalTS, tbn));
        float outlineCullMask = _ST.SampleLevel(sampler_ST, input.uv, 0);
        positionWS += smoothedNormalWS * _OutlineWidth * 0.08 * outlineCullMask;
        output.positionCS = TransformWorldToHClip(positionWS);
        output.positionCS.z += _OutlineClipSpaceZOffset * -0.0001;
    #else
        output.positionCS = TransformWorldToHClip(positionWS);
    #endif

    return output;
}

half4 OutlinePassFragment(Varyings input) : SV_Target
{
    half customMask = SAMPLE_TEXTURE2D(_CustomMask, sampler_CustomMask, input.uv).r;
    half4 finalColor = float4(_OutlineColor, 1.0);
    return finalColor;
}


#endif
