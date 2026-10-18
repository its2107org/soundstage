#!/bin/bash
# Builds Soundstage for the iPhone simulator, checks it against a pretend Klipsch soundbar running
# on this machine, and takes screenshots of the main screens in light and dark mode.
set -eo pipefail

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
c=[x for r,l in d.items() if "iOS" in r for x in l if x["name"].startswith("iPhone") and "Pro" in x["name"] and "Max" not in x["name"]]
c.sort(key=lambda x:x["name"])
print(c[-1]["udid"])')
echo "Using simulator $UDID"

xcodebuild -project Soundstage.xcodeproj -scheme Soundstage -configuration Debug -sdk iphonesimulator \
  -destination "id=$UDID" -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build.log | grep -E "error:|warning: unre|BUILD (SUCCEEDED|FAILED)" || true
grep -q "BUILD SUCCEEDED" build.log || { echo "::error::Build failed"; grep -E "error:" build.log | sort -u | head -80; exit 1; }

APP=build/Build/Products/Debug-iphonesimulator/Soundstage.app
BID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"
mkdir -p shots

# 1. End-to-end check against a pretend soundbar (on the normal web port, like the real one),
#    which also announces itself on the network like the real one.
sudo python3 scripts/fake_soundbar.py 80 shots/fake_soundbar.log &
BAR=$!
dns-sd -R "Living Room" _googlecast._tcp local 80 md="Klipsch Cinema 1200" > /dev/null &
ANNOUNCE=$!
trap 'sudo kill $BAR 2>/dev/null || true; kill $ANNOUNCE 2>/dev/null || true' EXIT
sleep 2
curl -s "http://127.0.0.1/api/getData?path=settings:/system/manufacturer&roles=value" || { echo "::error::Pretend soundbar didn't start"; exit 1; }
echo
ifconfig | grep "inet " || true
xcrun simctl launch --terminate-running-process "$UDID" "$BID" -SoundstageSelfTest
for i in $(seq 1 60); do
  DATA=$(xcrun simctl get_app_container "$UDID" "$BID" data)
  [ -f "$DATA/Documents/selftest.json" ] && break
  sleep 2
done
echo "--- What the pretend soundbar was asked to change ---"
grep "^SET" shots/fake_soundbar.log | head -60 || true
if [ -f "$DATA/Documents/selftest.json" ]; then
  cp "$DATA/Documents/selftest.json" shots/selftest.json
  python3 -m json.tool shots/selftest.json
  grep -q '"all passed"' shots/selftest.json || { echo "::error::Self-check against the pretend soundbar failed"; exit 1; }
else
  echo "::error::Self-check produced no result"
  exit 1
fi
xcrun simctl terminate "$UDID" "$BID" || true

# 2. Screenshots with a pretend soundbar.
shoot() { # name, extra args
  local name=$1; shift
  xcrun simctl launch --terminate-running-process "$UDID" "$BID" "$@"
  sleep 6
  xcrun simctl io "$UDID" screenshot "shots/$name.png"
}
for mode in light dark; do
  xcrun simctl ui "$UDID" appearance $mode
  shoot "home-$mode" -SoundstageDemo
  shoot "eq-$mode" -SoundstageDemo -SoundstageDemoEQ
  shoot "speakers-$mode" -SoundstageDemo -SoundstageDemoSpeakers
  shoot "preset-$mode" -SoundstageDemo -SoundstageDemoPreset
  shoot "settings-$mode" -SoundstageDemo -SoundstageDemoSettings
  shoot "off-$mode" -SoundstageDemo -SoundstageDemoOff
  shoot "unreachable-$mode" -SoundstageDemo -SoundstageDemoUnreachable
  shoot "welcome-$mode" -SoundstageDemoWelcome
done
ls -la shots
