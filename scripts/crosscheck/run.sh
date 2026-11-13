#!/bin/sh
# Run images in a second emulator (the Virtual Jaguar libretro core) and in
# vjag, and leave a picture from each side by side in out/crosscheck.
#
#     sh scripts/crosscheck/run.sh [frames] [image...]
#
# Without images it runs the four demos. The core is fetched and built on
# first use, into out/crosscheck/core. Needs git, make and a C compiler.
# Images may be .jag or .j64.
#
# For anything beyond a plain run, use the pieces directly. run.sh leaves the
# frontend at out/crosscheck/front:
#
#     out/crosscheck/front out/crosscheck/core/virtualjaguar_libretro.dylib \
#         game.j64 300 out/final.bmp out/crosscheck/scratch \
#         --holds-file holds.txt --eeprom-in in.eep --eeprom-out out.eep \
#         --shot 120:out/a.bmp --shot 200:out/b.bmp [--pal] [--var key=value]
#     v run scripts/crosscheck/compare.v out/a.bmp out/a-vjag.png --offset 16,3 --tolerance 2
#
# See docs/headless.md, "A second opinion".
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
    name=$(basename "${image%.*}")
    printf '%s: ' "$name"
    "$out/front" "$core" "$image" "$frames" "$out/$name-other.bmp" "$out/scratch" 2>/dev/null
    ./bin/vjag_test run "$image" --frames "$frames" --screenshot "$out/$name-vjag.png" >/dev/null
done
echo "pictures are in $out: compare <name>-other.bmp with <name>-vjag.png"
