package main

import "core:fmt"
import rlgl "vendor:raylib/rlgl"
import xr "openxr"

// =============================================================================
// XR STARTUP + TEARDOWN
// =============================================================================
//
// Instance, system, session, reference space — and the matching cleanup.

// -----------------------------------------------------------------------------
// Instance, system, session, reference space
// -----------------------------------------------------------------------------

xr_init :: proc() -> bool {
	xr.load_base_procs()

	extensions := []cstring{"XR_KHR_opengl_enable"}

	app_info := xr.ApplicationInfo {
		apiVersion         = xr.MAKE_VERSION(1, 0, 25),
		applicationName    = xr.make_string("editor", 128),
		applicationVersion = 1,
		engineName         = xr.make_string("editor", 128),
		engineVersion      = 1,
	}

	instance_info := xr.InstanceCreateInfo {
		sType                 = .INSTANCE_CREATE_INFO,
		applicationInfo       = app_info,
		enabledExtensionCount = u32(len(extensions)),
		enabledExtensionNames = raw_data(extensions),
	}

	if xr.CreateInstance(&instance_info, &xr_ctx.instance) != .SUCCESS {
		fmt.println("[xr] CreateInstance failed — is an OpenXR runtime installed and active?")
		return false
	}
	xr.load_instance_procs(xr_ctx.instance)

	system_info := xr.SystemGetInfo {
		sType      = .SYSTEM_GET_INFO,
		formFactor = .HEAD_MOUNTED_DISPLAY,
	}
	if xr.GetSystem(xr_ctx.instance, &system_info, &xr_ctx.system_id) != .SUCCESS {
		fmt.println("[xr] GetSystem failed — headset not connected?")
		return false
	}

	// Required before CreateSession. Most runtimes hard-error without it even
	// though the returned min/max GL versions can be ignored.
	gl_reqs := xr.GraphicsRequirementsOpenGLKHR {
		sType = .GRAPHICS_REQUIREMENTS_OPENGL_KHR,
	}
	xr.GetOpenGLGraphicsRequirementsKHR(xr_ctx.instance, xr_ctx.system_id, &gl_reqs)

	binding := xr.GraphicsBindingOpenGLWin32KHR {
		sType = .GRAPHICS_BINDING_OPENGL_WIN32_KHR,
		hDC   = wglGetCurrentDC(),
		hGLRC = wglGetCurrentContext(),
	}

	session_info := xr.SessionCreateInfo {
		sType    = .SESSION_CREATE_INFO,
		next     = &binding,
		systemId = xr_ctx.system_id,
	}
	if xr.CreateSession(xr_ctx.instance, &session_info, &xr_ctx.session) != .SUCCESS {
		fmt.println("[xr] CreateSession failed — GL context not current?")
		return false
	}

	space_info := xr.ReferenceSpaceCreateInfo {
		sType                = .REFERENCE_SPACE_CREATE_INFO,
		referenceSpaceType   = .STAGE,
		poseInReferenceSpace = {orientation = {0, 0, 0, 1}, position = {0, 0, 0}},
	}
	xr.CreateReferenceSpace(xr_ctx.session, &space_info, &xr_ctx.space)

	return true
}

xr_shutdown :: proc() {
	for eye in 0 ..< 2 {
		for target in xr_ctx.eye_targets[eye] {
			// Do NOT call UnloadRenderTexture: that would delete OpenXR's
			// color texture. Only the FBO and our depth buffer are ours.
			rlgl.UnloadFramebuffer(target.id)
			rlgl.UnloadTexture(target.depth.id)
		}
		delete(xr_ctx.eye_targets[eye])

		if xr_ctx.swapchains[eye] != nil {
			xr.DestroySwapchain(xr_ctx.swapchains[eye])
		}
	}

	for i in 0 ..< MAX_HANDS {
		if xr_ctx.input.aim_spaces[i] != nil {
			xr.DestroySpace(xr_ctx.input.aim_spaces[i])
		}
		if xr_ctx.input.grip_spaces[i] != nil {
			xr.DestroySpace(xr_ctx.input.grip_spaces[i])
		}
	}

	if xr_ctx.input.action_set != nil {
		xr.DestroyActionSet(xr_ctx.input.action_set)
	}

	if xr_ctx.space != nil    { xr.DestroySpace(xr_ctx.space) }
	if xr_ctx.session != nil  { xr.DestroySession(xr_ctx.session) }
	if xr_ctx.instance != nil { xr.DestroyInstance(xr_ctx.instance) }
}
