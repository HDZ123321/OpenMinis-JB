#!/bin/bash
# Build every native dependency the iOS app links against.
#
# Order matters: iSH's cross build wants the LAME/FFmpeg headers in place, the
# Alpine rootfs needs the fakefsify tool from the native iSH build, and rclone
# is independent but last because it is the slowest.
#
# Each script is invoked through `bash` rather than as `./deps/x.sh`. The
# checkout on this machine comes from a tarball and lands on a Windows
# filesystem, so git records every file as mode 100644 and the executable bit
# never survives into CI — running them directly fails with "Permission
# denied". Naming the interpreter makes the mode irrelevant.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
ROOT="$PWD"
echo "repo root: $ROOT"
date -u +"started %Y-%m-%dT%H:%M:%SZ"

step() {
  local label="$1"; shift
  echo
  echo "=============================================================="
  echo "== $label   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "=============================================================="
  "$@"
  echo "-- done: $label   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

step "LAME"                    bash deps/build_lame.sh
step "FFmpeg"                  bash deps/build_ffmpeg.sh
step "iSH"                     bash deps/build_ish.sh
step "Alpine rootfs"           bash deps/prepare_alpine_rootfs.sh
step "rclone"                  bash deps/build_rclone_ios.sh

echo
echo "=== dependency sizes ==="
du -sh deps/libs deps/include deps/resources deps/frameworks 2>/dev/null || true
echo "finished $(date -u +%Y-%m-%dT%H:%M:%SZ)"
