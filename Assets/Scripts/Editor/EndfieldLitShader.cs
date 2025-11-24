using System;
using UnityEditor;
using UnityEngine;
using UnityEditor.Rendering.Universal.ShaderGUI;
using UnityEditor.Rendering;

namespace Endfield.Rendering.Editor
{
    partial class EndfieldLitShader : BaseShaderGUI
    {
        static readonly string[] workflowModeNames = Enum.GetNames(typeof(LitGUI.WorkflowMode));

        private LitGUI.LitProperties litProperties;
        private LitDetailGUI.LitProperties litDetailProperties;
        private EndfieldProperties endfieldProperties;
        
        public override void FillAdditionalFoldouts(MaterialHeaderScopeList materialScopesList)
        {
            materialScopesList.RegisterHeaderScope(LitDetailGUI.Styles.detailInputs, Expandable.Details, _ => LitDetailGUI.DoDetailArea(litDetailProperties, materialEditor));
        }

        // collect properties from the material properties
        public override void FindProperties(MaterialProperty[] properties)
        {
            base.FindProperties(properties);
            litProperties = new LitGUI.LitProperties(properties);
            litDetailProperties = new LitDetailGUI.LitProperties(properties);
            endfieldProperties = new EndfieldProperties(properties);
        }

        // material changed check
        public override void ValidateMaterial(Material material)
        {
            SetMaterialKeywords(material, LitGUI.SetMaterialKeywords, LitDetailGUI.SetMaterialKeywords);
        }

        // material main surface options
        public override void DrawSurfaceOptions(Material material)
        {
            // Use default labelWidth
            EditorGUIUtility.labelWidth = 0f;

            if (litProperties.workflowMode != null)
                DoPopup(LitGUI.Styles.workflowModeText, litProperties.workflowMode, workflowModeNames);

            base.DrawSurfaceOptions(material);
            // DoPopup(new GUIContent("RenderType"), endfieldProperties.renderType, endfieldRenderTypeNames);
            materialEditor.ShaderProperty(endfieldProperties.renderType, "Render Type");
            // Debug.Log(endfieldProperties.renderType.intValue);
        }

        // material main surface inputs
        public override void DrawSurfaceInputs(Material material)
        {
            base.DrawSurfaceInputs(material);
            LitGUI.Inputs(litProperties, materialEditor, material);
            DrawEmissionProperties(material, true);
            DrawTileOffset(materialEditor, baseMapProp);
            
            materialEditor.TexturePropertySingleLine(new GUIContent("DiffuseRampMap"), endfieldProperties.diffuseRampMap);
            materialEditor.TexturePropertySingleLine(new GUIContent("SpecularRampMap"), endfieldProperties.specularRampMap);

            float renderTypeValue = endfieldProperties.renderType.floatValue;
            if (renderTypeValue == (float)RenderType.Cloth || renderTypeValue == (float)RenderType.Hair)
            {
                if (renderTypeValue == (float)RenderType.Cloth)
                {
                    materialEditor.TexturePropertySingleLine(new GUIContent("EmissionMaskMap"),
                        endfieldProperties.emissionMaskMap);
                    materialEditor.ColorProperty(endfieldProperties.flameColor, "FlameColor");
                    materialEditor.TexturePropertySingleLine(new GUIContent("FlowMap"), endfieldProperties.flowMap);
                    materialEditor.TexturePropertySingleLine(new GUIContent("FlameTex"), endfieldProperties.flameTex);
                }
                materialEditor.TexturePropertySingleLine(new GUIContent("P"), endfieldProperties.pMaskMap);
            }

            if (renderTypeValue == (float)RenderType.Skin)
            {
                materialEditor.FloatProperty(endfieldProperties.sssRadius, "SSS Radius");
                materialEditor.ColorProperty(endfieldProperties.sssColor, "SSS Color");
                materialEditor.FloatProperty(endfieldProperties.sssValue, "SSS Value");
            }

            if (renderTypeValue == (float)RenderType.Face)
            {
                materialEditor.ColorProperty(endfieldProperties.faceSideColor, "Face Side Color");
                materialEditor.TexturePropertySingleLine(new GUIContent("SDF"), endfieldProperties.sdfMap);
                materialEditor.TexturePropertySingleLine(new GUIContent("Custom Mask"), endfieldProperties.customMask);
                materialEditor.TexturePropertySingleLine(new GUIContent("Lip HL Mask"),
                    endfieldProperties.lipHighlightMask);
            }
        }

