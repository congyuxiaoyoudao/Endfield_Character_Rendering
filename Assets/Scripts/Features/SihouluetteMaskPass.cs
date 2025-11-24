using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SilhouluetteMaskPass : ScriptableRenderPass
{
    private string m_ProfilerTag;
    private ProfilingSampler m_ProfilingSampler;
    private ShaderTagId m_ShaderTagId;
    private FilteringSettings m_FilteringSettings;

    // Render target configures
    private RTHandle _maskTexture;

    
    // Ctor.
    public SilhouluetteMaskPass(string profilerTag, LayerMask layerMask)
    {
        m_ProfilerTag = profilerTag;
        m_ProfilingSampler = new (m_ProfilerTag);
        m_ShaderTagId = new ShaderTagId("SilhouluetteMask");
        m_FilteringSettings = new FilteringSettings(RenderQueueRange.all, layerMask);
    }

    public void Setup(RTHandle maskTexture)
    {
        _maskTexture = maskTexture;
    }
    
    // initialize resources
    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        Debug.Assert(_maskTexture != null, "MaskTexture not initialized");
     
        ConfigureTarget(_maskTexture);
        ConfigureClear(ClearFlag.All, Color.clear); 
    }

    // Dispatch pass
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        // Get command buffer
        CommandBuffer cmd = CommandBufferPool.Get(m_ProfilerTag);
        using (new ProfilingScope(cmd, m_ProfilingSampler))
        {
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            var drawSettings = CreateDrawingSettings(m_ShaderTagId, ref renderingData, SortingCriteria.CommonOpaque);
            context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref m_FilteringSettings);
        
            cmd.SetGlobalTexture("_SilhouluetteMask", _maskTexture);
        }
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
    
    public override void OnCameraCleanup(CommandBuffer cmd)
    {
    }
}