#include <HLSLSupport.cginc>

#define _NORMALMAP
#ifndef UNIVERSAL_FORWARD_LIT_PASS_INCLUDED
#define UNIVERSAL_FORWARD_LIT_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#if defined(LOD_FADE_CROSSFADE)
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/LODCrossFade.hlsl"
#endif

// GLES2 has limited amount of interpolators
#if defined(_PARALLAXMAP) && !defined(SHADER_API_GLES)
#define REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR
#endif

#if (defined(_NORMALMAP) || (defined(_PARALLAXMAP) && !defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR))) || defined(_DETAIL)
#define REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR
#endif

// keep this file in sync with LitGBufferPass.hlsl

struct Attributes
{
    float4 positionOS   : POSITION;
    float3 normalOS     : NORMAL;
    float4 tangentOS    : TANGENT;
    float2 texcoord     : TEXCOORD0;
    float2 staticLightmapUV   : TEXCOORD1;
    float2 dynamicLightmapUV  : TEXCOORD2;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float2 uv                       : TEXCOORD0;

#if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR)
    float3 positionWS               : TEXCOORD1;
#endif

    float3 normalWS                 : TEXCOORD2;
#if defined(REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR)
    half4 tangentWS                : TEXCOORD3;    // xyz: tangent, w: sign
#endif

#ifdef _ADDITIONAL_LIGHTS_VERTEX
    half4 fogFactorAndVertexLight   : TEXCOORD5; // x: fogFactor, yzw: vertex light
#else
    half  fogFactor                 : TEXCOORD5;
#endif

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    float4 shadowCoord              : TEXCOORD6;
#endif

#if defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR)
    half3 viewDirTS                : TEXCOORD7;
#endif

    DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 8);
#ifdef DYNAMICLIGHTMAP_ON
    float2  dynamicLightmapUV : TEXCOORD9; // Dynamic lightmap UVs
#endif

    float4 positionCS               : SV_POSITION;
    float4 positionScreen           : TEXCOORD10;
    float3 viewVector               : TEXCOORD11;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

void InitializeInputData(Varyings input, half3 normalTS, out InputData inputData)
{
    inputData = (InputData)0;

#if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR)
    inputData.positionWS = input.positionWS;
#endif

    half3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
#if defined(_NORMALMAP) || defined(_DETAIL)
    float sgn = input.tangentWS.w;      // should be either +1 or -1
    float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
    half3x3 tangentToWorld = half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz);

    #if defined(_NORMALMAP)
    inputData.tangentToWorld = tangentToWorld;
    #endif
    inputData.normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
#else
    inputData.normalWS = input.normalWS;
#endif

    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
    inputData.viewDirectionWS = viewDirWS;

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    inputData.shadowCoord = input.shadowCoord;
#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
    inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
#else
    inputData.shadowCoord = float4(0, 0, 0, 0);
#endif
#ifdef _ADDITIONAL_LIGHTS_VERTEX
    inputData.fogCoord = InitializeInputDataFog(float4(input.positionWS, 1.0), input.fogFactorAndVertexLight.x);
    inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
#else
    inputData.fogCoord = InitializeInputDataFog(float4(input.positionWS, 1.0), input.fogFactor);
#endif

#if defined(DYNAMICLIGHTMAP_ON)
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.dynamicLightmapUV, input.vertexSH, inputData.normalWS);
#else
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, inputData.normalWS);
#endif

    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);

    #if defined(DEBUG_DISPLAY)
    #if defined(DYNAMICLIGHTMAP_ON)
    inputData.dynamicLightmapUV = input.dynamicLightmapUV;
    #endif
    #if defined(LIGHTMAP_ON)
    inputData.staticLightmapUV = input.staticLightmapUV;
    #else
    inputData.vertexSH = input.vertexSH;
    #endif
    #endif
}

