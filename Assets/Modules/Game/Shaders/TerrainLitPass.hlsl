#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#if defined(LOD_FADE_CROSSFADE)
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/LODCrossFade.hlsl"
#endif

inline void InitializeTerrainLitSurfaceData(float2 uv, out SurfaceData outSurfaceData)
{
    outSurfaceData = (SurfaceData)0;

    half4 albedoAlpha = SampleAlbedoAlpha(uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
    outSurfaceData.alpha = albedoAlpha.a * _BaseColor.a;
    outSurfaceData.alpha = AlphaDiscard(outSurfaceData.alpha, _Cutoff);
    
    outSurfaceData.albedo = albedoAlpha.rgb * _BaseColor.rgb;
    outSurfaceData.albedo = AlphaModulate(outSurfaceData.albedo, outSurfaceData.alpha);

    half4 specularSmoothness = SampleSpecularSmoothness(uv, outSurfaceData.alpha, _SpecColor, TEXTURE2D_ARGS(_SpecGlossMap, sampler_SpecGlossMap));
    outSurfaceData.metallic = 0.0; // unused
    outSurfaceData.specular = specularSmoothness.rgb;
    outSurfaceData.smoothness = specularSmoothness.a;
    outSurfaceData.normalTS = SampleNormal(uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap));
    outSurfaceData.occlusion = 1.0;
    outSurfaceData.emission = SampleEmission(uv, _EmissionColor.rgb, TEXTURE2D_ARGS(_EmissionMap, sampler_EmissionMap));
}

float4 triplanarOffset(float3 vertPos, float3 normal, float3 scale, sampler2D tex, float2 offset) {
    float3 scaledPos = vertPos / scale;
    float4 colX = tex2D (tex, scaledPos.zy + offset);
    float4 colY = tex2D(tex, scaledPos.xz + offset);
    float4 colZ = tex2D (tex,scaledPos.xy + offset);
			
    // Square normal to make all values positive + increase blend sharpness
    float3 blendWeight = normal * normal;
    // Divide blend weight by the sum of its components. This will make x + y + z = 1
    blendWeight /= dot(blendWeight, 1);
    return colX * blendWeight.x + colY * blendWeight.y + colZ * blendWeight.z;
}

float3 worldToTexPos(float3 worldPos) {
    return worldPos / planetBoundsSize + 0.5;
}

void modify(Varyings varyings, InputData IN, inout SurfaceData surface)
{
    float3 t = worldToTexPos(IN.positionWS);
    float density = tex3D(DensityTex, t);
    // 0 = flat, 0.5 = vertical, 1 = flat (but upside down)
    float steepness = 1 - (dot(normalize(IN.positionWS), IN.normalWS) * 0.5 + 0.5);
    float dstFromCentre = length(IN.positionWS);

    float4 noise = triplanarOffset(IN.positionWS, IN.normalWS, 30, _NoiseTex, 0);
    float4 noise2 = triplanarOffset(IN.positionWS, IN.normalWS, 50, _NoiseTex, 0);
    //float angle01 = dot(normalize(IN.worldPos), IN.worldNormal) * 0.5 + 0.5;
    //o.Albedo = lerp(float3(1,0,0), float3(0,1,0), smoothstep(0.4,0.6,angle01));

    float metallic = 0;
    float rockMetalStrength = 0.4;
    float4 albedo;
			
    float threshold = 0.005;
    if (density < -threshold) {
        float rockDepthT = saturate(abs(density + threshold) * 20);

        
        albedo = lerp(_RockInnerShallow, _RockInnerDeep, rockDepthT);

        
        metallic = lerp(rockMetalStrength, 1, rockDepthT);
    }
    else {
        float4 grassCol = lerp(_GrassLight, _GrassDark, noise.r);
        int r = 10;
        float4 rockCol = lerp(_RockLight, _RockDark, (int)(noise2.r*r) / float(r));
        float n = (noise.r-0.4) * _Test;

        float rockWeight = smoothstep(0.24 + n, 0.24 + 0.001 + n, steepness);
        albedo = lerp(grassCol, rockCol, rockWeight);
        //o.Albedo = steepness > _Test;
        metallic = lerp(0, rockMetalStrength, rockWeight);
    }

    //o.Albedo = dstFromCentre > oceanRadius;
    
    //o.Albedo = metallic;

    half4 albedoAlpha = SampleAlbedoAlpha(varyings.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
    surface.albedo = albedoAlpha.rgb * albedo * _BaseColor.rgb;
    surface.albedo = AlphaModulate(surface.albedo, surface.alpha);

    surface.metallic = metallic;
    surface.smoothness = _Glossiness;
}

// Used for StandardSimpleLighting shader
void TerrainLitPassFragmentSimple(
    Varyings input
    , out half4 outColor : SV_Target0
#ifdef _WRITE_RENDERING_LAYERS
    , out float4 outRenderingLayers : SV_Target1
#endif
)
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    SurfaceData surfaceData;
    InitializeTerrainLitSurfaceData(input.uv, surfaceData);

    #ifdef LOD_FADE_CROSSFADE
    LODFadeCrossFade(input.positionCS);
    #endif

    InputData inputData;
    InitializeInputData(input, surfaceData.normalTS, inputData);
    SETUP_DEBUG_TEXTURE_DATA(inputData, input.uv, _BaseMap);


    // Additions
    modify(input, inputData, surfaceData);

    #ifdef _DBUFFER
    ApplyDecalToSurfaceData(input.positionCS, surfaceData, inputData);
    #endif

    half4 color = UniversalFragmentBlinnPhong(inputData, surfaceData);
    color.rgb = MixFog(color.rgb, inputData.fogCoord);
    color.a = OutputAlpha(color.a, IsSurfaceTypeTransparent(_Surface));

    outColor = color;

    #ifdef _WRITE_RENDERING_LAYERS
    uint renderingLayers = GetMeshRenderingLayer();
    outRenderingLayers = float4(EncodeMeshRenderingLayer(renderingLayers), 0, 0, 0);
    #endif
}