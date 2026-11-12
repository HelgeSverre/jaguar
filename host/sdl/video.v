module sdl

import hwtypes

// Video owns the window, the renderer, the streaming texture and, when the
// window is dressed as a console, the shell around the picture.
pub struct Video {
mut:
	window         voidptr
	renderer       voidptr
	texture        voidptr
	texture_width  int
	texture_height int
	fullscreen     bool
	capture_path   string
	shell          &Shell = unsafe { nil }
}

// Scene is everything one presented frame shows.
pub struct Scene {
pub:
	pixels  []u32 // the guest picture; empty shows `message` instead
	info    hwtypes.FrameInfo
	message []string // centred lines for a window with no picture
	overlay []string // status lines over the top-left of the picture
	readout string   // text on the shell's status strip
	glow    f32      // 0..1, how brightly the shell's eyes burn
}

// init starts the SDL subsystems the frontend needs.
pub fn init() ! {
	// A click on an unfocused window should press the shell button under it.
	C.SDL_SetHint(c'SDL_MOUSE_FOCUS_CLICKTHROUGH', c'1')
	if !C.SDL_Init(u32(C.SDL_INIT_VIDEO) | u32(C.SDL_INIT_AUDIO) | u32(C.SDL_INIT_GAMEPAD)) {
		return error('SDL_Init failed: ${last_error()}')
	}
}

// quit shuts SDL down. Destroy every wrapper first.
pub fn quit() {
	C.SDL_Quit()
}

// new_video opens a resizable window of the given size.
pub fn new_video(title string, width int, height int) !Video {
	return open_window(title, width, height, u64(C.SDL_WINDOW_RESIZABLE))
}

// new_shell_video opens a borderless, transparent window shaped by the
// console shell. `scale` is window points per pixel of the artwork.
pub fn new_shell_video(title string, scale f32) !Video {
	mut video := open_window(title, int(shell_width * scale), int(shell_height * scale),
		u64(C.SDL_WINDOW_BORDERLESS) | u64(C.SDL_WINDOW_TRANSPARENT))!
	video.shell = load_shell(video.renderer) or {
		video.close()
		return err
	}
	video.shell.scale = scale
	C.SDL_SetRenderDrawBlendMode(video.renderer, u32(C.SDL_BLENDMODE_BLEND))
	C.SDL_SetWindowHitTest(video.window, voidptr(shell_hit_test), video.shell)
	return video
}

