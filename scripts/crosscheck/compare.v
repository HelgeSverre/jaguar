// Compare a picture from the other emulator with a vjag screenshot.
//
//     v run scripts/crosscheck/compare.v other.bmp vjag.png [--offset 16,3] [--tolerance 2]
//
// Pixel (x, y) of the vjag picture is compared with pixel (x+dx, y+dy) of the
// other one, over the area both cover. Prints the compared pixels, those
// where any channel differs by more than the tolerance, and the largest
// channel difference. Exit status 0 when none exceeds the tolerance, 1 when
// some do, 2 on a usage or read error. Reads BMP and PNG (either side).
import os
import stbi

fn load(path string) !stbi.Image {
	return stbi.load(path, stbi.LoadParams{ desired_channels: 3 }) or {
		return error('cannot read ${path}')
	}
}

fn main() {
	mut files := []string{}
	mut dx, mut dy, mut tol := 16, 3, 2
	mut i := 1
	for i < os.args.len {
		a := os.args[i]
		match a {
			'--offset' {
				i++
				if i >= os.args.len || !os.args[i].contains(',') {
					eprintln('--offset takes dx,dy')
					exit(2)
				}
				dx = os.args[i].all_before(',').int()
				dy = os.args[i].all_after(',').int()
			}
			'--tolerance' {
				i++
				if i >= os.args.len {
					eprintln('--tolerance takes a number')
					exit(2)
				}
				tol = os.args[i].int()
			}
			else {
				files << a
			}
		}

		i++
	}
	if files.len != 2 {
		eprintln('usage: v run compare.v other.bmp vjag.png [--offset dx,dy] [--tolerance n]')
		exit(2)
	}
	other := load(files[0]) or {
		eprintln(err)
		exit(2)
	}
	mine := load(files[1]) or {
		eprintln(err)
		exit(2)
	}
	mut compared, mut over, mut worst := 0, 0, 0
	for y in 0 .. mine.height {
		for x in 0 .. mine.width {
			ox, oy := x + dx, y + dy
			if ox < 0 || oy < 0 || ox >= other.width || oy >= other.height {
				continue
			}
			a := unsafe { &u8(other.data) + (oy * other.width + ox) * other.nr_channels }
			b := unsafe { &u8(mine.data) + (y * mine.width + x) * mine.nr_channels }
			mut big := false
			for c in 0 .. 3 {
				d := int(unsafe { a[c] }) - int(unsafe { b[c] })
				m := if d < 0 { -d } else { d }
				if m > worst {
					worst = m
				}
				if m > tol {
					big = true
				}
			}
			compared++
			if big {
				over++
			}
		}
	}
	println('compared ${compared} pixels, ${over} differ by more than ${tol}, max channel difference ${worst}')
	exit(if over == 0 { 0 } else { 1 })
}
