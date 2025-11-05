Shader "FullScreen/DitheringJIN"
{
    Properties
    {
        [Toggle] _Colored("Color", Integer) = 0.0
        [Toggle] _Dither("Dither", Integer) = 0.0
        _Size("Size", Range(1, 15)) = 1
        _PaletteSize("Palette size", Range(2, 256)) = 2
        _Effect("Dither strength", Range(0, 1)) = 1
    }

    HLSLINCLUDE

    #pragma vertex Vert

    #pragma target 4.5
    #pragma only_renderers d3d11 playstation xboxone xboxseries vulkan metal switch

    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/RenderPass/CustomPass/CustomPassCommon.hlsl"

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

    uint _Colored;
    uint _Dither;
    uint _Size;
    uint _PaletteSize;
    float _Effect;

    float LuminanceRec709(float3 color)
    {
        return dot(color, float3(0.2126, 0.7152, 0.0722));
    }

    float3 ColorToGrey(float3 pixel) 
    {
        return LuminanceRec709(pixel).xxx;
    }

    float ColorSaturation(float color, int n) 
    {
        float step = 1.0/(n-1);
        for (int i = 0; i < n; i++) {
            if (color >= i*step && color < (i+1)*step) {
                float diff1 = abs(i*step - color);
                float diff2 = abs((i+1)*step - color);
                if (diff1 < diff2) return i*step; 
                return (i+1)*step;
            }
        }
        return 1;
    }

    float3 PixelSaturation(float3 color, int n) 
    {
        return float3(ColorSaturation(color.r, n), ColorSaturation(color.g, n), ColorSaturation(color.b, n));
    }

    uint BitInterleaving(uint x, uint y) 
    {
        uint result = 0;
        for (int i = 0; i < 16*8; i++)
        {
            result |= (x & 1U << i) << i | (y & 1U << i) << (i + 1);
        }
        return result;
    }

    float Mij(int i, int j)
    {
        uint n = pow(2, _Size);
        return ((float) reversebits(BitInterleaving(i ^ j, j ) << (32 - n))) / (n*n);
    }

    float4 FullScreenPass(Varyings varyings) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(varyings);
        float depth = LoadCameraDepth(varyings.positionCS.xy);
        PositionInputs posInput = GetPositionInput(varyings.positionCS.xy, _ScreenSize.zw, depth, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
        float3 viewDirection = GetWorldSpaceNormalizeViewDir(posInput.positionWS);
        float4 color = float4(0.0, 0.0, 0.0, 0.0);

        uint2 pixelPos = varyings.positionCS.xy;

        // Load the camera color buffer at the mip 0 if we're not at the before rendering injection point
        if (_CustomPassInjectionPoint != CUSTOMPASSINJECTIONPOINT_BEFORE_RENDERING)
            color = float4(CustomPassLoadCameraColor(pixelPos, 0), 1);

        // Add your custom pass code here

        float3 oldColor = _Colored*color.rgb + (1-_Colored)*ColorToGrey(color.rgb);

        int i = posInput.positionSS.x%pow(2, _Size);
        int j = posInput.positionSS.y%pow(2, _Size);

        float3 newColor = PixelSaturation(saturate(oldColor + _Effect * (Mij(i, j) - 0.5)), _PaletteSize);

        if (_Dither) return float4(newColor, color.a);
        return float4(oldColor, 1);
    }

    ENDHLSL

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
