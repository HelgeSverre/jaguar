// Minimal SDL3 binding: only the declarations the frontend uses.
//
// V takes struct layouts and constant values from the SDL headers at C
// compile time, so the field subsets below cannot drift from the ABI.
module sdl

#pkgconfig sdl3
#include <SDL3/SDL.h>

pub struct C.SDL_FRect {
pub mut:
	x f32
	y f32
	w f32
	h f32
}

pub struct C.SDL_AudioSpec {
pub mut:
	format   int
	channels int
	freq     int
}

pub struct C.SDL_KeyboardEvent {
pub:
	type     u32
	scancode int
	down     bool
	repeat   bool
}

pub struct C.SDL_GamepadButtonEvent {
pub:
	which  u32
	button u8
	down   bool
}

pub struct C.SDL_GamepadDeviceEvent {
pub:
	which u32
}

pub struct C.SDL_DropEvent {
pub:
	type u32
	data &char
}

pub union C.SDL_Event {
pub:
	type    u32
	key     C.SDL_KeyboardEvent
	gbutton C.SDL_GamepadButtonEvent
	gdevice C.SDL_GamepadDeviceEvent
	drop    C.SDL_DropEvent
}

fn C.SDL_Init(flags u32) bool
fn C.SDL_Quit()
fn C.SDL_GetError() &char
fn C.SDL_GetTicksNS() u64
fn C.SDL_DelayNS(ns u64)

fn C.SDL_CreateWindow(title &char, w int, h int, flags u64) voidptr
fn C.SDL_DestroyWindow(window voidptr)
fn C.SDL_SetWindowTitle(window voidptr, title &char) bool
fn C.SDL_SetWindowFullscreen(window voidptr, fullscreen bool) bool
fn C.SDL_CreateRenderer(window voidptr, name &char) voidptr
fn C.SDL_DestroyRenderer(renderer voidptr)
fn C.SDL_SetRenderVSync(renderer voidptr, vsync int) bool
fn C.SDL_GetRenderOutputSize(renderer voidptr, w &int, h &int) bool
fn C.SDL_SetRenderDrawColor(renderer voidptr, r u8, g u8, b u8, a u8) bool
fn C.SDL_RenderClear(renderer voidptr) bool
fn C.SDL_RenderTexture(renderer voidptr, texture voidptr, src &C.SDL_FRect, dst &C.SDL_FRect) bool
fn C.SDL_RenderDebugText(renderer voidptr, x f32, y f32, text &char) bool
fn C.SDL_SetRenderScale(renderer voidptr, x f32, y f32) bool
fn C.SDL_RenderPresent(renderer voidptr) bool
fn C.SDL_CreateTexture(renderer voidptr, format u32, access int, w int, h int) voidptr
fn C.SDL_DestroyTexture(texture voidptr)
fn C.SDL_SetTextureScaleMode(texture voidptr, mode int) bool
fn C.SDL_UpdateTexture(texture voidptr, rect voidptr, pixels voidptr, pitch int) bool

fn C.SDL_RenderReadPixels(renderer voidptr, rect voidptr) voidptr
fn C.SDL_SaveBMP(surface voidptr, file &char) bool
fn C.SDL_DestroySurface(surface voidptr)

fn C.SDL_PollEvent(event &C.SDL_Event) bool
fn C.SDL_PushEvent(event &C.SDL_Event) bool

fn C.SDL_OpenAudioDeviceStream(device u32, spec &C.SDL_AudioSpec, callback voidptr, userdata voidptr) voidptr
fn C.SDL_DestroyAudioStream(stream voidptr)
fn C.SDL_ResumeAudioStreamDevice(stream voidptr) bool
fn C.SDL_SetAudioStreamFormat(stream voidptr, src &C.SDL_AudioSpec, dst &C.SDL_AudioSpec) bool
fn C.SDL_PutAudioStreamData(stream voidptr, data voidptr, len int) bool
fn C.SDL_GetAudioStreamQueued(stream voidptr) int
fn C.SDL_ClearAudioStream(stream voidptr) bool

fn C.SDL_OpenGamepad(id u32) voidptr
fn C.SDL_CloseGamepad(gamepad voidptr)

// last_error returns SDL's description of the most recent failure.
fn last_error() string {
	return unsafe { cstring_to_vstring(C.SDL_GetError()) }
}
