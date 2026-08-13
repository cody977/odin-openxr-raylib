package main

import "core:fmt"
import rl "vendor:raylib"

// =============================================================================
// SCENE
// =============================================================================
//
// Your world. Plain raylib immediate-mode calls — this is the file you
// edit day to day; everything else is plumbing.
//
// Controller input: hand(.Left) / hand(.Right) return a ^HandState with
// .trigger, .stick, .a, .b, .menu, plus .*_pressed edges for this frame.
// See xr_input.odin for the full list.

cube_pos: rl.Vector3 = {0, 1.2, -2}
cube_color: rl.Color = rl.RED

// Draw the controllers and their pointing rays.
pointer :: proc() {
	for h in Hand {
		state := hand(h)
		if !state.active {
			continue
		}

		origin := xr_pose_position(state.aim)
		direction := xr_pose_forward(state.aim)

		// Controller body, at the grip pose so it sits in your fist.
		rl.DrawSphere(xr_pose_position(state.grip), 0.02, rl.WHITE)

		// Ray brightens as the trigger goes down — instant visual confirmation
		// that analog input is arriving.
		t := u8(state.trigger * 255)
		rl.DrawLine3D(origin, origin + direction * 5, {255, t, t, 255})
	}
}

draw_scene :: proc() {
	// 0.5m cube, 2m in front of you at roughly chest height.
	rl.DrawCube(cube_pos, 0.5, 0.5, 0.5, cube_color)
	rl.DrawCubeWires(cube_pos, 0.5, 0.5, 0.5, rl.MAROON)

	// Floor reference — without something at ground level it's very hard to
	// judge whether head tracking is behaving.
	rl.DrawGrid(20, 0.5)
}

update :: proc(dt: f32) {
	if rl.IsKeyPressed(.F) {
		srgb_write = !srgb_write
		fmt.printfln("[gl] sRGB framebuffer writes: %v", srgb_write)
	}

	left := hand(.Left)
	right := hand(.Right)

	// Left stick: slide the cube around on the floor plane.
	// Deadzone first — sticks never rest at exactly zero.
	if abs(left.stick.x) > 0.15 {
		cube_pos.x += left.stick.x * dt * 2
	}
	if abs(left.stick.y) > 0.15 {
		cube_pos.z -= left.stick.y * dt * 2
	}

	// Right stick vertical: raise and lower it.
	if abs(right.stick.y) > 0.15 {
		cube_pos.y += right.stick.y * dt * 2
	}

	// Trigger edge: recolor and buzz. Held state would be `right.trigger > 0.5`.
	if right.trigger_pressed {
		cube_color = rl.BLUE
		rumble(.Right, 0.05, 0, 0.6)
	}
	if right.trigger_released {
		cube_color = rl.RED
	}

	// A (right) / X (left) resets.
	if right.a_pressed || left.a_pressed {
		cube_pos = {0, 1.2, -2}
		rumble(.Right, 0.1, 0, 0.3)
	}

	// B (right) / Y (left) makes it green while held.
	if right.b {
		cube_color = rl.GREEN
	}
}
