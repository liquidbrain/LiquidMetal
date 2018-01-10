//
//  ViewController.swift
//  LiquidMetal
//
//  Created by John Koszarek on 9/4/17.
//  Copyright © 2017 John Koszarek. All rights reserved.
//

import UIKit
import Metal
import CoreMotion
import os.log

class ViewController: UIViewController, UIGestureRecognizerDelegate {

    // The interface to a single GPU.
    var device: MTLDevice!
    
    // Backing layer for a view that uses Metal for rendering.
    var metalLayer: CAMetalLayer!

    // Encodes the state for a configured graphics rendering pipeline.
    var pipelineState: MTLRenderPipelineState!
    
    // Ordered list of command buffers for a Metal device to execute.
    var commandQueue: MTLCommandQueue!

    var vertexBuffer: MTLBuffer?
    var uniformBuffer: MTLBuffer?

    var particleSystem: UnsafeMutableRawPointer!

    let gravity: Float = 9.80665
    let ptmRatio: Float = 32.0                                      // points-to-LiquidFun meters ratio
    let particleRadius: Float = 2                                   // particle radius (in points)
    let particleBoxSize = Size2D(width: 1.40625, height: 1.40625)   // 45 (a nice width in points) / ptmRatio

    //let backgroundColor = MTLClearColor(red: 55.0/255.0, green: 75.0/255.0, blue: 64.0/255.0, alpha: 1.0)    // storm gray-green
    //let backgroundColor = MTLClearColor(red: 64.0/255.0, green: 75.0/255.0, blue: 79.0/255.0, alpha: 1.0)    // storm gray
    let backgroundColor = MTLClearColor(red: 58.0/255.0, green: 62.0/255.0, blue: 61.0/255.0, alpha: 1.0)    // storm gray - darker
    //let backgroundColor = MTLClearColor(red: 36.0/255.0, green: 36.0/255.0, blue: 36.0/255.0, alpha: 1.0)    // storm gray - darkest

    var tapGesture: UITapGestureRecognizer!
    var doubleTapGesture: UITapGestureRecognizer!
    var longPressGesture: UILongPressGestureRecognizer!

    // Allows access to accelerometer data, rotation-rate data, magnetometer data, etc.
    let motionManager = CMMotionManager()

    // This method is called after the view controller has loaded its view hierarchy into memory.
    override func viewDidLoad() {
        super.viewDidLoad()

        LiquidFun.createWorld(withGravity: Vector2D(x: 0, y: -gravity))

        particleSystem = LiquidFun.createParticleSystem(
            withRadius: particleRadius / ptmRatio, dampingStrength: 0.2, gravityScale: 1, density: 1.2)
        LiquidFun.setMaxParticlesForSystem(particleSystem, maxParticles: 4500)

        let screenSize: CGSize = UIScreen.main.bounds.size
        let screenWidth = Float(screenSize.width)
        let screenHeight = Float(screenSize.height)

        LiquidFun.createParticleBox(forSystem: particleSystem,
                                    position: Vector2D(x: screenWidth * 0.5 / ptmRatio, y: screenHeight * 0.5 / ptmRatio),
                                    size: particleBoxSize)

        LiquidFun.createEdgeBox(withOrigin: Vector2D(x: 0, y: 0),
                                size: Size2D(width: screenWidth / ptmRatio,
                                height: screenHeight / ptmRatio))

        makeMetalLayer()
        vertexBuffer = ShaderBuffers.makeVertexBuffer(device: device, particleSystem: particleSystem)
        uniformBuffer = ShaderBuffers.makeUniformBuffer(device: device, particleRadius: particleRadius, ptmRatio: ptmRatio)
        buildRenderPipeline()

        render()

        let displayLink = CADisplayLink(target: self, selector: #selector(ViewController.update))
        displayLink.preferredFramesPerSecond = 30
        displayLink.add(to: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(ViewController.handleTap(gestureRecognizer:)))
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)

        //doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(ViewController.handleDoubleTap(gestureRecognizer:)))
        //doubleTapGesture.numberOfTapsRequired = 2
        //doubleTapGesture.delegate = self
        //view.addGestureRecognizer(doubleTapGesture)

        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(ViewController.handleLongPress(gestureRecognizer:)))
        longPressGesture.delegate = self
        view.addGestureRecognizer(longPressGesture)

