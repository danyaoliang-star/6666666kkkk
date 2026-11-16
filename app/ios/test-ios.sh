#!/bin/bash
set -euo pipefail
NATIVE_ROOT="$(cd "$(dirname "$0")" && pwd)"
RESULT_BUNDLE="${IOS_RESULT_BUNDLE:-$NATIVE_ROOT/build/NativeChecks.xcresult}"
python3 "$NATIVE_ROOT/verify_project.py"
plutil -lint "$NATIVE_ROOT/FamilyHealth.xcodeproj/project.pbxproj" "$NATIVE_ROOT/FamilyHealth/Info.plist" "$NATIVE_ROOT/FamilyHealth/Info-Debug.plist"
SIMULATOR_ID="${IOS_SIMULATOR_ID:-}"
if [[ -z "$SIMULATOR_ID" ]]; then
  SIMULATOR_ID="$(python3 - <<'PY'
import json, subprocess
data = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))
devices = [device for runtime, entries in data['devices'].items() if 'iOS' in runtime for device in entries if 'iPhone' in device['name'] and device.get('isAvailable', True)]
if not devices:
    raise SystemExit('No iPhone simulator is installed. Install an iOS simulator in Xcode settings first.')
devices.sort(key=lambda device: device['state'] != 'Booted')
print(devices[0]['udid'])
PY
)"
fi
xcodebuild -project "$NATIVE_ROOT/FamilyHealth.xcodeproj" -scheme FamilyHealth -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath "$NATIVE_ROOT/build/DerivedData" \
  -resultBundlePath "$RESULT_BUNDLE" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
