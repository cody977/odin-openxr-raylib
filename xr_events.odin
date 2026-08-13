package main

import "core:fmt"
import xr "openxr"

// =============================================================================
// SESSION STATE MACHINE
// =============================================================================
//
// The #1 reason a first OpenXR app renders black: nothing displays until
// the runtime reaches READY and you call BeginSession.

// -----------------------------------------------------------------------------
// Session state machine
// -----------------------------------------------------------------------------
// This is the #1 reason a first OpenXR app renders black with no errors:
// nothing displays until the runtime reaches READY and you call BeginSession.

xr_poll_events :: proc() {
	for {
		event := xr.EventDataBuffer{sType = .EVENT_DATA_BUFFER}
		if xr.PollEvent(xr_ctx.instance, &event) != .SUCCESS {
			break
		}

		#partial switch event.sType {
		case .EVENT_DATA_SESSION_STATE_CHANGED:
			changed := cast(^xr.EventDataSessionStateChanged)&event
			xr_ctx.state = changed.state
			fmt.printfln("[xr] session state -> %v", changed.state)

			#partial switch changed.state {
			case .READY:
				begin_info := xr.SessionBeginInfo {
					sType                        = .SESSION_BEGIN_INFO,
					primaryViewConfigurationType = .PRIMARY_STEREO,
				}
				xr.BeginSession(xr_ctx.session, &begin_info)
				xr_ctx.session_running = true

			case .STOPPING:
				// Headset taken off / app backgrounded. Must handle this or
				// the app hangs.
				xr_ctx.session_running = false
				xr.EndSession(xr_ctx.session)

			case .EXITING, .LOSS_PENDING:
				xr_ctx.should_quit = true
			}

		case .EVENT_DATA_INSTANCE_LOSS_PENDING:
			xr_ctx.should_quit = true
		}
	}
}
