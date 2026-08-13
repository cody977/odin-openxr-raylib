package main

import win32 "core:sys/windows"

// =============================================================================
// GL CONTEXT + GPU SELECTION
// =============================================================================
//
// Raw OpenGL and WGL entry points raylib doesn't expose, the constants
// they need, and the exported symbols that force a laptop onto its discrete
// GPU. Nothing here is VR-specific.

// -----------------------------------------------------------------------------
// GL context handoff
// -----------------------------------------------------------------------------
// OpenXR needs the HDC/HGLRC of the context it will share textures with.
// raylib creates that context inside InitWindow, and wgl*Current returns
// whatever is current on the calling thread — so calling these on the main
// thread after InitWindow gets us raylib's context without digging into its
// internal GLFW window handle.

foreign import opengl32 "system:opengl32.lib"

@(default_calling_convention = "system")
foreign opengl32 {
	wglGetCurrentDC :: proc() -> win32.HDC ---
	wglGetCurrentContext :: proc() -> win32.HGLRC ---
	glGetString :: proc(name: u32) -> cstring ---
	glEnable :: proc(cap: u32) ---
	glDisable :: proc(cap: u32) ---
}

GL_RENDERER :: 0x1F01
GL_FRAMEBUFFER_SRGB :: 0x8DB9

// When the swapchain is an sRGB format, whether GL converts linear->sRGB on
// write changes the brightness of everything. raylib does not enable this
// itself, and which setting is correct depends on the runtime, so it's a
// toggle: press F in the mirror window to flip it and pick what looks right.
srgb_write: bool = false

// -----------------------------------------------------------------------------
// Discrete GPU preference
// -----------------------------------------------------------------------------
// On laptops the driver hands OpenGL apps the integrated GPU by default. That
// is fatal for VR: SteamVR's compositor lives on the discrete GPU, and OpenGL
// textures cannot be shared across adapters, so the runtime accepts every
// frame and displays none of them.
//
// Exporting these two symbols is the documented opt-in that NVIDIA Optimus and
// AMD PowerXpress look for at process start.
//
// If it still reports Intel, override it in Windows Settings -> System ->
// Display -> Graphics -> add editor.exe -> High performance.

@(export, link_name = "NvOptimusEnablement")
NvOptimusEnablement: u32 = 1

@(export, link_name = "AmdPowerXpressRequestHighPerformance")
AmdPowerXpressRequestHighPerformance: i32 = 1

GL_RGBA8 :: 0x8058
GL_SRGB8_ALPHA8 :: 0x8C43

// FramebufferAttach takes plain i32 in this binding rather than enums, so
// these are the values from rlgl.h (rlFramebufferAttachType and
// rlFramebufferAttachTextureType) spelled out.
ATTACH_COLOR_CHANNEL0 :: i32(0)
ATTACH_DEPTH :: i32(100)
ATTACH_TEXTURE2D :: i32(100)
ATTACH_RENDERBUFFER :: i32(200)
