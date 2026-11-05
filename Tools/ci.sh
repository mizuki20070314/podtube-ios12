#!/bin/bash
# Helper for inspecting GitHub Actions runs (run from Git Bash on Windows).
#   Tools/ci.sh status [id]   - job/step status of the latest (or given) run
#   Tools/ci.sh wait [id]     - block until the run finishes, then print the conclusion
#   Tools/ci.sh errors [id]   - compiler errors from the failed steps
#   Tools/ci.sh download [id] [name] [dir] - download an artifact
export PATH="/c/Users/mizuk/tools/gh/bin:$PATH"
CMD=${1:-status}
head_run() {
  # id of the workflow run for the current HEAD commit (waits a little for it to be created)
  local sha; sha=$(git rev-parse HEAD)
  for i in $(seq 1 40); do
    local id; id=$(gh run list --commit "$sha" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
    if [ -n "$id" ]; then echo "$id"; return; fi
    sleep 4
  done
}
ID=${2:-$(head_run)}
case "$CMD" in
  status)
    gh run view "$ID" --json status,conclusion,jobs -q '"run '"$ID"': " + .status + " " + (.conclusion // "") + "\n" + (.jobs[] | .name + ": " + .status + " " + (.conclusion // "") + "\n" + (.steps | map("   " + .name + " [" + .status + " " + (.conclusion // "") + "]") | join("\n")))'
    ;;
  wait)
    gh run watch "$ID" --interval 10 > /dev/null 2>&1
    gh run view "$ID" --json status,conclusion -q '"run '"$ID"' finished: " + .status + " " + (.conclusion // "")'
    ;;
  errors)
    gh run view "$ID" --log-failed 2>&1 | grep -E "error:|Error:|error " | sed 's/^[^	]*	[^	]*	//' | sed -E 's/^[0-9T:.Z-]+ //' | sort -u | head -${3:-80}
    ;;
  download)
    NAME=${3:-PodTube-ipa}
    DIR=${4:-/tmp/pt/dl}
    mkdir -p "$DIR"
    gh run download "$ID" -n "$NAME" -D "$DIR"
    ls -la "$DIR"
    ;;
esac
