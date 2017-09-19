//
//  LiquidFun.h
//  LiquidMetal
//
//  Created by John Koszarek on 9/6/17.
//  Copyright © 2017 John Koszarek. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifndef LiquidFun_Definitions
#define LiquidFun_Definitions

typedef struct Vector2D {
    float x;
    float y;
} Vector2D;

typedef struct Size2D {
    float width;
    float height;
} Size2D;

#endif

@interface LiquidFun : NSObject

+ (void)createWorldWithGravity:(Vector2D)gravity;

/**
 * Creates a particle system.
 * @param radius The radius of each particle in the system.
 * @param dampingStrength Reduces the velocity of particles over time.
 * @param gravityScale Adjusts the effect of the physic's world gravity on its particles.
 * @param density The mass of particles, which affects how they interact with other physics bodies
 *                (but not how the particles interact with each other).
 */
+ (void*)createParticleSystemWithRadius:(float)radius
                        dampingStrength:(float)dampingStrength
                           gravityScale:(float)gravityScale
                                density:(float)density;

/**
 * Creates a particle group in the shape of a box.
 * @param particleSystem A b2ParticleSystem.
 * @param position The world position of the particle group.
 * @param size The size of the particle group.
 */
+ (void)createParticleBoxForSystem:(void*)particleSystem
                          position:(Vector2D)position
                              size:(Size2D)size;

/**
 * Create a bounding box.
 * @param origin The box's origin (lower left hand corner)
 * @param size The box's size.
 */
+ (void*)createEdgeBoxWithOrigin:(Vector2D)origin size:(Size2D)size;

/** Updates the global gravity vector. */
+ (void)setGravity:(Vector2D)gravity;

+ (int)particleCountForSystem:(void*)particleSystem;

/** Returns a pointer to the head of the particle positions array. */
+ (void*)particlePositionsForSystem:(void*)particleSystem;

/**
 * Performs collision detection, integration, and constraint solutions.
 * velocityIterations and positionIterations affect the accuracy and performance of the simulation.
 * Higher values mean greater accuracy, but at a greater performance cost.
 * @param timeStep The amount of time to simulate, this should not vary.
 * @velocityIterations For the velocity constraint solver.
 * @param positionIterations For the position constraint solver.
 */
+ (void)worldStep:(CFTimeInterval)timeStep velocityIterations:(int)velocityIterations
                                           positionIterations:(int)positionIterations;

@end
