Shader "URP/JadeBSSRDF"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor ("Base Color", Color) = (1,1,1,1)
        _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Range(0, 2.0)) = 1.0
        _AOMap ("Ambient Occlusion", 2D) = "white" {}
        _AOStrength("Ambient Occlusion Strength", Range(0.0, 1.0)) = 1.0
        _ThicknessMap ("Thickness Map", 2D) = "white" {}
        _ThicknessScale ("Thickness Scale", Range(0.0, 1.0)) = 1.0
        _Smoothness ("Smoothness", Range(0.0, 1.0)) = 0.8
        _Metallic ("Metallic", Range(0.0, 1.0)) = 0.0
        
        [Header(Subsurface Scattering)]
        _SubsurfaceColor ("Subsurface Color", Color) = (0.5, 0.8, 0.4, 1)
        _SubsurfaceRadius ("Scattering Radius", Range(0.1, 5.0)) = 2.0
        _SubsurfacePower ("Subsurface Power", Range(0.1, 10.0)) = 3.0
        _SubsurfaceDistortion ("Subsurface Distortion", Range(0.0, 1.0)) = 0.2
        
        [Header(Transmission)]
        _TransmissionStrength ("Transmission Strength", Range(0.0, 2.0)) = 1.0
        _TransmissionDistortion ("Transmission Distortion", Range(0.0, 1.0)) = 0.1
        
        [Header(Jade Properties)]
        _InnerGlow ("Inner Glow", Range(0.0, 2.0)) = 0.5
        _EdgeGlow ("EdgeGlow", Range(0.0, 5.0)) = 1.0
        _Translucency ("Translucency", Range(0.0, 1.0)) = 0.6
    }

    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque" 
            "RenderPipeline" = "UniversalPipeline" 
            "Queue" = "Geometry"
        }

        // Forward Pass
        Pass
        {
            Name "ForwardLit"
            Tags {"LightMode" = "UniversalForward"}
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            // 添加必要的变体
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half _BumpScale;
                float _AOStrength;
                float _ThicknessScale;
                half _Smoothness;
                half _Metallic;
                half4 _SubsurfaceColor;
                half _SubsurfaceRadius;
                half _SubsurfacePower;
                half _SubsurfaceDistortion;
                half _TransmissionStrength;
                half _TransmissionDistortion;
                half _InnerGlow;
                half _EdgeGlow;
                half _Translucency;
            CBUFFER_END

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
            TEXTURE2D(_AOMap); SAMPLER(sampler_AOMap);
            TEXTURE2D(_ThicknessMap); SAMPLER(sampler_ThicknessMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 texcoord : TEXCOORD0;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float4 tangentWS : TEXCOORD3;
                float3 viewDirWS : TEXCOORD4;
                float4 shadowCoord : TEXCOORD5;
                float4 positionCS : SV_POSITION;
            };

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                
                output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
                output.positionWS = vertexInput.positionWS;
                output.positionCS = vertexInput.positionCS;
                output.normalWS = normalInput.normalWS;
                output.tangentWS = half4(normalInput.tangentWS.xyz, input.tangentOS.w * GetOddNegativeScale());
                output.viewDirWS = GetWorldSpaceViewDir(vertexInput.positionWS);
                output.shadowCoord = GetShadowCoord(vertexInput);
                
                return output;
            }

            half3 SubsurfaceScattering(half3 lightDir, half3 viewDir, half3 normal, half3 thickness, half3 lightColor)
            {
                half3 backLightDir = lightDir + normal * _SubsurfaceDistortion;
                half backScatter = saturate(dot(-viewDir, normalize(backLightDir)));
                backScatter = pow(backScatter, _SubsurfacePower) * _SubsurfaceRadius;
                return _SubsurfaceColor.rgb * backScatter * thickness * lightColor;
            }

            half3 Transmission(half3 lightDir, half3 viewDir, half3 normal, half thickness, half3 lightColor)
            {
                half3 H = normalize(lightDir + normal * _TransmissionDistortion);
                half VdotH = pow(saturate(dot(viewDir, -H)), _SubsurfacePower);
                return _TransmissionStrength * VdotH * thickness * _SubsurfaceColor.rgb * lightColor;
            }

            half4 frag(Varyings input) : SV_Target
            {
                // 采样贴图
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv), _BumpScale);
                half ao = lerp(1.0, SAMPLE_TEXTURE2D(_AOMap, sampler_AOMap, input.uv).r, _AOStrength);
                half thickness = 1.0 - SAMPLE_TEXTURE2D(_ThicknessMap, sampler_ThicknessMap, input.uv).r;
                thickness *= _ThicknessScale;
                // 计算世界空间法线
                float sgn = input.tangentWS.w;
                float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
                float3x3 tangentToWorld = float3x3(input.tangentWS.xyz, bitangent, input.normalWS.xyz);
                half3 normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
                normalWS = normalize(normalWS);
                
                half3 viewDirWS = normalize(input.viewDirWS);
                half NdotV = saturate(dot(normalWS, viewDirWS));
                half fresnel = pow(1.0 - NdotV, _EdgeGlow);
                
                // 获取主光源（包含阴影）
                Light mainLight = GetMainLight(input.shadowCoord);
                half3 lightDir = normalize(mainLight.direction);
                half3 lightColor = mainLight.color * mainLight.distanceAttenuation * mainLight.shadowAttenuation;

                half NdotL = saturate(dot(normalWS, lightDir));
                half3 albedo = baseMap.rgb * _BaseColor.rgb;
                
                // PBR 计算
                half3 halfVector = normalize(lightDir + viewDirWS);
                half NdotH = saturate(dot(normalWS, halfVector));
                half LdotH = saturate(dot(lightDir, halfVector));
                
                half roughness = 1.0 - _Smoothness;
                half a = roughness * roughness;
                half a2 = a * a;
                half d = (NdotH * a2 - NdotH) * NdotH + 1.0;
                half specular = a2 / (3.14159 * d * d);
                
                half3 F0 = lerp(0.04, albedo, _Metallic);
                half3 F = F0 + (1.0 - F0) * pow(1.0 - LdotH, 5.0);
                
                // 基础光照（应用光源颜色和强度）
                half3 diffuse = albedo * NdotL * lightColor;
                half3 specularTerm = specular * F * lightColor;
                
                // 环境光
                half3 ambient = SampleSH(normalWS) * albedo * 0.3;
                
                half3 color = diffuse + specularTerm + ambient;
                color *= ao;
                
                // Subsurface effects
                half3 subsurface = SubsurfaceScattering(lightDir, viewDirWS, normalWS, half3(thickness, thickness, thickness), lightColor);
                half3 transmission = Transmission(lightDir, viewDirWS, normalWS, thickness, lightColor);
                half3 innerGlow = _SubsurfaceColor.rgb * _InnerGlow * thickness * ao;
                
                color += (subsurface + transmission + innerGlow) * 0.5; // 降低subsurface强度避免过亮
                color += fresnel * _SubsurfaceColor.rgb * _EdgeGlow * 0.1;
                
                color = lerp(color, color + _SubsurfaceColor.rgb * 0.2, _Translucency * thickness);
                
                // 确保最小亮度
                color = max(color, albedo * 0.05);
                
                return half4(color, 1.0);
            }
            ENDHLSL
        }
        
        // Shadow Pass
        Pass
        {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
    }
}