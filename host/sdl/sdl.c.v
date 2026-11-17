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

pub struct C.SDL_Rect {
pub mut:
	x int
	y int
	w int
	h int
}

pub struct C.SDL_Point {
pub:
	x int
	y int
}

pub struct C.SDL_Surface {
pub:
	w      int
	h      int
	pitch  int
	pixels voidptr
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
	type   u32
	which  u32
	button u8
	down   bool
}

pub struct C.SDL_GamepadAxisEvent {
pub:
	type  u32
	which u32
	axis  u8
	value i16
}

pub struct C.SDL_WindowEvent {
pub:
	type u32
}

pub struct C.SDL_MouseMotionEvent {
pub:
	x f32
	y f32
}

pub struct C.SDL_MouseButtonEvent {
pub:
	button u8
	down   bool
	x      f32
	y      f32
}

pub struct C.SDL_GamepadDeviceEvent {
pub:
	type  u32
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
	motion  C.SDL_MouseMotionEvent
	button  C.SDL_MouseButtonEvent
	gbutton C.SDL_GamepadButtonEvent
	gaxis   C.SDL_GamepadAxisEvent
	window  C.SDL_WindowEvent
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

fn C.SDL_SetHint(name &char, value &char) bool
fn C.SDL_SetWindowSize(window voidptr, w int, h int) bool
fn C.SDL_SetWindowHitTest(window voidptr, callback voidptr, data voidptr) bool
fn C.SDL_SetRenderDrawBlendMode(renderer voidptr, mode u32) bool
fn C.SDL_RenderFillRect(renderer voidptr, rect &C.SDL_FRect) bool
fn C.SDL_SetRenderClipRect(renderer voidptr, rect &C.SDL_Rect) bool
fn C.SDL_SetTextureBlendMode(texture voidptr, mode u32) bool
fn C.SDL_SetTextureAlphaMod(texture voidptr, alpha u8) bool
fn C.SDL_CreateTextureFromSurface(renderer voidptr, surface &C.SDL_Surface) voidptr
fn C.SDL_IOFromConstMem(mem voidptr, size usize) voidptr
fn C.SDL_LoadPNG_IO(src voidptr, closeio bool) &C.SDL_Surface
fn C.SDL_ConvertSurface(surface &C.SDL_Surface, format u32) &C.SDL_Surface

fn C.SDL_RenderReadPixels(renderer voidptr, rect voidptr) &C.SDL_Surface
fn C.SDL_SaveBMP(surface &C.SDL_Surface, file &char) bool
fn C.SDL_DestroySurface(surface &C.SDL_Surface)

fn C.SDL_PollEvent(event &C.SDL_Event) bool
fn C.SDL_PushEvent(event &C.SDL_Event) bool

fn C.SDL_OpenAudioDeviceStream(device u32, spec &C.SDL_AudioSpec, callback voidptr, userdata voidptr) voidptr
fn C.SDL_DestroyAudioStream(stream voidptr)
fn C.SDL_ResumeAudioStreamDevice(stream voidptr) bool
fn C.SDL_SetAudioStreamFormat(stream voidptr, src &C.SDL_AudioSpec, dst &C.SDL_AudioSpec) bool
fn C.SDL_PutAudioStreamData(stream voidptr, data voidptr, len int) bool
fn C.SDL_GetAudioStreamQueued(stream voidptr) int
fn C.SDL_ClearAudioStream(stream voidptr) bool
fn C.SDL_SetAudioStreamFrequencyRatio(stream voidptr, ratio f32) bool

fn C.SDL_OpenGamepad(id u32) voidptr
fn C.SDL_CloseGamepad(gamepad voidptr)
fn C.SDL_GetGamepads(count &int) &u32
fn C.SDL_GetJoysticks(count &int) &u32
fn C.SDL_IsGamepad(id u32) bool
fn C.SDL_GetGamepadButton(gamepad voidptr, button int) bool
fn C.SDL_GetGamepadAxis(gamepad voidptr, axis int) i16
fn C.SDL_GetGamepadName(gamepad voidptr) &char
fn C.SDL_GetJoystickNameForID(id u32) &char
fn C.SDL_GetGamepadSerial(gamepad voidptr) &char
fn C.SDL_GetGamepadVendor(gamepad voidptr) u16
fn C.SDL_GetGamepadProduct(gamepad voidptr) u16
fn C.SDL_GetGamepadMapping(gamepad voidptr) &char
fn C.SDL_GetGamepadConnectionState(gamepad voidptr) int
fn C.SDL_GetGamepadPowerInfo(gamepad voidptr, percent &int) int
fn C.SDL_GetGamepadButtonLabel(gamepad voidptr, button int) int
fn C.SDL_GamepadHasButton(gamepad voidptr, button int) bool
fn C.SDL_GamepadHasAxis(gamepad voidptr, axis int) bool
fn C.SDL_AddGamepadMappingsFromFile(path &char) int
fn C.SDL_GetVersion() int
fn C.SDL_free(memory voidptr)

pub struct C.SDL_GUID {
pub:
	data [16]u8
}

fn C.SDL_GetJoystickGUIDForID(id u32) C.SDL_GUID
fn C.SDL_GUIDToString(guid C.SDL_GUID, text &char, size int)
fn C.SDL_GetPlatform() &char

fn joystick_guid(id u32) string {
	mut buffer := [33]u8{}
	C.SDL_GUIDToString(C.SDL_GetJoystickGUIDForID(id), &char(&buffer[0]), 33)
	return unsafe { cstring_to_vstring(&char(&buffer[0])) }
}

fn c_text(value &char) string {
	if value == unsafe { nil } { return '' }
	return unsafe { cstring_to_vstring(value) }
}

// last_error returns SDL's description of the most recent failure.
fn last_error() string {
	return unsafe { cstring_to_vstring(C.SDL_GetError()) }
}

// Virtual devices exercise SDL's mapping and event path in regression tests.
pub struct C.SDL_VirtualJoystickDesc {
pub:
	version     u32
	type        u16
	vendor_id   u16
	product_id  u16
	naxes       u16
	nbuttons    u16
	button_mask u32
	axis_mask   u32
	name        &char
}

fn C.SDL_AttachVirtualJoystick(desc &C.SDL_VirtualJoystickDesc) u32
fn C.SDL_DetachVirtualJoystick(id u32) bool
fn C.SDL_OpenJoystick(id u32) voidptr
fn C.SDL_CloseJoystick(joystick voidptr)
fn C.SDL_SetJoystickVirtualButton(joystick voidptr, button int, down bool) bool
fn C.SDL_SetJoystickVirtualAxis(joystick voidptr, axis int, value i16) bool
fn C.SDL_UpdateJoysticks()
