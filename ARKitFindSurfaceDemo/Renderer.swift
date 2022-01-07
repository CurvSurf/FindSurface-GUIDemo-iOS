//
//  Renderer.swift
//  ARKitFindSurfaceDemo
//
//  The host app renderer.
//

import Foundation
import Metal
import MetalKit
import ARKit

protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

// We only use landscape orientation in this app
let orientation = UIInterfaceOrientation.landscapeRight

// Maximum number of points we store in the point cloud (accumulate mode)
let maxPoints = 500_000

// Number of sample points on the grid
let numGridPoints    = 500
let numGridPointsMax = 20000

// Mesh Segment Constant
let planeSegment     : simd_uint2 = vector2( 5, 5 )
let sphereSegment    : simd_uint2 = vector2( 20, 20 )
let cylinderSegment  : simd_uint2 = vector2( 20, 3 )
let coneSegment      : simd_uint2 = vector2( 20, 5 )
let torusSegment     : simd_uint2 = vector2( 20, 20 )

// Grid Constant
let gridExtent : simd_float3 = vector3( 100, 0, 100 )
let gridSegemnt: simd_uint2  = vector2( 100, 100 )

// Frustum Constant
let frustumWidth : Float = 0.8
let frustumHeight: Float = 0.6
let frustumDepth : Float = 0.5

let defaultEye: simd_float3 = vector3(2, 2, 2)
let ORIGIN: simd_float3 = vector3(0, 0, 0)
let YAXIS : simd_float3 = vector3(0, 1, 0)

// Third view camera Constant
let defaultHorizontalAngle: Float = -45.0 * Float.degreesToRadian
let defaultVerticalAngle: Float = 30.0 * Float.degreesToRadian
let defaultDistance: Float = 3.0

let minVerticalAngle:Float = -60.0 * Float.degreesToRadian
let maxVerticalAngle:Float =  60.0 * Float.degreesToRadian
let minDistance: Float = 0.5
let maxDistance: Float = 10.0

// Grid Height (Fixed Value)
let viewHeight: Float = 1.2


// Camera's threshold values for detecting when the camera moves so that we can accumulate the points
let cameraRotationThreshold = cos(2 * .degreesToRadian)
let cameraTranslationThreshold: Float = pow(0.02, 2)   // (meter-squared)

// The max number of command buffers in flight
let kMaxBuffersInFlight: Int = 3

// The max number result mesh our uniform buffer will hold
let kMaxResultMeshInstanceCount: Int = 32

// The 16 byte aligned size of our uniform structures
let kAlignedSharedUniformsSize: Int = (MemoryLayout<SharedUniforms>.size & ~0xFF) + 0x100
let kAlignedInstanceUniformsSize: Int = (MemoryLayout<InstanceUniforms>.size & ~0xFF) + 0x100
let kAlignedMeshInstanceUniformsSize: Int = ((MemoryLayout<InstanceUniforms>.size * kMaxResultMeshInstanceCount) & ~0xFF) + 0x100
let kAlignedUnprojectUniformsSize: Int = (MemoryLayout<UnprojectUniforms>.size & ~0xFF) + 0x100

// Vertex data for an image plane
let kImagePlaneVertexData: [Float] = [
    -1.0, -1.0,  0.0, 1.0,
    1.0, -1.0,  1.0, 1.0,
    -1.0,  1.0,  0.0, 0.0,
    1.0,  1.0,  1.0, 0.0,
]


class Renderer {
    let session: ARSession
    let device: MTLDevice
    let inFlightSemaphore = DispatchSemaphore(value: kMaxBuffersInFlight)
    var renderDestination: RenderDestinationProvider
    
    // Metal objects
    var commandQueue: MTLCommandQueue!
    
    var sharedUniformBuffer: MTLBuffer!
    var imagePlaneVertexBuffer: MTLBuffer!
    //
    var gridUnfiromBuffer: MTLBuffer!
    var frustumUniformBuffer: MTLBuffer!
    //
    var planeUniformBuffer: MTLBuffer!
    var sphereUniformBuffer: MTLBuffer!
    var cylinderUniformBuffer: MTLBuffer!
    var coneUniformBuffer: MTLBuffer!
    var torusUniformBuffer: MTLBuffer!
    //
    var unprojectUniformBuffer: MTLBuffer!
    var pointCloudBuffer: MTLBuffer!
    //
    var capturedImagePipelineState: MTLRenderPipelineState!
    var capturedImageDepthState: MTLDepthStencilState!
    var resultMeshPipelineState: MTLRenderPipelineState!
    var resultMeshDepthState: MTLDepthStencilState!
    //
    var unprojectPipelineState: MTLRenderPipelineState!
    var relaxedStencilState: MTLDepthStencilState!
    var pointCloudPipelineState: MTLRenderPipelineState!
    var pointCloudDepthState: MTLDepthStencilState!
    //
    var capturedImageTextureY: CVMetalTexture?
    var capturedImageTextureCbCr: CVMetalTexture?
    var depthTexture: CVMetalTexture?
    var confidenceTexture: CVMetalTexture?
    
    // Captured image texture cache
    var capturedImageTextureCache: CVMetalTextureCache!
    
    // Metal vertex descriptor specifying how vertices will by laid out for input into our
    //   resultMesh geometry render pipeline and how we'll layout our Model IO vertices
    var geometryVertexDescriptor: MTLVertexDescriptor!
    
    var gridMesh: MTKMesh!
    var frustumMesh: MTKMesh!
    
    // MetalKit mesh containing vertex data and index buffer for our resultMesh geometry
    var planeMesh: MTKMesh!
    var sphereMesh: MTKMesh!
    var cylinderMesh: MTKMesh!
    var coneMesh: MTKMesh!
    var torusMesh: MTKMesh!
    
    // Used to determine _uniformBufferStride each frame.
    //   This is the current frame number modulo kMaxBuffersInFlight
    var uniformBufferIndex: Int = 0
    
    // Offset within _sharedUniformBuffer to set for the current frame
    var sharedUniformBufferOffset: Int = 0
    
    // Offset within _frustumUniformBuffer to set for the current frame
    var frustumUniformBufferOffset: Int = 0
    
    // Offset within _[plane|sphere|cylinder|cone|torus]UniformBuffer to set for the current frame
    var resultMeshUniformBufferOffset: Int = 0
    
    // Offset within _unprojectUniformBuffer to set for the current frame
    var unprojectUniformBufferOffset: Int = 0
    
    // Offset within _pointCloudUniformBuffer to set for the current frame
    var pointCloudUniformBufferOffset: Int = 0
    
