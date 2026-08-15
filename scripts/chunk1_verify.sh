#!/bin/bash
# Chunk 1 verification: build LifeOS scheme, run focused onboarding-relevant tests.
# Run from the repo root.
set -euo pipefail

SCHEME="LifeOS"
PROJECT="LifeOS.xcodeproj"

# Pick any installed, available iOS simulator rather than hardcoding a device
# name/OS that may not exist on this machine.
SIMCTL_JSON=$(xcrun simctl list devices available -j 2>/tmp/simctl_err.log) || {
  echo "'xcrun simctl list' failed — CoreSimulatorService is likely unavailable on this machine." >&2
  cat /tmp/simctl_err.log >&2
  echo "Try: sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService, or restart Xcode/the Mac, then re-run." >&2
  exit 1
}

if [ -z "$SIMCTL_JSON" ]; then
  echo "No available iOS simulator found (empty simctl output). Open Xcode > Settings > Platforms and install an iOS simulator runtime, or create one in Window > Devices and Simulators." >&2
  exit 1
fi

SIM_UDID=$(printf '%s' "$SIMCTL_JSON" | /usr/bin/python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(0)
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        if d.get("isAvailable", True):
            print(d["udid"])
            sys.exit(0)
')

if [ -z "$SIM_UDID" ]; then
  echo "No available iOS simulator found. Open Xcode > Settings > Platforms and install an iOS simulator runtime, or create one in Window > Devices and Simulators." >&2
  exit 1
fi

DESTINATION="platform=iOS Simulator,id=$SIM_UDID"
echo "Using simulator: $(xcrun simctl list devices | grep "$SIM_UDID")"

echo "== plutil lint =="
plutil -lint "$PROJECT/project.pbxproj"

echo "== Build =="
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -quiet

echo "== Focused tests (onboarding / profile / goal creation) =="
# LifeOSUnitTests + LifeOSComponentTests are the headless targets; adjust the
# -only-testing filters below to whatever onboarding-specific test class you add.
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:LifeOSUnitTests \
  -only-testing:LifeOSComponentTests \
  -quiet

echo "Done. To list all available test identifiers:"
echo "  xcodebuild test -project $PROJECT -scheme $SCHEME -destination '$DESTINATION' -showTestPlans"
