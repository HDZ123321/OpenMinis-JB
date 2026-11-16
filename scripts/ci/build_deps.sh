#!/bin/bash
# Build the iOS native dependencies OpenMinis links against.
#
# Run from the repository root. This is the exact sequence BUILDING.md
# documents, kept in one script so the workflow file stays readable and so a
# local macOS machine can reproduce a CI failure with one command.
#
#   ./scripts/ci/build_deps.sh
#
# Products (all gitignored, regenerated here):
#   deps/libs/          libish.a libish_emu.a libfakefs.a libish_aot.a + headers
#   deps/include/       iSH headers
#   deps/resources/     VDSO, RootfsPatch.bundle, alpine-rootfs/ + .zip
#   deps/frameworks/    FFmpeg + 6 lib*.xcframework, Rclone.xcframework
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

step() {
    echo ""
    echo "=============================================================="
    echo "==> $*"
    echo "=============================================================="
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# LAME first: build_ffmpeg.sh links the MP3 encoder it produces.
step "build_lame.sh"
./deps/build_lame.sh

# FFmpeg must stay LGPL: --enable-gpl / --enable-nonfree would make the
# resulting binary undistributable. The script hardcodes the flag set.
step "build_ffmpeg.sh"
./deps/build_ffmpeg.sh

# iSH: cross-compiles libish/libish_emu/libfakefs for device arm64, then
# assembles deps/aot/aot_*.S into libish_aot.a. With no .S files present
# build_aot.sh emits a stub, which is what CI relies on — the real images are
# hundreds of MB and are not tracked.
step "build_ish.sh"
./deps/build_ish.sh

# Alpine minirootfs -> iSH fakefs. Needs deps/ish/build-native/tools/fakefsify,
# which build_ish.sh does not build (prepare_alpine_rootfs.sh does it itself).
step "prepare_alpine_rootfs.sh"
./deps/prepare_alpine_rootfs.sh

# rclone as a c-archive, device + simulator slices. Requires Go >= 1.25.5
# (deps/rclone-mobile/go.mod).
step "build_rclone_ios.sh"
./deps/build_rclone_ios.sh

step "deps build complete"
for p in deps/libs deps/include deps/resources deps/frameworks; do
    echo "--- $p"
    du -sh "$p" 2>/dev/null || echo "    MISSING"
done
