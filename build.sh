#!/usr/bin/env bash
# Build GeekBread for iOS Simulator and macOS (Mac Catalyst) in parallel,
# then export both .app bundles to build/dist/ so they're easy to find.
#
# Default:           ./build.sh           (both, in parallel)
# Single platform:   ./build.sh --ios     ./build.sh --mac
# Serial fallback:   ./build.sh --serial  (helpful when debugging)
#
# Parallel safety: the source tree (sources + generated .xcodeproj) is
# APFS-cloned into build/clone-{ios,mac}/ so each xcodebuild process owns
# a fully self-contained copy. cp -cR uses APFS clonefile() — copy-on-write
# at the block level, so the clone is essentially free.
set -euo pipefail

cd "$(dirname "$0")"

OUT="build/dist"
LOGS="build/logs"
CLONE_IOS="build/clone-ios"
CLONE_MAC="build/clone-mac"
mkdir -p "$OUT" "$LOGS"

# Tree items every clone needs: source dirs + the generated xcodeproj.
SOURCES=(GeekBread GeekBreadWidgets GeekBreadShareExtension GeekBreadTests GeekBread.xcodeproj)

clone_tree() {
  local dest="$1"
  rm -rf "$dest"
  mkdir -p "$dest"
  for item in "${SOURCES[@]}"; do
    cp -cR "$item" "$dest/$item"
  done
}

build_ios() {
  clone_tree "$CLONE_IOS"
  local derived="build/derived-ios"
  xcodebuild build \
    -project "$CLONE_IOS/GeekBread.xcodeproj" \
    -scheme GeekBread \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO \
    >"$LOGS/ios.log" 2>&1
  rm -rf "$OUT/GeekBread-iOS.app"
  cp -R "$derived/Build/Products/Debug-iphonesimulator/GeekBread.app" \
        "$OUT/GeekBread-iOS.app"
}

build_mac() {
  clone_tree "$CLONE_MAC"
  local derived="build/derived-mac"
  local archive="$OUT/GeekBread-Mac.xcarchive"
  rm -rf "$archive"
  xcodebuild archive \
    -project "$CLONE_MAC/GeekBread.xcodeproj" \
    -scheme GeekBread \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -archivePath "$archive" \
    -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO \
    >"$LOGS/mac.log" 2>&1
  rm -rf "$OUT/GeekBread-Mac.app"
  cp -R "$archive/Products/Applications/GeekBread.app" \
        "$OUT/GeekBread-Mac.app"
}

# Regenerate the root xcodeproj before cloning so both builds see the same
# spec. xcodegen is fast (~1s) — do it serially before fanning out.
xcodegen generate >"$LOGS/xcodegen.log" 2>&1

run_parallel() {
  echo "Building iOS and Mac Catalyst in parallel..."
  build_ios &  local pid_ios=$!
  build_mac &  local pid_mac=$!
  local fail=0
  wait $pid_ios || { echo "iOS build FAILED — tail $LOGS/ios.log" >&2; fail=1; }
  wait $pid_mac || { echo "Mac build FAILED — tail $LOGS/mac.log" >&2; fail=1; }
  return $fail
}

run_serial() {
  echo "Building iOS..."
  build_ios
  echo "Building Mac Catalyst..."
  build_mac
}

report() {
  echo
  echo "Outputs:"
  for app in "$OUT"/*.app; do
    [ -e "$app" ] || continue
    printf "  %s  (%s)\n" "$app" "$(du -sh "$app" | cut -f1)"
  done
  [ -e "$OUT/GeekBread-Mac.xcarchive" ] && \
    printf "  %s\n" "$OUT/GeekBread-Mac.xcarchive"
  echo
  echo "Open the Mac app:    open $OUT/GeekBread-Mac.app"
  echo "Install iOS sim app: xcrun simctl install booted $OUT/GeekBread-iOS.app"
}

case "${1:-all}" in
  --ios|ios)       build_ios; report ;;
  --mac|mac)       build_mac; report ;;
  --serial|serial) run_serial; report ;;
  all|"")          run_parallel; report ;;
  *) echo "usage: $0 [--ios|--mac|--serial|all]" >&2; exit 2 ;;
esac
