package main

import "core:fmt"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import xr "openxr"

// =============================================================================
// FRAME RENDERING
// =============================================================================
//
// One eye at a time into an OpenXR swapchain image, then the whole frame
// submitted as a projection layer. Plus the desktop mirror window.

// Everything drawn into one eye, between the matrix setup and teardown.
render_eye :: proc(target: rl.RenderTexture2D, view: xr.View) {
	proj := xr_projection(view.fov, 0.05, 1000)
	viewm := xr_view_matrix(view.pose)

	proj_f := matrix_to_gl(proj)
	view_f := matrix_to_gl(viewm)

	rl.BeginTextureMode(target)

	if srgb_write {
		glEnable(GL_FRAMEBUFFER_SRGB)
	} else {
		glDisable(GL_FRAMEBUFFER_SRGB)
	}

	rl.ClearBackground({26, 26, 38, 255})

	// --- BeginMode3D's body, with OpenXR's matrices ---
	rlgl.DrawRenderBatchActive()
	rlgl.MatrixMode(rlgl.PROJECTION)
	rlgl.PushMatrix()
	rlgl.LoadIdentity()
	rlgl.MultMatrixf(raw_data(proj_f[:]))

	rlgl.MatrixMode(rlgl.MODELVIEW)
	rlgl.LoadIdentity()
	rlgl.MultMatrixf(raw_data(view_f[:]))

	rlgl.EnableDepthTest()

	// ---- your scene ----
	draw_scene()
	pointer()
	// --------------------

	// --- EndMode3D's body ---
	rlgl.DrawRenderBatchActive()
	rlgl.MatrixMode(rlgl.PROJECTION)
	rlgl.PopMatrix()
	rlgl.MatrixMode(rlgl.MODELVIEW)
	rlgl.LoadIdentity()
	rlgl.DisableDepthTest()

	rl.EndTextureMode()

	// Leave it off for the desktop mirror, which is a plain backbuffer.
	glDisable(GL_FRAMEBUFFER_SRGB)
}

xr_frame :: proc() {
	frame_state := xr.FrameState{sType = .FRAME_STATE}
	xr.WaitFrame(xr_ctx.session, nil, &frame_state) // blocks; this is our pacing
	xr.BeginFrame(xr_ctx.session, nil)

	layers: [1]^xr.CompositionLayerBaseHeader
	layer_count: u32 = 0
	projection_views: [2]xr.CompositionLayerProjectionView
	projection_layer: xr.CompositionLayerProjection

	if frame_state.shouldRender {
		xr_sync_input(frame_state.predictedDisplayTime)

		views: [2]xr.View
		for &v in views {
			v.sType = .VIEW
		}

		locate_info := xr.ViewLocateInfo {
			sType                 = .VIEW_LOCATE_INFO,
			viewConfigurationType = .PRIMARY_STEREO,
			displayTime           = frame_state.predictedDisplayTime,
			space                 = xr_ctx.space,
		}
		view_state := xr.ViewState{sType = .VIEW_STATE}
		view_count: u32 = 2
		xr.LocateViews(xr_ctx.session, &locate_info, &view_state, 2, &view_count, &views[0])

		for eye in 0 ..< 2 {
			index: u32
			xr.AcquireSwapchainImage(xr_ctx.swapchains[eye], nil, &index)

			wait_info := xr.SwapchainImageWaitInfo {
				sType   = .SWAPCHAIN_IMAGE_WAIT_INFO,
				timeout = xr.Duration(1_000_000_000),
			}
			xr.WaitSwapchainImage(xr_ctx.swapchains[eye], &wait_info)

			render_eye(xr_ctx.eye_targets[eye][index], views[eye])
			xr_ctx.last_index[eye] = index

			xr.ReleaseSwapchainImage(xr_ctx.swapchains[eye], nil)

			projection_views[eye] = xr.CompositionLayerProjectionView {
				sType = .COMPOSITION_LAYER_PROJECTION_VIEW,
				pose  = views[eye].pose,
				fov   = views[eye].fov,
				subImage = {
					swapchain = xr_ctx.swapchains[eye],
					imageRect = {{0, 0}, {xr_ctx.view_w, xr_ctx.view_h}},
				},
			}
		}

		projection_layer = xr.CompositionLayerProjection {
			sType     = .COMPOSITION_LAYER_PROJECTION,
			space     = xr_ctx.space,
			viewCount = 2,
			views     = &projection_views[0],
		}
		layers[0] = cast(^xr.CompositionLayerBaseHeader)&projection_layer
		layer_count = 1
	}

	end_info := xr.FrameEndInfo {
		sType                = .FRAME_END_INFO,
		displayTime          = frame_state.predictedDisplayTime,
		environmentBlendMode = .OPAQUE,
		layerCount           = layer_count,
		// Must be nil when the count is zero — some runtimes validate this
		// pointer even though the spec says it's ignored.
		layers               = layer_count > 0 ? &layers[0] : nil,
	}
	end_result := xr.EndFrame(xr_ctx.session, &end_info)

	// --- diagnostics: delete once it's working ---
	@(static) logged: int
	if logged < 120 {
		logged += 1
		fmt.printfln(
			"[xr] state=%v shouldRender=%v layers=%v endFrame=%v",
			xr_ctx.state,
			frame_state.shouldRender,
			layer_count,
			end_result,
		)
	}
}

// Desktop mirror. Blit the left eye so you can see what's happening without
// the headset on.

draw_mirror :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	if len(xr_ctx.eye_targets[0]) > 0 {
		tex := xr_ctx.eye_targets[0][xr_ctx.last_index[0]].texture
		src := rl.Rectangle{0, 0, f32(tex.width), -f32(tex.height)} // negative = flip Y
		dst := rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
		rl.DrawTexturePro(tex, src, dst, {0, 0}, 0, rl.WHITE)
	}

	rl.DrawFPS(10, 10)
	rl.EndDrawing()
}
