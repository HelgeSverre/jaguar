#!/bin/sh
# Build a pinned SDL with direct USB access, without modifying system SDL or
# installing a kernel driver. Keep the installed dependency outside the checkout
# so `just clean` and installed vjag binaries can coexist.
set -eu
vjag_script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$vjag_script_dir/sdl-version.sh"
vjag_root=$(CDPATH= cd -- "$vjag_script_dir/.." && pwd)
vjag_work="$vjag_root/out/sdl-usb-$vjag_sdl_version"
vjag_stamp="$vjag_sdl_prefix/.vjag-usb-build"
vjag_signature="$vjag_sdl_sha256 direct-libusb-v1"

for vjag_tool in cmake curl tar pkg-config; do
	command -v "$vjag_tool" >/dev/null 2>&1 || {
		echo "Missing $vjag_tool; on macOS: brew install cmake pkgconf libusb" >&2
		exit 1
	}
done
pkg-config --exists 'libusb-1.0 >= 1.0.16' || {
	echo "libusb development files are required; on macOS: brew install libusb" >&2
	exit 1
}

if [ -f "$vjag_stamp" ] && [ "$(cat "$vjag_stamp")" = "$vjag_signature" ] &&
	[ -f "$vjag_sdl_prefix/lib/pkgconfig/sdl3.pc" ]; then
	echo "USB-enabled SDL is ready at $vjag_sdl_prefix"
	exit 0
fi

mkdir -p "$vjag_work"
vjag_archive="$vjag_work/SDL3-$vjag_sdl_version.tar.gz"
if [ ! -f "$vjag_archive" ]; then
	curl --fail --location --silent --show-error \
		"https://github.com/libsdl-org/SDL/releases/download/release-$vjag_sdl_version/SDL3-$vjag_sdl_version.tar.gz" \
		--output "$vjag_archive.part"
	mv "$vjag_archive.part" "$vjag_archive"
fi
if command -v sha256sum >/dev/null 2>&1; then
	vjag_actual=$(sha256sum "$vjag_archive" | cut -d ' ' -f 1)
else
	vjag_actual=$(shasum -a 256 "$vjag_archive" | cut -d ' ' -f 1)
fi
if [ "$vjag_actual" != "$vjag_sdl_sha256" ]; then
	echo "SDL archive checksum mismatch. Remove $vjag_archive and retry." >&2
	exit 1
fi

tar -xzf "$vjag_archive" -C "$vjag_work"
cmake -S "$vjag_work/SDL3-$vjag_sdl_version" -B "$vjag_work/build" \
	-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$vjag_sdl_prefix" \
	-DCMAKE_INSTALL_LIBDIR=lib -DSDL_HIDAPI_LIBUSB=ON \
	-DSDL_HIDAPI_LIBUSB_SHARED=OFF -DSDL_SHARED=ON -DSDL_STATIC=OFF \
	-DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
cmake --build "$vjag_work/build" --parallel "${VJAG_BUILD_JOBS:-4}"
cmake --install "$vjag_work/build"
install -m 0644 "$vjag_work/SDL3-$vjag_sdl_version/LICENSE.txt" "$vjag_sdl_prefix/LICENSE.txt"
printf '%s\n' "$vjag_signature" > "$vjag_stamp"
echo "USB-enabled SDL installed at $vjag_sdl_prefix"
echo "Normal just build/run/test/install commands will now use it."
