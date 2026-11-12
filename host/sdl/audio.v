module sdl

// max_queued_ms bounds audio latency: when the host has more than this
// queued, the backlog is dropped and counted.
const max_queued_ms = 150

// Audio pushes PCM to an SDL audio stream. No guest code runs on SDL's
// audio thread: the stream is opened without a callback and fed from the
// emulation loop, and SDL resamples from the guest rate to the device.
pub struct Audio {
mut:
	stream voidptr
	rate   int
pub mut:
	muted    bool
	overruns u64 // times the backlog was dropped
}

// new_audio opens the default playback device for signed 16-bit stereo.
pub fn new_audio() !Audio {
	spec := C.SDL_AudioSpec{
		format:   int(C.SDL_AUDIO_S16)
		channels: 2
		freq:     48000
	}
	stream := C.SDL_OpenAudioDeviceStream(u32(C.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK), &spec,
		unsafe { nil }, unsafe { nil })
	if stream == unsafe { nil } {
		return error('SDL_OpenAudioDeviceStream failed: ${last_error()}')
	}
	// Streams open paused.
	C.SDL_ResumeAudioStreamDevice(stream)
	return Audio{
		stream: stream
		rate:   48000
	}
}

// close stops playback and releases the device.
pub fn (mut a Audio) close() {
	C.SDL_DestroyAudioStream(a.stream)
	a.stream = unsafe { nil }
}

// push queues interleaved stereo frames generated at `rate` Hz.
pub fn (mut a Audio) push(samples []i16, frames int, rate f64) {
	if frames == 0 || rate < 1000 {
		return
	}
	guest_rate := int(rate + 0.5)
	if guest_rate != a.rate {
		spec := C.SDL_AudioSpec{
			format:   int(C.SDL_AUDIO_S16)
			channels: 2
			freq:     guest_rate
		}
		C.SDL_SetAudioStreamFormat(a.stream, &spec, unsafe { nil })
		a.rate = guest_rate
	}
	if a.muted {
		return
	}
	bytes_per_ms := a.rate * 4 / 1000
	if C.SDL_GetAudioStreamQueued(a.stream) > max_queued_ms * bytes_per_ms {
		C.SDL_ClearAudioStream(a.stream)
		a.overruns++
	}
	C.SDL_PutAudioStreamData(a.stream, samples.data, frames * 4)
}

// queued_ms returns how much audio is waiting to be played.
pub fn (a &Audio) queued_ms() int {
	bytes_per_ms := a.rate * 4 / 1000
	return if bytes_per_ms == 0 { 0 } else { C.SDL_GetAudioStreamQueued(a.stream) / bytes_per_ms }
}

// clear drops everything queued, e.g. after a reset or state restore.
pub fn (mut a Audio) clear() {
	C.SDL_ClearAudioStream(a.stream)
}
