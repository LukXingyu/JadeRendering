Shader "URP/JadeStandardPBR"
{
    Properties
    {
        [Header(Base Properties)]
        [MainTexture] _BaseMap ("Albedo Map", 2D) = "white" {}
        [MainColor] _BaseColor ("Base Color", Color) = (0.7, 0.9, 0.7, 1)
        
        [Header(PBR Maps)]
        _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Range(0, 2.0)) = 1.0
        _MetallicGlossMap ("Metallic(R) Smoothness(A)", 2D) = "white" {}
        _Metallic ("Metallic", Range(0.0, 1.0)) = 0.0
        _Smoothness ("Smoothness", Range(0.0, 1.0)) = 0.85
        _OcclusionMap ("Occlusion Map", 2D) = "white" {}
        _OcclusionStrength ("Occlusion Strength", Range(0.0, 1.0)) = 1.0
        
        [Header(Subsurface Scattering)]
        _ThicknessMap ("Thickness Map", 2D) = "white" {}
        _ThicknessScale ("Thickness Scale", Range(0.0, 2.0)) = 1.0
        _SubsurfaceColor ("Subsurface Color", Color) = (0.4, 0.8, 0.5, 1)
        _ScatteringPower ("Scattering Power", Range(1.0, 16.0)) = 4.0
        _ScatteringIntensity ("Scattering Intensity", Range(0.0, 2.0)) = 1.0
        
        [Header(Transmission)]
        _TransmissionStrength ("Transmission Strength", Range(0.0, 1.0)) = 0.5
        _TransmissionDistortion ("Transmission Distortion", Range(0.0, 0.5)) = 0.1
        _TransmissionShadowFade ("Shadow Fade", Range(0.0, 1.0)) = 0.5
        
        [Header(Jade Specific)]
        _FresnelPower ("Fresnel Power", Range(1.0, 8.0)) = 3.0
        _RimIntensity ("Rim Light Intensity", Range(0.0, 2.0)) = 0.8
        _InnerGlow ("Inner Glow", Range(0.0, 1.0)) = 0.3
        _DepthColor ("Depth Color", Color) = (0.2, 0.6, 0.3, 1)
        _DepthFactor ("Depth Factor", Range(0.0, 2.0)) = 0.5
    }

    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque" 
            "RenderPipeline" = "UniversalPipeline" 
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "ForwardLit"
            Tags {"LightMode" = "UniversalForward"}
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half _BumpScale;
                half _Metallic;
                half _Smoothness;
                half _OcclusionStrength;
                half _ThicknessScale;
                half4 _SubsurfaceColor;
                half _ScatteringPower;
                half _ScatteringIntensity;
                half _TransmissionStrength;
                half _TransmissionDistortion;
                half _TransmissionShadowFade;
                half _FresnelPower;
                half _RimIntensity;
                half _InnerGlow;
                half4 _DepthColor;
                half _DepthFactor;
            CBUFFER_END

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
            TEXTURE2D(_MetallicGlossMap); SAMPLER(sampler_MetallicGlossMap);
            TEXTURE2D(_OcclusionMap); SAMPLER(sampler_OcclusionMap);
            TEXTURE2D(_ThicknessMap); SAMPLER(sampler_ThicknessMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 texcoord : TEXCOORD0;
                float2 lightmapUV : TEXCOORD1;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float4 tangentWS : TEXCOORD3;
                float3 viewDirWS : TEXCOORD4;
                float4 shadowCoord : TEXCOORD5;
                float fogCoord : TEXCOORD6;
                DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 7);
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
                
                real sign = input.tangentOS.w * GetOddNegativeScale();
                output.tangentWS = half4(normalInput.tangentWS.xyz, sign);
                
                output.viewDirWS = GetWorldSpaceViewDir(vertexInput.positionWS);
                output.shadowCoord = GetShadowCoord(vertexInput);
                output.fogCoord = ComputeFogFactor(vertexInput.positionCS.z);
                
                OUTPUT_LIGHTMAP_UV(input.lightmapUV, unity_LightmapST, output.lightmapUV);
                OUTPUT_SH(output.normalWS.xyz, output.vertexSH);
                
                return output;
            }

            // Standard PBR functions
            half3 FresnelSchlick(half cosTheta, half3 F0)
            {
                return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
            }

            half3 FresnelSchlickRoughness(half cosTheta, half3 F0, half roughness)
            {
                return F0 + (max(half3(1.0 - roughness, 1.0 - roughness, 1.0 - roughness), F0) - F0) * pow(1.0 - cosTheta, 5.0);
            }

            half DistributionGGX(half3 N, half3 H, half roughness)
            {
                half a = roughness * roughness;
                half a2 = a * a;
                half NdotH = max(dot(N, H), 0.0);
                half NdotH2 = NdotH * NdotH;
                
                half nom = a2;
                half denom = (NdotH2 * (a2 - 1.0) + 1.0);
                denom = PI * denom * denom;
                
                return nom / max(denom, 0.0001);
            }

            half GeometrySchlickGGX(half NdotV, half roughness)
            {
                half r = (roughness + 1.0);
                half k = (r * r) / 8.0;
                
                half nom = NdotV;
                half denom = NdotV * (1.0 - k) + k;
                
                return nom / max(denom, 0.0001);
            }

            half GeometrySmith(half3 N, half3 V, half3 L, half roughness)
            {
                half NdotV = max(dot(N, V), 0.0);
                half NdotL = max(dot(N, L), 0.0);
                half ggx2 = GeometrySchlickGGX(NdotV, roughness);
                half ggx1 = GeometrySchlickGGX(NdotL, roughness);
                
                return ggx1 * ggx2;
            }

            // Subsurface scattering for jade
            half3 SubsurfaceScattering(half3 L, half3 V, half3 N, half thickness, half3 lightColor)
            {
                // Only apply SSS when light comes from behind (NdotL < 0)
                half NdotL = dot(N, L);
                
                // Back scattering - light going through the material
                half3 backLightDir = normalize(L + N * _TransmissionDistortion);
                half backScatter = saturate(dot(V, -backLightDir));
                backScatter = pow(backScatter, _ScatteringPower);
                
                // Attenuate by thickness and make sure it only happens on backlit areas
                half backLitMask = saturate(-NdotL); // Only on backface
                half3 transmission = backScatter * thickness * _SubsurfaceColor.rgb * backLitMask;
                
                return transmission * lightColor * _ScatteringIntensity;
            }

            // Light transmission
            half3 Transmission(half3 L, half3 V, half3 N, half thickness, half shadowAttenuation, half3 lightColor)
            {
                // Check if light is coming from behind
                half NdotL = dot(N, L);
                half backLitMask = saturate(-NdotL); // Only transmit when backlit
                
                half3 H = normalize(L + N * _TransmissionDistortion);
                half VdotH = pow(saturate(dot(V, -H)), _ScatteringPower);
                
                // Apply shadow fade to transmission
                half transmissionShadow = lerp(1.0, shadowAttenuation, _TransmissionShadowFade);
                
                return _TransmissionStrength * VdotH * thickness * backLitMask * _SubsurfaceColor.rgb * lightColor * transmissionShadow;
            }

            half4 frag(Varyings input) : SV_Target
            {
                // Sample textures
                half4 albedoAlpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 albedo = albedoAlpha.rgb * _BaseColor.rgb;
                
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv), _BumpScale);
                half4 metallicGloss = SAMPLE_TEXTURE2D(_MetallicGlossMap, sampler_MetallicGlossMap, input.uv);
                half metallic = metallicGloss.r * _Metallic;
                half smoothness = metallicGloss.a * _Smoothness;
                half roughness = 1.0 - smoothness;
                
                half occlusion = lerp(1.0, SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, input.uv).r, _OcclusionStrength);
                // Invert thickness - white = thick (less transmission), black = thin (more transmission)
                half thickness = (1.0 - SAMPLE_TEXTURE2D(_ThicknessMap, sampler_ThicknessMap, input.uv).r) * _ThicknessScale;
                
                // Calculate world space normal
                half sgn = input.tangentWS.w;
                half3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
                half3x3 tangentToWorld = half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz);
                half3 normalWS = TransformTangentToWorld(normalTS, tangentToWorld);
                normalWS = NormalizeNormalPerPixel(normalWS);
                
                half3 viewDirWS = SafeNormalize(input.viewDirWS);
                
                // PBR setup
                half3 F0 = lerp(half3(0.04, 0.04, 0.04), albedo, metallic);
                half NdotV = max(dot(normalWS, viewDirWS), 0.0);
                
                // Fresnel for rim lighting
                half fresnel = pow(abs(1.0 - NdotV), _FresnelPower);
                
                // Main light
                Light mainLight = GetMainLight(input.shadowCoord);
                half3 L = normalize(mainLight.direction);
                half3 H = normalize(viewDirWS + L);
                half NdotL = max(dot(normalWS, L), 0.0);
                half NdotH = max(dot(normalWS, H), 0.0);
                half LdotH = max(dot(L, H), 0.0);
                
                // Cook-Torrance BRDF
                half D = DistributionGGX(normalWS, H, roughness);
                half G = GeometrySmith(normalWS, viewDirWS, L, roughness);
                half3 F = FresnelSchlick(LdotH, F0);
                
                half3 nominator = D * G * F;
                half denominator = 4.0 * max(NdotV, 0.0) * max(NdotL, 0.0);
                half3 specular = nominator / max(denominator, 0.001);
                
                // Energy conservation
                half3 kS = F;
                half3 kD = (1.0 - kS) * (1.0 - metallic);
                
                // Direct lighting
                half3 radiance = mainLight.color * mainLight.distanceAttenuation * mainLight.shadowAttenuation;
                half3 directLighting = (kD * albedo / PI + specular) * radiance * NdotL;
                
                // Subsurface effects for jade
                half3 subsurface = SubsurfaceScattering(L, viewDirWS, normalWS, thickness, radiance);
                half3 transmission = Transmission(L, viewDirWS, normalWS, thickness, mainLight.shadowAttenuation, radiance);
                
                // Additional lights (Point Lights, Spot Lights, etc.)
                half3 additionalLighting = 0;
                half3 additionalSSS = 0;
                half3 additionalTransmission = 0;
                
                #ifdef _ADDITIONAL_LIGHTS
                uint pixelLightCount = GetAdditionalLightsCount();
                for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
                {
                    Light light = GetAdditionalLight(lightIndex, input.positionWS);
                    
                    // Skip if light doesn't contribute
                    half lightAttenuation = light.distanceAttenuation * light.shadowAttenuation;
                    if (lightAttenuation <= 0.0) continue;
                    
                    half3 attenuatedLightColor = light.color * lightAttenuation;
                    
                    half3 lightDir = normalize(light.direction);
                    half3 halfDir = normalize(viewDirWS + lightDir);
                    half lightNdotL = max(dot(normalWS, lightDir), 0.0);
                    half lightLdotH = max(dot(lightDir, halfDir), 0.0);
                    
                    // PBR lighting calculation for additional light
                    half lightD = DistributionGGX(normalWS, halfDir, roughness);
                    half lightG = GeometrySmith(normalWS, viewDirWS, lightDir, roughness);
                    half3 lightF = FresnelSchlick(lightLdotH, F0);
                    
                    half3 lightSpecular = (lightD * lightG * lightF) / max(4.0 * NdotV * lightNdotL, 0.001);
                    half3 lightKS = lightF;
                    half3 lightKD = (1.0 - lightKS) * (1.0 - metallic);
                    
                    // Direct lighting from additional light
                    additionalLighting += (lightKD * albedo / PI + lightSpecular) * attenuatedLightColor * lightNdotL;
                    
                    // Subsurface effects for additional lights
                    additionalSSS += SubsurfaceScattering(lightDir, viewDirWS, normalWS, thickness, attenuatedLightColor);
                    additionalTransmission += Transmission(lightDir, viewDirWS, normalWS, thickness, light.shadowAttenuation, attenuatedLightColor);
                }
                #endif
                
                // Indirect lighting (GI)
                half3 bakedGI = SAMPLE_GI(input.lightmapUV, input.vertexSH, normalWS);
                half3 irradiance = bakedGI * occlusion;
                
                half3 F_indirect = FresnelSchlickRoughness(NdotV, F0, roughness);
                half3 kS_indirect = F_indirect;
                half3 kD_indirect = (1.0 - kS_indirect) * (1.0 - metallic);
                half3 diffuseIBL = irradiance * albedo;
                
                // Simple specular IBL approximation
                half3 reflectionDir = reflect(-viewDirWS, normalWS);
                half mip = roughness * 6.0;
                half3 specularIBL = GlossyEnvironmentReflection(reflectionDir, roughness, occlusion) * F_indirect;
                
                half3 ambient = (kD_indirect * diffuseIBL + specularIBL) * occlusion;
                
                // Jade specific effects
                // Inner glow should only appear in lit areas with some ambient contribution
                half lightingMask = saturate(NdotL + 0.3); // Ensure it follows main lighting
                half3 innerGlow = _SubsurfaceColor.rgb * _InnerGlow * thickness * occlusion * lightingMask;
                
                half3 depthColor = lerp(albedo, _DepthColor.rgb, thickness * _DepthFactor);
                
                // Rim light only on edges facing camera
                half3 rimLight = _SubsurfaceColor.rgb * fresnel * _RimIntensity * occlusion * saturate(NdotL * 0.5 + 0.5);
                
                // Combine all lighting
                half3 finalColor = directLighting + additionalLighting + ambient;
                finalColor += subsurface + additionalSSS;
                finalColor += transmission + additionalTransmission;
                finalColor += innerGlow + rimLight;
                finalColor = lerp(finalColor, depthColor * finalColor, _DepthFactor * 0.3);
                
                // Apply fog
                finalColor = MixFog(finalColor, input.fogCoord);
                
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }

        // Shadow Caster Pass
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

        // DepthOnly Pass
        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }

        // Meta Pass for lightmap baking
        Pass
        {
            Name "Meta"
            Tags{"LightMode" = "Meta"}

            Cull Off

            HLSLPROGRAM
            #pragma vertex MetaPassVertex
            #pragma fragment MetaPassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/MetaInput.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
            CBUFFER_END

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            struct MetaAttributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float2 uv0          : TEXCOORD0;
                float2 uv1          : TEXCOORD1;
                float2 uv2          : TEXCOORD2;
            };

            struct MetaVaryings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
            };

            MetaVaryings MetaPassVertex(MetaAttributes input)
            {
                MetaVaryings output;
                output.positionCS = UnityMetaVertexPosition(input.positionOS.xyz, input.uv1, input.uv2);
                output.uv = TRANSFORM_TEX(input.uv0, _BaseMap);
                return output;
            }

            half4 MetaPassFragment(MetaVaryings input) : SV_Target
            {
                half4 albedoAlpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 albedo = albedoAlpha.rgb * _BaseColor.rgb;
                
                MetaInput metaInput;
                metaInput.Albedo = albedo;
                metaInput.Emission = 0;
                
                return UnityMetaFragment(metaInput);
            }
            ENDHLSL
        }
    }
    
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
