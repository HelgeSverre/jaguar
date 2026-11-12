module jerry

import math

// The JERRY wavetable ROM holds eight 128-entry waveforms, each entry a
// sign-extended 16-bit sample in a 32-bit word.
pub const wavetable_size = 0x1000
const table_entries = 128
const amplitude = 32767.0

// synthesized_wavetable builds a stand-in for the wavetable ROM.
//
// The shapes follow the documented table order (triangle, sine, amplitude
// modulated sine, twelve-partial sine, chirp, noisy triangle, delta, noise)
// but the bytes are computed, not dumped: programs that only need plausible
// waveforms work, bit-exact audio requires the real ROM as an asset.
pub fn synthesized_wavetable() []u8 {
	mut rom := []u8{len: wavetable_size}
	mut noise := u32(0x1234_5678)
	for table in 0 .. 8 {
		for i in 0 .. table_entries {
			phase := f64(i) / f64(table_entries)
			noise = noise * 1664525 + 1013904223
			random := f64(i32(noise) >> 16) / 32768.0
			triangle := if phase < 0.5 { 4.0 * phase - 1.0 } else { 3.0 - 4.0 * phase }
			sample := match table {
				0 {
					triangle
				}
				1 {
					math.sin(2.0 * math.pi * phase)
				}
				2 {
					math.sin(2.0 * math.pi * phase) * (0.5 - 0.5 * math.cos(2.0 * math.pi * phase))
				}
				3 {
					partials(phase, 12)
				}
				4 {
					math.sin(2.0 * math.pi * phase * phase * 8.0)
				}
				5 {
					0.75 * triangle + 0.25 * random
				}
				6 {
					if i == 0 { 1.0 } else { 0.0 }
				}
				else {
					random
				}
			}

			value := u32(i32(sample * amplitude))
			offset := table * table_entries * 4 + i * 4
			rom[offset] = u8(value >> 24)
			rom[offset + 1] = u8(value >> 16)
			rom[offset + 2] = u8(value >> 8)
			rom[offset + 3] = u8(value)
		}
	}
	return rom
}

// partials sums the first `count` harmonics with 1/n amplitudes, normalised.
fn partials(phase f64, count int) f64 {
	mut sum := 0.0
	mut norm := 0.0
	for n in 1 .. count + 1 {
		sum += math.sin(2.0 * math.pi * phase * f64(n)) / f64(n)
		norm += 1.0 / f64(n)
	}
	return sum / norm
}
