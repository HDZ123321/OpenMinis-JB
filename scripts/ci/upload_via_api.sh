#!/usr/bin/env bash
# Upload local files to the repo through the GitHub Contents API.
#
# git push cannot be used from this machine right now: the HTTPS proxy accepts
# the CONNECT tunnel and then drops the TLS handshake, so every push fails with
# "schannel: failed to receive handshake". api.github.com still answers
# directly, so single-file commits go through REST instead.
#
# Two Windows-specific traps this script works around:
#   * the payload goes in on stdin (gh api --input), because a base64 body for a
#     large file blows past the command-line length limit ("Argument list too
#     long");
#   * the scratch file lives in ./.upload-payload.json, because Node resolves
#     "/tmp/x" to D:\tmp\x here and the write fails with ENOENT.
#
# Each file becomes its own commit. An existing file needs its current blob sha
# (the API rejects an update without one); a new file must omit it.
#
# Usage: scripts/ci/upload_via_api.sh <path> [<path>...]
#        COMMIT_MSG="..." scripts/ci/upload_via_api.sh <path>
set -euo pipefail

GH="${GH:-/c/Users/pc/AppData/Local/Programs/GitHub CLI/gh.exe}"
REPO="${REPO:-HDZ123321/OpenMinis-JB}"
BRANCH="${BRANCH:-main}"

cd "$(dirname "$0")/../.."

for path in "$@"; do
  msg="${COMMIT_MSG:-Sync $path}"
  echo "== $path"
  sha="$("$GH" api "repos/$REPO/contents/$path?ref=$BRANCH" --jq '.sha' 2>/dev/null || true)"
  case "$sha" in
    \{*) sha="" ;;   # a 404 body came through as JSON; treat as "does not exist"
  esac

  node -e '
    const fs = require("fs");
    const [file, message, branch, sha] = process.argv.slice(1);
    const body = { message, content: fs.readFileSync(file).toString("base64"), branch };
    if (sha) body.sha = sha;
    fs.writeFileSync(".upload-payload.json", JSON.stringify(body));
  ' "$path" "$msg" "$BRANCH" "$sha"

  echo "   $([ -n "$sha" ] && echo "update (sha $sha)" || echo create)"
  "$GH" api -X PUT "repos/$REPO/contents/$path" --input .upload-payload.json --jq '"   -> " + .commit.sha'
  rm -f .upload-payload.json
done
