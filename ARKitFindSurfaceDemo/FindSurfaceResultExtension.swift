//
//  FindSurfaceResultExtension.swift
//  ARKitFindSurfaceDemo
//

import Foundation
import simd
import FindSurfaceFramework

extension FindPlaneResult {
    func getModelMatrix() -> matrix_float4x4 {
        let ll = lowerLeft
        let lr = lowerRight
        let ur = upperRight
        let ul = upperLeft
        
        let scaledXAxis = ur - ul
        let scaledZAxis = ll - ul
        let yAxis = simd_normalize( simd_cross( scaledZAxis, scaledXAxis ) )
        
        let center = (ll + lr + ur + ul) / 4.0
        
        return matrix_float4x4(
            simd_make_float4( scaledXAxis, 0 ),
            simd_make_float4( yAxis, 0 ),
            simd_make_float4( scaledZAxis, 0 ),
            simd_make_float4( center, 1 )
        )
    }
    
    func getModelMatrix(withCameraTransform cameraTransform: matrix_float4x4) -> matrix_float4x4 {
        let ll = lowerLeft
        let lr = lowerRight
        let ur = upperRight
        let ul = upperLeft
        
        let scaledXAxis = ur - ul
        let scaledZAxis = ll - ul
        let yAxis = simd_normalize( simd_cross( scaledZAxis, scaledXAxis ) )
        
        let center = (ll + lr + ur + ul) / 4.0
        
        // Flip a plane's normal vector if the normal vector does not forward to our camera
        return ( simd_dot( yAxis, simd_make_float3( cameraTransform.columns.2 ) ) > 0 )
        ? matrix_float4x4(
            simd_make_float4( scaledXAxis, 0 ),
            simd_make_float4( yAxis, 0 ),
            simd_make_float4( scaledZAxis, 0 ),
            simd_make_float4( center, 1 )
        )
        : matrix_float4x4(
            simd_make_float4( scaledXAxis, 0 ),
            simd_make_float4( -yAxis, 0 ),
            simd_make_float4( -scaledZAxis, 0 ),
            simd_make_float4( center, 1 )
        ) // Flip YZ
    }
    
    func getInstanceUniform(withCameraTransform cameraTransform: matrix_float4x4) -> InstanceUniforms {
        var ret = InstanceUniforms()
        ret.modelMatrix = getModelMatrix(withCameraTransform: cameraTransform)
        ret.modelType  = 0; // GeneralTransform
        ret.modelIndex = 0; // Plane (ColorIndex)
        
        return ret
    }
}

extension FindSphereResult {
    func getModelMatrix() -> matrix_float4x4 {
        return matrix_float4x4(
            simd_make_float4( radius, 0, 0, 0 ),
            simd_make_float4( 0, radius, 0, 0 ),
            simd_make_float4( 0, 0, radius, 0 ),
            simd_make_float4( center, 1 )
        )
    }
    
    func getModelMatrix(withCameraTransform cameraTransform: matrix_float4x4) -> matrix_float4x4 {
        return matrix_float4x4(
            radius * cameraTransform.columns.0,
            radius * cameraTransform.columns.1,
            radius * cameraTransform.columns.2,
            simd_make_float4( center, 1 )
        )
    }
    
    func getInstanceUniform(withCameraTransform cameraTransform: matrix_float4x4) -> InstanceUniforms {
        var ret = InstanceUniforms()
        ret.modelMatrix = getModelMatrix(withCameraTransform: cameraTransform)
        ret.modelType  = 0; // GeneralTransform
        ret.modelIndex = 1; // Sphere (ColorIndex)
        
        return ret
    }
    
}

extension FindCylinderResult {
    func getModelMatrix() -> matrix_float4x4 {
        let t = top
        let b = bottom
        
        let center = (t + b) / 2.0
        let scaledYAxis = t - b
        
        let axis = simd_normalize( scaledYAxis )
        
        let globalAxis = [
            simd_make_float3( 1, 0, 0 ),
            simd_make_float3( 0, 1, 0 ),
            simd_make_float3( 0, 0, 1 )
        ]
        let testVal = [
            abs( simd_dot( axis, globalAxis[0] ) ),
            abs( simd_dot( axis, globalAxis[1] ) ),
            abs( simd_dot( axis, globalAxis[2] ) )
        ]
        
        var maxIdx = 0
        if testVal[1] < testVal[maxIdx] { maxIdx = 1 }
        if testVal[2] < testVal[maxIdx] { maxIdx = 2 }
        
        let BASE_AXIS_INDEX = (maxIdx + 1) % 3
        let scaledXAxis = radius * simd_normalize( simd_cross( axis, globalAxis[BASE_AXIS_INDEX] ) )
        let scaledZAxis = radius * simd_normalize( simd_cross( scaledXAxis, axis ) )
        
        return matrix_float4x4 (
            simd_make_float4( scaledXAxis, 0 ),
            simd_make_float4( scaledYAxis, 0 ),
            simd_make_float4( scaledZAxis, 0 ),
            simd_make_float4( center, 1 )
        )
    }
    
    func getModelMatrix(withCameraTransform cameraTransform: matrix_float4x4) -> matrix_float4x4 {
        let t = top
        let b = bottom
        
        let center = (t + b) / 2.0
        let scaledYAxis = t - b
        
        let baseAxis = simd_make_float3( cameraTransform.columns.2 )
        
        let scaledXAxis = radius * simd_normalize( simd_cross( scaledYAxis, baseAxis ) )
        let scaledZAxis = radius * simd_normalize( simd_cross( scaledXAxis, scaledYAxis ) )
        
        return matrix_float4x4 (
            simd_make_float4( scaledXAxis, 0 ),
            simd_make_float4( scaledYAxis, 0 ),
            simd_make_float4( scaledZAxis, 0 ),
            simd_make_float4( center, 1 )
        )
    }
    
