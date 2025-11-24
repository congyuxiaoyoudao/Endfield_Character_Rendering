using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class CharacterRotate : MonoBehaviour
{
    public bool enableRotation = false;
    public float rotationSpeed = 100;
    // Update is called once per frame
    void Update()
    {
        if (enableRotation)
            this.transform.Rotate(Vector3.up * Time.deltaTime * rotationSpeed);
    }
}