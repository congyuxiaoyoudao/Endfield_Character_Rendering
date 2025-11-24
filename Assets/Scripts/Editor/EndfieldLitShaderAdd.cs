using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using UnityEditor;
using UnityEngine;

namespace Endfield.Rendering.Editor
{
    partial class EndfieldLitShader : BaseShaderGUI
    {
        public enum RenderType
        {
            /// <summary>
            /// Render as cloth.
            /// </summary>
            Cloth = 0,

            /// <summary>
            /// Render as skin.
            /// </summary>
            Skin = 1,
            
            /// <summary>
            /// Render as face.
            /// </summary>
            Face = 2,
            
            /// <summary>
            /// Render as hair.
            /// </summary>
            Hair = 3
        }
        
        private struct EndfieldProperties
        {
            public MaterialProperty renderType;
            public MaterialProperty diffuseRampMap;
            public MaterialProperty specularRampMap;
            public MaterialProperty pMaskMap;
            
            public MaterialProperty emissionMaskMap;
            public MaterialProperty flameColor;
            public MaterialProperty flowMap;
            public MaterialProperty flameTex;
            
            // skin
            public MaterialProperty sssRadius;
            public MaterialProperty sssColor;
            public MaterialProperty sssValue;
            
            // face
            public MaterialProperty faceSideColor;
            public MaterialProperty sdfMap;
            public MaterialProperty customMask;
            public MaterialProperty lipHighlightMask;
            public MaterialProperty sdfShadowSharpness;
            public MaterialProperty sdfShadowCenter;
            
            // rim
            public MaterialProperty rimWidth;
            public MaterialProperty rimIntensity;
            public MaterialProperty rimColor;
            
            // hair
            public MaterialProperty anisotropicHLColor;
            public MaterialProperty anisotropicHLIntensity;
            
            // outline
            public MaterialProperty outline;
            public MaterialProperty stMap;
            public MaterialProperty outlineColor;
            public MaterialProperty outlineWidth;
            public MaterialProperty outlineClipSpaceZOffset;
            
            // shadow controller
            public MaterialProperty sceneShadowCenter;
            public MaterialProperty sceneShadowSharpness;
            public MaterialProperty halfLambertShadowCenter;
            public MaterialProperty halfLambertShadowSharpness;
            
            // global lightness controller
            public MaterialProperty directLightingIntensity;
            public MaterialProperty giIntensity;

            public EndfieldProperties(MaterialProperty[] properties)
            {
                renderType = FindProperty("_RenderType", properties, false);
                diffuseRampMap = FindProperty("_DiffuseRampMap", properties, false);
                specularRampMap = FindProperty("_SpecularRampMap", properties, false);
                pMaskMap = FindProperty("_PMaskMap", properties, false);
                
                emissionMaskMap = FindProperty("_EmissionMask", properties, false);
                flameColor = FindProperty("_FlameColor", properties, false);
                flowMap = FindProperty("_FlowMap", properties, false);
                flameTex = FindProperty("_FlameTex", properties, false);
                
                // skin
                sssRadius = FindProperty("_SSS_Radius", properties, false);
                sssColor = FindProperty("_SSS_Color", properties, false);
                sssValue = FindProperty("_SSS_Value", properties, false);
                
                // face
                faceSideColor = FindProperty("_FaceSideColor", properties, false);
                sdfMap = FindProperty("_SDFMap", properties, false);
                customMask = FindProperty("_CustomMask", properties, false);
                lipHighlightMask = FindProperty("_LipHighlightMask", properties, false);
                sdfShadowSharpness = FindProperty("_SDFSharpness", properties, false);
                sdfShadowCenter = FindProperty("_SDFShadowCenter", properties, false);
                
                // rim
                rimWidth = FindProperty("_RimWidth", properties, false);
                rimIntensity = FindProperty("_RimIntensity", properties, false);
                rimColor = FindProperty("_RimColor", properties, false);
                
                // hair
                anisotropicHLColor = FindProperty("_AnisotropicHLColor", properties, false);
                anisotropicHLIntensity = FindProperty("_AnisotropicHLIntensity", properties, false);
                
                // outline
                outline = FindProperty("_Outline", properties, false);
                stMap = FindProperty("_ST", properties, false);
                outlineColor = FindProperty("_OutlineColor", properties, false);
                outlineWidth = FindProperty("_OutlineWidth", properties, false);
                outlineClipSpaceZOffset = FindProperty("_OutlineClipSpaceZOffset", properties, false);
                
                // shadow controller
                sceneShadowCenter = FindProperty("_SceneShadowCenter", properties, false);
                sceneShadowSharpness = FindProperty("_SceneShadowSharpness", properties, false);
                halfLambertShadowCenter = FindProperty("_HalfLambertShadowCenter", properties, false);
                halfLambertShadowSharpness = FindProperty("_HalfLambertShadowSharpness", properties, false);
                
                directLightingIntensity = FindProperty("_DirectLightingIntensity", properties, false);
                giIntensity = FindProperty("_GIIntensity", properties, false);
            }
        }

