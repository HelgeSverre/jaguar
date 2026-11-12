module sdl

import hwtypes

// Video owns the window, the renderer and the streaming texture.
pub struct Video {
mut:
	window         voidptr
	renderer       voidptr
	texture        voidptr
	texture_width  int
	texture_height int
	fullscreen     bool
	capture_path   string
}

// init starts the SDL subsystems the frontend needs.
pub fn init() ! {
	if !C.SDL_Init(u32(C.SDL_INIT_VIDEO) | u32(C.SDL_INIT_AUDIO) | u32(C.SDL_INIT_GAMEPAD)) {
		return error('SDL_Init failed: ${last_error()}')
	}
}

// quit shuts SDL down. Destroy every wrapper first.
pub fn quit() {
	C.SDL_Quit()
}

// new_video opens a resizable window.
pub fn new_video(title string, width int, height int) !Video {
	window := C.SDL_CreateWindow(title.str, width, height,
		u64(C.SDL_WINDOW_RESIZABLE) | u64(C.SDL_WINDOW_HIGH_PIXEL_DENSITY))
	if window == unsafe { nil } {
		return error('SDL_CreateWindow failed: ${last_error()}')
	}
	renderer := C.SDL_CreateRenderer(window, unsafe { nil })
	if renderer == unsafe { nil } {
		C.SDL_DestroyWindow(window)
		return error('SDL_CreateRenderer failed: ${last_error()}')
	}
	C.SDL_SetRenderVSync(renderer, 0)
	return Video{
		window:   window
		renderer: renderer
	}
}

// close destroys the texture, renderer and window.
pub fn (mut v Video) close() {
	if v.texture != unsafe { nil } {
		C.SDL_DestroyTexture(v.texture)
		v.texture = unsafe { nil }
	}
	C.SDL_DestroyRenderer(v.renderer)
	C.SDL_DestroyWindow(v.window)
}

// set_title changes the window title.
pub fn (v &Video) set_title(title string) {
	C.SDL_SetWindowTitle(v.window, title.str)
}

// toggle_fullscreen switches between windowed and borderless fullscreen.
pub fn (mut v Video) toggle_fullscreen() {
	v.fullscreen = !v.fullscreen
	C.SDL_SetWindowFullscreen(v.window, v.fullscreen)
}

// present uploads a frame and draws it letterboxed at a 4:3 aspect, with
// optional overlay text in the top-left corner.
pub fn (mut v Video) present(pixels []u32, info hwtypes.FrameInfo, overlay []string) ! {
	if v.texture == unsafe { nil } || v.texture_width != info.width
		|| v.texture_height != info.height {
		// A guest mode change only replaces the host texture.
		if v.texture != unsafe { nil } {
			C.SDL_DestroyTexture(v.texture)
		}
		v.texture = C.SDL_CreateTexture(v.renderer, u32(C.SDL_PIXELFORMAT_XRGB8888),
			int(C.SDL_TEXTUREACCESS_STREAMING), info.width, info.height)
		if v.texture == unsafe { nil } {
			return error('SDL_CreateTexture failed: ${last_error()}')
		}
		C.SDL_SetTextureScaleMode(v.texture, int(C.SDL_SCALEMODE_LINEAR))
		v.texture_width = info.width
		v.texture_height = info.height
	}
	C.SDL_UpdateTexture(v.texture, unsafe { nil }, pixels.data, info.pitch * 4)

	mut output_width := 0
	mut output_height := 0
	C.SDL_GetRenderOutputSize(v.renderer, &output_width, &output_height)
	mut width := f32(output_width)
	mut height := width * 3.0 / 4.0
	if height > f32(output_height) {
		height = f32(output_height)
		width = height * 4.0 / 3.0
	}
	destination := C.SDL_FRect{
		x: (f32(output_width) - width) / 2
		y: (f32(output_height) - height) / 2
		w: width
		h: height
	}
	C.SDL_SetRenderDrawColor(v.renderer, 0, 0, 0, 255)
	C.SDL_RenderClear(v.renderer)
	C.SDL_RenderTexture(v.renderer, v.texture, unsafe { nil }, &destination)
	if overlay.len > 0 {
		C.SDL_SetRenderScale(v.renderer, 2, 2)
		for i, line in overlay {
			C.SDL_SetRenderDrawColor(v.renderer, 0, 0, 0, 255)
			C.SDL_RenderDebugText(v.renderer, 5, f32(5 + i * 10), line.str)
			C.SDL_SetRenderDrawColor(v.renderer, 255, 255, 0, 255)
			C.SDL_RenderDebugText(v.renderer, 4, f32(4 + i * 10), line.str)
		}
		C.SDL_SetRenderScale(v.renderer, 1, 1)
	}
	if v.capture_path != '' {
		v.capture()!
	}
	C.SDL_RenderPresent(v.renderer)
}

// capture_next_frame saves what the renderer draws on the next `present`
// as a BMP: the picture as the host shows it, after scaling and overlay.
pub fn (mut v Video) capture_next_frame(path string) {
	v.capture_path = path
}

fn (mut v Video) capture() ! {
	path := v.capture_path
	v.capture_path = ''
	surface := C.SDL_RenderReadPixels(v.renderer, unsafe { nil })
	if surface == unsafe { nil } {
		return error('SDL_RenderReadPixels failed: ${last_error()}')
	}
	saved := C.SDL_SaveBMP(surface, path.str)
	C.SDL_DestroySurface(surface)
	if !saved {
		return error('SDL_SaveBMP failed: ${last_error()}')
	}
}

// ticks_ns returns a monotonic host time in nanoseconds.
pub fn ticks_ns() u64 {
	return C.SDL_GetTicksNS()
}

// sleep_ns blocks the calling thread.
pub fn sleep_ns(ns u64) {
	C.SDL_DelayNS(ns)
}
