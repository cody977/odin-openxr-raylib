package main

import "core:fmt"
import xr "openxr"

// =============================================================================
// INPUT ACTIONS
// =============================================================================
//
// OpenXR does not let you read a button directly. You declare abstract actions
// ("trigger", "jump"), suggest which physical inputs they map to on each
// controller type, and the runtime does the binding — which is why the same
// code works on Touch, Index, and WMR, and why users can rebind you.
//
// Order is fixed and one-shot:
//   1. CreateActionSet
//   2. CreateAction        (ALL of them — you cannot add more later)
//   3. SuggestInteractionProfileBindings  (once per controller profile)
//   4. CreateActionSpace   (for pose actions)
//   5. AttachSessionActionSets            (permanent for the session)
// Then every frame: SyncActions, then GetActionState* per action per hand.
//
// To add a button: add an Action field, create it in xr_init_actions, add its
// binding path, and read it in xr_sync_input. Four edits, all in this file.

Hand :: enum {
	Left  = 0,
	Right = 1,
}

// Everything readable about one controller this frame.
HandState :: struct {
	// tracking
	active:           bool, // controller is being tracked right now
	aim:              xr.Posef, // pointing ray — for raycasts / laser pointers
	grip:             xr.Posef, // physical hand position — for held objects

	// analog
	trigger:          f32, // 0..1
	squeeze:          f32, // 0..1 (side grip button)
	stick:            [2]f32, // -1..1 each axis, y is +up

	// buttons, held state
	a:                bool, // A on right, X on left
	b:                bool, // B on right, Y on left
	stick_click:      bool,
	menu:             bool, // left controller only

	// just-pressed this frame (equivalent to LOVR's 'pressed')
	a_pressed:        bool,
	b_pressed:        bool,
	stick_pressed:    bool,
	menu_pressed:     bool,
	trigger_pressed:  bool, // crosses the threshold going up
	squeeze_pressed:  bool,

	// just-released this frame
	a_released:       bool,
	b_released:       bool,
	trigger_released: bool,
}

Input :: struct {
	action_set:         xr.ActionSet,
	hand_paths:         [MAX_HANDS]xr.Path,

	// actions
	aim_action:         xr.Action,
	grip_action:        xr.Action,
	trigger_action:     xr.Action,
	squeeze_action:     xr.Action,
	stick_action:       xr.Action,
	stick_click_action: xr.Action,
	a_action:           xr.Action,
	b_action:           xr.Action,
	menu_action:        xr.Action,
	haptic_action:      xr.Action,

	// spaces for the two pose actions
	aim_spaces:         [MAX_HANDS]xr.Space,
	grip_spaces:        [MAX_HANDS]xr.Space,

	// per-frame state — what you actually read
	hands:              [MAX_HANDS]HandState,

	// previous analog values, for edge detection
	prev_trigger:       [MAX_HANDS]f32,
	prev_squeeze:       [MAX_HANDS]f32,
}

TRIGGER_THRESHOLD :: 0.5

// -----------------------------------------------------------------------------
// Setup
// -----------------------------------------------------------------------------

@(private = "file")
make_action :: proc(name, localized: string, type: xr.ActionType, out: ^xr.Action) {
	info := xr.ActionCreateInfo {
		sType               = .ACTION_CREATE_INFO,
		actionName          = xr.make_string(name, 64),
		actionType          = type,
		countSubactionPaths = MAX_HANDS,
		subactionPaths      = &xr_ctx.input.hand_paths[0],
		localizedActionName = xr.make_string(localized, 128),
	}
	xr.CreateAction(xr_ctx.input.action_set, &info, out)
}

@(private = "file")
path :: proc(s: string) -> xr.Path {
	p: xr.Path
	xr.StringToPath(xr_ctx.instance, fmt.ctprint(s), &p)
	return p
}

