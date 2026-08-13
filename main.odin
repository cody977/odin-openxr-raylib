package main

import "core:fmt"
import rl "vendor:raylib"

// =============================================================================
// ENTRY POINT
// =============================================================================
//
// Window, init order, and the frame loop.

main :: proc() {
	// No VSYNC_HINT and no SetTargetFPS: xrWaitFrame paces us to the headset's
	// refresh rate. A 60 Hz desktop vsync fighting a 90 Hz headset means judder.
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1280, 720, "editor (VR)")
	defer rl.CloseWindow()

	if !xr_init() {
		fmt.println("[xr] init failed — exiting")
		return
	}
	defer xr_shutdown()

	// If this says Intel/AMD integrated on a laptop with a discrete GPU, stop
	// here and fix it — nothing will display no matter what OpenXR reports.
	fmt.printfln("[gl] renderer: %v", glGetString(GL_RENDERER))

	xr_create_swapchains()
	xr_init_actions()

	for !rl.WindowShouldClose() && !xr_ctx.should_quit {
		xr_poll_events()

		if xr_ctx.session_running {
			update(rl.GetFrameTime())
			xr_frame()
		}

		// BeginDrawing/EndDrawing stay OUT of the eye loop — EndDrawing swaps
		// buffers, and calling it between eyes breaks the frame.
		draw_mirror()
	}
}
