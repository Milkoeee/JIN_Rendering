using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Windows;
using static UnityEditor.Rendering.CameraUI;

public class JINComputeShader : MonoBehaviour
{
    public ComputeShader cs;
    public int space_size = 256;
    float space_size_f = 256.0f;
    [Range(0.0f, 1.0f)]
    public float sparcity_init = 0.5f;
    public bool do_rgb = false;

    RenderTexture img0;
    RenderTexture img1;
    CommandBuffer cmd;

    int kernel_init_id;
    int kernel_init_rgb_id;
    int kernel_loop_id;
    int kernel_loop_rgb_id;
    int input_id = Shader.PropertyToID("Input");
    int output_id = Shader.PropertyToID("Output");
    int texture_size_id = Shader.PropertyToID("TextureSize");
    int unlit_texture_id = Shader.PropertyToID("_UnlitColorMap");
    int sparcity_id = Shader.PropertyToID("Sparcity");
    public bool execute = false;

    int run_idx = 0;

    void CreateOutputRT(int size)
    {
        img0 = new RenderTexture(space_size, space_size, 0, GraphicsFormat.R16G16B16A16_UNorm);
        img0 .enableRandomWrite = true;
        img0 .wrapMode = TextureWrapMode.Clamp;
        img0 .filterMode = FilterMode.Point;
        img0 .Create();
        img1 = new RenderTexture(space_size, space_size, 0, GraphicsFormat.R16G16B16A16_UNorm);
        img1 .enableRandomWrite = true;
        img1 .wrapMode = TextureWrapMode.Clamp;
        img1 .filterMode = FilterMode.Point;
        img1 .Create();
    }

    void ExecuteInit()
    {
        if (cmd == null)
        {
            cmd = new CommandBuffer();
        }

        int kernel_id;
        if (do_rgb)
            kernel_id = kernel_init_rgb_id;
        else
            kernel_id = kernel_init_id;

        cmd.SetComputeTextureParam(cs, kernel_id, output_id, img0);
        cmd.SetComputeFloatParams(cs, texture_size_id, space_size_f, space_size_f);
        cmd.SetComputeFloatParam(cs, sparcity_id, sparcity_init);

        cmd.DispatchCompute(cs, kernel_id,
                            (space_size + 8 - 1) / 8,
                            (space_size + 8 - 1) / 8,
                            1);

        Graphics.ExecuteCommandBuffer(cmd);

        Renderer curRenderer = gameObject.GetComponent<Renderer>();
        curRenderer.sharedMaterial.SetTexture(unlit_texture_id, img0);

        run_idx = 0;
    }

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        CreateOutputRT(space_size);
        if (cs != null)
        {
            kernel_init_id = cs.FindKernel("CSMainInit");
            kernel_init_rgb_id = cs.FindKernel("CSMainInitRGB");
            kernel_loop_id = cs.FindKernel("CSMainLoop");
            kernel_loop_rgb_id = cs.FindKernel("CSMainLoopRGB");
        }

        ExecuteInit();
    }

    public void OnValidate()
    {
        space_size_f = (float)space_size;

        CreateOutputRT(space_size);
        ExecuteInit();
    }

    // Update is called once per frame
    void Update()
    {
        RenderTexture input;
        RenderTexture output;
        if (run_idx % 2 == 0)
        {
            input = img0;
            output = img1;
        }
        else
        {
            input = img1;
            output = img0;
        }

        int kernel_id;
        if (do_rgb)
            kernel_id = kernel_loop_rgb_id;
        else
            kernel_id = kernel_loop_id;

        cmd.SetComputeTextureParam(cs, kernel_id, input_id, input);
        cmd.SetComputeTextureParam(cs, kernel_id, output_id, output);
        cmd.SetComputeFloatParams(cs, texture_size_id, space_size_f, space_size_f);

        cmd.DispatchCompute(cs, kernel_id,
                            (space_size + 8 - 1) / 8,
                            (space_size + 8 - 1) / 8,
                            1);

        Graphics.ExecuteCommandBuffer(cmd);

        Renderer curRenderer = gameObject.GetComponent<Renderer>();
        curRenderer.sharedMaterial.SetTexture(unlit_texture_id, output);

        ++run_idx;
    }
}
