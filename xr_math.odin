package main

import "core:math"
import rl "vendor:raylib"
import xr "openxr"

// =============================================================================
// MATRICES
// =============================================================================
//
// Projection and view matrices from OpenXR poses, plus column-major packing
// for rlgl. Convention mistakes here produce a world that swims when you
// move your head.

// -----------------------------------------------------------------------------
// Matrices
// -----------------------------------------------------------------------------
// Camera3D can only express a symmetric FOV. Headset lenses are asymmetric —
// the left eye sees further left than right — so the projection has off-center
// terms that fovy cannot represent. BeginMode3D would build the wrong matrix,
// which is why render_eye() inlines its body with these instead.

xr_projection :: proc(fov: xr.Fovf, near, far: f32) -> rl.Matrix {
	l := math.tan(fov.angleLeft)
	r := math.tan(fov.angleRight)
	d := math.tan(fov.angleDown)
	u := math.tan(fov.angleUp)

	w := r - l
	h := u - d

	m: rl.Matrix
	m[0, 0] = 2 / w
	m[1, 1] = 2 / h
	m[0, 2] = (r + l) / w
	m[1, 2] = (u + d) / h
	m[2, 2] = -(far + near) / (far - near)
	m[3, 2] = -1
	m[2, 3] = -(2 * far * near) / (far - near)
	return m
}

// OpenXR gives a camera transform; a view matrix is its inverse.
// OpenXR and raylib are both right-handed Y-up, so no axis flipping.
//
// ORDER MATTERS: camera-to-world is translate * rotate. Reversed, the head
// position gets rotated by the head orientation and the world appears to slide
// toward and away from you as you turn.
//
// Odin's rl.Matrix is matrix[4,4]f32 with native `*`, so this uses the
// operator rather than rl.MatrixMultiply (which is deprecated and uses
// raylib's own argument ordering).
xr_view_matrix :: proc(pose: xr.Posef) -> rl.Matrix {
	q := quaternion(
		w = pose.orientation.w,
		x = pose.orientation.x,
		y = pose.orientation.y,
		z = pose.orientation.z,
	)
	rot := rl.QuaternionToMatrix(q)
	trans := rl.MatrixTranslate(pose.position.x, pose.position.y, pose.position.z)
	return rl.MatrixInvert(trans * rot)
}

// Pack a matrix into the 16 floats OpenGL expects, column-major.
// Written out explicitly rather than using rl.MatrixToFloatV, because Odin's
// rl.Matrix is the transpose of raylib's C Matrix and it's not worth guessing
// whether the binding compensates.
matrix_to_gl :: proc(m: rl.Matrix) -> [16]f32 {
	out: [16]f32
	for col in 0 ..< 4 {
		for row in 0 ..< 4 {
			out[col * 4 + row] = m[row, col]
		}
	}
	return out
}

// A pose's forward direction is local -Z rotated by its orientation.
// This is what LÖVR's lovr.headset.getDirection() returns.
xr_pose_forward :: proc(pose: xr.Posef) -> rl.Vector3 {
	q := quaternion(
		w = pose.orientation.w,
		x = pose.orientation.x,
		y = pose.orientation.y,
		z = pose.orientation.z,
	)
	return rl.Vector3RotateByQuaternion({0, 0, -1}, q)
}

// OpenXR's Vector3f is its own type; this converts it for raylib.
xr_pose_position :: proc(pose: xr.Posef) -> rl.Vector3 {
	return {pose.position.x, pose.position.y, pose.position.z}
}
