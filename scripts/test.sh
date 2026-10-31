#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/swift-env.sh"
# Command Line Tools bundles Swift Testing outside SwiftPM's default search path.
testing_frameworks="$(xcode-select -p)/Library/Developer/Frameworks"
testing_options=()
if [[ -d "$testing_frameworks/Testing.framework" ]]; then
  testing_options=(-Xswiftc "-F$testing_frameworks" -Xlinker -rpath -Xlinker "$testing_frameworks")
fi
swift test "${swift_options[@]}" "${testing_options[@]}" "$@"
