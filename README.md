# odin-raylib-openxr

--DISCLAIMER--
I am only a hobbyist programmer and wanted to use Odin for VR so I used claude to get Openxr working with Raylib.
Everything is AI generated (since I could not do it alone).
Has been tested and working on Windows 11 with Quest3 using Steam Link.

--ABOUT--
A minimal PC VR application in Odin. raylib provides the OpenGL context and
all the drawing; OpenXR provides head pose, per-eye projection, controller
input, and the swapchain images the compositor displays.

The trick that makes it work: raylib's `RenderTexture2D` is a plain struct
holding OpenGL object ids. Nothing requires those ids to come from raylib, so
we build a framebuffer around the texture OpenXR hands us. From that point on
`BeginTextureMode` renders straight into the headset's swapchain, and ordinary
raylib draw calls — `DrawModelEx`, materials, custom shaders — work unchanged.

## Features

- Stereo rendering with correct asymmetric per-eye projection
- Head and controller tracking
- Full Meta Touch input: triggers, grips, thumbsticks, A/B/X/Y, menu, haptics
- Desktop mirror window
- ~900 lines across 10 files, no engine, no abstraction layer

## Requirements

Windows, an OpenXR runtime (SteamVR or Meta Link), and a tethered headset.
Odin has no Android target, so standalone Quest builds are not possible.

## Setup
1. `odin run . -out:editor.exe`

`scene.odin` is the file you edit; everything prefixed `xr_` is plumbing.
See the [guide PDF](odin-raylib-openxr-guide.pdf) for how it all fits together
and a symptom-to-cause table for the failures that are silent in VR.



<img width="738" height="467" alt="image" src="https://github.com/user-attachments/assets/3a3ea4f1-1d49-4f77-880e-4d7616e9e54e" />

