//
//  Helper.swift
//  ARKitFindSurfaceDemo
//
//  General Helper methods and properties
//

import ARKit
import simd

extension Float {
    static let degreesToRadian = Float.pi / 180
    static let _2pi = Float.pi * 2.0
}

extension UIInterfaceOrientation {
    var cameraToDisplayRotation: Int {
        get {
            switch self {
            case .landscapeLeft:
                return 180
            case .portrait:
                return 90
            case .portraitUpsideDown:
                return -90
            default:
                return 0
            }
        }
    }
}

extension matrix_float3x3 {
    mutating func copy(from affine: CGAffineTransform) {
        columns.0 = simd_float3(Float(affine.a), Float(affine.c), Float(affine.tx))
        columns.1 = simd_float3(Float(affine.b), Float(affine.d), Float(affine.ty))
        columns.2 = simd_float3(0, 0, 1)
    }
}

func matrixLookAtRH(eye: simd_float3, at: simd_float3, up: simd_float3) -> matrix_float4x4 {
    let zAxis = simd_normalize( eye - at )
    let xAxis = simd_normalize( simd_cross(up, zAxis) )
    let yAxis = simd_normalize( simd_cross(zAxis, xAxis) )
    
    return matrix_float4x4.init(columns: (vector_float4( xAxis.x, yAxis.x, zAxis.x, 0),
                                          vector_float4( xAxis.y, yAxis.y, zAxis.y, 0),
                                          vector_float4( xAxis.z, yAxis.z, zAxis.z, 0),
                                          vector_float4( -simd_dot(xAxis, eye), -simd_dot(yAxis, eye), -simd_dot(zAxis, eye), 1 )))
    
}

func matrixPerspectiveFovRH(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, ys, 0,   0),
                                         vector_float4( 0,  0, zs, -1),
                                         vector_float4( 0,  0, zs * nearZ, 0)))
}

func matrixRotateAxis(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                                         vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                                         vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                                         vector_float4(                  0,                   0,                   0, 1)))
}

func matrixRotateY(radians: Float) -> matrix_float4x4 {
    let ct = cosf(radians)
    let st = sinf(radians)
    
    return matrix_float4x4.init(columns:(vector_float4(ct, 0, -st, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(st, 0, ct, 0),
                                         vector_float4(0, 0, 0, 1)))
}

func pickPoint(rayDirection ray_dir: simd_float3, rayPosition ray_pos: simd_float3, vertices list: UnsafePointer<simd_float4>, count: Int, _ unitRadius: Float) -> Int {
    let UR_SQ_PLUS_ONE = unitRadius * unitRadius + 1.0
    var minLen: Float = Float.greatestFiniteMagnitude
    var maxCos: Float = -Float.greatestFiniteMagnitude
    
    var pickIdx   : Int = -1
    var pickIdxExt: Int = -1
    
    for idx in 0..<count {
        let sub = simd_make_float3(list[idx]) - ray_pos
        let len1 = simd_dot( ray_dir, sub )
        
        if len1 < Float.ulpOfOne { continue; } // Float.ulpOfOne == FLT_EPSILON
        // 1. Inside ProbeRadius (Picking Cylinder Radius)
        if simd_length_squared(sub) < UR_SQ_PLUS_ONE * (len1 * len1) {
            if len1 < minLen { // find most close point to camera (in z-direction distance)
                minLen = len1
                pickIdx = idx
            }
        }
        // 2. Outside ProbeRadius
        else {
            let cosine = len1 / simd_length(sub)
            if cosine > maxCos { // find most close point to probe radius
                maxCos = cosine
                pickIdxExt = idx
            }
        }
    }
    
    return pickIdx < 0 ? pickIdxExt : pickIdx
}