float4 triplanarOffset(float3 vertPos, float3 normal, float3 scale, sampler2D tex, float2 offset)
{
    float3 scaledPos = vertPos / scale;
    float4 colX = tex2D(tex, scaledPos.zy + offset);
    float4 colY = tex2D(tex, scaledPos.xz + offset);
    float4 colZ = tex2D(tex, scaledPos.xy + offset);

    // Square normal to make all values positive + increase blend sharpness
    float3 blendWeight = normal * normal;
    // Divide blend weight by the sum of its components. This will make x + y + z = 1
    blendWeight /= dot(blendWeight, 1);
    return colX * blendWeight.x + colY * blendWeight.y + colZ * blendWeight.z;
}

// Reoriented Normal Mapping
// http://blog.selfshadow.com/publications/blending-in-detail/
// Altered to take normals (-1 to 1 ranges) rather than unsigned normal maps (0 to 1 ranges)
float3 blend_rnm(float3 n1, float3 n2)
{
    n1.z += 1;
    n2.xy = -n2.xy;

    return n1 * dot(n1, n2) / n1.z - n2;
}

// Sample normal map with triplanar coordinates
// Returned normal will be in obj/world space (depending whether pos/normal are given in obj or world space)
// Based on: medium.com/@bgolus/normal-mapping-for-a-triplanar-shader-10bf39dca05a
float3 triplanarNormal(float3 vertPos, float3 normal, float3 scale, float2 offset, sampler2D normalMap)
{
    float3 absNormal = abs(normal);

    // Calculate triplanar blend
    float3 blendWeight = saturate(pow(normal, 4));
    // Divide blend weight by the sum of its components. This will make x + y + z = 1
    blendWeight /= dot(blendWeight, 1);

    // Calculate triplanar coordinates
    float2 uvX = vertPos.zy * scale + offset;
    float2 uvY = vertPos.xz * scale + offset;
    float2 uvZ = vertPos.xy * scale + offset;

    // Sample tangent space normal maps
    // UnpackNormal puts values in range [-1, 1] (and accounts for DXT5nm compression)
    float3 tangentNormalX = UnpackNormal(tex2D(normalMap, uvX));
    float3 tangentNormalY = UnpackNormal(tex2D(normalMap, uvY));
    float3 tangentNormalZ = UnpackNormal(tex2D(normalMap, uvZ));

    // Swizzle normals to match tangent space and apply reoriented normal mapping blend
    tangentNormalX = blend_rnm(half3(normal.zy, absNormal.x), tangentNormalX);
    tangentNormalY = blend_rnm(half3(normal.xz, absNormal.y), tangentNormalY);
    tangentNormalZ = blend_rnm(half3(normal.xy, absNormal.z), tangentNormalZ);

    // Apply input normal sign to tangent space Z
    float3 axisSign = sign(normal);
    tangentNormalX.z *= axisSign.x;
    tangentNormalY.z *= axisSign.y;
    tangentNormalZ.z *= axisSign.z;

    // Swizzle tangent normals to match input normal and blend together
    float3 outputNormal = normalize(
        tangentNormalX.zyx * blendWeight.x +
        tangentNormalY.xzy * blendWeight.y +
        tangentNormalZ.xyz * blendWeight.z
    );

    return outputNormal;
}

float4 test(float v)
{
    return float4(v, v, v, 1);
}

float3 worldToTexPos(float3 worldPos)
{
    return worldPos / planetBoundsSize + 0.5;
}

