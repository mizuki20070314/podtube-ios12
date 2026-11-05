#!/bin/bash
# Installs the simulator build and takes screenshots of several screens (used by CI; run on macOS).
# usage: Tools/ci_screenshots.sh <PodTube.app> <simulator-udid> [scenario-filter]
set -u
APP="$1"
UDID="$2"
FILTER="${3:-}"
BUNDLE=com.podtube.ios12
OUT=shots
mkdir -p "$OUT"

xcrun simctl install "$UDID" "$APP"

# name, seconds to wait, launch args...
shot() {
  local name="$1"; local wait="$2"; shift 2
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then return; fi
  echo "=== $name"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" -AppleLanguages "(ja)" -AppleLocale ja_JP "$@" || echo "launch failed"
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" || echo "screenshot failed"
  # keep a crash marker if the app is no longer running
  if ! xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -q "UIKitApplication:$BUNDLE"; then
    echo "!!! app not running after $name" | tee -a "$OUT/crashes.txt"
  fi
}

VID=dQw4w9WgXcQ
shot 01_home_dark 16 -pt-theme dark
shot 02_home_light 16 -pt-theme light
shot 03_search 14 -pt-theme dark -route "search:猫"
shot 04_suggest 6 -pt-theme dark -route "suggest:ねこ"
shot 05_watch 18 -pt-theme dark -route "watch:$VID"
shot 06_watch_mini 18 -pt-theme dark -route "watch:$VID;wait:9;minimize;wait:2"
shot 07_comments 22 -pt-theme dark -route "watch:$VID;wait:9;comments"
shot 08_channel 14 -pt-theme dark -route "channel:UCuAXFkgsw1L7xaCfnd5JJOw"
shot 09_playlist 14 -pt-theme dark -route "playlist:PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI"
shot 10_shorts 22 -pt-theme dark -route "tab:1"
shot 11_subs 6 -pt-theme dark -route "tab:2"
shot 12_library 6 -pt-theme dark -route "tab:3"
shot 13_settings 6 -pt-theme dark -route "settings"
shot 14_sheet 6 -pt-theme dark -route "sheet"
shot 15_landscape 22 -pt-theme dark -route "watch:$VID;wait:9;landscape;wait:3"
shot 16_watch_light 18 -pt-theme light -route "watch:$VID"
shot 17_controls 14 -pt-theme dark -route "watch:$VID;wait:7;w:seek60;wait:2;w:controls"
shot 18_captions 22 -pt-theme dark -route "watch:$VID;wait:8;w:captions;wait:3;w:seek60;wait:4"
shot 19_description 16 -pt-theme dark -route "watch:$VID;wait:7;w:expand"
shot 20_player_settings 14 -pt-theme dark -route "watch:$VID;wait:7;w:settings"
shot 21_search_light 14 -pt-theme light -route "search:ホロライブ"
shot 22_shorts_light 22 -pt-theme light -route "tab:1"
shot 24_diag 26 -pt-theme dark -route "diag"
shot 25_channel_about 20 -pt-theme dark -route "channel:UCuAXFkgsw1L7xaCfnd5JJOw;wait:7;channeltab:3"
shot 23_chapters 18 -pt-theme dark -route "watch:aircAruvnKk;wait:8;w:chapters"

xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
ls -la "$OUT"
