//
//  Shaders.metal
//  ARKitFindSurfaceDemo
//
//  This sample app's shaders.
//

#include <metal_stdlib>
#include <simd/simd.h>

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

typedef struct {
    float2 position [[attribute(kVertexAttributePosition)]];
    float2 texCoord [[attribute(kVertexAttributeTexcoord)]];
} ImageVertex;


typedef struct {
    float4 position [[position]];
    float2 texCoord;
} ImageColorInOut;


// Captured image vertex function
vertex ImageColorInOut capturedImageVertexTransform(ImageVertex in [[stage_in]]) {
    ImageColorInOut out;
    
    // Pass through the image vertex's position
    out.position = float4(in.position, 0.0, 1.0);
    
    // Pass through the texture coordinate
    out.texCoord = in.texCoord;
    
    return out;
}

// Captured image fragment function
fragment float4 capturedImageFragmentShader(ImageColorInOut in [[stage_in]],
                                            texture2d<float, access::sample> capturedImageTextureY [[ texture(kTextureIndexY) ]],
                                            texture2d<float, access::sample> capturedImageTextureCbCr [[ texture(kTextureIndexCbCr) ]]) {
    
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);
    
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
        float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
        float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
        float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
    );
    
    // Sample Y and CbCr textures to get the YCbCr color at the given texture coordinate
    float4 ycbcr = float4(capturedImageTextureY.sample(colorSampler, in.texCoord).r,
                          capturedImageTextureCbCr.sample(colorSampler, in.texCoord).rg, 1.0);
    
    // Return converted RGB color
    return ycbcrToRGBTransform * ycbcr;
}


typedef struct {
    float3 position [[attribute(kVertexAttributePosition)]];
} Vertex;


typedef struct {
    float4 position [[position]];
    float4 color;
} VertexInOut;


// Result mesh geometry vertex function
constant float3 COLOR_LIST[] = {
    float3( 1, 0, 0 ),
    float3( 1, 1, 0 ),
    float3( 0, 1, 0 ),
    float3( 0, 1, 1 ),
    float3( 1, 0, 1 ),
};
constant float _2_PI_ = 6.28318530718f;

vertex VertexInOut resultMeshGeometryVertexTransform(Vertex in [[stage_in]],
                                                     constant SharedUniforms &sharedUniforms [[ buffer(kBufferIndexSharedUniforms) ]],
                                                     constant InstanceUniforms *instanceUniforms [[ buffer(kBufferIndexInstanceUniforms) ]],
                                                     ushort vid [[vertex_id]],
                                                     ushort iid [[instance_id]])
{
    VertexInOut out;
    float4 position = float4(in.position, 1.0);
    
    if( instanceUniforms[iid].modelType == 1 ) // Cone Mesh
    {
        float ratio = mix(1.0, instanceUniforms[iid].param1, (in.position.y + 0.5f));
        position.x *= ratio;
        position.z *= ratio;
    }
    else if( instanceUniforms[iid].modelType == 2 ) // Torus Mesh
    {
        float mr = instanceUniforms[iid].param1;
        float tr = instanceUniforms[iid].param2;
        
        float ratio = (in.position.y + 0.5f);
        if( ratio > 0.99f ) { ratio = 0.0f; }
        float theta = mix(0.0f, _2_PI_, ratio);
        
        float c = cos(-theta);
        float s = sin(-theta);
        matrix_float3x3 rotY(c, 0, -s, 0, 1, 0, s, 0, c);
        
        float3 base = float3( tr * in.position.x + mr, -tr * in.position.z, 0.0f );
        position = float4( rotY * base, 1 );
    }
    
    float4x4 modelMatrix = instanceUniforms[iid].modelMatrix;
    float4x4 modelViewMatrix = sharedUniforms.viewMatrix * modelMatrix;
    
    // Calculate the position of our vertex in clip space and output for clipping and rasterization
    out.position = sharedUniforms.projectionMatrix * modelViewMatrix * position;
    out.color    = float4( COLOR_LIST[ instanceUniforms[iid].modelIndex ], sharedUniforms.meshAlpha );
    
    return out;
}

