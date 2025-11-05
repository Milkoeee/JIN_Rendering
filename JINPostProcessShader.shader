Shader "FullScreen/JIN_PostProcess"
{
    HLSLINCLUDE

    #pragma vertex Vert

    #pragma target 4.5
    #pragma only_renderers d3d11 playstation xboxone xboxseries vulkan metal switch

    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/RenderPass/CustomPass/CustomPassCommon.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/NormalBuffer.hlsl"

    // The PositionInputs struct allow you to retrieve a lot of useful information for your fullScreenShader:
    // struct PositionInputs
    // {
    //     float3 positionWS;  // World space position (could be camera-relative)
    //     float2 positionNDC; // Normalized screen coordinates within the viewport    : [0, 1) (with the half-pixel offset)
    //     uint2  positionSS;  // Screen space pixel coordinates                       : [0, NumPixels)
    //     uint2  tileCoord;   // Screen tile coordinates                              : [0, NumTiles)
    //     float  deviceDepth; // Depth from the depth buffer                          : [0, 1] (typically reversed)
    //     float  linearDepth; // View space Z coordinate                              : [Near, Far]
    // };

    // To sample custom buffers, you have access to these functions:
    // But be careful, on most platforms you can't sample to the bound color buffer. It means that you
    // can't use the SampleCustomColor when the pass color buffer is set to custom (and same for camera the buffer).
    // float4 CustomPassSampleCustomColor(float2 uv);
    // float4 CustomPassLoadCustomColor(uint2 pixelCoords);
    // float LoadCustomDepth(uint2 pixelCoords);
    // float SampleCustomDepth(float2 uv);

    // There are also a lot of utility function you can use inside Common.hlsl and Color.hlsl,
    // you can check them out in the source code of the core SRP package.

float _Param;
float _PowColor;
float _PostCount;
float _TimeRadius;
float _TimeSpeed;
float _MaxDistance;
float _Sigma;

float JIN_Remap(float x, float cur_min, float cur_max, float new_min, float new_max)
{
    float x01 = (x - cur_min) / (cur_max - cur_min);

    return x01 * (new_max - new_min) + new_min;
}

float GaussLike(float x, float sig = 0.1)
{
    float xx = (x-0.5);
    xx *= xx;
    return exp(-xx/sig);
}

float GaussLikeNorm(float x, float sig = 0.1)
{
    return    (GaussLike(x, sig) - GaussLike(0.0f, sig))
        / // ----------------------------------------------
              (GaussLike(0.5f, sig) - GaussLike(0.0f, sig));
}

float NormalizeLinearDepth(float linearDepth)
{
    //return (linearDepth - Near) / (Far - Near);

    return     (linearDepth - g_fNearPlane)
       / // -----------------------------------
                (g_fFarPlane - g_fNearPlane);
}

float3 GetColor(float2 positionSS)
{
    return CustomPassLoadCameraColor(positionSS, 0).rgb;
}

float GetDepth(float2 positionSS)
{
    return LoadCameraDepth(positionSS);
}

float GetLinearDepthMeter(PositionInputs posInput)
{
    return posInput.linearDepth;
}

float GetLinearEyeDepth(float2 positinoSS)
{
    float depth = LoadCameraDepth(positinoSS);
    PositionInputs posInput = GetPositionInput(positinoSS, _ScreenSize.zw, depth, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
    return LinearEyeDepth(depth, _ZBufferParams);
}

    float4 FullScreenPass(Varyings varyings) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(varyings);
        float4 color = float4(0.0, 0.0, 0.0, 0.0);

        uint2 pos00   = varyings.positionCS.xy;
        float depth00  = LoadCameraDepth(pos00);
        PositionInputs posInput00 = GetPositionInput(pos00,   _ScreenSize.zw, depth00,  UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
        
        if (IsSky(posInput00.deviceDepth))
            return float4(0.0f, 0.0f, 0.0f, 1.0f);

        // Load the camera color buffer at the mip 0 if we're not at the before rendering injection point
        if (_CustomPassInjectionPoint != CUSTOMPASSINJECTIONPOINT_BEFORE_RENDERING)
            color = float4(CustomPassLoadCameraColor(pos00, 0), 1);

        float3 viewDirection = GetWorldSpaceNormalizeViewDir(posInput00.positionWS);
        
        uint2 pos_10  = (uint2)((int2)pos00 + int2(-1,  0));
        uint2 pos10   = (uint2)((int2)pos00 + int2( 1,  0));
        uint2 pos0_1  = (uint2)((int2)pos00 + int2( 0, -1));
        uint2 pos01   = (uint2)((int2)pos00 + int2( 0,  1));

        float depth_10 = LoadCameraDepth(pos_10);
        float depth10  = LoadCameraDepth(pos10);
        float depth0_1 = LoadCameraDepth(pos0_1);
        float depth01  = LoadCameraDepth(pos01);

        PositionInputs posInput_10 = GetPositionInput(pos_10, _ScreenSize.zw, depth_10, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
        PositionInputs posInput10  = GetPositionInput(pos10,  _ScreenSize.zw, depth10,  UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
        PositionInputs posInput0_1 = GetPositionInput(pos0_1, _ScreenSize.zw, depth0_1, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
        PositionInputs posInput01  = GetPositionInput(pos01,  _ScreenSize.zw, depth01,  UNITY_MATRIX_I_VP, UNITY_MATRIX_V);

        float linearDepth00  = posInput00 .linearDepth;
        float linearDepth_10 = posInput_10.linearDepth;
        float linearDepth10  = posInput10 .linearDepth;
        float linearDepth0_1 = posInput0_1.linearDepth;
        float linearDepth01  = posInput01 .linearDepth;

        float laplacian = linearDepth_10 + linearDepth10 + linearDepth0_1 + linearDepth01 - 4.0f * linearDepth00;

        //return float4(laplacian.xxx, 1.0f);

        float dx = (linearDepth10 - linearDepth_10) / 2.0f;
        float dy = (linearDepth01 - linearDepth0_1) / 2.0f;

        //float sumdd = abs(dx) + abs(dy);
        float sobel = sqrt(dx*dx + dy*dy);

        float is_edge = (float)(sobel > _Param);

        //return float4(is_edge.xxx, 1.0f);

        float3 dist_color = saturate(pow(color.rgb, _PowColor));
        float3 scaled_color = dist_color * _PostCount;
        float3 quant_color = (float3)uint3(scaled_color);
        float3 post_color = quant_color / _PostCount;

        //float3 output = lerp(quant_color, float3(0, 0, 0), is_edge);
        //float3 output = lerp(color, float3(0, 0, 0), is_edge);

        float time_loop = fmod(_TimeSpeed * _Time, 1.0f);

        #if 0
        float linearDepthNormalized = NormalizeLinearDepth(posInput00.linearDepth);

        float min_bound = saturate(time_loop - _TimeRadius);
        float max_bound = saturate(time_loop + _TimeRadius);

        float new_lin_depth = JIN_Remap(linearDepthNormalized, min_bound, max_bound, 0.0f, 1.0f);

        if (min_bound < linearDepthNormalized && linearDepthNormalized < max_bound)
            return float4(lerp(new_lin_depth.xxx, float3(1, 0, 0), is_edge), 1.0f);
        else
            return float4(0.0f.xxx, 1.0f);
        #else
        float time_rescale = JIN_Remap(time_loop, 0.0f, 1.0f, g_fNearPlane, _MaxDistance);
        float min_bound = time_rescale - _TimeRadius;
        float max_bound = time_rescale + _TimeRadius;

        float depth_bounded = JIN_Remap(posInput00.linearDepth, g_fNearPlane, g_fFarPlane, min_bound, max_bound);
        float depth_bounded01 = JIN_Remap(posInput00.linearDepth, min_bound, max_bound, 0.0f, 1.0f);

        //float gradient = GaussLikeNorm(depth_bounded01, _Sigma);
        float gradient = depth_bounded01;
        //gradient = abs(sin(gradient * 2.0f * PI)) * depth_bounded01;

        if (min_bound < posInput00.linearDepth && posInput00.linearDepth < max_bound)
        {
            if (posInput00.linearDepth > max_bound - 0.1)
                return float4(0.0f, 0.0f, 1.0f, 1.0f);
            else
                return float4(float3(0, 0, gradient * 0.2), 1.0f);
                //return float4(lerp(float3(0, 0, 1)*gradient * 0.2, float3(1, 0, 0), is_edge), 1.0f);
        }
        else
            return float4(0.0f.xxx, 1.0f);
        #endif
    }

    ENDHLSL
    
    Properties
    {
        _Param("Param", Range(0.0, 10.0)) = 0.0
        _PostCount("Posterization Count", Range(0.0, 255.0)) = 10.0
        _PowColor("Color Power", Range(0.0125, 3.0)) = 2.0
        _TimeRadius("Time Radius", Range(0.0125, 5.0)) = 0.1
        _MaxDistance("Max Distance", Range(0.0125, 20.0)) = 10
        _TimeSpeed("Time Speed", Range(0.0125, 10.0)) = 1.0
        _Sigma("Sigma", Range(0.0125, 2.0)) = 0.1
    }
    SubShader
    {
        Tags{ "RenderPipeline" = "HDRenderPipeline" }
        Pass
        {
            Name "Custom Pass 0"

            ZWrite Off
            ZTest Always
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Off

            HLSLPROGRAM
                #pragma fragment FullScreenPass
            ENDHLSL
        }
    }
    Fallback Off
}