//
//  Math.swift
//  LiquidMetal
//
//  Created by John Koszarek on 9/20/17.
//  Copyright © 2017 John Koszarek. All rights reserved.
//

class Math {

    // Creates an orthographic projection matrix (per the OpenGL library), using the following arguments:
    // left, right: The left-and-rightmost x-coordinates of the screen (points).
    //              left should be 0 and right should be the screen’s width in points.
    // bottom, top: The bottom-most and top-most y-coordinates of the screen.
    //              bottom should be 0 and top should be the screen height in points.
    // near, far: The nearest and farthest z-coordinates.
    //            Pass in near and far values of -1 to 1 in order to create the 0 to 1 range of
    //            z-coordinates that Metal expects.
    class func createOrthographicMatrix(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> [Float] {
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
}
