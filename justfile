# vjag task runner — `just --list` for grouped commands.
# External tools: v (0.5.2), clang, SDL3, hyperfine (benchmark only).

set shell := ["sh", "-cu"]
set positional-arguments := true

install_dir := env_var('HOME') / ".local/bin"
rom_dir := "data/roms"

# List all recipes.
default:
    @just --list

# Debug build of the desktop app and the headless runner.
[group('build')]
build:
    @mkdir -p bin
    v -o bin/vjag-debug cmd/vjag/
    v -o bin/vjag_test-debug cmd/vjag_test/

# Optimized build of the desktop app and the headless runner.
[group('build')]
release:
    @mkdir -p bin
    v -prod -o bin/vjag cmd/vjag/
    v -prod -o bin/vjag_test cmd/vjag_test/

[group('build')]
clean:
    rm -rf bin out

# Run the optimized desktop app, e.g. `just run path/to/image.jag`.
[group('run')]
run *args: release
    ./bin/vjag "$@"

# Run the debug desktop app (runtime checks kept, slower).
[group('run')]
dev *args: build
    ./bin/vjag-debug "$@"

# Rebuild a game written with jagkit from its V source and play it, e.g. `just demo wirewing`.
[group('run')]
demo name="maw": release
    v run demos/{{ name }}
    ./bin/vjag demos/{{ name }}.jag

# Run the headless runner, e.g. `just headless inspect image.jag --json`.
[group('run')]
headless *args: release
    ./bin/vjag_test "$@"

# Unit tests; optionally limit to one module, e.g. `just test m68k`.
[group('check')]
test module=".":
    v test {{ module }}

# Same tests under the optimized compiler; output must match `test`.
[group('check')]
test-prod module=".":
    v -prod test {{ module }}

[group('check')]
fmt:
    v fmt -w .

[group('check')]
lint:
    v fmt -verify .
    v vet .

[group('check')]
check: lint test release

# Download the third-party conformance corpora into data/tests (gitignored).
[group('check')]
fetch-tests:
    sh scripts/fetch-m68000-tests.sh

# Boot every local image headlessly and write the compatibility report.
[group('check')]
compat dir=rom_dir: release
    ./bin/vjag_test compat "{{ dir }}" --report-json out/compat.json --screenshots out/compat

# Unthrottled core throughput on one image, e.g. `just benchmark image.jag`.
[group('bench')]
benchmark image frames="600": release
    ./bin/vjag_test bench "{{ image }}" --frames {{ frames }}

# Wall-clock comparison of debug and optimized runners on one image.
[group('bench')]
benchmark-builds image frames="120": build release
    hyperfine --warmup 1 \
        './bin/vjag_test-debug bench "{{ image }}" --frames {{ frames }}' \
        './bin/vjag_test bench "{{ image }}" --frames {{ frames }}'

[group('install')]
install dest=install_dir: release
    mkdir -p {{ dest }}
    install -m 0755 bin/vjag {{ dest }}/vjag
    install -m 0755 bin/vjag_test {{ dest }}/vjag_test
    @echo "Installed vjag and vjag_test to {{ dest }}"

[group('install')]
uninstall dest=install_dir:
    rm -f {{ dest }}/vjag {{ dest }}/vjag_test
    @echo "Removed vjag and vjag_test from {{ dest }}"

[group('install')]
reinstall dest=install_dir: (uninstall dest) (install dest)
