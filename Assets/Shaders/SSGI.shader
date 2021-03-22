Shader "Hidden/Shader/SSGI"
{
    HLSLINCLUDE

    #pragma target 4.5
    #pragma only_renderers d3d11 ps4 xboxone vulkan metal switch

    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/PostProcessing/Shaders/FXAA.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/PostProcessing/Shaders/RTUpscale.hlsl"	
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/NormalBuffer.hlsl"

    struct Attributes
    {
        uint vertexID : SV_VertexID;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float2 texcoord   : TEXCOORD0;
        UNITY_VERTEX_OUTPUT_STEREO
    };

    Varyings Vert(Attributes input)
    {
        Varyings output;
        UNITY_SETUP_INSTANCE_ID(input);
        UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
        output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
        output.texcoord = GetFullScreenTriangleTexCoord(input.vertexID);
        return output;
    }

    // List of properties to control your post process effect
    float _Intensity;
    TEXTURE2D_X(_InputTexture);
    float4 _InputTexture_TexelSize;
    float4x4 _InverseProjectionMatrix;
    float _IndirectAmount;
    int _SamplesCount;
    int _Noise;
    int _Debug;
    float _NoiseAmount;

    float2 ModDither3(float2 u)
    {
        float noiseX = fmod(u.x + u.y + fmod(208. + u.x * 3.58, 13. + fmod(u.y * 22.9, 9.)), 7.) * .143;
        float noiseY = fmod(u.y + u.x + fmod(203. + u.y * 3.18, 12. + fmod(u.x * 27.4, 8.)), 6.) * .139;
        return float2(noiseX, noiseY) * 2.0 - 1.0;
    }

    float2 Dither(float2 coord, float seed, float2 size)
    {
        float noiseX = ((frac(1.0 - (coord.x + seed * 1.0) * (size.x / 2.0)) * 0.25) + (frac((coord.y + seed * 2.0) * (size.y / 2.0)) * 0.75)) * 2.0 - 1.0;
        float noiseY = ((frac(1.0 - (coord.x + seed * 3.0) * (size.x / 2.0)) * 0.75) + (frac((coord.y + seed * 4.0) * (size.y / 2.0)) * 0.25)) * 2.0 - 1.0;
        return float2(noiseX, noiseY) * _ScreenSize;
    }

    float lenSq(float3 v)
    {
        return pow(v.x, 2.0) + pow(v.y, 2.0) + pow(v.z, 2.0);
    }

    // ipm = InverseProjectionMatrix
    float3 GetViewPos(float2 coord, float4x4 ipm)
    {
        float depth = SampleCameraDepth(coord);

        float x = coord.x * 2 - 1;
        float y = (1 - coord.y) * 2 - 1;
        float4 projPos = float4(x, y, depth, 1.0f);
        float4 posVS = mul(projPos, ipm);
        return posVS.xyz / posVS.w;

        //float3 pixelPosNDC = float3((coord) * 2.0 - 1.0, depth * 2.0 - 1.0);
        //float4 pixelPosClip = mul(ipm, float4(pixelPosNDC, 1.0));
        //float3 pixelPosCam = pixelPosClip.xyz / pixelPosClip.w;
        //return pixelPosCam;
    }

    float3 GetViewNormal(float2 coord, float4x4 ipm)
    {
        NormalData normalData;
        DecodeFromNormalBuffer(coord * _ScreenSize, normalData);
        return normalData.normalWS.xyz;

        //float pW = _InputTexture_TexelSize.x;
        //float pH = _InputTexture_TexelSize.y;

        //float3 p1 = GetViewPos(coord + float2(pW, 0), ipm).xyz;
        //float3 p2 = GetViewPos(coord + float2(0, pH), ipm).xyz;
        //float3 p3 = GetViewPos(coord + float2(-pW, 0), ipm).xyz;
        //float3 p4 = GetViewPos(coord + float2(0, -pH), ipm).xyz;

        //float3 vP = GetViewPos(coord, ipm);

        //float3 dx = vP - p1;
        //float3 dy = p2 - vP;
        //float3 dx2 = p3 - vP;
        //float3 dy2 = vP - p4;

        //if (length(dx2) < length(dx) && coord.x - pW >= 0 || coord.x + pW > 1.0) 
        //{
        //    dx = dx2;
        //}


        //if (length(dy2) < length(dy) && coord.y - pH >= 0 || coord.y + pH > 1.0)
        //{
        //    dy = dy2;
        //}

        //return normalize(-cross(dx, dy).xyz);
    }

    float3 LightSample(float2 coord, float4x4 ipm, float2 lightCoord, float3 normal, float3 position, float n, float2 texSize)
    {
        float2 random = float2(1.0, 1.0);

        if (_Noise > 0)
        {
            random = (ModDither3((coord * texSize) + float2(n * 82.294, n * 127.721))) * 0.01 * _NoiseAmount;
        }
        else
        {
            random = Dither(coord, _Time.x, texSize) * 0.1 * _NoiseAmount;
        }

        lightCoord *= float2(0.7, 0.7);

        float3 lightColor = SampleCameraColor((lightCoord) + random).rgb;
        float3 lightNormal = GetViewNormal(frac(lightCoord) + random, ipm).rgb;
        float3 lightPosition = GetViewPos(frac(lightCoord) + random, ipm).xyz;

        float3 lightPath = lightPosition - position;
        float3 lightDir = normalize(lightPath);

        float cosEmit = clamp(dot(lightDir, -lightNormal), 0.0, 1.0);
        float cosCath = clamp(dot(lightDir, normal) * 0.5 + 0.5, 0.0, 1.0);
        float distFall = pow(lenSq(lightPath), 0.1) + 1.0;

        return (lightColor * cosEmit * cosCath / distFall) * (length(lightPosition) / 20.0);
    }

    float4 CustomPostProcess(Varyings input) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
    _InverseProjectionMatrix = UNITY_MATRIX_I_P;
        uint2 positionSS = input.texcoord * _ScreenSize.xy;
        float3 direct = SampleCameraColor(input.texcoord);//LOAD_TEXTURE2D_X(_InputTexture, positionSS).xyz;
        float3 color = normalize(direct).rgb;
        float3 indirect = float3(0, 0, 0);
        float2 texSize = _InputTexture_TexelSize.zw;

        float3 position = GetViewPos(input.texcoord, _InverseProjectionMatrix);
        float3 normal = GetViewNormal(input.texcoord, _InverseProjectionMatrix);

        // spiral sample
        float dlong = PI * (3.0 - sqrt(5.0));
        float dz = 1.0 / float(_SamplesCount);
        float l = 0.0;
        float z = 1.0 - dz / 2.0;
        float debug;

        for (int i = 0; i < _SamplesCount; i++) 
        {
            float r = sqrt(1.0 - z);

            float xPoint = (cos(l) * r) * 0.5 + 0.5;
            float yPoint = (sin(l) * r) * 0.5 + 0.5;

            z = z - dz;
            l = l + dlong;

            indirect += LightSample(input.texcoord, _InverseProjectionMatrix, float2(xPoint, yPoint), normal, position, float(i), texSize);
        }

        float depth = SampleCameraDepth(input.texcoord);
        if (_Debug == 1)
        {
            return float4(debug, debug, debug, 1);//
        }
        else if (_Debug == 2)
        {
            return float4(position, 1);
        }

        return float4(direct + (indirect / float(_SamplesCount) * _IndirectAmount), 1);
    }

    ENDHLSL

    SubShader
    {
        Pass
        {
            Name "SSGI"

            ZWrite Off
            ZTest Always
            Blend Off
            Cull Off

            HLSLPROGRAM
                #pragma fragment CustomPostProcess
                #pragma vertex Vert
            ENDHLSL
        }
    }
    Fallback Off
}
