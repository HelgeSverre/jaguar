module cli

import os

// A film is one PPM image per frame; --video-from skips the first frames
// for the film and for the sound alike.
fn test_a_film_has_a_picture_for_every_frame_asked_for() {
	image := os.join_path(os.dir(@FILE), '..', 'demos', 'hello.jag')
	dir := os.join_path(os.temp_dir(), 'vjag_video_test_${os.getpid()}')
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	film := os.join_path(dir, 'deeper', 'film.ppm')
	sound := os.join_path(dir, 'sound.wav')
	whole := os.join_path(dir, 'whole.wav')
	run_headless(image, ImageOptions{}, RunOptions{
		frames:     20
		video:      film
		video_from: 17
		wav:        sound
	})!
	run_headless(image, ImageOptions{}, RunOptions{
		frames: 20
		wav:    whole
	})!

	bytes := os.read_bytes(film)!
	mut at := 0
	mut pictures := 0
	for at < bytes.len {
		// "P6\n<width> <height>\n255\n", then three bytes a pixel.
		mut end := at
		mut lines := 0
		for lines < 3 {
			if bytes[end] == `\n` {
				lines++
			}
			end++
		}
		header := bytes[at..end].bytestr().split('\n')
		assert header[0] == 'P6'
		assert header[2] == '255'
		size := header[1].split(' ').map(it.int())
		assert size[0] >= 320 && size[0] <= 352
		assert size[1] == 240
		at = end + size[0] * size[1] * 3
		pictures++
	}
	assert at == bytes.len, 'the last picture must be complete'
	assert pictures == 3

	// Three of twenty frames of sound, give or take a frame's worth.
	part := os.file_size(sound) - 44
	all := os.file_size(whole) - 44
	assert part > all * 2 / 20
	assert part < all * 4 / 20
}
