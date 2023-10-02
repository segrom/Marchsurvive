using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class CameraEffect : MonoBehaviour
{
	EffectManager effectManager;
	[SerializeField] Camera _waterDepthCamera;
	[SerializeField] Shader _depthShader;

	void OnRenderImage(RenderTexture source, RenderTexture target)
	{
		/*Init();

		if (effectManager != null)
		{
			effectManager.HandleEffects(source, target);
		}
		else
		{
			Graphics.Blit(source, target);
		}*/
	}

	private void Awake()
	{
		Init();
	}

	void Init()
	{
		_waterDepthCamera.depthTextureMode = DepthTextureMode.Depth;
		if (effectManager == null)
		{
			effectManager = FindObjectOfType<EffectManager>();
		}
	}

	private void Update()
	{
		_waterDepthCamera.Render();
	}
}