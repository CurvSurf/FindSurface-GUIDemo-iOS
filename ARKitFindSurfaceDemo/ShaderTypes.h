//
//  ShaderTypes.h
//  ARKitFindSurfaceDemo
//
//  Types and enums that are shared between shaders and the host app code.
//

//
//  Header containing types and enum constants shared between Metal shaders and C/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>


// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum BufferIndices {
    kBufferIndexMeshPositions      = 0,
    kBufferIndexInstanceUniforms   = 1,
    kBufferIndexSharedUniforms     = 2,
    
    kBufferIndexPointCloudBuffer   = 3,
    kBufferIndexUnprojectUniforms  = 4
    
} BufferIndices;

// Attribute index values shared between shader and C code to ensure Metal shader vertex
//   attribute indices match the Metal API vertex descriptor attribute indices
typedef enum VertexAttributes {
    kVertexAttributePosition  = 0,
    kVertexAttributeTexcoord  = 1
} VertexAttributes;

// Texture index values shared between shader and C code to ensure Metal shader texture indices
//   match indices of Metal API texture set calls
typedef enum TextureIndices {
    kTextureIndexColor      = 0,
    kTextureIndexY          = 1,
    kTextureIndexCbCr       = 2,
    
    kTextureIndexDepth      = 3,
    kTextureIndexConfidence = 4
} TextureIndices;

// Structure shared between shader and C code to ensure the layout of shared uniform data accessed in
//    Metal shaders matches the layout of uniform data set in C code
typedef struct {
    // Camera Uniforms
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    
    // Point Cloud Confidence
    int confidenceThreshold;
    
    // Mesh Transparent
    float meshAlpha;
    
    // Torus Segment (fixed value)
    int torusTubeSegment;
    int torusRingSegment;
} SharedUniforms;

// Structure shared between shader and C code to ensure the layout of instance uniform data accessed in
//    Metal shaders matches the layout of uniform data set in C code
typedef struct {
    matrix_float4x4 modelMatrix;
    int             modelType;  // 0 - General, 1 - Cone, 2 - Torus
    int             modelIndex; // 0 ~ 4 ( 0: Plane, 1: Sphere, 2: Cylinder, 3: Cone, 4: Torus )
                                // 5: Grid, 6: Frustum
    float           param1;     // Cone -> Top Radius / Bottom Radius, Torus -> Mean Radius
    float           param2;     // Torus -> Tube Radius
} InstanceUniforms;

// Structure shared between shader and C code to ensure the layout of instance uniform data accessed in
//    Metal shaders matches the layout of uniform data set in C code
typedef struct {
    matrix_float4x4 localToWorld;
    matrix_float3x3 cameraIntrinsicsInversed;
    simd_float2 cameraResolution;
    simd_int2   gridResolution;
    
    float spacing;
    int maxPoints;
    int pointCloudCurrentIndex;
} UnprojectUniforms;

#endif /* ShaderTypes_h */
