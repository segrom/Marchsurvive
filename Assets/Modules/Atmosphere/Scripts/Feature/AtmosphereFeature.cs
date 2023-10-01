using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace Modules.Water.Scripts
{
    public class AtmosphereFeature : ScriptableRendererFeature
    {
        
        private AtmospherePass _atmospherePass;
        
        public override void Create()
        {
            _atmospherePass = new AtmospherePass();
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(_atmospherePass);
        }
        
        
    }
}