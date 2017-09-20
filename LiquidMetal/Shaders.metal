//
//  Shaders.metal
//  LiquidMetal
//
//  Created by John Koszarek on 9/12/17.
//  Copyright © 2017 John Koszarek. All rights reserved.
//

// TODO: Investigate using SIMD structures (e.g., vectors).

#include <metal_stdlib>

using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
};

struct Uniforms {
    float4x4 ndcMatrix; // matrix translating positions from screen points to normalized device coordinates
    float ptmRatio;
    float pointSize;
};

// Receives the vertex’s position in LiquidFun’s coordinate system, then converts it to Metal’s
// coordinate system and outputs it via vertexOut.
// For example:
// LiquidFun world co-ords might be 10 x 17.75 LiquidFun units (meters), with the origin at the lower right-hand corner.
// Screen co-ords might be 320 x 568 points, with the origin at the lower right-hand corner.
// Normalized device co-ords will be -1 x 1, with the origin in the center.
vertex VertexOut particle_vertex(const device packed_float2* vertex_array [[buffer(0)]],
                                 const device Uniforms& uniforms [[buffer(1)]],
                                 unsigned int vid [[vertex_id]]) {
    VertexOut vertexOut;

    float2 position = vertex_array[vid];
    vertexOut.position = uniforms.ndcMatrix * float4(position.x * uniforms.ptmRatio, position.y * uniforms.ptmRatio, 0, 1);
    vertexOut.pointSize = uniforms.pointSize;

    return vertexOut;
}

// Returns the color white as a 4-component vector with 16-bit floating-point values.
fragment half4 basic_fragment() {
    return half4(1.0);
}