// Result mesh geometry fragment function
fragment float4 resultMeshGeometryFragment(VertexInOut in [[stage_in]],
                                           constant SharedUniforms &uniforms [[ buffer(kBufferIndexSharedUniforms) ]])
{
    return in.color;
}


// Unproject Point Cloud Vertex Function
///  Vertex shader that takes in a 2D grid-point and infers its 3D position in world-space, along with confidence
vertex void unprojectVertex(uint vertexID [[vertex_id]],
                            device float4 *pointCloudOutput [[buffer(kBufferIndexPointCloudBuffer)]], // Writable Buffer
                            constant UnprojectUniforms &uniforms [[buffer(kBufferIndexUnprojectUniforms)]],
                            texture2d<float, access::sample> depthTexture [[texture(kTextureIndexDepth)]],
                            texture2d<unsigned int, access::sample> confidenceTexture [[texture(kTextureIndexConfidence)]])
{
    constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);
    
    const auto gridX = vertexID % uniforms.gridResolution.x;
    const auto gridY = vertexID / uniforms.gridResolution.x;
    
    const auto alternatingOffsetX = (gridY % 2) * uniforms.spacing / 2.0;
    
    const auto cameraPoint = float2(
        alternatingOffsetX + (static_cast<float>(gridX) + 0.5) * uniforms.spacing,
                             (static_cast<float>(gridY) + 0.5) * uniforms.spacing
    );
    
    const auto currentPointIndex = (uniforms.pointCloudCurrentIndex + vertexID) % uniforms.maxPoints;
    const auto texCoord = cameraPoint / uniforms.cameraResolution;
    // Sample the depth map to get the depth value
    const auto depth = depthTexture.sample(colorSampler, texCoord).r;
    // With a 2D point plus depth, we can now get its 3D position
    const auto localPoint = uniforms.cameraIntrinsicsInversed * simd_float3( cameraPoint, 1 ) * depth;
    const auto worldPoint = uniforms.localToWorld * simd_float4( localPoint, 1 );
    const auto position   = worldPoint / worldPoint.w;
    
    // Sample the confidence map to get the confidence value
    const auto confidence = confidenceTexture.sample(colorSampler, texCoord).r;
    
    // Write the data to the buffer
    pointCloudOutput[currentPointIndex] = float4( position.xyz, static_cast<float>(confidence) );
}

// Point Cloud Vertex Shader outputs and Fragment shader inputs
struct PointCloudVertexOut {
    float4 position  [[position]];
    float  pointSize [[point_size]];
    float4 color;
};

static constant float4 CONFIDENCE_COLOR[] = {
    float4( 1.0, 0.0, 0.0, 1.0 ),
    float4( 0.0, 0.0, 1.0, 1.0 ),
    float4( 0.0, 1.0, 0.0, 1.0 )
};
vertex PointCloudVertexOut pointCloudVertex(uint vertexID [[vertex_id]],
                                            constant float4 *pointCloudBuffer [[buffer(kBufferIndexPointCloudBuffer)]],
                                            constant SharedUniforms &uniforms [[buffer(kBufferIndexSharedUniforms)]])
{
    const auto pointData  = pointCloudBuffer[vertexID];
    const int  confidence = clamp( static_cast<int>( pointData.w ), 0, 2 );
    
    float4 cameraBasedPoisition = uniforms.viewMatrix * float4( pointData.xyz, 1 );
    float4 projectedPosition    = uniforms.projectionMatrix * cameraBasedPoisition;
    
    float distanceRatio = clamp( abs(cameraBasedPoisition.z), 0.0, 2.0 ) / 2.0; // max distance: 2 meter
    
    // prepare for output
    PointCloudVertexOut out;
    out.position  = projectedPosition;
    out.pointSize = mix( 10.0, 5.0, distanceRatio );
    out.color     = CONFIDENCE_COLOR[ confidence ];
    
    if( confidence < uniforms.confidenceThreshold ) {
        out.color.a = 0.0;
    }
    
    return out;
}

fragment float4 pointCloudFragment(PointCloudVertexOut in [[stage_in]], const float2 coords [[point_coord]]) {
    // we draw within a circle
    const float distSquared = length_squared(coords - float2(0.5));
    if (in.color.a == 0 || distSquared > 0.25) {
        discard_fragment();
    }
    
    return in.color;
}
