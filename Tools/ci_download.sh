#!/bin/bash
# Resumable download of one workflow artifact. `gh run download` dies on a slow or flaky link (TLS handshake
# timeouts, "unexpected EOF") and starts over each time; this resumes with `curl -C -` instead.
#   Tools/ci_download.sh <run-id> <artifact-name> <out-dir>
# The files end up directly in <out-dir>; the zip stays next to it as <out-dir>.zip.
# The API answers with a short-lived signed URL, so a fresh one is requested for every attempt.
export PATH="/c/Users/mizuk/tools/gh/bin:$PATH"
REPO=${PT_REPO:-mizuki20070314/podtube-ios12}
RUN="$1"; NAME="$2"; OUT="${3%/}"
if [ -z "$RUN" ] || [ -z "$NAME" ] || [ -z "$OUT" ]; then
  echo "usage: $0 <run-id> <artifact-name> <out-dir>"
  exit 1
fi
ZIP="$OUT.zip"
mkdir -p "$OUT"

META=$(gh api "repos/$REPO/actions/runs/$RUN/artifacts" --jq '.artifacts[] | select(.name=="'"$NAME"'") | [.id, .size_in_bytes] | @tsv')
ID=$(echo "$META" | cut -f1)
SIZE=$(echo "$META" | cut -f2 | tr -d '\r')
if [ -z "$ID" ] || [ -z "$SIZE" ]; then
  echo "artifact '$NAME' not found in run $RUN"
  exit 1
fi
echo "artifact $NAME: id=$ID, $SIZE bytes"

TOKEN=$(gh auth token)
have() { if [ -f "$ZIP" ]; then stat -c %s "$ZIP"; else echo 0; fi; }
for i in $(seq 1 40); do
  [ "$(have)" -ge "$SIZE" ] && break
  URL=$(curl -s -o /dev/null -w '%{redirect_url}' --connect-timeout 30 --max-time 60 \
    -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/actions/artifacts/$ID/zip")
  if [ -z "$URL" ]; then sleep 3; continue; fi
  echo "attempt $i: have $(have) of $SIZE"
  curl -s -L -C - --connect-timeout 30 --max-time 240 -o "$ZIP" "$URL"
done
if [ "$(have)" -lt "$SIZE" ]; then
  echo "gave up at $(have) of $SIZE bytes (run again to resume)"
  exit 2
fi

python -I -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$ZIP" "$OUT"
echo "extracted $(ls "$OUT" | wc -l) files into $OUT"
