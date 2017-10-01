//
//  ShaderBuffers.swift
//  LiquidMetal
//
//  Created by John Koszarek on 9/20/17.
//  Copyright © 2017 John Koszarek. All rights reserved.
//

import UIKit
import Metal

class ShaderBuffers {

    static var vertexCount = 0

    class func makeVertexBuffer(device: MTLDevice!, particleSystem: UnsafeMutableRawPointer!) -> MTLBuffer? {
        vertexCount = Int(LiquidFun.particleCount(forSystem: particleSystem))
        
        let positions = LiquidFun.particlePositions(forSystem: particleSystem)
        let bufferSize = MemoryLayout<Float>.size * vertexCount * 2
        
        let vertexBuffer = device.makeBuffer(bytes: positions!, length: bufferSize, options: [])
        
        return vertexBuffer;
    }

    class func makeUniformBuffer(device: MTLDevice!, particleRadius: Float, ptmRatio: Float) -> MTLBuffer? {
        // Create the orthographic projection matrix using normalized device coordinates
        // (for near and far).
        let screenSize: CGSize = UIScreen.main.bounds.size
        let screenWidth = Float(screenSize.width)
        let screenHeight = Float(screenSize.height)
        let ndcMatrix = Math.createOrthographicMatrix(left: 0, right: screenWidth,
                                                 bottom: 0, top: screenHeight,
                                                 near: -1, far: 1)
        
        // Calculate the size of the Uniforms struct (from Shaders.metal) in memory.
        let floatSize = MemoryLayout<Float>.size
        let float4x4ByteAlignment = floatSize * 4
        let float4x4Size = floatSize * 16   // ndcMatrix
        let otherFloatsSize = floatSize * 2 // ptmRatio and pointSize
        let paddingBytesSize = float4x4ByteAlignment - otherFloatsSize
        let uniformsStructSize = float4x4Size + otherFloatsSize + paddingBytesSize
        
        // Create the uniform buffer.
        let uniformBuffer = device.makeBuffer(length: uniformsStructSize, options: [])

        // Copy the contents of the Uniform struct data members ??? to the unform buffer.
        if uniformBuffer != nil {
            let bufferPointer = uniformBuffer!.contents()   // pointer to the shared copy of the buffer data
            var ptmRatioRW = ptmRatio                       // make copy of pmtRatio constant for memcpy
            var particleRadiusRW = particleRadius           // make copy of particleRadius constant for memcpy
            memcpy(bufferPointer, ndcMatrix, float4x4Size)
            memcpy(bufferPointer + float4x4Size, &ptmRatioRW, floatSize)
            memcpy(bufferPointer + float4x4Size + floatSize, &particleRadiusRW, floatSize)
        }

        return uniformBuffer;
    }
}