xr_init_actions :: proc() {
	in_ := &xr_ctx.input

	set_info := xr.ActionSetCreateInfo {
		sType                  = .ACTION_SET_CREATE_INFO,
		actionSetName          = xr.make_string("gameplay", 64),
		localizedActionSetName = xr.make_string("Gameplay", 128),
		priority               = 0,
	}
	xr.CreateActionSet(xr_ctx.instance, &set_info, &in_.action_set)

	in_.hand_paths[Hand.Left] = path("/user/hand/left")
	in_.hand_paths[Hand.Right] = path("/user/hand/right")

	// All actions must exist before AttachSessionActionSets.
	make_action("aim", "Aim Pose", .POSE_INPUT, &in_.aim_action)
	make_action("grip", "Grip Pose", .POSE_INPUT, &in_.grip_action)
	make_action("trigger", "Trigger", .FLOAT_INPUT, &in_.trigger_action)
	make_action("squeeze", "Grip Squeeze", .FLOAT_INPUT, &in_.squeeze_action)
	make_action("stick", "Thumbstick", .VECTOR2F_INPUT, &in_.stick_action)
	make_action("stick_click", "Thumbstick Click", .BOOLEAN_INPUT, &in_.stick_click_action)
	make_action("button_a", "A / X Button", .BOOLEAN_INPUT, &in_.a_action)
	make_action("button_b", "B / Y Button", .BOOLEAN_INPUT, &in_.b_action)
	make_action("menu", "Menu Button", .BOOLEAN_INPUT, &in_.menu_action)
	make_action("haptic", "Vibration", .VIBRATION_OUTPUT, &in_.haptic_action)

	xr_suggest_touch_bindings()
	xr_suggest_simple_bindings()

	// Action spaces turn pose actions into something LocateSpace can query.
	for i in 0 ..< MAX_HANDS {
		aim_info := xr.ActionSpaceCreateInfo {
			sType             = .ACTION_SPACE_CREATE_INFO,
			action            = in_.aim_action,
			subactionPath     = in_.hand_paths[i],
			poseInActionSpace = {orientation = {0, 0, 0, 1}, position = {0, 0, 0}},
		}
		xr.CreateActionSpace(xr_ctx.session, &aim_info, &in_.aim_spaces[i])

		grip_info := xr.ActionSpaceCreateInfo {
			sType             = .ACTION_SPACE_CREATE_INFO,
			action            = in_.grip_action,
			subactionPath     = in_.hand_paths[i],
			poseInActionSpace = {orientation = {0, 0, 0, 1}, position = {0, 0, 0}},
		}
		xr.CreateActionSpace(xr_ctx.session, &grip_info, &in_.grip_spaces[i])
	}

	attach_info := xr.SessionActionSetsAttachInfo {
		sType           = .SESSION_ACTION_SETS_ATTACH_INFO,
		countActionSets = 1,
		actionSets      = &in_.action_set,
	}
	xr.AttachSessionActionSets(xr_ctx.session, &attach_info)
}

// Meta Touch — the profile Quest 2 / 3 / Pro controllers report.
//
// Note the asymmetry, which is the hardware's own: X/Y are on the left
// controller and A/B on the right, so one a_action maps to X on the left hand
// and A on the right. The menu button exists only on the left — the right
// controller's system button is reserved by the runtime and cannot be bound.
xr_suggest_touch_bindings :: proc() {
	in_ := &xr_ctx.input

	bindings := []xr.ActionSuggestedBinding {
		{in_.aim_action, path("/user/hand/left/input/aim/pose")},
		{in_.aim_action, path("/user/hand/right/input/aim/pose")},
		{in_.grip_action, path("/user/hand/left/input/grip/pose")},
		{in_.grip_action, path("/user/hand/right/input/grip/pose")},
		{in_.trigger_action, path("/user/hand/left/input/trigger/value")},
		{in_.trigger_action, path("/user/hand/right/input/trigger/value")},
		{in_.squeeze_action, path("/user/hand/left/input/squeeze/value")},
		{in_.squeeze_action, path("/user/hand/right/input/squeeze/value")},
		{in_.stick_action, path("/user/hand/left/input/thumbstick")},
		{in_.stick_action, path("/user/hand/right/input/thumbstick")},
		{in_.stick_click_action, path("/user/hand/left/input/thumbstick/click")},
		{in_.stick_click_action, path("/user/hand/right/input/thumbstick/click")},
		{in_.a_action, path("/user/hand/left/input/x/click")},
		{in_.a_action, path("/user/hand/right/input/a/click")},
		{in_.b_action, path("/user/hand/left/input/y/click")},
		{in_.b_action, path("/user/hand/right/input/b/click")},
		{in_.menu_action, path("/user/hand/left/input/menu/click")},
		{in_.haptic_action, path("/user/hand/left/output/haptic")},
		{in_.haptic_action, path("/user/hand/right/output/haptic")},
	}

	suggested := xr.InteractionProfileSuggestedBinding {
		sType                  = .INTERACTION_PROFILE_SUGGESTED_BINDING,
		interactionProfile     = path("/interaction_profiles/oculus/touch_controller"),
		countSuggestedBindings = u32(len(bindings)),
		suggestedBindings      = raw_data(bindings),
	}
	result := xr.SuggestInteractionProfileBindings(xr_ctx.instance, &suggested)
	fmt.printfln("[xr] touch controller bindings: %v", result)
}