    func getInstanceUniform(withCameraTransform cameraTransform: matrix_float4x4) -> InstanceUniforms {
        var ret = InstanceUniforms()
        ret.modelMatrix = getModelMatrix(withCameraTransform: cameraTransform)
        ret.modelType  = 0; // GeneralTransform
        ret.modelIndex = 2; // Cylinder (ColorIndex)
        
        return ret
    }
}

extension FindConeResult {
    func getModelMatrix() -> matrix_float4x4 {
        let t = top
        let b = bottom
        
        let center = (t + b) / 2.0
        let scaledYAxis = t - b
        
        let axis = simd_normalize( scaledYAxis )
        
        let globalAxis = [
            simd_make_float3( 1, 0, 0 ),
            simd_make_float3( 0, 1, 0 ),
            simd_make_float3( 0, 0, 1 )
        ]
        let testVal = [
            abs( simd_dot( axis, globalAxis[0] ) ),
            abs( simd_dot( axis, globalAxis[1] ) ),
            abs( simd_dot( axis, globalAxis[2] ) )
        ]
        
        var maxIdx = 0
        if testVal[1] < testVal[maxIdx] { maxIdx = 1 }
        if testVal[2] < testVal[maxIdx] { maxIdx = 2 }
        
        let BASE_AXIS_INDEX = (maxIdx + 1) % 3
        let scaledXAxis = bottomRadius * simd_normalize( simd_cross( axis, globalAxis[BASE_AXIS_INDEX] ) )
        let scaledZAxis = bottomRadius * simd_normalize( simd_cross( scaledXAxis, axis ) )
        
        return matrix_float4x4 (
            simd_make_float4( scaledXAxis, 0 ),
            simd_make_float4( scaledYAxis, 0 ),
            simd_make_float4( scaledZAxis, 0 ),
            simd_make_float4( center, 1 )
        )
    }
    
    func getModelMatrix(withCameraTransform cameraTransform: matrix_float4x4) -> matrix_float4x4 {
        let t = top
        let b = bottom
        
        let center = (t + b) / 2.0
        let scaledYAxis = t - b
        
        let baseAxis = simd_make_float3( cameraTransform.columns.2 )
        
        let scaledXAxis = bottomRadius * simd_normalize( simd_cross( scaledYAxis, baseAxis ) )
        let scaledZAxis = bottomRadius * simd_normalize( simd_cross( scaledXAxis, scaledYAxis ) )
        
        return matrix_float4x4 (
            simd_make_float4( scaledXAxis, 0 ),
            simd_make_float4( scaledYAxis, 0 ),
            simd_make_float4( scaledZAxis, 0 ),
            simd_make_float4( center, 1 )
        )
    }
    
    func getInstanceUniform(withCameraTransform cameraTransform: matrix_float4x4) -> InstanceUniforms {
        var ret = InstanceUniforms()
        ret.modelMatrix = getModelMatrix(withCameraTransform: cameraTransform)
        ret.modelType  = 1; // ConeTransform (Deform + Transform)
        ret.modelIndex = 3; // Cone (ColorIndex)
        ret.param1     = topRadius / bottomRadius
        
        return ret
    }
}

extension FindTorusResult {
    func getModelMatrix() -> matrix_float4x4 {
        let axis = normal
        
        let globalAxis = [
            simd_make_float3( 1, 0, 0 ),
            simd_make_float3( 0, 1, 0 ),
            simd_make_float3( 0, 0, 1 )
        ]
        let testVal = [
            abs( simd_dot( axis, globalAxis[0] ) ),
            abs( simd_dot( axis, globalAxis[1] ) ),
            abs( simd_dot( axis, globalAxis[2] ) )
        ]
        
        var maxIdx = 0
        if testVal[1] < testVal[maxIdx] { maxIdx = 1 }
        if testVal[2] < testVal[maxIdx] { maxIdx = 2 }
        
        let BASE_AXIS_INDEX = (maxIdx + 1) % 3
        
        let xAxis = simd_normalize( simd_cross( axis, globalAxis[BASE_AXIS_INDEX] ) )
        let zAxis = simd_normalize( simd_cross( xAxis, axis ) )
        
        return matrix_float4x4(
            simd_make_float4( xAxis, 0 ),
            simd_make_float4( axis, 0 ),
            simd_make_float4( zAxis, 0 ),
            simd_make_float4( center, 1 )
        )
    }
    
    func getModelMatrix(withCameraTransform cameraTransform: matrix_float4x4) -> matrix_float4x4 {
        let axis = normal
        let baseAxis = simd_make_float3( cameraTransform.columns.2 )
        
        let xAxis = simd_normalize( simd_cross( axis, baseAxis ) )
        let zAxis = simd_normalize( simd_cross( xAxis, axis ) )
        
        return matrix_float4x4(
            simd_make_float4( xAxis, 0 ),
            simd_make_float4( axis, 0 ),
            simd_make_float4( zAxis, 0 ),
            simd_make_float4( center, 1 )
        )
    }
    
    func getInstanceUniform(withCameraTransform cameraTransform: matrix_float4x4) -> InstanceUniforms {
        var ret = InstanceUniforms()
        ret.modelMatrix = getModelMatrix(withCameraTransform: cameraTransform)
        ret.modelType  = 2; // TorusTransform (Deform + Transform)
        ret.modelIndex = 4; // Torus (ColorIndex)
        ret.param1     = meanRadius
        ret.param2     = tubeRadius
        
        return ret
    }
}
