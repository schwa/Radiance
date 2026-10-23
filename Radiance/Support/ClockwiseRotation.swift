import GeometryLite3D
import simd

/// Axis rotations where positive angles turn clockwise when viewed down the axis toward the origin.
///
/// GeometryLite3D's `xRotation`/`yRotation`/`zRotation` initializers rotated this way before 0.2.7 and turn
/// counterclockwise (right-handed) since. Radiance's model rotation controls, saved document rotations, horizon
/// correction, and orientation candidates were all built on the old direction, so they use these to keep it.
nonisolated extension simd_float4x4 {
    init(clockwiseXRotation angle: AngleF) {
        self.init(xRotation: .radians(-angle.radians))
    }

    init(clockwiseYRotation angle: AngleF) {
        self.init(yRotation: .radians(-angle.radians))
    }

    init(clockwiseZRotation angle: AngleF) {
        self.init(zRotation: .radians(-angle.radians))
    }
}
