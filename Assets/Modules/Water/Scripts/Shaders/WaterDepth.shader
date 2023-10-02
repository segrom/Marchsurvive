Shader "Custom/Water Depth Replacement"
{
	SubShader
	{
		Tags {"LightMode"="ShadowCaster"}
		
		HLSLINCLUDE
		#include <HLSLSupport.cginc>
		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
		ENDHLSL
		Pass
		{
			
			ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull[_Cull]

			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
			#pragma multi_compile_fragment _ LOD_FADE_CROSSFADE
			#pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

			struct Attributes
			{
				float4 positionOS : POSITION;
				float3 normalOS : NORMAL;
				float2 texcoord : TEXCOORD0;
			};

			struct Varyings
			{
				float2 uv : TEXCOORD0;
				float4 positionScreen : TEXCOORD1;
				float4 positionCS : SV_POSITION;
			};

			float3 _LightDirection;
			float3 _LightPosition;
			sampler2D _CameraDepthTexture;

			float4 GetShadowPositionHClip(Attributes input)
			{
				float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
				float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

				#if _CASTING_PUNCTUAL_LIGHT_SHADOW
    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
				#else
				float3 lightDirectionWS = _LightDirection;
				#endif

				float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

				#if UNITY_REVERSED_Z
				positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
				#else
    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
				#endif

				return positionCS;
			}
			
			Varyings vert(Attributes input)
			{
				Varyings output;
				
				/*
				// Vertex wave anim
				float3 worldPos = mul(unity_ObjectToWorld, input.positionOS).xyz;

				float vertexAnimWeight = length(worldPos - _WorldSpaceCameraPos);
				vertexAnimWeight = saturate(pow(vertexAnimWeight / 10, 3));

				float waveAnimDetail = 100;
				float maxWaveAmplitude = 0.001 * vertexAnimWeight; // 0.001
				float waveAnimSpeed = 1;

				float3 worldNormal = normalize(mul(unity_ObjectToWorld, float4(input.normalOS, 0)).xyz);
				float theta = acos(worldNormal.z);
				float phi = atan2(input.positionOS.y, input.positionOS.x);
				float waveA = sin(_Time.y * waveAnimSpeed + theta * waveAnimDetail);
				float waveB = sin(_Time.y * waveAnimSpeed + phi * waveAnimDetail);
				float waveVertexAmplitude = (waveA + waveB) * maxWaveAmplitude;
				input.positionOS = input.positionOS + float4(worldNormal, 0) * waveVertexAmplitude;*/

				VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
				
				output.uv = input.texcoord;
				output.positionCS = vertexInput.positionCS;
				output.positionScreen = vertexInput.positionNDC;
				return output;
			}

			half4 frag(Varyings input) : SV_TARGET
			{
				float nonLinearDepth = SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, input.positionScreen);
				float depth = LinearEyeDepth(nonLinearDepth, _ZBufferParams);
				return depth;
			}
			ENDHLSL
		}
	}
}