    // Addresses to write shared uniforms to each frame
    var sharedUniformBufferAddress: UnsafeMutableRawPointer!
    
    // Address to write frustum uniform to each frame
    var frustumUniformBufferAddress: UnsafeMutableRawPointer!
    
    // Addresses to write plane uniforms to each frame
    var planeUniformBufferAddress: UnsafeMutableRawPointer!
    
    // Addresses to write sphere uniforms to each frame
    var sphereUniformBufferAddress: UnsafeMutableRawPointer!
    
    // Addresses to write cylinder uniforms to each frame
    var cylinderUniformBufferAddress: UnsafeMutableRawPointer!
    
    // Addresses to write cone uniforms to each frame
    var coneUniformBufferAddress: UnsafeMutableRawPointer!
    
    // Addresses to write torus uniforms to each frame
    var torusUniformBufferAddress: UnsafeMutableRawPointer!
    
    // Addresses to write unproject uniforms to each frame
    var unprojectUniformBufferAddress: UnsafeMutableRawPointer!
    
    // Addresses to write pointcloud uniforms to each frame
    var pointCloudUniformBufferAddress: UnsafeMutableRawPointer!
    
    // The number of plane instances to render
    var planeInstanceCount: Int = 0
    
    // The number of sphere instances to render
    var sphereInstanceCount: Int = 0
    
    // The number of cylinder instances to render
    var cylinderInstanceCount: Int = 0
    
    // The number of cone instances to render
    var coneInstanceCount: Int = 0
    
    // The number of torus instances to render
    var torusInstanceCount: Int = 0
    
    // The total number of instance to render
    var totalInstanceCount: Int = 0
    
    // The number of point cloud to render
    var realSampleCount: Int = 0
    var currentPointIndex: Int = 0
    var currentPointCount: Int = 0
    var pointCloudCache: UnsafeMutableRawPointer!
    
    // Flag variable indicating use "sceneDepth" or "smoothedSceneDepth"
    var useSmoothedSceneDepth: Bool = false
    
    // Flag variable indicating how to accumulate point cloud sample
    var useFullSampling: Bool = true
    
    // Point Cloud Confidence Threadhold
    var confidenceThreshold = 2
    
    // Mesh Alpha
    var meshAlpha: Float = 0.5
    
    // Flag varaible indicating show or hide point cloud
    var showPointCloud = true
    
    // The current viewport size
    var viewportSize: CGSize = CGSize()
    
    // Flag for viewport size changes
    var viewportSizeDidChange: Bool = false
    
    var lastCameraTransform = matrix_float4x4()
    let rotateToARCamera = matrix_float4x4( simd_float4(1, 0, 0, 0),
                                            simd_float4(0, -1, 0, 0),
                                            simd_float4(0, 0, -1, 0),
                                            simd_float4(0, 0, 0, 1) ) // FlipYZ
                         * matrix_float4x4( simd_quaternion(Float(orientation.cameraToDisplayRotation), simd_float3(0, 0, 1)) )
    
    // FindSurfaceResult
    var liveMeshTransform: InstanceUniforms? = nil
    var foundMeshTransform = [InstanceUniforms]()
    
    // 3rd Person View
    var currentViewMode: Bool = false // false: Normal View, true: 3rd Person View
    var thirdViewMatrix: matrix_float4x4 = matrix_float4x4()
    var thirdProjMatrix: matrix_float4x4 = matrix_float4x4()
    
    var cameraHAngle: Float = defaultHorizontalAngle
    var cameraVAngle: Float = defaultVerticalAngle
    var cameraDistance: Float = defaultDistance
    
