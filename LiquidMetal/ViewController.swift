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

class ViewController: UIViewController {

    // The interface to a single GPU.
    var device: MTLDevice!
    
    // Backing layer for a view that uses Metal for rendering.
    var metalLayer: CAMetalLayer!

    // Encodes the state for a configured graphics rendering pipeline.
    var pipelineState: MTLRenderPipelineState!
    
    // Ordered list of command buffers for a Metal device to execute.
    var commandQueue: MTLCommandQueue!

    var vertexBuffer: MTLBuffer!
    var uniformBuffer: MTLBuffer!

    var particleSystem: UnsafeMutableRawPointer!
    var particleCount: Int = 0

    let gravity: Float = 9.80665
    let ptmRatio: Float = 32.0      // points-to-LiquidFun meters conversion ratio
    let particleRadius: Float = 9   // particle radius (in points)

    let motionManager: CMMotionManager = CMMotionManager()

    // This method is called after the view controller has loaded its view hierarchy into memory.
    override func viewDidLoad() {
        super.viewDidLoad()

        print("Create world!")
        LiquidFun.createWorld(withGravity: Vector2D(x: 0, y: -gravity))

        print("Create particle system!")
        particleSystem = LiquidFun.createParticleSystem(
            withRadius: particleRadius / ptmRatio, dampingStrength: 0.2, gravityScale: 1, density: 1.2)
        LiquidFun.setMaxParticlesForSystem(particleSystem, maxParticles: 1500)

        let screenSize: CGSize = UIScreen.main.bounds.size
        let screenWidth = Float(screenSize.width)
        let screenHeight = Float(screenSize.height)

        print("Create particle box!")
        LiquidFun.createParticleBox(forSystem: particleSystem,
                                    position: Vector2D(x: screenWidth * 0.5 / ptmRatio, y: screenHeight * 0.5 / ptmRatio),
                                    size: Size2D(width: 50 / ptmRatio, height: 50 / ptmRatio))

        LiquidFun.createEdgeBox(withOrigin: Vector2D(x: 0, y: 0),
                                      size: Size2D(width: screenWidth / ptmRatio,
                                    height: screenHeight / ptmRatio))

        print("Print particle info!")
        printParticleInfo()

        print("Create the Metal later, shaders, and build the render pipeline!")
        createMetalLayer()
        refreshVertexBuffer()
        refreshUniformBuffer()
        buildRenderPipeline()

        print("Render!")
        render()

        print("Runloop!")
        let displayLink = CADisplayLink(target: self, selector: #selector(ViewController.update))
        displayLink.preferredFramesPerSecond = 30
        displayLink.add(to: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)

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

    func createMetalLayer() {
        device = MTLCreateSystemDefaultDevice()

        metalLayer = CAMetalLayer()             // a layer that manages a pool of Metal drawables
        metalLayer.device = device              // device used for creating the MTLTexture objects for rendering
        metalLayer.pixelFormat = .bgra8Unorm    // four 8-bit normalized unsigned ints in BGRA order
        metalLayer.framebufferOnly = true       // allocate MTLTexture object(s) optimized for display purposes
        metalLayer.frame = view.layer.frame
        
        view.layer.addSublayer(metalLayer)
    }

    func refreshVertexBuffer () {
        particleCount = Int(LiquidFun.particleCount(forSystem: particleSystem))

        let positions = LiquidFun.particlePositions(forSystem: particleSystem)
        let bufferSize = MemoryLayout<Float>.size * particleCount * 2

        vertexBuffer = device.makeBuffer(bytes: positions!, length: bufferSize, options: [])
    }

    func refreshUniformBuffer () {
        // Create the orthographic projection matrix using normalized device coordinates
        // (for near and far).
        let screenSize: CGSize = UIScreen.main.bounds.size
        let screenWidth = Float(screenSize.width)
        let screenHeight = Float(screenSize.height)
        let ndcMatrix = createOrthographicMatrix(left: 0, right: screenWidth,
                                                bottom: 0, top: screenHeight,
                                                near: -1, far: 1)

        // Calculate the size of the Uniforms struct (from Shaders.metal) in memory.
        let floatSize = MemoryLayout<Float>.size
        let float4x4ByteAlignment = floatSize * 4
        let float4x4Size = floatSize * 16   // ndcMatrix
        let otherFloatsSize = floatSize * 2 // ptmRatio and pointSize
        let paddingBytesSize = float4x4ByteAlignment - otherFloatsSize
        let uniformsStructSize = float4x4Size + otherFloatsSize + paddingBytesSize

        // Create the uniform buffer and copy the contents of each data member.
        uniformBuffer = device.makeBuffer(length: uniformsStructSize, options: [])
        let bufferPointer = uniformBuffer.contents()
        var ptmRatioRW = ptmRatio               // make copies of constants for memcpy
        var particleRadiusRW = particleRadius
        memcpy(bufferPointer, ndcMatrix, float4x4Size)
        memcpy(bufferPointer + float4x4Size, &ptmRatioRW, floatSize)
        memcpy(bufferPointer + float4x4Size + floatSize, &particleRadiusRW, floatSize)
    }

    func buildRenderPipeline() {
        // Get access to the fragment and vertext shaders (.metal files in an Xcode project are
        // compiled and built into a single default library).
        let defaultLibrary = device.newDefaultLibrary()
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

        // Clear the screen to green.
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable?.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor =
            MTLClearColor(red: 0.0, green: 104.0/255.0, blue: 5.0/255.0, alpha: 1.0)

        // Create the commands that will be committed to and executed by the GPU.
        let commandBuffer = commandQueue.makeCommandBuffer()
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)

        // Set the pipeline state and vertex/uniform buffers to use.
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, at: 0)
        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, at: 1)