fn open_window(title string, width int, height int, flags u64) !Video {
	window := C.SDL_CreateWindow(title.str, width, height,
		flags | u64(C.SDL_WINDOW_HIGH_PIXEL_DENSITY))
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

// close destroys the textures, renderer and window.
pub fn (mut v Video) close() {
	if v.texture != unsafe { nil } {
		C.SDL_DestroyTexture(v.texture)
		v.texture = unsafe { nil }
	}
	if v.shell != unsafe { nil } {
		C.SDL_SetWindowHitTest(v.window, unsafe { nil }, unsafe { nil })
		C.SDL_DestroyTexture(v.shell.texture)
		v.shell = unsafe { nil }
	}
	C.SDL_DestroyRenderer(v.renderer)
	C.SDL_DestroyWindow(v.window)
}

// shell returns the console shell of this window, or nil for a plain one.
pub fn (v &Video) shell() &Shell {
	return v.shell
}

// set_shell_scale resizes a shell window.
pub fn (mut v Video) set_shell_scale(scale f32) {
	if v.shell == unsafe { nil } {
		return
	}
	v.shell.scale = scale
	if !v.fullscreen {
		C.SDL_SetWindowSize(v.window, int(shell_width * scale), int(shell_height * scale))
	}
}

// set_title changes the window title.
pub fn (v &Video) set_title(title string) {
	C.SDL_SetWindowTitle(v.window, title.str)
}

// toggle_fullscreen switches between windowed and borderless fullscreen.
// Fullscreen shows the bare picture; the shell returns with the window.
pub fn (mut v Video) toggle_fullscreen() {
	v.fullscreen = !v.fullscreen
	C.SDL_SetWindowFullscreen(v.window, v.fullscreen)
	if v.shell != unsafe { nil } {
		v.shell.active = !v.fullscreen
		v.shell.hover = Control{}
		v.shell.held = Control{}
	}
}

// present draws one scene: the picture or message, and the shell around it
// when the window has one.
pub fn (mut v Video) present(scene Scene) ! {
	mut output_width := 0
	mut output_height := 0
	C.SDL_GetRenderOutputSize(v.renderer, &output_width, &output_height)
	if v.shell != unsafe { nil } && !v.fullscreen {
		// One artwork pixel is `k` output pixels.
		k := f32(output_width) / f32(shell_width)
		C.SDL_SetRenderDrawColor(v.renderer, 0, 0, 0, 0)
		C.SDL_RenderClear(v.renderer)
		v.draw_content(scene, scaled(shell_screen, k))!
		v.draw_shell(scene, k, f32(output_width), f32(output_height))
	} else {
		C.SDL_SetRenderDrawColor(v.renderer, 0, 0, 0, 255)
		C.SDL_RenderClear(v.renderer)
		v.draw_content(scene, C.SDL_FRect{0, 0, f32(output_width), f32(output_height)})!
	}
	if v.capture_path != '' {
		v.capture()!
	}
	C.SDL_RenderPresent(v.renderer)
}

fn scaled(box Box, k f32) C.SDL_FRect {
	return C.SDL_FRect{f32(box.x) * k, f32(box.y) * k, f32(box.w) * k, f32(box.h) * k}
}

// draw_content fills `area` with the guest picture at 4:3, or with the
// message when there is no picture, and puts the overlay on top.
fn (mut v Video) draw_content(scene Scene, area C.SDL_FRect) ! {
	if scene.pixels.len > 0 {
		v.upload(scene.pixels, scene.info)!
		mut width := area.w
		mut height := width * 3.0 / 4.0
		if height > area.h {
			height = area.h
			width = height * 4.0 / 3.0
		}
		destination := C.SDL_FRect{
			x: area.x + (area.w - width) / 2
			y: area.y + (area.h - height) / 2
			w: width
			h: height
		}
		C.SDL_SetRenderDrawColor(v.renderer, 0, 0, 0, 255)
		C.SDL_RenderFillRect(v.renderer, &area)
		C.SDL_RenderTexture(v.renderer, v.texture, unsafe { nil }, &destination)
	} else {
		C.SDL_SetRenderDrawColor(v.renderer, 10, 10, 14, 255)
		C.SDL_RenderFillRect(v.renderer, &area)
		// Debug text is 8 pixels per glyph: use the largest whole scale that
		// keeps the longest line within four fifths of the area.
		mut longest := 1
		for line in scene.message {
			if line.len > longest {
				longest = line.len
			}
		}
		fit := int(area.w * 0.8) / (longest * 8)
		scale := f32(if fit < 1 { 1 } else { fit })
		C.SDL_SetRenderScale(v.renderer, scale, scale)
		top := (area.y + area.h / 2) / scale - f32(scene.message.len * 7)
		for i, line in scene.message {
			shade := u8(if i == 0 { 255 } else { 140 })
			C.SDL_SetRenderDrawColor(v.renderer, shade, shade, shade, 255)
			left := (area.x + area.w / 2) / scale - f32(line.len * 4)
			C.SDL_RenderDebugText(v.renderer, left, top + f32(i * 14), line.str)
		}
		C.SDL_SetRenderScale(v.renderer, 1, 1)
	}
	if scene.overlay.len > 0 {
		C.SDL_SetRenderScale(v.renderer, 2, 2)
		left := area.x / 2 + 4
		top := area.y / 2 + 4
		for i, line in scene.overlay {
			C.SDL_SetRenderDrawColor(v.renderer, 0, 0, 0, 255)
			C.SDL_RenderDebugText(v.renderer, left + 1, top + 1 + f32(i * 10), line.str)
			C.SDL_SetRenderDrawColor(v.renderer, 255, 255, 0, 255)
			C.SDL_RenderDebugText(v.renderer, left, top + f32(i * 10), line.str)
		}
		C.SDL_SetRenderScale(v.renderer, 1, 1)
	}
}

// upload copies a guest frame into the streaming texture, replacing the
// texture when the guest changes its picture size.
fn (mut v Video) upload(pixels []u32, info hwtypes.FrameInfo) ! {
	if v.texture == unsafe { nil } || v.texture_width != info.width
		|| v.texture_height != info.height {
		if v.texture != unsafe { nil } {
			C.SDL_DestroyTexture(v.texture)
		}
		v.texture = C.SDL_CreateTexture(v.renderer, u32(C.SDL_PIXELFORMAT_XRGB8888),
			int(C.SDL_TEXTUREACCESS_STREAMING), info.width, info.height)
		if v.texture == unsafe { nil } {
			return error('SDL_CreateTexture failed: ${last_error()}')
		}
		C.SDL_SetTextureScaleMode(v.texture, int(C.SDL_SCALEMODE_LINEAR))
		C.SDL_SetTextureBlendMode(v.texture, u32(C.SDL_BLENDMODE_NONE))
		v.texture_width = info.width
		v.texture_height = info.height
	}
	C.SDL_UpdateTexture(v.texture, unsafe { nil }, pixels.data, info.pitch * 4)
}

// draw_shell lays the console over the picture, then lights what is live:
// the eyes, the control under the pointer, and the readout.
fn (mut v Video) draw_shell(scene Scene, k f32, width f32, height f32) {
	texture := v.shell.texture
	whole := C.SDL_FRect{0, 0, width, height}
	C.SDL_SetTextureBlendMode(texture, u32(C.SDL_BLENDMODE_BLEND))
	C.SDL_SetTextureAlphaMod(texture, 255)
	C.SDL_RenderTexture(v.renderer, texture, unsafe { nil }, &whole)

	// Additive copies of the artwork brighten a part in its own shape.
	C.SDL_SetTextureBlendMode(texture, u32(C.SDL_BLENDMODE_ADD))
	glow := if scene.glow < 0 {
		f32(0)
	} else if scene.glow > 1 {
		f32(1)
	} else {
		scene.glow
	}
	C.SDL_SetTextureAlphaMod(texture, u8(glow * 255))
	for eye in shell_eyes {
		v.relight(eye, k)
	}
	if v.shell.hover.kind != .none {
		C.SDL_SetTextureAlphaMod(texture, 110)
		v.relight(v.shell.hover.box, k)
	}
	if v.shell.held.kind != .none {
		pressed := scaled(v.shell.held.box, k)
		C.SDL_SetRenderDrawColor(v.renderer, 0, 0, 0, 120)
		C.SDL_RenderFillRect(v.renderer, &pressed)
	}
	v.draw_readout(scene.readout, k)
}

fn (mut v Video) relight(box Box, k f32) {
	source := scaled(box, 1)
	destination := scaled(box, k)
	C.SDL_RenderTexture(v.renderer, v.shell.texture, &source, &destination)
}

// draw_readout writes on the status strip. Text wider than the strip
// scrolls through it like a ticker.
fn (mut v Video) draw_readout(text string, k f32) {
	if text == '' {
		return
	}
	strip := scaled(shell_readout, k)
	// Glyphs are 8x8; make them about half the strip high. Everything from
	// here to the end is in units of one glyph pixel.
	scale := f32(if int(strip.h) / 14 < 1 { 1 } else { int(strip.h) / 14 })
	C.SDL_SetRenderScale(v.renderer, scale, scale)
	clip :=
		C.SDL_Rect{int(strip.x / scale), int(strip.y / scale), int(strip.w / scale), int(strip.h / scale)}
	C.SDL_SetRenderClipRect(v.renderer, &clip)
	C.SDL_SetRenderDrawColor(v.renderer, 255, 56, 32, 255)
	top := (strip.y + strip.h / 2) / scale - 4
	left := strip.x / scale + 4
	width := text.len * 8
	if width <= clip.w - 8 {
		C.SDL_RenderDebugText(v.renderer, left, top, text.str)
	} else {
		lap := width + 48
		offset := int(C.SDL_GetTicksNS() / 30_000_000) % lap
		C.SDL_RenderDebugText(v.renderer, left - f32(offset), top, text.str)
		C.SDL_RenderDebugText(v.renderer, left - f32(offset) + f32(lap), top, text.str)
	}
	C.SDL_SetRenderClipRect(v.renderer, unsafe { nil })
	C.SDL_SetRenderScale(v.renderer, 1, 1)
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
