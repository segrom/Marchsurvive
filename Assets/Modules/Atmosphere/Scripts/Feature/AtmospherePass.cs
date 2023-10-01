using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Modules.Water.Scripts
{
    public class AtmospherePass: ScriptableRenderPass
    {
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(name: "WaterPass");
        }
    }
}