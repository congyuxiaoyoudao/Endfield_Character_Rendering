using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

// Predefine shader property id here
static class ShaderPropertyId
{
    public static readonly int SkinDiffuse = Shader.PropertyToID("_SkinDiffuse");
    public static readonly int SkinDepth = Shader.PropertyToID("_SkinDepth");
    public static readonly int SkinSSS = Shader.PropertyToID("_SkinSSS");
    public static readonly int SkinSpecular = Shader.PropertyToID("_SkinSpecular");
}

[CreateAssetMenu(menuName = "Rendering/Endfield/Endfield Render Feature")]
public class EndfieldRenderFeature : ScriptableRendererFeature
{
    // public feature settings
    [System.Serializable]
    public class EndfieldRenderSettings
    {
        [Header("Common")]
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingOpaques;

        public LayerMask LayerMask = -1;
    }

    [SerializeField] public EndfieldRenderSettings settings = new EndfieldRenderSettings();
    
 
    // Pass instances
    private SilhouluetteMaskPass m_SilhouluetteMaskPass;

    // Render Targets
    RTHandle m_silhouluetteMaskTexture;
    
    /// <inheritdoc/>
    public override void Create()
    {
        m_SilhouluetteMaskPass = new SilhouluetteMaskPass("Silhouluette Mask Pass", settings.LayerMask);
        // Configures where the render pass should be injected.
        m_SilhouluetteMaskPass.renderPassEvent = settings.renderPassEvent;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_SilhouluetteMaskPass);
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        var descriptor = renderingData.cameraData.cameraTargetDescriptor;
        descriptor.graphicsFormat = UnityEngine.Experimental.Rendering.GraphicsFormat.R16_SFloat;
        descriptor.depthBufferBits = 0;
        descriptor.msaaSamples = 1;
        descriptor.sRGB = false;
        RenderingUtils.ReAllocateIfNeeded(ref m_silhouluetteMaskTexture, descriptor, name: "_SilhouluetteMaskTexture");
        // RenderingUtils.ReAllocateIfNeeded(ref m_skinSSSTexture, descriptor, name: "_SkinSSSTexture");
        //
        // descriptor.graphicsFormat = UnityEngine.Experimental.Rendering.GraphicsFormat.R16_SFloat;
        // RenderingUtils.ReAllocateIfNeeded(ref m_skinSpecularTexture, descriptor, name: "_SkinSpecularTexture");
        //
        // descriptor.depthBufferBits = 24;
        // descriptor.graphicsFormat = UnityEngine.Experimental.Rendering.GraphicsFormat.None;
        m_SilhouluetteMaskPass.Setup(m_silhouluetteMaskTexture);
    }
}


