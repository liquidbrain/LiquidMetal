//
//  Created by John Koszarek on 9/20/17.
//  Copyright © 2017 John Koszarek. All rights reserved.
//

import UIKit
import Metal

/// Functions for creating the buffers used by this app's shaders.
final class ShaderBuffers {

    private static let nbrOfPositions = 2   // x and y

    private static let float4x4Size = MemoryLayout<Float>.size * 16                                             // ndcMatrix
    private static let uniformsStructSize = (MemoryLayout<Float>.size * 16)                                     // ndcMatrix
                                          + (MemoryLayout<Float>.size * 2)                                      // ptmRatio and pointSize
                                          + ((MemoryLayout<Float>.size * 4) - (MemoryLayout<Float>.size * 2))   // padding bytes

    static private(set) var vertexCount = 0

    /**
     Returns a buffer large enough to hold the x and y postions for all particles.
     */
    class func makeVertexBuffer(device: MTLDevice, particleSystem: UnsafeMutableRawPointer!) -> MTLBuffer? {
        vertexCount = Int(LiquidFun.particleCount(forSystem: particleSystem))
        let positions = LiquidFun.particlePositions(forSystem: particleSystem)
        let bufferSize = MemoryLayout<Float>.size * vertexCount * nbrOfPositions
        
        let vertexBuffer = device.makeBuffer(bytes: positions!, length: bufferSize, options: [])
        
        return vertexBuffer
    }

    /**
     Returns a buffer containing values for our shader uniforms: normalized device coorderinates, points-to-LiquidFun
     meters ratio, and particle radius.
     */
    class func makeUniformBuffer(device: MTLDevice, particleRadius: Float, ptmRatio: Float) -> MTLBuffer? {
        // Create the orthographic projection matrix using normalized device coordinates
        // (for near and far).
        let screenSize: CGSize = UIScreen.main.bounds.size
        let screenWidth = Float(screenSize.width)
        let screenHeight = Float(screenSize.height)
        let ndcMatrix = Math.createOrthographicMatrix(left: 0, right: screenWidth,
                                                      bottom: 0, top: screenHeight,
                                                      near: -1, far: 1)

        // Create the uniform buffer.
        let uniformBuffer = device.makeBuffer(length: uniformsStructSize, options: [])

        // Copy the normalized device coorderinates, points-to-LiquidFun meters ratio, and particle radius
        // to the uniform buffer.
        if uniformBuffer != nil {
            let bufferPointer = uniformBuffer!.contents()   // pointer to the shared copy of the buffer data
            var ptmRatioRW = ptmRatio                       // make copy of pmtRatio constant for memcpy
            var particleRadiusRW = particleRadius           // make copy of particleRadius constant for memcpy
            memcpy(bufferPointer, ndcMatrix, float4x4Size)
            memcpy(bufferPointer + float4x4Size, &ptmRatioRW, MemoryLayout<Float>.size)
            memcpy(bufferPointer + float4x4Size + MemoryLayout<Float>.size, &particleRadiusRW, MemoryLayout<Float>.size)
        }

        return uniformBuffer;
    }
}
