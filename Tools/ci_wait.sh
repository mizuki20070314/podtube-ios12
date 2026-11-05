#!/bin/bash
# Polls a workflow run until it completes, then downloads the screenshots artifact.
#   Tools/ci_wait.sh <run-id> [out-dir]
export PATH="/c/Users/mizuk/tools/gh/bin:$PATH"
ID="$1"
OUT="${2:-/tmp/pt/shots_$ID}"
for i in $(seq 1 240); do
  s=$(gh run view "$ID" --json status -q .status 2>/dev/null)
  [ "$s" = "completed" ] && break
  sleep 15
done
gh run view "$ID" --json conclusion,jobs -q '.conclusion + " | " + (.jobs | map(.name[0:14] + "=" + (.conclusion // .status)) | join(", "))'
bash "$(dirname "$0")/ci_download.sh" "$ID" screenshots "$OUT"
