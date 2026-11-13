#!/bin/sh
# Run images in a second emulator (the Virtual Jaguar libretro core) and in
# vjag, and leave a picture from each side by side in out/crosscheck.
#
#     sh scripts/crosscheck/run.sh [frames] [image...]
#
# Without images it runs the four demos. The core is fetched and built on
# first use, into out/crosscheck/core. Needs git, make and a C compiler.
set -eu
cd "$(dirname "$0")/../.."
frames="${1:-120}"
[ $# -gt 0 ] && shift
[ $# -gt 0 ] || set -- demos/hello.jag demos/maw.jag demos/wirewing.jag demos/hero.jag

out=out/crosscheck
core_dir="$out/core"
mkdir -p "$out/scratch"
if [ ! -d "$core_dir" ]; then
    git clone --quiet --depth 1 https://github.com/libretro/virtualjaguar-libretro.git "$core_dir"
fi
core=$(ls "$core_dir"/virtualjaguar_libretro.* 2>/dev/null | head -1 || true)
if [ -z "$core" ]; then
    make -C "$core_dir" -j4 >"$out/core-build.log" 2>&1
    core=$(ls "$core_dir"/virtualjaguar_libretro.* | head -1)
fi
cc -O1 -I "$core_dir/libretro-common/include" -o "$out/front" scripts/crosscheck/front.c
[ -x bin/vjag_test ] || just release

for image in "$@"; do
    name=$(basename "$image" .jag)
    printf '%s: ' "$name"
    "$out/front" "$core" "$image" "$frames" "$out/$name-other.bmp" "$out/scratch" 2>/dev/null
    ./bin/vjag_test run "$image" --frames "$frames" --screenshot "$out/$name-vjag.png" >/dev/null
done
echo "pictures are in $out: compare <name>-other.bmp with <name>-vjag.png"
