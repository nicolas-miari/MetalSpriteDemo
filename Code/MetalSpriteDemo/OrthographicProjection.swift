//
//  OrthographicProjection.swift
//  MetalSpriteDemo
//
//  Created by Nicolás Miari on 2019/04/10.
//  Copyright © 2019 Nicolás Miari. All rights reserved.
//

import Foundation
import simd

/**
 Encapsulates all 6 planes needed to specify an orthographic projection matrix.
 */
struct OrthographicProjectionDescriptor {
    var left: Float
    var right: Float
    var bottom: Float
    var top: Float
    var near: Float
    var far: Float
}

/**
 Creates a 4x4 projection matrix with the top, bottom, left, right, near, and
 far planes specified in the passed descriptor.

 - seealso: `OrthographicProjectionDescriptor`.
 */
func orthographicProjectionMatrix(_ descriptor: OrthographicProjectionDescriptor) -> float4x4 {

    let row0 = float4(2/(descriptor.right - descriptor.left), 0, 0, 0)
    let row1 = float4(0, 2/(descriptor.top - descriptor.bottom), 0, 0)
    let row2 = float4(0, 0, 1/(descriptor.far - descriptor.near), 0)
    let row3 = float4(
        (descriptor.left + descriptor.right) / (descriptor.left - descriptor.right),
        (descriptor.top + descriptor.bottom) / (descriptor.bottom - descriptor.top), descriptor.near / (descriptor.near - descriptor.far), 1)

    return float4x4(rows: [row0, row1, row2, row3])
}
