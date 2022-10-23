Shader "Missnish/FlowMap"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _FlowMap ("Flow Map", 2D) = "white"{}
        _Speed ("Flow Speed", float) = 1
        _Intensity ("Flow Intensity", float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _FlowMap;
            float _Speed;
            float _Intensity;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            float3 TexBlend(sampler2D tex, float2 uv1, float2 uv2, float mask)
            {
                float3 blendRes1 = tex2D(tex, uv1);
                float3 blendRes2 = tex2D(tex, uv2);
                return lerp(blendRes1, blendRes2, mask);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                //FlowMap
                //float2 uvNew = i.uv + float2(0.0, _Speed * _Time.x);
                //float3 finalRGB = tex2D(_MainTex, uvNew);
                float2 flowDir = tex2D(_FlowMap, i.uv).xy;                  //从FlowMap图中采样RG通道作为偏移向量
                flowDir = (flowDir - 0.5) * 2.0;                            //将采样结果从[0, 1] → [-1, 1]

                //构造周期相同，但有半个相位偏差的函数
                float phase1 = frac(_Time * _Speed);                        //time x - y[0, 1]
                float phase2 = frac(_Time * _Speed + 0.5);                  //time offset x + 0.5 - [0, 1]
                float flowBlend = abs((phase1 - 0.5) * 2.0);                //oscillating(权重值?) - 用作 Mask 混合两次采样的结果

                //构造偏移后的uv
                float2 uvFlow1 = i.uv + (flowDir * phase1 * _Intensity);
                float2 uvFlow2 = i.uv + (flowDir * phase2 * _Intensity);
                
                //对MainTex采样两次
                //float3 flowRes1 = tex2D(_MainTex, uvFlow1);
                //float3 flowRes2 = tex2D(_MainTex, uvFlow2);

                //将采样结果进行混合
                float3 flowColor =  TexBlend(_MainTex, uvFlow1, uvFlow2, flowBlend);

                return float4(flowColor, 1.0);
            }
            ENDCG
        }
    }
}