void modify(Varyings varyings, inout InputData input, inout SurfaceData surface)
{
    float3 t = worldToTexPos(input.positionWS);
    float density = tex3D(DensityTex, t);
    
    //return test(density * params.x);
    float3 viewDir = input.viewDirectionWS;
    
    float4 screenPos = varyings.positionScreen;

    // -------- Calculate water depth --------
    float nonLinearDepth = SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, screenPos);
    float depth = LinearEyeDepth(nonLinearDepth, _ZBufferParams);
    float dstToWater = screenPos.w;
    float waterViewDepth = depth - dstToWater;
    float waterDensityMap = density * 500;

    // -------- Normals ----------
    float waveSpeed = 0.35;
    float waveNormalScale = 0.05;
    float waveStrength = 0.4;
				
    float2 waveOffsetA = float2(_Time.x * waveSpeed, _Time.x * waveSpeed * 0.8);
    float2 waveOffsetB = float2(_Time.x * waveSpeed * - 0.8, _Time.x * waveSpeed * -0.3);
    float3 waveNormal1 = triplanarNormal(input.positionWS, input.normalWS, waveNormalScale, waveOffsetA, waveNormalA);
    float3 waveNormal2 = triplanarNormal(input.positionWS, input.normalWS, waveNormalScale, waveOffsetB, waveNormalB);
    float3 waveNormal = triplanarNormal(input.positionWS, waveNormal1, waveNormalScale, waveOffsetB, waveNormalB);
    input.normalWS = normalize(waveNormal + waveNormal2);
    surface.normalTS = input.normalWS ;

    
    // -------- Foam --------
    float foamSize = 4; // 2.25
    float foamSpeed = 0.5;
    float foamNoiseScale = 13;
    float foamNoiseStrength = 4.7;
    float numFoamLines = 2.5;
    float2 noiseScroll = float2(_Time.x, -_Time.x * 0.3333) * 0.25;
    float foamNoise = triplanarOffset(input.positionWS, input.normalWS, foamNoiseScale, foamNoiseTex, noiseScroll);
    foamNoise = smoothstep(0.2, .8, foamNoise);

    /*
    float foam = saturate(waterDensityMap / foamSize);
    float numFoamLines = 2.75;
    float foamAnim = sin((foam  - _Time.y * foamSpeed) * tau * (numFoamLines - 1)) * (1-foam) * 0.5 + 0.5;
    foam = min(foamAnim, foam);
    foam = foam < min(0.5, 0.5 + (foamNoise - 0.5) * foamNoiseStrength);
    */
    float foamT = saturate(waterDensityMap / foamSize);

    //return test(foamNoise * (1-foam));
    float foamTime = _Time.y * foamSpeed;
    float mask = (1 - foamT);
    float mask2 = smoothstep(1, 0.6, foamT) * (foamNoise - .5);
    mask2 = lerp(1, mask2, 1 - (1 - foamT) * (1 - foamT));

    float v = sin(foamT * 3.1415 * (1 + 2 * (numFoamLines - 1)) - foamTime) * (mask > 0);

    v = saturate(v) + (foamT < 0.35 + foamNoise * 0.15);

    //return test(foamT);

    float foamAlpha = smoothstep(1, 0.7, foamT);
    
    //return test(f2);
    float foam = (v > 1 - mask2) * foamAlpha;


    //float foamAnim = sin((foam  - _Time.y * foamSpeed) * tau * (numFoamLines - 1)) * (1-foam) * 0.5 + 0.5;
    //foam = min(foamAnim, foam);
    //foam = foam < 0.5;

    // -------- Water Transparency --------
    // Make water appear more transparent when viewed from above

    float alphaFresnel = 1 - saturate(pow(saturate(dot(-viewDir, varyings.normalWS)), alphaFresnelPow));
    alphaFresnel = max(0.7, alphaFresnel);
    float alphaFresnelNearFix = pow(saturate((screenPos.w - _ProjectionParams.y) / 4), 3);
    alphaFresnel = lerp(1, alphaFresnel, alphaFresnelNearFix);

    // Fade water at intersection with geometry
    float alphaEdge = 1 - exp(-waterViewDepth * edgeFade);

    // Dont want distant water to have any transparency because transparent water against sky causes issue with atmosphere shader
    //float opaqueWaterDst = 40;
    //float waterDstAlpha = saturate(dstToWater / opaqueWaterDst);

    // Calculate final alpha
    //return test(waterDstAlpha);
    float opaqueWater = max(0, foam);
    float alpha = saturate(max(opaqueWater, alphaEdge * alphaFresnel));
    //return test(alphaFresnel);

    // -------- Lighting and colour output --------

    float3 col = lerp(shallowCol, deepCol, 1 - exp(-waterViewDepth * colDepthFactor));
    col = saturate(col) ;
    col = col + foam;
    
    surface.alpha = alpha;
    half4 albedoAlpha = SampleAlbedoAlpha(varyings.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
    surface.albedo = albedoAlpha.rgb * col * _BaseColor.rgb;
    surface.albedo = AlphaModulate(surface.albedo, surface.alpha);
}