    init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider) {
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        loadMetal()
        loadAssets()
        pointCloudCache = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<simd_float4>.stride * maxPoints, alignment: 1)
    }
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
        
        let fovYdegree  = Float( 65.0 )
        let aspectRatio = Float( size.width ) / Float( size.height )
        
        thirdProjMatrix = matrixPerspectiveFovRH(fovyRadians: Float.degreesToRadian * fovYdegree, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 200.0)
        viewportSizeDidChange = true
    }
    
    func update() {
        // Wait to ensure only kMaxBuffersInFlight are getting processed by any stage in the Metal
        //   pipeline (App, Metal, Drivers, GPU, etc)
        let _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        // Create a new command buffer for each renderpass to the current drawable
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            commandBuffer.label = "MyCommand"
            
            // Add completion handler which signal _inFlightSemaphore when Metal and the GPU has fully
            //   finished processing the commands we're encoding this frame.  This indicates when the
            //   dynamic buffers, that we're writing to this frame, will no longer be needed by Metal
            //   and the GPU.
            // Retain our CVMetalTextures for the duration of the rendering cycle. The MTLTextures
            //   we use from the CVMetalTextures are not valid unless their parent CVMetalTextures
            //   are retained. Since we may release our CVMetalTexture ivars during the rendering
            //   cycle, we must retain them separately here.
            var textures = [capturedImageTextureY, capturedImageTextureCbCr]
            commandBuffer.addCompletedHandler{ [weak self] commandBuffer in
                if let strongSelf = self {
                    strongSelf.inFlightSemaphore.signal()
                }
                textures.removeAll()
            }
            
            updateBufferStates()
            updateGameState()
            
            if let renderPassDescriptor = renderDestination.currentRenderPassDescriptor,
               let currentDrawable = renderDestination.currentDrawable,
               let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            {
                renderEncoder.label = "MyRenderEncoder"
                
                if let currentFrame = session.currentFrame,
                   shouldAccumulate(frame: currentFrame),
                   updateDepthTextures(frame: currentFrame) {
                    accumulatePoints(frame: currentFrame, commandBuffer: commandBuffer, renderEncoder: renderEncoder)
                }
                
                if !currentViewMode {
                    drawCapturedImage(renderEncoder: renderEncoder)
                }
                
                if showPointCloud {
                    drawPointCloud(renderEncoder: renderEncoder)
                }
                drawResultMeshGeometry(renderEncoder: renderEncoder)
                
                // We're done encoding commands
                renderEncoder.endEncoding()
                
                // Schedule a present once the framebuffer is complete using the current drawable
                commandBuffer.present(currentDrawable)
            }
            
            // Finalize rendering here & push the command buffer to the GPU
            commandBuffer.commit()
        }
    }
    
    // MARK: - Private
    
    // MARK: - Load Metal & Assets
    
    func loadMetal() {
        // Create and load our basic Metal state objects
        
        // Set the default formats needed to render
        renderDestination.depthStencilPixelFormat = .depth32Float
        renderDestination.colorPixelFormat = .bgra8Unorm
        renderDestination.sampleCount = 1
        
        // Calculate our uniform buffer sizes. We allocate kMaxBuffersInFlight instances for uniform
        //   storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        //   buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        //   to another. Result Mesh uniforms should be specified with a max instance count for instancing.
        //   Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        //   argument in the constant address space of our shading functions.
        let sharedUniformBufferSize = kAlignedSharedUniformsSize * kMaxBuffersInFlight
        let instanceUnfiromBufferSize = kAlignedInstanceUniformsSize * kMaxBuffersInFlight
        let resultMeshUniformBufferSize = kAlignedMeshInstanceUniformsSize * kMaxBuffersInFlight
        let unprojectUniformBufferSize = kAlignedUnprojectUniformsSize * kMaxBuffersInFlight
        
        var gridUniformValue = InstanceUniforms(modelMatrix: matrix_float4x4(simd_float4(1, 0, 0, 0),
                                                                             simd_float4(0, 1, 0, 0),
                                                                             simd_float4(0, 0, 1, 0),
                                                                             simd_float4(0, -viewHeight, 0, 1)),
                                                modelType: 0, modelIndex: 5, param1: 0, param2: 0)
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        //   CPU can access the buffer
        sharedUniformBuffer = device.makeBuffer(length: sharedUniformBufferSize, options: .storageModeShared)
        sharedUniformBuffer.label = "SharedUniformBuffer"
        
        gridUnfiromBuffer = device.makeBuffer(bytes: &gridUniformValue, length: MemoryLayout<InstanceUniforms>.size, options: .storageModeShared)
        gridUnfiromBuffer.label = "GridUniformBuffer" // fixed uniform (do not need multiple)
        
        frustumUniformBuffer = device.makeBuffer(length: instanceUnfiromBufferSize, options: .storageModeShared)
        frustumUniformBuffer.label = "FrustumUniformBuffer"
        
        planeUniformBuffer = device.makeBuffer(length: resultMeshUniformBufferSize, options: .storageModeShared)
        planeUniformBuffer.label = "PlaneUniformBuffer"
        
        sphereUniformBuffer = device.makeBuffer(length: resultMeshUniformBufferSize, options: .storageModeShared)
        sphereUniformBuffer.label = "SphereUniformBuffer"
        
        cylinderUniformBuffer = device.makeBuffer(length: resultMeshUniformBufferSize, options: .storageModeShared)
        cylinderUniformBuffer.label = "CylinderUniformBuffer"
        
        coneUniformBuffer = device.makeBuffer(length: resultMeshUniformBufferSize, options: .storageModeShared)
        coneUniformBuffer.label = "ConeUniformBuffer"
        
        torusUniformBuffer = device.makeBuffer(length: resultMeshUniformBufferSize, options: .storageModeShared)
        torusUniformBuffer.label = "TorusUniformBuffer"
        
        unprojectUniformBuffer = device.makeBuffer(length: unprojectUniformBufferSize, options: .storageModeShared)
        unprojectUniformBuffer.label = "UnprojectUniformBuffer"
        
        // Create point cloud buffer objects.
        pointCloudBuffer = device.makeBuffer(length: MemoryLayout<simd_float4>.stride * maxPoints, options: .storageModeShared)
        pointCloudBuffer.label = "PointCloudBuffer"
        
        // Create a vertex buffer with our image plane vertex data.
        let imagePlaneVertexDataCount = kImagePlaneVertexData.count * MemoryLayout<Float>.size
        imagePlaneVertexBuffer = device.makeBuffer(bytes: kImagePlaneVertexData, length: imagePlaneVertexDataCount, options: [])
        imagePlaneVertexBuffer.label = "ImagePlaneVertexBuffer"
        
        // Load all the shader files with a metal file extension in the project
        let defaultLibrary = device.makeDefaultLibrary()!
        
        let capturedImageVertexFunction = defaultLibrary.makeFunction(name: "capturedImageVertexTransform")!
        let capturedImageFragmentFunction = defaultLibrary.makeFunction(name: "capturedImageFragmentShader")!
        
        // Create a vertex descriptor for our image plane vertex buffer
        let imagePlaneVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        imagePlaneVertexDescriptor.attributes[0].format = .float2
        imagePlaneVertexDescriptor.attributes[0].offset = 0
        imagePlaneVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Texture coordinates.
        imagePlaneVertexDescriptor.attributes[1].format = .float2
        imagePlaneVertexDescriptor.attributes[1].offset = 8
        imagePlaneVertexDescriptor.attributes[1].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Buffer Layout
        imagePlaneVertexDescriptor.layouts[0].stride = 16
        imagePlaneVertexDescriptor.layouts[0].stepRate = 1
        imagePlaneVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create a pipeline state for rendering the captured image
        let capturedImagePipelineStateDescriptor = MTLRenderPipelineDescriptor()
        capturedImagePipelineStateDescriptor.label = "MyCapturedImagePipeline"
        capturedImagePipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        capturedImagePipelineStateDescriptor.vertexFunction = capturedImageVertexFunction
        capturedImagePipelineStateDescriptor.fragmentFunction = capturedImageFragmentFunction
        capturedImagePipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        capturedImagePipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        capturedImagePipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        do {
            try capturedImagePipelineState = device.makeRenderPipelineState(descriptor: capturedImagePipelineStateDescriptor)
        } catch let error {
            print("Failed to created captured image pipeline state, error \(error)")
        }
        
        let capturedImageDepthStateDescriptor = MTLDepthStencilDescriptor()
        capturedImageDepthStateDescriptor.depthCompareFunction = .always
        capturedImageDepthStateDescriptor.isDepthWriteEnabled = false
        capturedImageDepthState = device.makeDepthStencilState(descriptor: capturedImageDepthStateDescriptor)
        
        // Create captured image texture cache
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        capturedImageTextureCache = textureCache
        
        let resultMeshGeometryVertexFunction = defaultLibrary.makeFunction(name: "resultMeshGeometryVertexTransform")!
        let resultMeshGeometryFragmentFunction = defaultLibrary.makeFunction(name: "resultMeshGeometryFragment")!
        
        // Create a vertex descriptor for our Metal pipeline.
        geometryVertexDescriptor = MTLVertexDescriptor()
        
        let attrPosIndex = Int(kVertexAttributePosition.rawValue) // 0
        let bufferIndex = Int(kBufferIndexMeshPositions.rawValue) // 0
        
        // Positions.
        geometryVertexDescriptor.attributes[attrPosIndex].format = .float3
        geometryVertexDescriptor.attributes[attrPosIndex].offset = 0
        geometryVertexDescriptor.attributes[attrPosIndex].bufferIndex = bufferIndex
        
        // Position Buffer Layout
        geometryVertexDescriptor.layouts[bufferIndex].stride = 12
        geometryVertexDescriptor.layouts[bufferIndex].stepRate = 1
        geometryVertexDescriptor.layouts[bufferIndex].stepFunction = .perVertex
        
        // Create a reusable pipeline state for rendering result mesh geometry
        let resultMeshPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        resultMeshPipelineStateDescriptor.label = "MyResultMeshPipeline"
        resultMeshPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        resultMeshPipelineStateDescriptor.vertexFunction = resultMeshGeometryVertexFunction
        resultMeshPipelineStateDescriptor.fragmentFunction = resultMeshGeometryFragmentFunction
        resultMeshPipelineStateDescriptor.vertexDescriptor = geometryVertexDescriptor
        resultMeshPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        resultMeshPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        // Alpha Blending
        resultMeshPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
        resultMeshPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        resultMeshPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        resultMeshPipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor    = .sourceAlpha;
        resultMeshPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor      = .sourceAlpha;
        
        do {
            try resultMeshPipelineState = device.makeRenderPipelineState(descriptor: resultMeshPipelineStateDescriptor)
        } catch let error {
            print("Failed to created result mesh geometry pipeline state, error \(error)")
        }
        
        let resultMeshDepthStateDescriptor = MTLDepthStencilDescriptor()
        resultMeshDepthStateDescriptor.depthCompareFunction = .less
        resultMeshDepthStateDescriptor.isDepthWriteEnabled = true
        resultMeshDepthState = device.makeDepthStencilState(descriptor: resultMeshDepthStateDescriptor)
        
        // Create a reusable pipeline state for unproject point cloud
        let unprojectVertexFunction = defaultLibrary.makeFunction(name: "unprojectVertex")
        
        let unprojectPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        unprojectPipelineStateDescriptor.vertexFunction = unprojectVertexFunction
        unprojectPipelineStateDescriptor.isRasterizationEnabled = false
        unprojectPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        unprojectPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        do {
            try unprojectPipelineState = device.makeRenderPipelineState(descriptor: unprojectPipelineStateDescriptor)
        } catch let error {
            print("Failed to created unproject pipeline state, error \(error)")
        }
        
        // point cloud does not need to read/write depth
        let relaxedStateDescriptor = MTLDepthStencilDescriptor()
        relaxedStencilState = device.makeDepthStencilState(descriptor: relaxedStateDescriptor)
        
        // Create a reusable pipeline state for rendering point cloud
        let pointCloudVertexFunction = defaultLibrary.makeFunction(name: "pointCloudVertex")
        let pointCloudFragmentFunction = defaultLibrary.makeFunction(name: "pointCloudFragment")
        
        let pointCloudPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pointCloudPipelineStateDescriptor.vertexFunction = pointCloudVertexFunction
        pointCloudPipelineStateDescriptor.fragmentFunction = pointCloudFragmentFunction
        pointCloudPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        pointCloudPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        do {
            try pointCloudPipelineState = device.makeRenderPipelineState(descriptor: pointCloudPipelineStateDescriptor)
        } catch let error {
            print("Failed to created point cloud pipeline state, error \(error)")
        }
        
        let pointCloudDepthStateDescriptor = MTLDepthStencilDescriptor()
        pointCloudDepthStateDescriptor.depthCompareFunction = .lessEqual
        pointCloudDepthStateDescriptor.isDepthWriteEnabled  = true
        pointCloudDepthState = device.makeDepthStencilState(descriptor: pointCloudDepthStateDescriptor)
        
        
        // Create the command queue
        commandQueue = device.makeCommandQueue()
    }
    
    func loadAssets() {
        // Create and load our assets into Metal objects including meshes and textures
        
        // Create a MetalKit mesh buffer allocator so that ModelIO will load mesh data directly into
        //   Metal buffers accessible by the GPU
        let metalAllocator = MTKMeshBufferAllocator(device: device)
        
        // Create a Model IO vertexDescriptor so that we format/layout our model IO mesh vertices to
        //   fit our Metal render pipeline's vertex descriptor layout
        let vertexDescriptor = MTKModelIOVertexDescriptorFromMetal(geometryVertexDescriptor)
        
        // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
        (vertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        
        // Use ModelIO to create a mesh as our object
        let meshs = [
            MDLMesh(planeWithExtent: vector3(1.0, 0.0, 1.0), segments: planeSegment, geometryType: .triangles, allocator: metalAllocator),
            MDLMesh(sphereWithExtent: vector3(1.0, 1.0, 1.0), segments: sphereSegment, inwardNormals: false, geometryType: .triangles, allocator: metalAllocator),
            MDLMesh(cylinderWithExtent: vector3(1.0, 1.0, 1.0), segments: cylinderSegment, inwardNormals: false, topCap: false, bottomCap: false, geometryType: .triangles, allocator: metalAllocator),
            MDLMesh(cylinderWithExtent: vector3(1.0, 1.0, 1.0), segments: coneSegment, inwardNormals: false, topCap: false, bottomCap: false, geometryType: .triangles, allocator: metalAllocator),
            MDLMesh(cylinderWithExtent: vector3(1.0, 1.0, 1.0), segments: torusSegment, inwardNormals: false, topCap: false, bottomCap: false, geometryType: .triangles, allocator: metalAllocator)
        ]
        
        for mesh in meshs {
            // Perform the format/relayout of mesh vertices by setting the new vertex descriptor in our Model IO mesh
            mesh.vertexDescriptor = vertexDescriptor
        }
        
        // Create a MetalKit mesh (and submeshes) backed by Metal buffers
        do {
            try planeMesh    = MTKMesh(mesh: meshs[0], device: device)
            try sphereMesh   = MTKMesh(mesh: meshs[1], device: device)
            try cylinderMesh = MTKMesh(mesh: meshs[2], device: device)
            try coneMesh     = MTKMesh(mesh: meshs[3], device: device)
            try torusMesh    = MTKMesh(mesh: meshs[4], device: device)
        } catch let error {
            print("Error creating MetalKit mesh, error \(error)")
        }
        
        // Create Grid for 3D-View
        let grid = MDLMesh(planeWithExtent: gridExtent, segments: gridSegemnt, geometryType: .lines, allocator: metalAllocator)
        grid.vertexDescriptor = vertexDescriptor
        do {
            try gridMesh = MTKMesh(mesh: grid, device: device)
        }catch let error {
            print("Error creating MetalKit mesh (Grid), error \(error)")
        }

        // Create Frustum for 3D-View
        let halfW = frustumWidth / 2.0
        let halfH = frustumHeight / 2.0

        let frustumVertices: [Float] = [
            0, 0, 0,
            -halfW,  halfH, -frustumDepth,
             halfW,  halfH, -frustumDepth,
             halfW, -halfH, -frustumDepth,
            -halfW, -halfH, -frustumDepth,
        ]
        let frustumLineIndex: [UInt16] = [
            0, 1, 0, 2, 0, 3, 0, 4,
            1, 2, 2, 3, 3, 4, 4, 1
        ]
        
        let frustumVtxBuffer = metalAllocator.newBuffer(with: Data(bytes: frustumVertices, count: (MemoryLayout<Float>.stride * frustumVertices.count)) , type: .vertex)
        let frustumIdxBuffer = metalAllocator.newBuffer(with: Data(bytes: frustumLineIndex, count: (MemoryLayout<UInt16>.stride * frustumLineIndex.count)) , type: .index)
        
        let frustum = MDLMesh(vertexBuffer: frustumVtxBuffer,
                              vertexCount: frustumVertices.count,
                              descriptor: vertexDescriptor,
                              submeshes: [MDLSubmesh(indexBuffer: frustumIdxBuffer, indexCount: frustumLineIndex.count, indexType: .uInt16, geometryType: .lines, material: nil)])
        
        do {
            try frustumMesh = MTKMesh(mesh: frustum, device: device)
        }catch let error {
            print("Error creating MetalKit mesh (Frustum), error \(error)")
        }
    }
    
    // MARK: - Update
    
    func updateBufferStates() {
        // Update the location(s) to which we'll write to in our dynamically changing Metal buffers for
        //   the current frame (i.e. update our slot in the ring buffer used for the current frame)
        
        uniformBufferIndex = (uniformBufferIndex + 1) % kMaxBuffersInFlight
        
        sharedUniformBufferOffset = kAlignedSharedUniformsSize * uniformBufferIndex
        unprojectUniformBufferOffset = kAlignedUnprojectUniformsSize * uniformBufferIndex
        frustumUniformBufferOffset = kAlignedInstanceUniformsSize * uniformBufferIndex
        resultMeshUniformBufferOffset = kAlignedMeshInstanceUniformsSize * uniformBufferIndex
        
        sharedUniformBufferAddress = sharedUniformBuffer.contents().advanced(by: sharedUniformBufferOffset)
        unprojectUniformBufferAddress = unprojectUniformBuffer.contents().advanced(by: unprojectUniformBufferOffset)
        frustumUniformBufferAddress  = frustumUniformBuffer.contents().advanced(by: frustumUniformBufferOffset)
        planeUniformBufferAddress    = planeUniformBuffer.contents().advanced(by: resultMeshUniformBufferOffset)
        sphereUniformBufferAddress   = sphereUniformBuffer.contents().advanced(by: resultMeshUniformBufferOffset)
        cylinderUniformBufferAddress = cylinderUniformBuffer.contents().advanced(by: resultMeshUniformBufferOffset)
        coneUniformBufferAddress     = coneUniformBuffer.contents().advanced(by: resultMeshUniformBufferOffset)
        torusUniformBufferAddress    = torusUniformBuffer.contents().advanced(by: resultMeshUniformBufferOffset)
    }
    
    func updateGameState() {
        // Update any game state
        
        guard let currentFrame = session.currentFrame else {
            return
        }
        
        updateSharedUniforms(frame: currentFrame)
        updateThirdViewInstanceUniforms(frame: currentFrame)
        updateMeshUniforms(frame: currentFrame)
        updateUnprojectUniforms(frame: currentFrame)
        updateCapturedImageTextures(frame: currentFrame)
        
        if viewportSizeDidChange {
            viewportSizeDidChange = false
            updateImagePlane(frame: currentFrame)
        }
    }
    
    func updateSharedUniforms(frame: ARFrame) {
        // Update the shared uniforms of the frame
        
        let uniforms = sharedUniformBufferAddress.assumingMemoryBound(to: SharedUniforms.self)
        
        if currentViewMode
        {
            uniforms.pointee.viewMatrix = thirdViewMatrix
            uniforms.pointee.projectionMatrix = thirdProjMatrix
        }
        else
        {
            uniforms.pointee.viewMatrix = frame.camera.viewMatrix(for: orientation)
            uniforms.pointee.projectionMatrix = frame.camera.projectionMatrix(for: orientation, viewportSize: viewportSize, zNear: 0.001, zFar: 10)
        }
        
        uniforms.pointee.confidenceThreshold = Int32(confidenceThreshold)
        uniforms.pointee.meshAlpha           = meshAlpha
        uniforms.pointee.torusTubeSegment    = Int32(torusSegment.x)
        uniforms.pointee.torusRingSegment    = Int32(torusSegment.y)
    }
    
    func updateMeshUniforms(frame: ARFrame) {
        // Clear Instance Count
        planeInstanceCount = 0
        sphereInstanceCount = 0
        cylinderInstanceCount = 0
        coneInstanceCount = 0
        torusInstanceCount = 0
        
        var planeIndex = 0
        var sphereIndex = 0
        var cylinderIndex = 0
        var coneIndex = 0
        var torusIndex = 0
        
        let planeUniforms = planeUniformBufferAddress.assumingMemoryBound(to: InstanceUniforms.self)
        let sphereUniforms = sphereUniformBufferAddress.assumingMemoryBound(to: InstanceUniforms.self)
        let cylinderUniforms = cylinderUniformBufferAddress.assumingMemoryBound(to: InstanceUniforms.self)
        let coneUniforms = coneUniformBufferAddress.assumingMemoryBound(to: InstanceUniforms.self)
        let torusUniforms = torusUniformBufferAddress.assumingMemoryBound(to: InstanceUniforms.self)
        
        for uniform in foundMeshTransform {
            switch uniform.modelIndex
            {
            case 0: // Plane
                planeUniforms[planeIndex] = uniform
                planeIndex = (planeIndex + 1) % kMaxResultMeshInstanceCount
                if( planeInstanceCount < kMaxResultMeshInstanceCount ) { planeInstanceCount += 1 }
            case 1: // Sphere
                sphereUniforms[sphereIndex] = uniform
                sphereIndex = (sphereIndex + 1) % kMaxResultMeshInstanceCount
                if( sphereInstanceCount < kMaxResultMeshInstanceCount ) { sphereInstanceCount += 1 }
            case 2: // Cylinder
                cylinderUniforms[cylinderIndex] = uniform
                cylinderIndex = (cylinderIndex + 1) % kMaxResultMeshInstanceCount
                if( cylinderInstanceCount < kMaxResultMeshInstanceCount ) { cylinderInstanceCount += 1 }
            case 3: // Cone
                coneUniforms[coneIndex] = uniform
                coneIndex = (coneIndex + 1) % kMaxResultMeshInstanceCount
                if( coneInstanceCount < kMaxResultMeshInstanceCount ) { coneInstanceCount += 1 }
            case 4: // Torus
                torusUniforms[torusIndex] = uniform
                torusIndex = (torusIndex + 1) % kMaxResultMeshInstanceCount
                if( torusInstanceCount < kMaxResultMeshInstanceCount ) { torusInstanceCount += 1 }
            default:
                continue
            }
        }
        
        if let uniform = liveMeshTransform {
            switch uniform.modelIndex
            {
            case 0: // Plane
                planeUniforms[planeIndex] = uniform
                planeIndex = (planeIndex + 1) % kMaxResultMeshInstanceCount
                if( planeInstanceCount < kMaxResultMeshInstanceCount ) { planeInstanceCount += 1 }
            case 1: // Sphere
                sphereUniforms[sphereIndex] = uniform
                sphereIndex = (sphereIndex + 1) % kMaxResultMeshInstanceCount
                if( sphereInstanceCount < kMaxResultMeshInstanceCount ) { sphereInstanceCount += 1 }
            case 2: // Cylinder
                cylinderUniforms[cylinderIndex] = uniform
                cylinderIndex = (cylinderIndex + 1) % kMaxResultMeshInstanceCount
                if( cylinderInstanceCount < kMaxResultMeshInstanceCount ) { cylinderInstanceCount += 1 }
            case 3: // Cone
                coneUniforms[coneIndex] = uniform
                coneIndex = (coneIndex + 1) % kMaxResultMeshInstanceCount
                if( coneInstanceCount < kMaxResultMeshInstanceCount ) { coneInstanceCount += 1 }
            case 4: // Torus
                torusUniforms[torusIndex] = uniform
                torusIndex = (torusIndex + 1) % kMaxResultMeshInstanceCount
                if( torusInstanceCount < kMaxResultMeshInstanceCount ) { torusInstanceCount += 1 }
            default:
                break
            }
        }
        
        totalInstanceCount = planeInstanceCount + sphereInstanceCount + cylinderInstanceCount + coneInstanceCount + torusInstanceCount
    }
    
    func updateUnprojectUniforms(frame: ARFrame) {
        let uniforms = unprojectUniformBufferAddress.assumingMemoryBound(to: UnprojectUniforms.self)
        let camera = frame.camera;
        
        let cameraResolution = simd_float2( Float(frame.camera.imageResolution.width), Float(frame.camera.imageResolution.height) )
        
        let gridArea = cameraResolution.x * cameraResolution.y
        let spacing  = sqrt( gridArea / Float( useFullSampling ? numGridPointsMax : numGridPoints ) )
        let deltaX   = Int32(round(cameraResolution.x / spacing))
        let deltaY   = Int32(round(cameraResolution.y / spacing))
        
        uniforms.pointee.localToWorld             = camera.viewMatrix(for: orientation).inverse * rotateToARCamera
        
        uniforms.pointee.cameraIntrinsicsInversed = camera.intrinsics.inverse
        uniforms.pointee.cameraResolution         = cameraResolution
        uniforms.pointee.gridResolution           = simd_int2( deltaX, deltaY )
        
        uniforms.pointee.spacing                  = spacing
        uniforms.pointee.maxPoints                = Int32(maxPoints)
        uniforms.pointee.pointCloudCurrentIndex   = Int32(currentPointIndex)
        
        realSampleCount = Int(deltaX * deltaY)
    }
    
    func updateThirdViewInstanceUniforms(frame: ARFrame) {
        if currentViewMode
        {
            let uniforms = frustumUniformBufferAddress.assumingMemoryBound(to: InstanceUniforms.self)
            
            uniforms.pointee.modelMatrix = frame.camera.transform
            uniforms.pointee.modelType   = 0
            uniforms.pointee.modelIndex  = 6
            uniforms.pointee.param1      = 0
            uniforms.pointee.param2      = 0
        }
    }
    
    func updateCapturedImageTextures(frame: ARFrame) {
        // Create two textures (Y and CbCr) from the provided frame's captured image
        let pixelBuffer = frame.capturedImage
        
        if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2) {
            return
        }
        
        capturedImageTextureY = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.r8Unorm, planeIndex:0)
        capturedImageTextureCbCr = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.rg8Unorm, planeIndex:1)
    }
    
    func updateDepthTextures(frame: ARFrame) -> Bool {
        guard let sceneDepth = useSmoothedSceneDepth ? frame.smoothedSceneDepth : frame.sceneDepth,
              let confidenceMap = sceneDepth.confidenceMap else { return false }
        
        depthTexture = createTexture(fromPixelBuffer: sceneDepth.depthMap, pixelFormat: .r32Float, planeIndex: 0)
        confidenceTexture = createTexture(fromPixelBuffer: confidenceMap, pixelFormat: .r8Uint, planeIndex: 0)
        
        return true
    }
    
    func createTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, capturedImageTextureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }
    
    func updateImagePlane(frame: ARFrame) {
        // Update the texture coordinates of our image plane to aspect fill the viewport
        let displayToCameraTransform = frame.displayTransform(for: .landscapeRight, viewportSize: viewportSize).inverted()

        let vertexData = imagePlaneVertexBuffer.contents().assumingMemoryBound(to: Float.self)
        for index in 0...3 {
            let textureCoordIndex = 4 * index + 2
            let textureCoord = CGPoint(x: CGFloat(kImagePlaneVertexData[textureCoordIndex]), y: CGFloat(kImagePlaneVertexData[textureCoordIndex + 1]))
            let transformedCoord = textureCoord.applying(displayToCameraTransform)
            vertexData[textureCoordIndex] = Float(transformedCoord.x)
            vertexData[textureCoordIndex + 1] = Float(transformedCoord.y)
        }
    }
    
    // MARK: - Accumulate Point Cloud
    
    private func shouldAccumulate(frame: ARFrame) -> Bool {
        if !useFullSampling {
            let cameraTransform = frame.camera.transform
            return currentPointCount == 0
                || dot(cameraTransform.columns.2, lastCameraTransform.columns.2) <= cameraRotationThreshold
                || distance_squared(cameraTransform.columns.3, lastCameraTransform.columns.3) >= cameraTranslationThreshold
        }
        return true
    }
    
    private func accumulatePoints(frame: ARFrame, commandBuffer: MTLCommandBuffer, renderEncoder: MTLRenderCommandEncoder) {
        var retainingTextures = [ depthTexture, confidenceTexture ]
        commandBuffer.addCompletedHandler { buffer in
            retainingTextures.removeAll()
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Unproject")
        
        renderEncoder.setDepthStencilState(relaxedStencilState)
        renderEncoder.setRenderPipelineState(unprojectPipelineState)
        
        renderEncoder.setVertexBuffer(pointCloudBuffer, offset: 0, index: Int(kBufferIndexPointCloudBuffer.rawValue))
        renderEncoder.setVertexBuffer(unprojectUniformBuffer, offset: unprojectUniformBufferOffset, index: Int(kBufferIndexUnprojectUniforms.rawValue))
        renderEncoder.setVertexTexture( CVMetalTextureGetTexture(depthTexture!), index: Int(kTextureIndexDepth.rawValue))
        renderEncoder.setVertexTexture( CVMetalTextureGetTexture(confidenceTexture!), index: Int(kTextureIndexConfidence.rawValue))
        
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: realSampleCount)
        
        renderEncoder.popDebugGroup()
        
        if useFullSampling { // Full sampling
            currentPointIndex = 0
            currentPointCount = realSampleCount
        }
        else { // Accumulate small sampling
            currentPointIndex = (currentPointIndex + realSampleCount) % maxPoints
            currentPointCount = min( currentPointCount + realSampleCount, maxPoints )
        }
        
        lastCameraTransform = frame.camera.transform
    }
    
    // MARK: - Draw
    
    private func drawCapturedImage(renderEncoder: MTLRenderCommandEncoder) {
        guard let textureY = capturedImageTextureY, let textureCbCr = capturedImageTextureCbCr else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("DrawCapturedImage")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.none)
        renderEncoder.setRenderPipelineState(capturedImagePipelineState)
        renderEncoder.setDepthStencilState(capturedImageDepthState)
        
        // Set mesh's vertex buffers
        renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
        
        // Set any textures read/sampled from our render pipeline
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureY), index: Int(kTextureIndexY.rawValue))
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureCbCr), index: Int(kTextureIndexCbCr.rawValue))
        
        // Draw each submesh of our mesh
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder.popDebugGroup()
    }
    
    private func drawResultMeshGeometry(renderEncoder: MTLRenderCommandEncoder) {
        guard currentViewMode || totalInstanceCount > 0 else { return }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("DrawResultMeshs")
        
        // Set render command encoder state
        renderEncoder.setFrontFacing(.counterClockwise) // MDLMesh create clockwise front face for Left-Handed
        renderEncoder.setCullMode(.back)
        renderEncoder.setRenderPipelineState(resultMeshPipelineState)
        renderEncoder.setDepthStencilState(resultMeshDepthState)
        
        // Set any buffers fed into our render pipeline
        renderEncoder.setVertexBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        renderEncoder.setFragmentBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        
        if currentViewMode // case third person view
        {
            // Draw Grid
            renderEncoder.setVertexBuffer(gridUnfiromBuffer, offset: 0, index: Int(kBufferIndexInstanceUniforms.rawValue))
            for bufferIndex in 0..<gridMesh.vertexBuffers.count {
                let vertexBuffer = gridMesh.vertexBuffers[bufferIndex]
                renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index:bufferIndex)
            }
            // Draw each submesh of our mesh
            for submesh in gridMesh.submeshes {
                renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset)
            }
            
            // Draw Frustum
            renderEncoder.setVertexBuffer(frustumUniformBuffer, offset: frustumUniformBufferOffset, index: Int(kBufferIndexInstanceUniforms.rawValue))
            for bufferIndex in 0..<frustumMesh.vertexBuffers.count {
                let vertexBuffer = frustumMesh.vertexBuffers[bufferIndex]
                renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index:bufferIndex)
            }
            // Draw each submesh of our mesh
            for submesh in frustumMesh.submeshes {
                renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset)
            }
        }
        
        if planeInstanceCount > 0
        {
            renderEncoder.setVertexBuffer(planeUniformBuffer, offset: resultMeshUniformBufferOffset, index: Int(kBufferIndexInstanceUniforms.rawValue))
            
            // Set mesh's vertex buffers
            for bufferIndex in 0..<planeMesh.vertexBuffers.count {
                let vertexBuffer = planeMesh.vertexBuffers[bufferIndex]
                renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index:bufferIndex)
            }
            
            // Draw each submesh of our mesh
            for submesh in planeMesh.submeshes {
                renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset, instanceCount: planeInstanceCount)
            }
        }
        
        if sphereInstanceCount > 0
        {
            renderEncoder.setVertexBuffer(sphereUniformBuffer, offset: resultMeshUniformBufferOffset, index: Int(kBufferIndexInstanceUniforms.rawValue))
            
            // Set mesh's vertex buffers
            for bufferIndex in 0..<sphereMesh.vertexBuffers.count {
                let vertexBuffer = sphereMesh.vertexBuffers[bufferIndex]
                renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index:bufferIndex)
            }
            
            // Draw each submesh of our mesh
            for submesh in sphereMesh.submeshes {
                renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset, instanceCount: sphereInstanceCount)
            }
        }
        
        if cylinderInstanceCount > 0
        {
            renderEncoder.setVertexBuffer(cylinderUniformBuffer, offset: resultMeshUniformBufferOffset, index: Int(kBufferIndexInstanceUniforms.rawValue))
            
            // Set mesh's vertex buffers
            for bufferIndex in 0..<cylinderMesh.vertexBuffers.count {
                let vertexBuffer = cylinderMesh.vertexBuffers[bufferIndex]
                renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index:bufferIndex)
            }
            
            // Draw each submesh of our mesh
            for submesh in cylinderMesh.submeshes {
                renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset, instanceCount: cylinderInstanceCount)
            }
        }
        
        if coneInstanceCount > 0
        {
            renderEncoder.setVertexBuffer(coneUniformBuffer, offset: resultMeshUniformBufferOffset, index: Int(kBufferIndexInstanceUniforms.rawValue))
            
            // Set mesh's vertex buffers
            for bufferIndex in 0..<coneMesh.vertexBuffers.count {
                let vertexBuffer = coneMesh.vertexBuffers[bufferIndex]
                renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index:bufferIndex)
            }
            
            // Draw each submesh of our mesh
            for submesh in coneMesh.submeshes {
                renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset, instanceCount: coneInstanceCount)
            }
        }
        
        if torusInstanceCount > 0
        {
            renderEncoder.setVertexBuffer(torusUniformBuffer, offset: resultMeshUniformBufferOffset, index: Int(kBufferIndexInstanceUniforms.rawValue))
            
            // Set mesh's vertex buffers
            for bufferIndex in 0..<torusMesh.vertexBuffers.count {
                let vertexBuffer = torusMesh.vertexBuffers[bufferIndex]
                renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index:bufferIndex)
            }
            
            // Draw each submesh of our mesh
            for submesh in torusMesh.submeshes {
                renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset, instanceCount: torusInstanceCount)
            }
        }
        
        renderEncoder.popDebugGroup()
    }
    
    private func drawPointCloud(renderEncoder: MTLRenderCommandEncoder) {
        guard currentPointCount > 0 else { return }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("DrawPointClouds")
        
        // Set render command encoder state
        renderEncoder.setDepthStencilState(pointCloudDepthState)
        renderEncoder.setRenderPipelineState(pointCloudPipelineState)
        
        // Set any buffers fed into our render pipeline
        renderEncoder.setVertexBuffer(pointCloudBuffer, offset: 0, index: Int(kBufferIndexPointCloudBuffer.rawValue))
        renderEncoder.setVertexBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        
        // Draw Point Cloud
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: currentPointCount)
        
        renderEncoder.popDebugGroup()
    }
    
    func toggleSceneDepth() {
        useSmoothedSceneDepth = !useSmoothedSceneDepth
    }
    
    func setSmoothedSceneDepth(useSmoothed: Bool) {
        useSmoothedSceneDepth = useSmoothed
    }
    
    func toggleSamplingMethod() {
        useFullSampling = !useFullSampling
        currentPointCount = 0
        currentPointIndex = 0
    }
    
    func setSamplingMethod(useFull: Bool) {
        useFullSampling = useFull
        currentPointIndex = 0
        currentPointCount = 0
    }
    
    func copyPointCloudCache() -> (pointCloud: UnsafePointer<simd_float4>, pointCount: Int)? {
        guard currentPointCount > 0 else { return nil }
        pointCloudCache.copyMemory(from: pointCloudBuffer.contents(), byteCount: MemoryLayout<simd_float4>.stride * currentPointCount)
        return ( UnsafePointer<simd_float4>( pointCloudCache.assumingMemoryBound(to: simd_float4.self) ), currentPointCount )
    }
    
    func copyPointCloudCacheWithConfidence() -> (pointCloud: UnsafePointer<simd_float4>, pointCount: Int)? {
        guard confidenceThreshold > 0 else { return copyPointCloudCache() }
        guard currentPointCount > 0   else { return nil }
        
        var realCount = 0
        let src = pointCloudBuffer.contents().assumingMemoryBound(to: simd_float4.self)
        let dst = pointCloudCache.assumingMemoryBound(to: simd_float4.self)
        for i in 0..<currentPointCount {
            if Int(src[i].w) < confidenceThreshold { continue }
            dst[realCount] = src[i]
            realCount += 1
        }
        
        if realCount > 0 {
            return ( UnsafePointer<simd_float4>( pointCloudCache.assumingMemoryBound(to: simd_float4.self) ), realCount )
        }
        
        return nil
    }
    
    // MARK: - Update / Add / Remove FindSurfaceResult
    
    public func updateLiveMesh(_ uniform: InstanceUniforms) {
        liveMeshTransform = uniform
    }
    
    public func clearLiveMesh() {
        liveMeshTransform = nil
    }
    
    public func appendLiveMesh() {
        if let uniform = liveMeshTransform {
            appendResultMesh(uniform)
        }
    }
    
    public func appendResultMesh(_ uniform: InstanceUniforms) {
        foundMeshTransform.append(uniform)
    }
    
    public func removeLastResultMesh() {
        if !foundMeshTransform.isEmpty {
            foundMeshTransform.removeLast()
        }
    }
    
    public func removeAllResultMesh() {
        foundMeshTransform.removeAll()
    }
    
    // MARK: - Third Person View (Change View State)
    private func updateThirdViewMatrix() {
        let zAxis = simd_normalize( simd_float3( cosf(cameraHAngle) * cosf(cameraVAngle), sinf(cameraVAngle), -sinf(cameraHAngle) * cosf(cameraVAngle) ) )
        let xAxis = simd_normalize( simd_cross( simd_float3(0, 1, 0), zAxis) )
        let yAxis = simd_normalize( simd_cross(zAxis, xAxis) )
        
        let eye = zAxis * cameraDistance
        
        thirdViewMatrix = matrix_float4x4.init(columns: (vector_float4( xAxis.x, yAxis.x, zAxis.x, 0),
                                                         vector_float4( xAxis.y, yAxis.y, zAxis.y, 0),
                                                         vector_float4( xAxis.z, yAxis.z, zAxis.z, 0),
                                                         vector_float4( -simd_dot(xAxis, eye), -simd_dot(yAxis, eye), -simd_dot(zAxis, eye), 1 )))
    }
    
    public func setViewState(toThirdView: Bool) {
        currentViewMode = toThirdView
        if currentViewMode { // Changed to 3rd person view
            // reset view matrix
            cameraHAngle = defaultHorizontalAngle
            cameraVAngle = defaultVerticalAngle
            cameraDistance = defaultDistance
            updateThirdViewMatrix()
        }
    }
    
    public func rotate3rdView(dx: Float, dy: Float) {
        guard currentViewMode else { return }
        
        cameraHAngle += dx
        while cameraHAngle < 0.0 { cameraHAngle += Float._2pi }
        while cameraHAngle > Float._2pi { cameraHAngle -= Float._2pi }
        
        cameraVAngle = simd_clamp( cameraVAngle + dy, minVerticalAngle, maxVerticalAngle )
        
        updateThirdViewMatrix()
    }
    
    public func zoom3rdView(d: Float) {
        guard currentViewMode else { return }
        
        cameraDistance = simd_clamp( cameraDistance + d, minDistance, maxDistance )
        
        updateThirdViewMatrix()
    }
}
