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

func pickPoint( rayDirection ray_dir: simd_float3, rayPosition ray_pos: simd_float3, vertices list: UnsafePointer<simd_float4>, count: Int, _ unitRadius: Float) -> Int {
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