///////////////////////////////////////////////////////////////////////////////
//                  Vertex and Fragment functions                            //
///////////////////////////////////////////////////////////////////////////////

// Used in Standard (Physically Based) shader
Varyings WaterLitPassVertex(Attributes input)
{
    Varyings output = (Varyings)0;

    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);

    // normalWS and tangentWS already normalize.
    // this is required to avoid skewing the direction during interpolation
    // also required for per-vertex lighting and SH evaluation
    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

    half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);

    half fogFactor = 0;
    #if !defined(_FOG_FRAGMENT)
        fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
    #endif

    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
    output.positionScreen = vertexInput.positionNDC;
    float3 viewVector = mul(unity_CameraInvProjection, float4((output.positionScreen.xy/output.positionScreen.w) * 2 - 1, 0, -1));
    output.viewVector = mul(unity_CameraToWorld, float4(viewVector,0));

    // already normalized from normal transform to WS.
    output.normalWS = normalInput.normalWS;
#if defined(REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR) || defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR)
    real sign = input.tangentOS.w * GetOddNegativeScale();
    half4 tangentWS = half4(normalInput.tangentWS.xyz, sign);
#endif
#if defined(REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR)
    output.tangentWS = tangentWS;
#endif

#if defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR)
    half3 viewDirWS = GetWorldSpaceNormalizeViewDir(vertexInput.positionWS);
    half3 viewDirTS = GetViewDirectionTangentSpace(tangentWS, output.normalWS, viewDirWS);
    output.viewDirTS = viewDirTS;
#endif

    OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, output.staticLightmapUV);
#ifdef DYNAMICLIGHTMAP_ON
    output.dynamicLightmapUV = input.dynamicLightmapUV.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
#endif
    OUTPUT_SH(output.normalWS.xyz, output.vertexSH);
#ifdef _ADDITIONAL_LIGHTS_VERTEX
    output.fogFactorAndVertexLight = half4(fogFactor, vertexLight);
#else
    output.fogFactor = fogFactor;
#endif

#if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR)
    output.positionWS = vertexInput.positionWS;
#endif

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    output.shadowCoord = GetShadowCoord(vertexInput);
#endif

    output.positionCS = vertexInput.positionCS;

    return output;
}

// Used in Standard (Physically Based) shader
void WaterLitPassFragment(
    Varyings input
    , out half4 outColor : SV_Target0
#ifdef _WRITE_RENDERING_LAYERS
    , out float4 outRenderingLayers : SV_Target1
#endif
)
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

#if defined(_PARALLAXMAP)
#if defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR)
    half3 viewDirTS = input.viewDirTS;
#else
    half3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
    half3 viewDirTS = GetViewDirectionTangentSpace(input.tangentWS, input.normalWS, viewDirWS);
#endif
    ApplyPerPixelDisplacement(viewDirTS, input.uv);
#endif

    SurfaceData surfaceData;
    InitializeStandardLitSurfaceData(input.uv, surfaceData);

#ifdef LOD_FADE_CROSSFADE
    LODFadeCrossFade(input.positionCS);
#endif

    InputData inputData;
    InitializeInputData(input, surfaceData.normalTS, inputData);
    SETUP_DEBUG_TEXTURE_DATA(inputData, input.uv, _BaseMap);

    
    modify(input, inputData, surfaceData);

#ifdef _DBUFFER
    ApplyDecalToSurfaceData(input.positionCS, surfaceData, inputData);
#endif

    half4 color = UniversalFragmentPBR(inputData, surfaceData);
    color.rgb = MixFog(color.rgb, inputData.fogCoord);
    color.a = OutputAlpha(color.a, IsSurfaceTypeTransparent(_Surface));

    outColor = color;

#ifdef _WRITE_RENDERING_LAYERS
    uint renderingLayers = GetMeshRenderingLayer();
    outRenderingLayers = float4(EncodeMeshRenderingLayer(renderingLayers), 0, 0, 0);
#endif
}

#endif