        // Tell the GPU to draw some points.
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount, instanceCount: 1)
        renderEncoder.endEncoding()

        // Commits the command buffer for execution as soon as possible.
        commandBuffer.present(drawable!)
        commandBuffer.commit()
    }

    func update(displayLink:CADisplayLink) {
        autoreleasepool {
            LiquidFun.worldStep(displayLink.duration, velocityIterations: 8, positionIterations: 3)
            refreshVertexBuffer()
            render()
        }
    }

    // Creates an orthographic projection matrix (per the OpenGL library), using the following arguments:
    // left, right: The left-and-rightmost x-coordinates of the screen (points).
    //              left should be 0 and right should be the screen’s width in points.
    // bottom, top: The bottom-most and top-most y-coordinates of the screen.
    //              bottom should be 0 and top should be the screen height in points.
    // near, far: The nearest and farthest z-coordinates.
    //            Pass in near and far values of -1 to 1 in order to create the 0 to 1 range of
    //            z-coordinates that Metal expects.
    func createOrthographicMatrix(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> [Float] {
        let ral = right + left
        let rsl = right - left
        let tab = top + bottom
        let tsb = top - bottom
        let fan = far + near
        let fsn = far - near

        return [2.0 / rsl, 0.0, 0.0, 0.0,
                0.0, 2.0 / tsb, 0.0, 0.0,
                0.0, 0.0, -2.0 / fsn, 0.0,
                -ral / rsl, -tab / tsb, -fan / fsn, 1.0]
    }

    func printParticleInfo() {
        let count = Int(LiquidFun.particleCount(forSystem: particleSystem))
        print("There are \(count) particles present")

        let positions = (LiquidFun.particlePositions(forSystem: particleSystem)).assumingMemoryBound(to: Vector2D.self)

        for i in 0..<count {
            let position = positions[i]
            print("particle: \(i) position: (\(position.x), \(position.y))")
        }
    }

    // Tells this object that one or more new touches occurred in a view.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let touchLocation = touch.location(in: view)
            let position = Vector2D(x: Float(touchLocation.x) / ptmRatio,
                                    y: Float(view.bounds.height - touchLocation.y) / ptmRatio)
            let size = Size2D(width: 100 / ptmRatio, height: 100 / ptmRatio)
            LiquidFun.createParticleBox(forSystem: particleSystem, position: position, size: size)
            super.touchesBegan(touches, with: event)
        }
    }
}
