using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.HighDefinition;

[Serializable]
[VolumeComponentMenu("Post-processing/Custom/SSGI")]
public sealed class SSGIPostProcessing : CustomPostProcessVolumeComponent, IPostProcessComponent
{
    public ClampedFloatParameter IndirectIntensity = new ClampedFloatParameter(0f, 0f, 512f);
    public ClampedIntParameter SampleCount = new ClampedIntParameter (8, 8, 128);
    public ClampedFloatParameter NoiseAmount = new ClampedFloatParameter(2, 0, 5);
    public ClampedIntParameter DebugMode = new ClampedIntParameter(0, 0, 2);
    public BoolParameter Noise = new BoolParameter(true);

    Material m_Material;

    public bool IsActive() => m_Material != null && IndirectIntensity.value > 0f;

    public override CustomPostProcessInjectionPoint injectionPoint => CustomPostProcessInjectionPoint.BeforePostProcess;

    public override void Setup()
    {
        if (Shader.Find("Hidden/Shader/SSGI") != null)
            m_Material = new Material(Shader.Find("Hidden/Shader/SSGI"));
    }

    public override void Render(CommandBuffer cmd, HDCamera camera, RTHandle source, RTHandle destination)
    {
        if (m_Material == null)
            return;

        var invProjectionMatrix = GL.GetGPUProjectionMatrix(camera.camera.projectionMatrix, false).inverse;

        m_Material.SetFloat("_IndirectAmount", IndirectIntensity.value);
        m_Material.SetFloat("_NoiseAmount", NoiseAmount.value);
        m_Material.SetInt("_SamplesCount", SampleCount.value);
        m_Material.SetInt("_Noise", Noise.value ? 1 : 0);
        m_Material.SetInt("_Debug", DebugMode.value);
        //m_Material.SetMatrix("_InverseProjectionMatrix", invProjectionMatrix);

        m_Material.SetTexture("_InputTexture", source);

        HDUtils.DrawFullScreen(cmd, m_Material, destination);
    }

    public override void Cleanup() => CoreUtils.Destroy(m_Material);
}
