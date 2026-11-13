module jagkit

// ram_size is the Jaguar's main memory: two megabytes from address 0.
pub const ram_size = 0x200000

// Region is a stretch of main memory a program uses: the image itself, a
// picture buffer, a display list.
pub struct Region {
pub:
	name  string
	start u32
	size  int // in bytes
}

// check_regions makes sure that every region lies in main memory and that
// no two share a byte. Nothing on the Jaguar stops a program from drawing
// over its own code; this is the check to make at build time, with the
// image as one of the regions.
pub fn check_regions(regions []Region) ! {
	mut problems := []string{}
	for i, r in regions {
		if r.size <= 0 {
			problems << '`${r.name}` has no size'
			continue
		}
		end := u64(r.start) + u64(r.size)
		if end > ram_size {
			problems << '`${r.name}` ends at 0x${end:06x}, past the end of memory at 0x${ram_size:06x}'
		}
		for other in regions[..i] {
			other_end := u64(other.start) + u64(other.size)
			if other.size > 0 && u64(r.start) < other_end && u64(other.start) < end {
				problems << '`${other.name}` (0x${other.start:06x}..0x${other_end:06x}) and `${r.name}` (0x${r.start:06x}..0x${end:06x}) overlap'
			}
		}
	}
	if problems.len > 0 {
		return error('memory layout:\n  ' + problems.join('\n  '))
	}
}
