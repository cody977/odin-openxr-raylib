package main

import "core:fmt"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import xr "openxr"

// =============================================================================
// SWAPCHAINS
// =============================================================================
//
// Where OpenXR's textures become raylib render targets. wrap_swapchain_image
// is the load-bearing trick of this whole project.

// -----------------------------------------------------------------------------
// Swapchains, wrapped as raylib render targets
// -----------------------------------------------------------------------------

xr_create_swapchains :: proc() {
	view_count: u32
	xr.EnumerateViewConfigurationViews(
		xr_ctx.instance,
		xr_ctx.system_id,
		.PRIMARY_STEREO,
		0,
		&view_count,
		nil,
	)

	views := make([]xr.ViewConfigurationView, view_count)
	defer delete(views)
	for &v in views {
		v.sType = .VIEW_CONFIGURATION_VIEW
	}
	xr.EnumerateViewConfigurationViews(
		xr_ctx.instance,
		xr_ctx.system_id,
		.PRIMARY_STEREO,
		view_count,
		&view_count,
		raw_data(views),
	)

	// SteamVR's "recommended" size already includes whatever supersampling
	// multiplier is set in its settings, which is often 1.4x or higher. Scale
	// it down while bringing the app up, then raise it once frames are landing.
	RENDER_SCALE :: 0.6

	xr_ctx.view_w = i32(f32(views[0].recommendedImageRectWidth) * RENDER_SCALE)
	xr_ctx.view_h = i32(f32(views[0].recommendedImageRectHeight) * RENDER_SCALE)
	fmt.printfln(
		"[xr] eye resolution %vx%v (recommended %vx%v)",
		xr_ctx.view_w,
		xr_ctx.view_h,
		views[0].recommendedImageRectWidth,
		views[0].recommendedImageRectHeight,
	)

	format := xr_pick_swapchain_format()

	for eye in 0 ..< 2 {
		sc_info := xr.SwapchainCreateInfo {
			sType       = .SWAPCHAIN_CREATE_INFO,
			usageFlags  = {.COLOR_ATTACHMENT, .SAMPLED},
			format      = format,
			sampleCount = 1,
			width       = u32(xr_ctx.view_w),
			height      = u32(xr_ctx.view_h),
			faceCount   = 1,
			arraySize   = 1,
			mipCount    = 1,
		}
		xr.CreateSwapchain(xr_ctx.session, &sc_info, &xr_ctx.swapchains[eye])

		img_count: u32
		xr.EnumerateSwapchainImages(xr_ctx.swapchains[eye], 0, &img_count, nil)

		images := make([]xr.SwapchainImageOpenGLKHR, img_count)
		defer delete(images)
		for &img in images {
			img.sType = .SWAPCHAIN_IMAGE_OPENGL_KHR
		}
		xr.EnumerateSwapchainImages(
			xr_ctx.swapchains[eye],
			img_count,
			&img_count,
			cast(^xr.SwapchainImageBaseHeader)raw_data(images),
		)

		// Build every FBO up front. The runtime cycles through these images;
		// AcquireSwapchainImage tells us which index to use each frame.
		for img in images {
			append(
				&xr_ctx.eye_targets[eye],
				wrap_swapchain_image(img.image, xr_ctx.view_w, xr_ctx.view_h),
			)
		}
	}
}

// Prefer plain RGBA8. raylib does not do sRGB conversion on write, so an
// sRGB swapchain double-applies gamma and the whole scene looks washed out.
xr_pick_swapchain_format :: proc() -> i64 {
	count: u32
	xr.EnumerateSwapchainFormats(xr_ctx.session, 0, &count, nil)

	formats := make([]i64, count)
	defer delete(formats)
	xr.EnumerateSwapchainFormats(xr_ctx.session, count, &count, raw_data(formats))

	for f in formats {
		if f == GL_RGBA8 {
			fmt.println("[xr] using linear RGBA8 swapchain")
			return f
		}
	}
	fmt.printfln("[xr] RGBA8 unavailable; offered formats: %v", formats)
	fmt.printfln("[xr] falling back to 0x%X — press F in the window to toggle sRGB writes", formats[0])
	return formats[0]
}

// THE CORE HACK.
// A raylib RenderTexture2D is just { id, texture, depth }. We create the FBO
// and the depth buffer ourselves, then attach OpenXR's texture as the color
// target. From raylib's perspective this is an ordinary render texture.
wrap_swapchain_image :: proc(gl_tex: u32, w, h: i32) -> rl.RenderTexture2D {
	target: rl.RenderTexture2D

	target.id = rlgl.LoadFramebuffer() // raylib 5.0 signature: LoadFramebuffer(w, h)
	rlgl.EnableFramebuffer(target.id)

	// Color: OpenXR's, not ours. Never unload this.
	target.texture.id = gl_tex
	target.texture.width = w
	target.texture.height = h
	target.texture.format = .UNCOMPRESSED_R8G8B8A8
	target.texture.mipmaps = 1

	// Depth: ours. OpenXR only supplies depth if you enable the depth-layer
	// extension, so raylib needs its own or nothing z-tests.
	target.depth.id = rlgl.LoadTextureDepth(w, h, true)
	target.depth.width = w
	target.depth.height = h
	target.depth.format = rl.PixelFormat(19) // raylib's internal depth marker
	target.depth.mipmaps = 1

	rlgl.FramebufferAttach(target.id, target.texture.id, ATTACH_COLOR_CHANNEL0, ATTACH_TEXTURE2D, 0)
	rlgl.FramebufferAttach(target.id, target.depth.id, ATTACH_DEPTH, ATTACH_RENDERBUFFER, 0)

	if !rlgl.FramebufferComplete(target.id) {
		fmt.println("[xr] framebuffer incomplete")
	}
	rlgl.DisableFramebuffer()

	return target
}
