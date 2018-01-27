//
//  Created by John Koszarek on 1/10/18.
//  Copyright © 2018 John Koszarek. All rights reserved.
//

import UIKit
import AVFoundation
import Metal
import os.log

public struct PhysicsWorldDefinition {
    var gravity: Float
    var ptmRatio: Float         // points-to-LiquidFun meters ratio
}

struct ParticleSystemDefinition {
    var radiusInPoints: Float
    var boxSize: Size2D
    var dampingStrength: Float  // reduces the velocity of particles over time
    var density: Float          // particles mass
    var maxParticles: Int32
}

/// Handles rendering and physics for the app, including the particle system.
final class Engine {

    static let particleSystemGravityScale: Float = 1.0

    /** The layer that is used for text. */
    var textLayer: CATextLayer?

    /** The layer that Metal uses for rendering. */
    var metalLayer: CAMetalLayer!

    /** The interface to a single GPU. */
    var metalDevice: MTLDevice!

    /** The queue that organizes the order in which command buffers are executed by the GPU. */
    var commandQueue: MTLCommandQueue!

    /** The graphics functions and configuration state used in a rendering pass. */
    var pipelineState: MTLRenderPipelineState!

    /** The vertex buffer which holds the x and y postions for all particles. */
    var vertexBuffer: MTLBuffer?

    /** The buffer for our shader uniforms: normalized device coorderinates, points-to-LiquidFun
        meters ratio, and particle radius. */
    var uniformBuffer: MTLBuffer?

    /** The particle system. */
    var particleSystem: UnsafeMutableRawPointer?

    var parentView: UIView

    var screenWidth: Float
    var screenHeight: Float

    var physicsWorldDefinition: PhysicsWorldDefinition
    var particleSystemDefinition: ParticleSystemDefinition

    var backgroundColor: MTLClearColor

    // Plays a sound when the user taps the screen. */
    var tapAudioPlayer: AVAudioPlayer?

    var isTextBeingDrawn: Bool

    init?(view: UIView,
          screenWidth: Float,
          screenHeight: Float,
          physicsWorldDefinition: PhysicsWorldDefinition,
          particleSystemDefinition: ParticleSystemDefinition,
          backgroundColor: MTLClearColor,
          tapAudioFilename: String?) {
        self.parentView = view
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.physicsWorldDefinition = physicsWorldDefinition
        self.particleSystemDefinition = particleSystemDefinition
        self.backgroundColor = backgroundColor
        self.isTextBeingDrawn = false

        // Create the Metal device which serves as the interface to a single GPU.
        let md = MTLCreateSystemDefaultDevice()
        guard md != nil else {
            return
        }
        metalDevice = md!

        // Create the Metal layer which manages a pool of Metal drawables.
        metalLayer = CAMetalLayer()
        metalLayer.device = metalDevice         // device used for creating the MTLTexture objects for rendering
        metalLayer.pixelFormat = .bgra8Unorm    // four 8-bit normalized unsigned ints in BGRA order
        metalLayer.framebufferOnly = true       // allocate MTLTexture object(s) optimized for display purposes
        metalLayer.frame = view.layer.frame
        view.layer.addSublayer(metalLayer)

        // Create the queue that organizes the order in which command buffers are executed by the GPU.
        let cq = metalDevice.makeCommandQueue()
        guard cq != nil else {
            return
        }
        commandQueue = cq!

        // Create the buffer used for shader uniforms.
        uniformBuffer = ShaderBuffers.makeUniformBuffer(device: metalDevice,
                                                        particleRadius: particleSystemDefinition.radiusInPoints,
                                                        ptmRatio: physicsWorldDefinition.ptmRatio)

        // Get access to the fragment and vertext shaders (.metal files in an Xcode project are compiled
        // and built into a single default library).
        let defaultLibrary = metalDevice.makeDefaultLibrary()
        guard defaultLibrary != nil else {
            return
        }
        let vertexProgram = defaultLibrary!.makeFunction(name: "particle_vertex")
        let fragmentProgram = defaultLibrary!.makeFunction(name: "basic_fragment")

        // Create the rendering configuration state.
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexProgram
        pipelineDescriptor.fragmentFunction = fragmentProgram
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm    // four 8-bit normalized unsigned ints in BGRA order

        // Create the graphics functions and configuration state used in a rendering pass.
        do {
            try pipelineState = metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }
        catch {
            return nil
        }

        // Create the physics world and the particle system.
        createPhysicsWorld()
        createParticleSystem()
        setMaxParticles(maxParticles: particleSystemDefinition.maxParticles)

        // Create the audio player used for sound when the user taps the screen.
        if let tapAudioFilename = tapAudioFilename {
            let url = URL(fileURLWithPath: tapAudioFilename)
            tapAudioPlayer = try? AVAudioPlayer(contentsOf: url)
        }
    }

    deinit {
        LiquidFun.destroyWorld()
    }

    private func createPhysicsWorld() {
        LiquidFun.createWorld(withGravity: Vector2D(x: 0, y: -(physicsWorldDefinition.gravity)))
        LiquidFun.createEdgeBox(withOrigin: Vector2D(x: 0, y: 0),
                                size: Size2D(width: screenWidth / physicsWorldDefinition.ptmRatio,
                                             height: screenHeight / physicsWorldDefinition.ptmRatio))
    }

