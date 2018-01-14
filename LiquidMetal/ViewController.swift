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

    static let gravity: Float = 9.80665     // standard (earth) gravity
    static let ptmRatio: Float = 32.0       // points-to-LiquidFun meters ratio
    static let particleBoxSize = Size2D(width: 1.40625, height: 1.40625)

    //let backgroundColor = MTLClearColor(red: 55.0/255.0, green: 75.0/255.0, blue: 64.0/255.0, alpha: 1.0)    // storm gray-green
    //let backgroundColor = MTLClearColor(red: 64.0/255.0, green: 75.0/255.0, blue: 79.0/255.0, alpha: 1.0)    // storm gray
    let backgroundColor = MTLClearColor(red: 58.0/255.0, green: 62.0/255.0, blue: 61.0/255.0, alpha: 1.0)    // storm gray - darker
    //let backgroundColor = MTLClearColor(red: 36.0/255.0, green: 36.0/255.0, blue: 36.0/255.0, alpha: 1.0)    // storm gray - darkest

    // Handles rendering and physics, including the particle system.
    var engine: Engine!

    // Allows the app to synchronize its drawing to the refresh rate of the display.
    var coreAnimationDisplayLink: CADisplayLink!

    // Allows access to accelerometer data, rotation-rate data, magnetometer data, etc.
    var motionManager: CMMotionManager!

    var tapGesture: UITapGestureRecognizer!
    var doubleTapGesture: UITapGestureRecognizer!
    var longPressGesture: UILongPressGestureRecognizer!

    // This method is called after the view controller has loaded its view hierarchy into memory.
    override func viewDidLoad() {
        super.viewDidLoad()

        let screenSize: CGSize = UIScreen.main.bounds.size
        let screenWidth = Float(screenSize.width)
        let screenHeight = Float(screenSize.height)

        let physicsWorldDef = PhysicsWorldDefinition(gravity: ViewController.gravity,
                                                     ptmRatio: ViewController.ptmRatio)
        let particleSystemDef = ParticleSystemDefinition(radiusInPoints: 2.0,
                                                         boxSize: ViewController.particleBoxSize,
                                                         dampingStrength: 0.2,
                                                         density: 1.2,
                                                         maxParticles: 4500)

        engine = Engine(view: view!,
                        screenWidth: screenWidth,
                        screenHeight: screenHeight,
                        physicsWorldDefinition: physicsWorldDef,
                        particleSystemDefinition: particleSystemDef,
                        initialBackgroundColor: backgroundColor)
        guard engine != nil else {
            return
        }

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

        motionManager = CMMotionManager()
        motionManager.startAccelerometerUpdates(to: OperationQueue(),
                                                withHandler: { (accelerometerData, error) -> Void in
                                                    let acceleration = accelerometerData?.acceleration
                                                    let gravityX = ViewController.gravity * Float((acceleration?.x)!)
                                                    let gravityY = ViewController.gravity * Float((acceleration?.y)!)
                                                    LiquidFun.setGravity(Vector2D(x: gravityX, y: gravityY))
        })
    }

    // Override this method to release any resources that can be recreated.
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    deinit {
        motionManager.stopAccelerometerUpdates()    // stops accelerometer updates
        coreAnimationDisplayLink.invalidate()       // removes the display link from all run loops
    }

    @objc
    func update(displayLink:CADisplayLink) {
        autoreleasepool {
            engine.physicsWorldStep(timeStep: displayLink.duration, velocityIterations: 8, positionIterations: 3)
            if (engine.particleCount() > 0) {
                engine.drawParticles()
            }
            else {
                engine.clearScreen()
            }
        }
    }

    @objc
    func handleTap(gestureRecognizer: UITapGestureRecognizer) {
        os_log("Handle tap", log: OSLog.default, type: .debug)

        let touchLocation = gestureRecognizer.location(in: view)
        let position = Vector2D(x: Float(touchLocation.x) / ViewController.ptmRatio,
                                y: Float(view.bounds.height - touchLocation.y) / ViewController.ptmRatio)

        engine.createParticleBox(position: position, size: Size2D(width: ViewController.particleBoxSize.width,
                                                                  height: ViewController.particleBoxSize.height))
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

        engine.destroyParticles()
        if engine.particleCount() > 0 {
            os_log("Particles still alive", log: OSLog.default, type: .debug)
        }
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
