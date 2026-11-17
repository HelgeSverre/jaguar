#!/bin/sh
# Use the optional USB-enabled SDL for compilation and tests. Its pkg-config
# metadata embeds an rpath, so running/installing the resulting binary needs
# no environment override. Otherwise retain the normal system SDL workflow.
set -eu
. "$(dirname "$0")/sdl-version.sh"

if [ -f "$vjag_sdl_prefix/lib/pkgconfig/sdl3.pc" ]; then
	export PKG_CONFIG_PATH="$vjag_sdl_prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
	# V's built-in pkg-config resolver searches its defaults before
	# PKG_CONFIG_PATH. Override that order too, preserving other packages.
	vjag_pc_defaults=${PKG_CONFIG_PATH_DEFAULTS:-$(pkg-config --variable=pc_path pkg-config)}
	export PKG_CONFIG_PATH_DEFAULTS="$PKG_CONFIG_PATH${vjag_pc_defaults:+:$vjag_pc_defaults}"
elif [ -n "${VJAG_SDL_PREFIX:-}" ]; then
	echo "SDL not found at VJAG_SDL_PREFIX=$VJAG_SDL_PREFIX; run just setup-sdl-usb first" >&2
	exit 1
fi

exec "$@"