// Fallback so something still works on non-Meta hardware. Every runtime
// supports this profile, but it has only select and menu — no stick, no A/B.
xr_suggest_simple_bindings :: proc() {
	in_ := &xr_ctx.input

	bindings := []xr.ActionSuggestedBinding {
		{in_.aim_action, path("/user/hand/left/input/aim/pose")},
		{in_.aim_action, path("/user/hand/right/input/aim/pose")},
		{in_.grip_action, path("/user/hand/left/input/grip/pose")},
		{in_.grip_action, path("/user/hand/right/input/grip/pose")},
		{in_.a_action, path("/user/hand/left/input/select/click")},
		{in_.a_action, path("/user/hand/right/input/select/click")},
		{in_.menu_action, path("/user/hand/left/input/menu/click")},
		{in_.menu_action, path("/user/hand/right/input/menu/click")},
		{in_.haptic_action, path("/user/hand/left/output/haptic")},
		{in_.haptic_action, path("/user/hand/right/output/haptic")},
	}

	suggested := xr.InteractionProfileSuggestedBinding {
		sType                  = .INTERACTION_PROFILE_SUGGESTED_BINDING,
		interactionProfile     = path("/interaction_profiles/khr/simple_controller"),
		countSuggestedBindings = u32(len(bindings)),
		suggestedBindings      = raw_data(bindings),
	}
	xr.SuggestInteractionProfileBindings(xr_ctx.instance, &suggested)
}

// -----------------------------------------------------------------------------
// Per-frame read
// -----------------------------------------------------------------------------

@(private = "file")
get_bool :: proc(action: xr.Action, hand: int) -> (current: bool, changed: bool) {
	info := xr.ActionStateGetInfo {
		sType         = .ACTION_STATE_GET_INFO,
		action        = action,
		subactionPath = xr_ctx.input.hand_paths[hand],
	}
	state := xr.ActionStateBoolean{sType = .ACTION_STATE_BOOLEAN}
	if xr.GetActionStateBoolean(xr_ctx.session, &info, &state) != .SUCCESS {
		return false, false
	}
	if !state.isActive {
		return false, false
	}
	return bool(state.currentState), bool(state.changedSinceLastSync)
}

@(private = "file")
get_float :: proc(action: xr.Action, hand: int) -> f32 {
	info := xr.ActionStateGetInfo {
		sType         = .ACTION_STATE_GET_INFO,
		action        = action,
		subactionPath = xr_ctx.input.hand_paths[hand],
	}
	state := xr.ActionStateFloat{sType = .ACTION_STATE_FLOAT}
	if xr.GetActionStateFloat(xr_ctx.session, &info, &state) != .SUCCESS {
		return 0
	}
	if !state.isActive {
		return 0
	}
	return state.currentState
}

@(private = "file")
get_vec2 :: proc(action: xr.Action, hand: int) -> [2]f32 {
	info := xr.ActionStateGetInfo {
		sType         = .ACTION_STATE_GET_INFO,
		action        = action,
		subactionPath = xr_ctx.input.hand_paths[hand],
	}
	state := xr.ActionStateVector2f{sType = .ACTION_STATE_VECTOR2F}
	if xr.GetActionStateVector2f(xr_ctx.session, &info, &state) != .SUCCESS {
		return {0, 0}
	}
	if !state.isActive {
		return {0, 0}
	}
	return {state.currentState.x, state.currentState.y}
}

