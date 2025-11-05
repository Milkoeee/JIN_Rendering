using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Windows;
using static UnityEditor.Rendering.CameraUI;

public class BlurComputeShader : MonoBehaviour
{
    public Texture2D Input;
    public ComputeShader cs;
    [Range(1, 64)]
    public int radius = 1;

    int wave_size = 8;



    int width;
    int height;

    RenderTexture Output;
    CommandBuffer cmd;

    int kernel_id;
    int input_id = Shader.PropertyToID("Input");
    int radius_id = Shader.PropertyToID("Radius");
    int output_id = Shader.PropertyToID("Output");
    int texture_size_id = Shader.PropertyToID("TextureSize");
    int unlit_texture_id = Shader.PropertyToID("_UnlitColorMap");

    void CreateOutputRT(Texture2D input_img)
    {
        Output = new RenderTexture(input_img.width, input_img.height, 0, GraphicsFormat.R16G16B16A16_UNorm);
        Output.enableRandomWrite = true;
        Output.wrapMode = TextureWrapMode.Clamp;
        Output.filterMode = FilterMode.Point;
        Output.Create();
    }

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        if (Input != null)
        {
            cmd = new CommandBuffer();

            width = Input.width;
            height =  Input.height;

            CreateOutputRT(Input);
        }

        if (cs != null)
        {
            kernel_id = cs.FindKernel("CSMain");
        }

    }

    public void OnValidate()
    {
        if (Output == null)
        {
            CreateOutputRT(Input);
        }
        if (cmd == null)
        {
            cmd = new CommandBuffer();
        }
        if (Input != null && cs != null && Output!=null)
        {
            width = Input.width;
            height = Input.height;
            cmd.SetComputeTextureParam(cs, kernel_id, input_id, Input);
            cmd.SetComputeTextureParam(cs, kernel_id, output_id, Output);
            cmd.SetComputeFloatParam(cs, radius_id, radius);
            cmd.SetComputeFloatParams(cs, texture_size_id, width, height);

            cmd.DispatchCompute(cs, kernel_id,
                                (width + 8 - 1) / 8,
                                height,
                                1);

            Graphics.ExecuteCommandBuffer(cmd);

            Renderer curRenderer = gameObject.GetComponent<Renderer>();
            curRenderer.sharedMaterial.SetTexture(unlit_texture_id, Output);
        }
    }
}
