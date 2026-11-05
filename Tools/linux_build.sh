#!/bin/bash
# Builds the Foundation-only Core + the ptcli test harness with the Linux Swift toolchain (run inside WSL).
# usage: Tools/linux_build.sh [run ptcli args...]
export PATH=/opt/swift/usr/bin:$PATH
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT=/tmp/ptbuild
mkdir -p "$OUT"
swiftc -O -swift-version 5 -o "$OUT/ptcli" "$ROOT"/PodTube/Sources/Core/*.swift "$ROOT"/Tools/ptcli/*.swift 2>&1 \
  | grep -E "error|warning: var|warning: imm|warning: init" | sort -u | head -60
if [ "${PIPESTATUS[0]}" -ne 0 ] || [ ! -x "$OUT/ptcli" ]; then
  echo "BUILD FAILED"; exit 1
fi
echo "BUILD OK"
if [ "$#" -gt 0 ]; then
  "$OUT/ptcli" "$@"
fi