xr_sync_input :: proc(predicted_time: xr.Time) {
	in_ := &xr_ctx.input

	active := xr.ActiveActionSet {
		actionSet     = in_.action_set,
		subactionPath = xr.Path(0), // XR_NULL_PATH — all subaction paths
	}
	sync_info := xr.ActionsSyncInfo {
		sType                 = .ACTIONS_SYNC_INFO,
		countActiveActionSets = 1,
		activeActionSets      = &active,
	}
	// Returns SESSION_NOT_FOCUSED whenever a system overlay has focus. That's
	// normal, not an error — leave last frame's state alone and bail.
	if xr.SyncActions(xr_ctx.session, &sync_info) != .SUCCESS {
		return
	}

	for i in 0 ..< MAX_HANDS {
		h := &in_.hands[i]

		// --- poses ---
		aim_loc := xr.SpaceLocation{sType = .SPACE_LOCATION}
		xr.LocateSpace(in_.aim_spaces[i], xr_ctx.space, predicted_time, &aim_loc)
		h.active =
			(.POSITION_VALID in aim_loc.locationFlags) &&
			(.ORIENTATION_VALID in aim_loc.locationFlags)
		if h.active {
			h.aim = aim_loc.pose
		}

		grip_loc := xr.SpaceLocation{sType = .SPACE_LOCATION}
		xr.LocateSpace(in_.grip_spaces[i], xr_ctx.space, predicted_time, &grip_loc)
		if .POSITION_VALID in grip_loc.locationFlags {
			h.grip = grip_loc.pose
		}

		// --- analog ---
		h.trigger = get_float(in_.trigger_action, i)
		h.squeeze = get_float(in_.squeeze_action, i)
		h.stick = get_vec2(in_.stick_action, i)

		// Analog edges are threshold crossings tracked against last frame.
		h.trigger_pressed =
			h.trigger >= TRIGGER_THRESHOLD && in_.prev_trigger[i] < TRIGGER_THRESHOLD
		h.trigger_released =
			h.trigger < TRIGGER_THRESHOLD && in_.prev_trigger[i] >= TRIGGER_THRESHOLD
		h.squeeze_pressed =
			h.squeeze >= TRIGGER_THRESHOLD && in_.prev_squeeze[i] < TRIGGER_THRESHOLD
		in_.prev_trigger[i] = h.trigger
		in_.prev_squeeze[i] = h.squeeze

		// --- buttons ---
		// changedSinceLastSync gives the edge for free, so digital inputs need
		// no manual previous-state tracking.
		a_now, a_changed := get_bool(in_.a_action, i)
		h.a = a_now
		h.a_pressed = a_now && a_changed
		h.a_released = !a_now && a_changed

		b_now, b_changed := get_bool(in_.b_action, i)
		h.b = b_now
		h.b_pressed = b_now && b_changed
		h.b_released = !b_now && b_changed

		s_now, s_changed := get_bool(in_.stick_click_action, i)
		h.stick_click = s_now
		h.stick_pressed = s_now && s_changed

		m_now, m_changed := get_bool(in_.menu_action, i)
		h.menu = m_now
		h.menu_pressed = m_now && m_changed
	}
}

// -----------------------------------------------------------------------------
// Convenience
// -----------------------------------------------------------------------------

// hand(.Right).trigger_pressed reads better than digging into the context.
hand :: proc(h: Hand) -> ^HandState {
	return &xr_ctx.input.hands[int(h)]
}

// duration in seconds, frequency in Hz (0 lets the runtime pick),
// amplitude 0..1.
rumble :: proc(h: Hand, duration: f32 = 0.1, frequency: f32 = 0, amplitude: f32 = 0.5) {
	vibration := xr.HapticVibration {
		sType     = .HAPTIC_VIBRATION,
		duration  = xr.Duration(i64(duration * 1_000_000_000)),
		frequency = frequency,
		amplitude = amplitude,
	}
	info := xr.HapticActionInfo {
		sType         = .HAPTIC_ACTION_INFO,
		action        = xr_ctx.input.haptic_action,
		subactionPath = xr_ctx.input.hand_paths[int(h)],
	}
	xr.ApplyHapticFeedback(xr_ctx.session, &info, cast(^xr.HapticBaseHeader)&vibration)
}
