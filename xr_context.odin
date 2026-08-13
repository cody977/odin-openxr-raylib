package main

import rl "vendor:raylib"
import xr "openxr"

// =============================================================================
// XR CONTEXT
// =============================================================================
//
// The one global holding every OpenXR handle. Read-only from most files.

MAX_HANDS :: 2

XR :: struct {
	instance:      xr.Instance,
	system_id:     xr.SystemId,
	session:       xr.Session,
	space:         xr.Space, // STAGE — floor-level origin
	state:         xr.SessionState,
	session_running: bool,
	should_quit:   bool,

	// per eye
	swapchains:    [2]xr.Swapchain,
	eye_targets:   [2][dynamic]rl.RenderTexture2D,
	last_index:    [2]u32, // which image we actually rendered, for the mirror
	view_w:        i32,
	view_h:        i32,

	// input — see xr_input.odin
	input:         Input,
}

xr_ctx: XR