        // internal class SingleLineDrawer : MaterialPropertyDrawer
        // {
        //     public override void OnGUI(Rect position, MaterialProperty prop, GUIContent label, MaterialEditor editor)
        //     {
        //         editor.TexturePropertySingleLine(label, prop);
        //     }
        //     public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
        //     {
        //         return 0;
        //     }
        // }

        // internal class FoldoutDrawer : MaterialPropertyDrawer
        // {
        //     bool showPosition;
        //     public override void OnGUI(Rect position, MaterialProperty prop, string label, MaterialEditor editor)
        //     {
        //         showPosition = EditorGUILayout.Foldout(showPosition, label);
        //         prop.floatValue = Convert.ToSingle(showPosition);
        //     }
        //     public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
        //     {
        //         return 0;
        //     }
        // }
     
        // static Dictionary<string, MaterialProperty> s_MaterialProperty = new Dictionary<string, MaterialProperty>();
        // static List<MaterialData> s_List = new List<MaterialData>();
        // public override void OnGUI(MaterialEditor materialEditorIn, MaterialProperty[] properties)
        // {
        //     base.OnGUI(materialEditorIn, properties);
        //
        //
        //     EditorGUILayout.Space();
        //
        //     Shader shader = (materialEditor.target as Material).shader;
        //     s_List.Clear();
        //     s_MaterialProperty.Clear();
        //     for (int i = 0; i < properties.Length; i++)
        //     {
        //         var propertie = properties[i];
        //         var attributes = shader.GetPropertyAttributes(i);
        //         foreach (var item in attributes)
        //         {
        //             if (item.Contains("ext"))
        //             {
        //                 if (!s_MaterialProperty.ContainsKey(propertie.name))
        //                 {
        //                     s_MaterialProperty[propertie.name] = propertie;
        //                     s_List.Add(new MaterialData() { prop = propertie, indentLevel = false });
        //                     
        //                 }
        //             }
        //             else if (item.Contains("Toggle"))
        //             {
        //                 //根据Toggle标签每帧启动宏
        //                 if (s_MaterialProperty.TryGetValue(propertie.name, out var __))
        //                 {
        //                     if (propertie.type == MaterialProperty.PropType.Float)
        //                     {
        //                         string keyword = "";
        //                         Match match = Regex.Match(item, @"(\w+)\s*\((.*)\)");
        //                         if (match.Success)
        //                             keyword = match.Groups[2].Value.Trim();
        //                         if(string.IsNullOrEmpty(keyword))
        //                             keyword = propertie.name.ToUpperInvariant() + "_ON";
        //                         foreach (Material material in propertie.targets)
        //                         {
        //                             if (propertie.floatValue == 1.0f)
        //                                 material.EnableKeyword(keyword);
        //                             else
        //                                 material.DisableKeyword(keyword);
        //                         }
        //                     }
        //                 }
        //             }
        //             else if (item.StartsWith("if"))
        //             {
        //                 Match match = Regex.Match(item, @"(\w+)\s*\((.*)\)");
        //                 if (match.Success)
        //                 {
        //                     var name = match.Groups[2].Value.Trim();
        //                     if (s_MaterialProperty.TryGetValue(name, out var a))
        //                     {
        //                         if (a.floatValue == 0f)
        //                         {
        //                             //如果有if标签，并且Foldout没有展开不进行绘制
        //                             s_List.RemoveAt(s_List.Count - 1);
        //                         }
        //                         else
        //                             s_List[s_List.Count - 1].indentLevel = true;
        //                     }
        //                 }
        //             }
        //         }
        //     }
        //     PropertiesDefaultGUI(materialEditor, s_List);
        // }
        //
        // public class MaterialData
        // {
        //     public MaterialProperty prop;
        //     public bool indentLevel = false;
        // }
        // public void PropertiesDefaultGUI(MaterialEditor materialEditor, List<MaterialData> props)
        // {
        //     for (int i = 0; i < props.Count; i++)
        //     {
        //         MaterialProperty prop = props[i].prop;
        //         bool indentLevel = props[i].indentLevel;
        //         if ((prop.flags & (MaterialProperty.PropFlags.HideInInspector | MaterialProperty.PropFlags.PerRendererData)) == MaterialProperty.PropFlags.None)
        //         {
        //             float propertyHeight = materialEditor.GetPropertyHeight(prop, prop.displayName);
        //             Rect controlRect = EditorGUILayout.GetControlRect(true, propertyHeight, EditorStyles.layerMaskField);
        //             if (indentLevel) EditorGUI.indentLevel++;
        //             materialEditor.ShaderProperty(controlRect, prop, prop.displayName);
        //             if (indentLevel) EditorGUI.indentLevel--;
        //         }
        //     }
        // }
    }
}
