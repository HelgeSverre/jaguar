module cli

import os

// WavWriter collects interleaved 16-bit stereo PCM and writes a WAV file.
struct WavWriter {
mut:
	samples []i16
	rate    int
}

// append adds `frames` stereo frames generated at `rate` Hz. The file takes
// the first non-zero rate; a guest that changes its sample rate mid-run is
// written at the first one.
fn (mut w WavWriter) append(samples []i16, frames int, rate f64) {
	if frames == 0 {
		return
	}
	if w.rate == 0 {
		w.rate = int(rate + 0.5)
	}
	w.samples << samples[..frames * 2]
}

// save writes the collected audio as a canonical 44-byte-header WAV.
fn (w &WavWriter) save(path string) ! {
	data_bytes := u32(w.samples.len * 2)
	rate := u32(if w.rate == 0 { 48000 } else { w.rate })
	mut out := []u8{cap: 44 + int(data_bytes)}
	out << 'RIFF'.bytes()
	put_u32(mut out, 36 + data_bytes)
	out << 'WAVEfmt '.bytes()
	put_u32(mut out, 16)
	put_u16(mut out, 1) // PCM
	put_u16(mut out, 2) // channels
	put_u32(mut out, rate)
	put_u32(mut out, rate * 4)
	put_u16(mut out, 4) // block align
	put_u16(mut out, 16) // bits per sample
	out << 'data'.bytes()
	put_u32(mut out, data_bytes)
	for sample in w.samples {
		put_u16(mut out, u16(sample))
	}
	os.write_file_array(path, out)!
}

fn put_u16(mut out []u8, value u16) {
	out << u8(value)
	out << u8(value >> 8)
}

fn put_u32(mut out []u8, value u32) {
	put_u16(mut out, u16(value))
	put_u16(mut out, u16(value >> 16))
}
