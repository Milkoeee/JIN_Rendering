Shader"JIN/JIN_000"
{
    Properties
    {
        _SliderScale("Slider Scale", Range(0.0, 10.0)) = 0.0
        _Color("Color", Color) = (1.0, 1.0, 1.0, 1.0)
        _BasecolorTexture("Basecolor", 2D) = "white" {}
        _MetalnessTexture("Metalness", 2D) = "white" {}
        _RoughnessTexture("Roughness", 2D) = "white" {}
        _AOTexture("AO", 2D) = "white" {}
        _NormalTexture("Normal", 2D) = "white" {}
    }
    SubShader
    {
        Tags{ "RenderPipeline" = "HDRenderPipeline" "RenderType" = "Opaque" }
        LOD 100

HLSLINCLUDE

#pragma editor_sync_compilation
#pragma target 4.5
#pragma only_renderers d3d11 playstation xboxone xboxseries vulkan metal switch

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"

float _Scale;
float _SliderScale;
float4 _Color;

TEXTURE2D(_BasecolorTexture);
SAMPLER(sampler_BasecolorTexture);
float4 _BasecolorTexture_ST;
float4 _BasecolorTexture_TexelSize;
float4 _BasecolorTexture_MipInfo;

TEXTURE2D(_MetalnessTexture);
SAMPLER(sampler_MetalnessTexture);
float4 _MetalnessTexture_ST;
float4 _MetalnessTexture_TexelSize;
float4 _MetalnessTexture_MipInfo;

TEXTURE2D(_RoughnessTexture);
SAMPLER(sampler_RoughnessTexture);
float4 _RoughnessTexture_ST;
float4 _RoughnessTexture_TexelSize;
float4 _RoughnessTexture_MipInfo;

TEXTURE2D(_AOTexture);
SAMPLER(sampler_AOTexture);
float4 _AOTexture_ST;
float4 _AOTexture_TexelSize;
float4 _AOTexture_MipInfo;

TEXTURE2D(_NormalTexture);
SAMPLER(sampler_NormalTexture);
float4 _NormalTexture_ST;
float4 _NormalTexture_TexelSize;
float4 _NormalTexture_MipInfo;

// Point Light
float4 _LightPositionWS;
float4 _LightIntensity;

struct VertexData
{
    float4 vertexOS : POSITION;
    float3 normalOS : NORMAL;
    float3 tangentOS : TANGENT;
    float2 uv : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct VertexToPixel
{
    float4 vertexCS : SV_POSITION;
    float3 normalWS : NORMAL;
    float3 positionWS : TEXCOORD1;
    float3 tangentWS : TEXCOORD2;
    float2 uv : TEXCOORD3;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

VertexToPixel VertexShaderMain(VertexData v)
{
    VertexToPixel o;

    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_TRANSFER_INSTANCE_ID(v, o);

    o.vertexCS = TransformObjectToHClip(v.vertexOS.xyz);
    o.normalWS = TransformObjectToWorldNormal(v.normalOS.xyz);
    o.tangentWS = TransformObjectToWorldNormal(v.tangentOS.xyz);
    o.positionWS = TransformObjectToWorld(v.vertexOS.xyz);
    o.uv = v.uv;

    return o;
}

float V_SmithGGXCorrelatedFast(float NoV, float NoL, float roughness)
{
    float a = roughness;
    float GGXV = NoL * (NoV * (1.0 - a) + a);
    float GGXL = NoV * (NoL * (1.0 - a) + a);
    return 0.5 / (GGXV + GGXL);
}

float D_GGX(float NoH, float a)
{
    float a2 = a * a;
    float f = (NoH * a2 - NoH) * NoH + 1.0;
    return a2 / (PI * f * f);
}

float4 PixelShaderMain(VertexToPixel i) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(i);

    float3 lightPosWS = GetCameraRelativePositionWS(_LightPositionWS.xyz);

    float3 to_light = lightPosWS - i.positionWS;
    float d2 = dot(to_light, to_light);
    float3 wi = to_light / sqrt(d2);

    // Create matrix 'tangent space to world space [Camera Relative]'
    float3x3 tangent_to_world = CreateTangentToWorld(i.normalWS, i.tangentWS, 1.0f);
    // Sample the normal from texture
    float3 normalTSColor = _NormalTexture.Sample(sampler_NormalTexture, i.uv).xyz;
    // Convert from [0;1] -> [-1;1] (normalize because the data is 8 bits)
    float3 normalTS = normalize( normalTSColor.xyz * 2.0f - 1.0f );
    // [0; 1] -> x2 -> [0; 2] -> -1 -> [-1; 1]

    // Transform normal Tangent Space to world (in practice just a mat-mul)
    float3 texture_normal_ws = TransformTangentToWorld(normalTS, tangent_to_world, true);

    // Perturbation of the normal from vertices and normal from the texture (converted to World Space)
    float3 n = normalize(i.normalWS + _SliderScale * texture_normal_ws);
    float3 wo = normalize( -lightPosWS );
    float3 wh = normalize(wi + wo);

    float cos0o = dot(n, wo);
    float cos0oh = dot(wo, wh);
    float cos0h = dot(n, wh);
    float cos0i = dot(n, wi);

    float3 basecolor = _BasecolorTexture.Sample(sampler_BasecolorTexture, i.uv).rgb;
    float metalness = _MetalnessTexture.Sample(sampler_MetalnessTexture, i.uv).x;
    float roughness = _RoughnessTexture.Sample(sampler_RoughnessTexture, i.uv).x;
    float ao = _AOTexture.Sample(sampler_AOTexture, i.uv).x;

    float alpha = roughness * roughness;

    float3 diffuse_albedo = lerp(basecolor, 0.0f.xxx, metalness);
    float3 specular_albedo = lerp(0.04f.xxx, basecolor, metalness);

    // Rest of the light equation
    float inv_sqr_law = 1.0f / ( 4.0 * PI * d2 );

    float finv = 1.0 - cos0oh;
    float finv2 = finv*finv;
    float finv4 = finv2*finv2;




    float3 F = specular_albedo + (1.0f - specular_albedo) * finv4 * finv;
    float D = D_GGX(cos0h, alpha);
    float V = V_SmithGGXCorrelatedFast(cos0o, cos0i, alpha);







    float3 diffuse_brdf = diffuse_albedo / PI;
    float3 specular_brdf = F * D * V;

    float3 result = ( ( _Color.rgb * diffuse_brdf + specular_brdf ) * _LightIntensity.rgb ) * ( max(cos0i, 0.0f) * inv_sqr_law );
    //float3 result = ( ( _Color.rgb * diffuse_brdf ) * _LightIntensity.rgb ) * ( max(cos0i, 0.0f) * inv_sqr_law );

    // GetCurrentExposureMultiplier() * 
    return float4(result, 1.0f);
}
ENDHLSL

        Pass
        {

            Name "JIN_Shader"
            Tags{ "LightMode" = "ForwardOnly" }

            ZTest LEqual
            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex VertexShaderMain
            #pragma fragment PixelShaderMain
            #pragma multi_compile_instancing
            ENDHLSL
        }
    }
}