        motionManager.startAccelerometerUpdates(to: OperationQueue(),
                                       withHandler: { (accelerometerData, error) -> Void in
                                           let acceleration = accelerometerData?.acceleration
                                           let gravityX = self.gravity * Float((acceleration?.x)!)
                                           let gravityY = self.gravity * Float((acceleration?.y)!)
                                           LiquidFun.setGravity(Vector2D(x: gravityX, y: gravityY))
        })
    }

    // Override this method to release any resources that can be recreated.
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    // Clean up the physics world.
    deinit {
        LiquidFun.destroyWorld()
    }

    func makeMetalLayer() {
        device = MTLCreateSystemDefaultDevice()

        metalLayer = CAMetalLayer()             // a layer that manages a pool of Metal drawables
        metalLayer.device = device              // device used for creating the MTLTexture objects for rendering
        metalLayer.pixelFormat = .bgra8Unorm    // four 8-bit normalized unsigned ints in BGRA order
        metalLayer.framebufferOnly = true       // allocate MTLTexture object(s) optimized for display purposes
        metalLayer.frame = view.layer.frame
        
        view.layer.addSublayer(metalLayer)
    }

    func buildRenderPipeline() {
        // Get access to the fragment and vertext shaders (.metal files in an Xcode project are
        // compiled and built into a single default library).
        let defaultLibrary = device.makeDefaultLibrary()
        let vertexProgram = defaultLibrary?.makeFunction(name: "particle_vertex")
        let fragmentProgram = defaultLibrary?.makeFunction(name: "basic_fragment")

        // Create the rendering configuration state.
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexProgram
        pipelineDescriptor.fragmentFunction = fragmentProgram
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm    // four 8-bit normalized unsigned ints in BGRA order
        
        // Initialize the rendering pipeline state.
        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }
        catch {
            print("Unable to initialize the rendering pipeline state")
        }
        
        // Create the command queue used to submit work to the GPU.
        commandQueue = device.makeCommandQueue()
    }

    func render() {
        let drawable = metalLayer.nextDrawable()

        // Clear the screen to a color.
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable?.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = backgroundColor

        // Create the commands that will be committed to and executed by the GPU.
        let commandBuffer = commandQueue.makeCommandBuffer()
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)

        // UNWRAPPING THESE CAN CAUSE THE APP TO CRASH!!

        // Set the pipeline state and vertex/uniform buffers to use.
        renderEncoder?.setRenderPipelineState(pipelineState)
        renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder?.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

        // Tell the GPU to draw some points.
        renderEncoder?.drawPrimitives(type: .point, vertexStart: 0, vertexCount: ShaderBuffers.vertexCount, instanceCount: 1)
        renderEncoder?.endEncoding()

        // Commits the command buffer for execution as soon as possible.
        commandBuffer?.present(drawable!)
        commandBuffer?.commit()
    }

    func clearScreen() {
        let drawable = metalLayer.nextDrawable()

        // Clear the screen to a color.
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable?.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = backgroundColor

        // Create the commands that will be committed to and executed by the GPU.
        let commandBuffer = commandQueue.makeCommandBuffer()
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        renderEncoder?.endEncoding()

        // Commits the command buffer for execution as soon as possible.
        commandBuffer?.present(drawable!)
        commandBuffer?.commit()
    }

    @objc
    func update(displayLink:CADisplayLink) {
        autoreleasepool {
            LiquidFun.worldStep(displayLink.duration, velocityIterations: 8, positionIterations: 3)
            if (LiquidFun.particleCount(forSystem: particleSystem) > 0) {
                vertexBuffer = ShaderBuffers.makeVertexBuffer(device: device, particleSystem: particleSystem)
                render()
            }
            else {
                clearScreen()
            }
        }
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

    @objc
    func handleTap(gestureRecognizer: UITapGestureRecognizer) {
        os_log("Handle tap", log: OSLog.default, type: .debug)

        let touchLocation = gestureRecognizer.location(in: view)
        let position = Vector2D(x: Float(touchLocation.x) / ptmRatio,
                                y: Float(view.bounds.height - touchLocation.y) / ptmRatio)

        LiquidFun.createParticleBox(forSystem: particleSystem, position: position, size: particleBoxSize)
    }

    @objc
    func handleDoubleTap(gestureRecognizer: UITapGestureRecognizer) {
        // Note we're not currently using UITapGestureRecognizer doubleTapGesture because we'd need the
        // double tap gesture to fail before a single tap is regcognized; this made the single tap to
        // create a new particle box feel sluggish.
        os_log("Handle double tap", log: OSLog.default, type: .debug)
    }

    @objc
    func handleLongPress(gestureRecognizer: UILongPressGestureRecognizer) {
        os_log("Handle long press", log: OSLog.default, type: .debug)

        LiquidFun.destroyParticles(forSystem: particleSystem);
    }

    /*
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        os_log("Gesture recognizer", log: OSLog.default, type: .debug)

        // Don't recognize a single tap until a double-tap fails; this prevents a double-tap from being
        // recorded as both a single and a double tap.
        if gestureRecognizer == tapGesture && otherGestureRecognizer == doubleTapGesture {
            return true
        }
        return false
    }
    */
}
