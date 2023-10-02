using System;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Modules.Water.Scripts
{
    public class AtmosphereFeature : ScriptableRendererFeature
    {
        
        class AtmospherePass: ScriptableRenderPass
        {
            private AtmosphereSettings _settings;
            private Material _atmosphereMat;
            private RTHandle _cameraColorTargetHandle;
            RenderTargetIdentifier colorBuffer;
            int temporaryBufferID = Shader.PropertyToID("_TemporaryBuffer");

            const string ProfilerTag = "Template Pass";
            
            public AtmospherePass(AtmosphereSettings settings)
            {
                _settings = settings;
                _atmosphereMat = new Material(_settings.shader);
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                // Grab the camera target descriptor. We will use this when creating a temporary render texture.
                RenderTextureDescriptor descriptor = renderingData.cameraData.cameraTargetDescriptor;
        
                // Enable these if your pass requires access to the CameraDepthTexture or the CameraNormalsTexture.
                ConfigureInput(ScriptableRenderPassInput.Depth);
        
                // Grab the color buffer from the renderer camera color target.
                colorBuffer = renderingData.cameraData.renderer.cameraColorTargetHandle;
            }

            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                if (cmd == null) throw new ArgumentNullException("cmd");
                // Since we created a temporary render texture in OnCameraSetup, we need to release the memory here to avoid a leak.
                cmd.ReleaseTemporaryRT(temporaryBufferID);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                if(!Application.isPlaying) return;
                CommandBuffer cmd = CommandBufferPool.Get(name: "AtmospherePass");
            
                _settings.SetProperties(_atmosphereMat);

                using (new ProfilingScope(cmd, new ProfilingSampler(ProfilerTag)))
                {

                    cmd.Blit(colorBuffer, colorBuffer, _atmosphereMat);
                }

                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }
        
        public AtmosphereSettings atmosphereSettings;
        private AtmospherePass _atmospherePass;
        
        public override void Create()
        {
            _atmospherePass = new AtmospherePass(atmosphereSettings);
            _atmospherePass.renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if(_atmospherePass is null)
            {
                Debug.LogWarning("AtmospherePass is null");
                return;
            }
            renderer.EnqueuePass(_atmospherePass);
        }
        
        
    }
}