    private func createParticleSystem() {
        particleSystem = LiquidFun.createParticleSystem(withRadius: particleSystemDefinition.radiusInPoints / physicsWorldDefinition.ptmRatio,
                                                        dampingStrength: particleSystemDefinition.dampingStrength,
                                                        gravityScale: Engine.particleSystemGravityScale,
                                                        density: particleSystemDefinition.density)
    }

    /**
     Performs collision detection, integration, and constraint solutions.
     velocityIterations and positionIterations affect the accuracy and performance of the simulation.
     Higher values mean greater accuracy, but at a greater performance cost.

     - Parameter timeStep: The amount of time to simulate, this should not vary.
     - Parameter velocityIterations: For the velocity constraint solver.
     - Parameter positionIterations: For the position constraint solver.
     */
    func physicsWorldStep(timeStep: CFTimeInterval, velocityIterations: Int32, positionIterations: Int32) {
        LiquidFun.worldStep(timeStep, velocityIterations: velocityIterations, positionIterations: positionIterations)
    }

    /**
     Creates a particle group in the shape of a box.

     - Parameter position: The world position of the particle group.
     - Parameter size: The size of the particle group.
     */
    func createParticleBox(position: Vector2D, size: Size2D) {
        LiquidFun.createParticleBox(forSystem: particleSystem, position: position, size: size)
    }

    /**
     Set the maximum number of particles. The oldest particles will be destroyed to stay within the
     max limit.

     - Parameter maxParticles: The maximum number of particles.
     */
    func setMaxParticles(maxParticles: Int32) {
        LiquidFun.setMaxParticlesForSystem(particleSystem, maxParticles: maxParticles)
    }

    func particleCount() -> Int32 {
        return LiquidFun.particleCount(forSystem: particleSystem)
    }

    func destroyParticles() {
        LiquidFun.destroyParticles(forSystem: particleSystem);
    }

    func printParticlePostions() {
        let count = Int(LiquidFun.particleCount(forSystem: particleSystem))
        print("Particles: \(count)")

        let positions = (LiquidFun.particlePositions(forSystem: particleSystem)).assumingMemoryBound(to: Vector2D.self)
        for i in 0 ..< count {
            let position = positions[i]
            print("Particle \(i) position: (\(position.x), \(position.y))")
        }
    }

    func drawParticles() {
        // The vertex buffer which holds the x and y postions for all particles.
        let vb = ShaderBuffers.makeVertexBuffer(device: metalDevice, particleSystem: particleSystem)
        guard vb != nil else {
            return
        }
        vertexBuffer = vb

        // Get a Metal drawable.
        let drawable = metalLayer.nextDrawable()
        guard drawable != nil else {
            return
        }

        // Clear the screen to the background color.
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable!.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = backgroundColor

        // Create the commands that will be committed to and executed by the GPU.
        let commandBuffer = commandQueue.makeCommandBuffer()
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)

        // Set the pipeline state and vertex/uniform buffers to use.
        renderEncoder?.setRenderPipelineState(pipelineState!)
        renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder?.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

        // Tell the GPU to draw the particles.
        renderEncoder?.drawPrimitives(type: .point, vertexStart: 0, vertexCount: ShaderBuffers.vertexCount, instanceCount: 1)
        renderEncoder?.endEncoding()

        // Commits the command buffer for execution as soon as possible.
        commandBuffer?.present(drawable!)
        commandBuffer?.commit()
    }

    func drawText(fontName: String, fontSize: Float, fontColor: UIColor, text: String, animate: Bool = false) {
        if isTextBeingDrawn {
            clearText()
        }

        let font = CTFontCreateWithName(fontName as CFString, CGFloat(fontSize), nil)
        let fontSizeCG = CGFloat(fontSize)
        let fontColorCG = fontColor.cgColor
        let frameRectCG = CGRect(x: parentView.layer.bounds.origin.x,
                                 y: parentView.layer.bounds.midY - fontSizeCG,
                                 width: parentView.layer.bounds.width,
                                 height: (fontSizeCG * 2))

        textLayer = CATextLayer()
        textLayer!.frame = frameRectCG
        textLayer!.font = font
        textLayer!.fontSize = fontSizeCG
        textLayer!.foregroundColor = fontColorCG
        textLayer!.string = text
        textLayer!.alignmentMode = kCAAlignmentCenter
        textLayer!.contentsScale = UIScreen.main.scale
        textLayer!.isWrapped = false

        if animate {
            let fadeAnimation = CABasicAnimation(keyPath: "opacity")
            fadeAnimation.fromValue = 0.0
            fadeAnimation.toValue = 1.0
            fadeAnimation.duration = 1.75
            fadeAnimation.repeatCount = Float.greatestFiniteMagnitude
            fadeAnimation.autoreverses = true
            textLayer!.opacity = 0.0
            textLayer!.add(fadeAnimation, forKey: "fadeAnimation")
        }

        parentView.layer.addSublayer(textLayer!)
    }

    func clearText() {
        if let textLayer = textLayer {
            textLayer.removeFromSuperlayer()
        }
    }

    func clearViewToBackgroundColor() {
        // Get a Metal drawable.
        let drawable = metalLayer.nextDrawable()
        guard drawable != nil else {
            return
        }

        // Clear the screen to a color.
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable?.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = backgroundColor

        // Create the commands that will be committed to and executed by the GPU.
        let commandBuffer = commandQueue?.makeCommandBuffer()
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        renderEncoder?.endEncoding()

        // Commits the command buffer for execution as soon as possible.
        commandBuffer?.present(drawable!)
        commandBuffer?.commit()
    }

    func playTapAudio() {
        tapAudioPlayer?.play()
    }
}
