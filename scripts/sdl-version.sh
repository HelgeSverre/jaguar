# Shared by setup-sdl-usb.sh and with-sdl.sh. This version was verified with
# Microsoft's 045e:0719 Xbox 360 wireless receiver on macOS.
vjag_sdl_version=3.4.18
vjag_sdl_sha256=9c75cf16330322c217dedd2e0609f1124f1b54b8633e763467b4684d0f4334a3
vjag_sdl_prefix=${VJAG_SDL_PREFIX:-"$HOME/.local/lib/vjag/sdl3-$vjag_sdl_version-usb-$(uname -s)-$(uname -m)"}
