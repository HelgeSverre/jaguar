#!/bin/sh
# Fetch the SingleStepTests/m68000 instruction corpus (MIT licensed) used by
# m68k/sst_test.v. The corpus is pinned to one commit and unpacked into
# data/tests/m68000/, which is gitignored: never commit the corpus.
#
# Usage: scripts/fetch-m68000-tests.sh [--force]
set -eu

COMMIT=64b253116a3de04aaac4346c43680960dc9b67e5
URL="https://github.com/SingleStepTests/m68000/archive/${COMMIT}.tar.gz"
EXPECTED_FILES=127

root=$(cd "$(dirname "$0")/.." && pwd)
dest="${root}/data/tests/m68000"
stamp="${dest}/.commit"

if [ "${1:-}" != "--force" ] && [ -f "${stamp}" ] && [ "$(cat "${stamp}")" = "${COMMIT}" ]; then
	echo "m68000 corpus already present at ${dest} (${COMMIT})"
	exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

echo "Downloading SingleStepTests/m68000 @ ${COMMIT}"
curl --fail --location --silent --show-error --output "${work}/corpus.tar.gz" "${URL}"
mkdir "${work}/unpacked"
tar -xzf "${work}/corpus.tar.gz" -C "${work}/unpacked" --strip-components=1

count=$(find "${work}/unpacked/v1" -name '*.json.bin' | wc -l | tr -d ' ')
if [ "${count}" -ne "${EXPECTED_FILES}" ]; then
	echo "error: expected ${EXPECTED_FILES} corpus files, found ${count}" >&2
	exit 1
fi

mkdir -p "${dest}"
find "${dest}" -name '*.json.bin' -delete
find "${work}/unpacked/v1" -name '*.json.bin' -exec mv {} "${dest}/" \;
cp "${work}/unpacked/LICENSE" "${dest}/LICENSE"
cp "${work}/unpacked/README.md" "${dest}/README.md"
echo "${COMMIT}" > "${stamp}"
echo "Installed ${count} corpus files into ${dest}"
