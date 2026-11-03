#!/bin/bash
# Screenshot tour driver (UX review harness). See ScreenshotTour.swift.
#
#   run_screenshot_tour.sh <pass> <simulator-id> <derived-data> <out-dir> [golden-dir]
#
# pass:
#   restore  first launch (catalog import, insights from the mock), then seed
#            the store from $SNAPSHOT with seed_store_from_snapshot.py, then
#            save the app's data container as the golden copy
#   light    full tour, light appearance
#   dark     full tour, dark appearance
#   ax       Home, library and workout at the largest accessibility text size
#   ax_live  workout + summary at AX5, resized live (Home hides every
#            template row at AX5, so the workout can't be started there)
#
# Every tour pass first copies the golden container back, so each pass sees
# identical data (the workout test finishes a workout, which would otherwise
# leak into the next pass). Start mock_functions_server.py first, and run
# `xcodebuild build-for-testing` with the same derived-data path.
#
# The simulator must be one you own: this replaces the app's data on it.
set -euo pipefail

PASS="$1"
SIM="$2"
DD="$3"
OUT="$4"
GOLDEN="${5:-$OUT/../golden_container}"
BUNDLE=com.eddelord.ClaudeLifter
HERE="$(cd "$(dirname "$0")/../.." && pwd)"

run_tests() {
    local suffix="$1" size="$2"; shift 2
    local only=()
    for t in "$@"; do only+=("-only-testing:ClaudeLifterUITests/ScreenshotTour/$t"); done
    (cd "$HERE" && \
        TEST_RUNNER_SCREENSHOT_DIR="$OUT" \
        TEST_RUNNER_SCREENSHOT_SUFFIX="$suffix" \
        TEST_RUNNER_SCREENSHOT_CONTENT_SIZE="$size" \
        TEST_RUNNER_SCREENSHOT_RESTORE="${RESTORE:-0}" \
        TEST_RUNNER_SCREENSHOT_SECTIONS="${SECTIONS:-}" \
        xcodebuild -scheme ClaudeLifter \
            -destination "platform=iOS Simulator,id=$SIM" \
            -derivedDataPath "$DD" \
            test-without-building "${only[@]}" \
        | grep -E "Test Case .*(passed|failed|skipped)|error:|TEST (SUCCEEDED|FAILED)|\*\* TEST" || true)
}

restore_golden() {
    xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
    local container
    container="$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)"
    rsync -a --delete --exclude 'Library/Caches' "$GOLDEN/" "$container/"
}

mkdir -p "$OUT"
case "$PASS" in
    restore)
        # Needs SNAPSHOT=<path to a GET /api/sync/snapshot body> in the env.
        xcrun simctl ui "$SIM" appearance light
        RESTORE=1 run_tests restore "" test00_firstLaunch
        xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
        container="$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)"
        python3 -I "$HERE/ClaudeLifterUITests/ScreenshotHarness/seed_store_from_snapshot.py" \
            --store "$container/Library/Application Support/default.store" \
            --snapshot "$SNAPSHOT"
        mkdir -p "$GOLDEN"
        rsync -a --delete --exclude 'Library/Caches' "$container/" "$GOLDEN/"
        echo "golden container saved to $GOLDEN"
        ;;
    light|dark)
        restore_golden
        xcrun simctl ui "$SIM" appearance "$PASS"
        run_tests "$PASS" "" test01_tour
        ;;
    ax)
        restore_golden
        xcrun simctl ui "$SIM" appearance light
        SECTIONS=home,library,workout run_tests ax5 \
            UICTContentSizeCategoryAccessibilityXXXL test01_tour
        ;;
    ax_live)
        # Workout + summary at AX5. The tour starts the workout at the
        # default size and writes READY_FOR_RESIZE into $OUT; flip the size
        # then with `xcrun simctl ui $SIM content_size
        # accessibility-extra-extra-extra-large` (see the AX section of the
        # tour), and set it back to `large` afterwards.
        restore_golden
        xcrun simctl ui "$SIM" appearance light
        SECTIONS=workoutLiveResize run_tests ax5 "" test01_tour
        ;;
    *)
        echo "unknown pass: $PASS" >&2
        exit 2
        ;;
esac
