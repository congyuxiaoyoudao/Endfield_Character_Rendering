using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode] 
public class SetSDFProperty : MonoBehaviour
{
    public Material EndfieldFaceMaterial;
    public Material EndfieldEyeMatrial;
    public Material EndfieldBrowMaterial;
    public GameObject HeadCenter;
    public GameObject HeadFront;
    public GameObject HeadRight;
    
    void Start()
    {
    }

    // We calculate the sdf parameters here so that do not need do it in shader
    void UpdateSDFParameters()
    {
        Vector3 headCenter = HeadCenter.transform.position;
        Vector3 headForward = Vector3.Normalize(HeadFront.transform.position - headCenter);
        Vector3 headRight = Vector3.Normalize(HeadRight.transform.position - headCenter);
        
        EndfieldFaceMaterial.SetVector("_HeadRight",headRight);
        EndfieldFaceMaterial.SetVector("_HeadCenter", headCenter);
        EndfieldFaceMaterial.SetVector("_HeadForward",headForward);
        EndfieldBrowMaterial.SetVector("_HeadForward",headForward);
        
        Vector3 headUp = Vector3.Cross(headForward, headRight);
        Vector3 mainLightDir = -RenderSettings.sun.transform.forward;
        
        Vector3 mainLightDirProj = mainLightDir - Vector3.Dot(mainLightDir, headUp) * headUp;
        float flipThreshold = Vector3.Dot(mainLightDirProj, headRight);
        // Debug.Log("Flip Threshold: " + flipThreshold);
        EndfieldFaceMaterial.SetFloat("_FlipSDFThreshold",flipThreshold);
        
        // TODO: normalized angle threshold
        Vector3 headBack = -headForward;
        float y = Vector3.Dot(mainLightDirProj, headRight);
        float x = Vector3.Dot(mainLightDirProj, headBack);
        float normalizedAngle = Mathf.Atan2(y, x) / 3.14f; // -1 to 1
        float angleThreshold = normalizedAngle> 0.0f ? 1.0f - normalizedAngle : normalizedAngle + 1.0f;
        // Debug.Log("Angle Threshold: " + angleThreshold);
        EndfieldFaceMaterial.SetFloat("_AngleThreshold",angleThreshold);
        EndfieldEyeMatrial.SetFloat("_AngleThreshold",angleThreshold);
        EndfieldEyeMatrial.SetVector("_HeadForward",headForward);
    }

    // Update is called once per frame
    void Update()
    {
        UpdateSDFParameters();
    }
}
