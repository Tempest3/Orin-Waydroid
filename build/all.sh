#!/usr/bin/env bash
# Everything from source on an x86_64 Linux host: fetch → kernel → Android Mesa → release tarballs in dist/.
set -euo pipefail
D=$(dirname "$0")
"$D/fetch.sh"
"$D/kernel.sh"
"$D/mesa-android.sh" all
"$D/package.sh"