        // material main advanced options
        public override void DrawAdvancedOptions(Material material)
        {
            if (litProperties.reflections != null && litProperties.highlights != null)
            {
                materialEditor.ShaderProperty(litProperties.highlights, LitGUI.Styles.highlightsText);
                materialEditor.ShaderProperty(litProperties.reflections, LitGUI.Styles.reflectionsText);
            }

            base.DrawAdvancedOptions(material);
            
            materialEditor.RangeProperty(endfieldProperties.directLightingIntensity,"Direct Lighting Intensity");
            materialEditor.RangeProperty(endfieldProperties.giIntensity,"Global Illumination Intensity");
            
            float renderTypeValue = endfieldProperties.renderType.floatValue;
            if (renderTypeValue == (float)RenderType.Face)
            {
                materialEditor.RangeProperty(endfieldProperties.sdfShadowCenter,"SDF Shadow Center");
                materialEditor.RangeProperty(endfieldProperties.sdfShadowSharpness, "SDF Shadow Sharpness");
            }
            
            materialEditor.RangeProperty(endfieldProperties.sceneShadowCenter, "Scene Shadow Center");
            materialEditor.RangeProperty(endfieldProperties.sceneShadowSharpness, "Scene Shadow Sharpness");
            materialEditor.RangeProperty(endfieldProperties.halfLambertShadowCenter, "Half Lambert Shadow Center");
            materialEditor.RangeProperty(endfieldProperties.halfLambertShadowSharpness, "Half Lambert Shadow Sharpness");
            
            materialEditor.ColorProperty(endfieldProperties.rimColor, "Rim Color");
            materialEditor.FloatProperty(endfieldProperties.rimWidth, "Rim Width");
            materialEditor.FloatProperty(endfieldProperties.rimIntensity, "Rim Intensity");
            materialEditor.ColorProperty(endfieldProperties.anisotropicHLColor, "Anisotropic HL Color");
            materialEditor.FloatProperty(endfieldProperties.anisotropicHLIntensity, "Anisotropic HL Intensity");

            materialEditor.ShaderProperty(endfieldProperties.outline, "Outline");
            if (endfieldProperties.outline.floatValue == 1)
            {
                materialEditor.TexturePropertySingleLine(new GUIContent("ST"), endfieldProperties.stMap);
                materialEditor.ColorProperty(endfieldProperties.outlineColor, "Outline Color");
                materialEditor.FloatProperty(endfieldProperties.outlineWidth, "Outline Width");
                materialEditor.FloatProperty(endfieldProperties.outlineClipSpaceZOffset, "Outline Clip Space Z Offset");
            }
        }

        public override void AssignNewShaderToMaterial(Material material, Shader oldShader, Shader newShader)
        {
            if (material == null)
                throw new ArgumentNullException("material");

            // _Emission property is lost after assigning Standard shader to the material
            // thus transfer it before assigning the new shader
            if (material.HasProperty("_Emission"))
            {
                material.SetColor("_EmissionColor", material.GetColor("_Emission"));
            }

            base.AssignNewShaderToMaterial(material, oldShader, newShader);

            if (oldShader == null || !oldShader.name.Contains("Legacy Shaders/"))
            {
                SetupMaterialBlendMode(material);
                return;
            }

            SurfaceType surfaceType = SurfaceType.Opaque;
            BlendMode blendMode = BlendMode.Alpha;
            if (oldShader.name.Contains("/Transparent/Cutout/"))
            {
                surfaceType = SurfaceType.Opaque;
                material.SetFloat("_AlphaClip", 1);
            }
            else if (oldShader.name.Contains("/Transparent/"))
            {
                // NOTE: legacy shaders did not provide physically based transparency
                // therefore Fade mode
                surfaceType = SurfaceType.Transparent;
                blendMode = BlendMode.Alpha;
            }
            material.SetFloat("_Blend", (float)blendMode);

            material.SetFloat("_Surface", (float)surfaceType);
            if (surfaceType == SurfaceType.Opaque)
            {
                material.DisableKeyword("_SURFACE_TYPE_TRANSPARENT");
            }
            else
            {
                material.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
            }

            if (oldShader.name.Equals("Standard (Specular setup)"))
            {
                material.SetFloat("_WorkflowMode", (float)LitGUI.WorkflowMode.Specular);
                Texture texture = material.GetTexture("_SpecGlossMap");
                if (texture != null)
                    material.SetTexture("_MetallicSpecGlossMap", texture);
            }
            else
            {
                material.SetFloat("_WorkflowMode", (float)LitGUI.WorkflowMode.Metallic);
                Texture texture = material.GetTexture("_MetallicGlossMap");
                if (texture != null)
                    material.SetTexture("_MetallicSpecGlossMap", texture);
            }
        }
    }
}
