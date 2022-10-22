Shader "Missnish/MoveUV"
{
    Properties
    {
        [Head(PBR)]
        _Color("Color", Color) = (1.0, 1.0, 1.0)
        _MainTex ("Albedo", 2D) = "white" {}
        _MetallicTex ("Metallic", 2D) = "white" {}
        _Roughness ("Roughness", 2D) = "white" {}
        _NormalTex("Normal", 2D) = "bump"{}
        _NormalIntensity("Normal Intensity", float) = 1.0
        _AOTex("Ambient Occlusion", 2D) = "white"{}
        _AOIntensity("Ambient Occlusion Intensity", Range(0, 1)) = 1.0
        _CubeMap("CubeMap", Cube) = "white"{}
        _CubeMapIntensity("CubeMap Light Intensity", float) = 1.0
        
        [Head(Flow Map)]
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
            #include "UnityLightingCommon.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 pos : SV_POSITION;
                float3 posWS : TEXCOORD1;
                float3 normal : TEXCOORD2;
                float3 tangent : TEXCOORD3;
                float3 binormal : TEXCOORD4;
            };

            float3 _Color;
            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _MetallicTex;
            sampler2D _Roughness;
            sampler2D _NormalTex;
            sampler2D _AOTex;
            samplerCUBE _CubeMap;
            float4 _CubeMap_HDR;
            float _AOIntensity;
            float _CubeMapIntensity;
            float _NormalIntensity;

            sampler2D _FlowMap;
            float _Speed;
            float _Intensity;

            //-----------------------Vertex Shader-----------------------
            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.posWS = mul(unity_ObjectToWorld, v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                o.tangent = normalize(mul(unity_ObjectToWorld, v.tangent).xyz);
                //v.tangent.w：tangent的第四个分量，为了处理不同平台下的兼容性问题
                o.binormal = cross(o.normal, o.tangent) * v.tangent.w;

                return o;
            }

            //-----------------------Custom Function-----------------------
            //法线分布函数
            float NormalDistribution(float NdotH, float roughness)
            {
                float squareRough = roughness * roughness;
                float squareDot = NdotH * NdotH;

                float resultD = squareRough / (UNITY_PI * (squareDot * (squareRough - 1.0) + 1.0) * (squareDot * (squareRough - 1.0) + 1.0));
                return resultD;
            }

            float kDirect(float roughness)
            {
                return ((roughness + 1.0) * (roughness + 1.0)) / 8.0;
            }

            float kIBL(float roughness)
            {
                return roughness * roughness / 2.0;
            }

            //几何遮蔽函数
            float Geometry(float NdotL, float NdotV, float roughness, float k)
            {
                //几何障碍(Geometry Obstruction): 从视角观察方向看过去的微表面互相遮挡
                float viewG = NdotV / lerp(NdotV, 1.0, k);
                //几何阴影(Geometry Shadowing): 从光线反射方向所产生的的微表面互相遮挡
                float lightG = NdotL / lerp(NdotL, 1.0, k);

                float resultG = lightG * viewG;
                return resultG;
            }

            //菲涅尔方程
            float3 Fresnel(float NdotV, float3 F0)
            {
                float3 resultF = F0 + (1.0 - F0) * pow(1.0 - NdotV, 5);
                return resultF;
            }

            //_FlowMap
            float3 FlowMap(sampler2D FlowMap, sampler2D Albedo, float2 uv)
            {
                //float2 uvNew = i.uv + float2(0.0, _Speed * _Time.x);
                //float3 finalRGB = tex2D(_MainTex, uvNew);

                float2 flowDir = tex2D(FlowMap, uv).xy;                  //从FlowMap图中采样RG通道作为偏移向量
                flowDir = (flowDir - 0.5) * 2.0;                            //将采样结果从[0, 1] → [-1, 1]

                //构造周期相同，但有半个相位偏差的函数
                float phase1 = frac(_Time * _Speed);                        //time x - y[0, 1]
                float phase2 = frac(_Time * _Speed + 0.5);                  //time offset x + 0.5 - [0, 1]
                float flowBlend = abs((phase1 - 0.5) * 2.0);                //oscillating(权重值?) - 用作 Mask 混合两次采样的结果

                //构造偏移后的uv
                float2 uvFlow1 = uv + (flowDir * phase1 * _Intensity);
                float2 uvFlow2 = uv + (flowDir * phase2 * _Intensity);
                
                //对MainTex采样两次
                float3 flowRes1 = tex2D(Albedo, uvFlow1);
                float3 flowRes2 = tex2D(Albedo, uvFlow2);

                //将采样结果进行混合
                return lerp(flowRes1, flowRes2, flowBlend);

            }


            //-----------------------Fragment Shader-----------------------
            fixed4 frag (v2f i) : SV_Target
            {

                //数据准备
                float4 normalMap = (tex2D(_NormalTex, i.uv));
                float3 normalData = UnpackNormal(normalMap);          //对法线数据进行解码，将压缩的法线数据从[0,1]恢复成[-1,1]
                normalData.xy *= _NormalIntensity;
                float3x3 TBN = float3x3(i.tangent, i.binormal, i.normal);
                float3 normalDir = normalize(mul(normalData.xyz, TBN));
                float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.posWS.xyz);
                float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
                float3 halfDir = normalize(viewDir + lightDir);
                float3 reflectDir = normalize(reflect(-viewDir, normalDir));

                float3 lightColor = _LightColor0.rgb;
                //float3 baseColor = _Color * tex2D(_MainTex, i.uv);
                float3 baseColor = _Color * pow(FlowMap(_FlowMap, _MainTex, i.uv), 2.2);
                float roughness = tex2D(_Roughness, i.uv);
                float metalness = tex2D(_MetallicTex, i.uv);
                float aoMap = tex2D(_AOTex, i.uv);    
                float ao = lerp(1, aoMap, _AOIntensity);

                float NdotH = max(0.00001, dot(normalDir, halfDir));
                float NdotL = max(0.00001, dot(normalDir, lightDir));       //入射方向即光线方向: ωi - lightDir
                float NdotV = max(0.00001, dot(normalDir, viewDir));        //出射方向即观察方向: ωo - viewDir

                //Direct: Specular
                float NDF = NormalDistribution(NdotH, roughness);
                float3 F0 = lerp(float3(0.04, 0.04, 0.04), baseColor, metalness);
                float3 ks = Fresnel(NdotV, F0);
                float directG = Geometry(NdotL, NdotV, roughness, kDirect(roughness));

                float3 directSpecularBRDF = (NDF * ks * directG) / (4 * NdotL * NdotV);            //镜面反射BRDF
                float3 lightEnergy = lightColor * NdotL;                                           //受光程度

                float3 directSpecular = directSpecularBRDF * lightEnergy * UNITY_PI;               //直接光 - 镜面反射结果

                //Direct: Diffuse
                float kd = (1.0 - ks) * (1.0 - metalness);
                float3 directDiffuseBRDF = kd * baseColor;                                           //漫反射BRDF
                //float3 directDiffuse = directDiffuseBRDF * lightEnergy;
                float3 directDiffuse = pow(directDiffuseBRDF * lightEnergy, 1 / 2.2);                //直接光 - 漫反射结果
                
                //Indirect: Specular - CubeMap Specular; Reflection Probe
                float roughnessSmooth = roughness * (1.7 - 0.7 * roughness);            //粗糙度缓动曲线
                half mipLevel = roughness * 6.0;                                        //6 - PBR中通常取的MipMap层数
                float4 cubeMapSpecularColor = texCUBE(_CubeMap, float4(reflectDir, mipLevel));
                float3 envLightSpecularEnergy = DecodeHDR(cubeMapSpecularColor, _CubeMap_HDR) * _CubeMapIntensity;
                float indirectG = Geometry(NdotL, NdotV, roughness, kIBL(roughness));
                float3 indirectSpecularBRDF = (NDF * ks * indirectG) / (4 * NdotL * NdotV);
                float3 indirectSpecular = indirectSpecularBRDF * envLightSpecularEnergy;

                //Indirect: Diffuse - CubeMap Diffuse; 球谐函数(SH); Light Probe
                float4 cubeMapDiffuseColor = texCUBElod(_CubeMap, float4(normalDir, mipLevel));                     //方法一: 用NormalDir采样CubeMap的Diffuse
                float3 envLightDiffuseEnergy = DecodeHDR(cubeMapDiffuseColor, _CubeMap_HDR) * _CubeMapIntensity;
                //float3 envLightDiffuseEnergySH = ShadeSH9(float4(normalDir, 1.0));                                //方法二: 球谐函数
                float3 indirectDiffuse = pow(kd * baseColor * envLightDiffuseEnergy, 1 / 2.2);

                float3 finalRGB = (directSpecular + directDiffuse + indirectSpecular + indirectDiffuse) * ao;

                return float4(finalRGB, 1.0);
            }
            ENDCG
        }
    }
}
