#!/bin/bash
# woz_regression.sh - Regression test for WOZ disk emulation
# Run from vsim/ directory

BASELINE_DIR="regression_baseline"
TEST_LOG="regression_test.log"
WOZ_IMAGE="ArkanoidIIgs.woz"
STOP_FRAME=1500
SCREENSHOT_FRAME=800

set -e

# Capture baseline (run once with known-good code)
capture_baseline() {
    echo "=== Capturing regression baseline ==="
    mkdir -p $BASELINE_DIR

    echo "Running simulation to frame $STOP_FRAME..."
    ./obj_dir/Vemu --woz $WOZ_IMAGE --screenshot $SCREENSHOT_FRAME --stop-at-frame $STOP_FRAME 2>&1 | tee $BASELINE_DIR/full.log

    echo "Extracting byte stream..."
    grep -a "BYTE_COMPLETE_ASYNC" $BASELINE_DIR/full.log > $BASELINE_DIR/bytes.txt

    echo "Extracting track changes..."
    grep -a "sony_ctl=4\|drive35_track CHANGED\|WOZ_CTRL.*Physical" $BASELINE_DIR/full.log > $BASELINE_DIR/tracks.txt

    echo "Copying screenshot..."
    cp screenshot_frame_0${SCREENSHOT_FRAME}.png $BASELINE_DIR/

    # Save summary stats
    echo "Bytes: $(wc -l < $BASELINE_DIR/bytes.txt)" > $BASELINE_DIR/summary.txt
    echo "Tracks: $(wc -l < $BASELINE_DIR/tracks.txt)" >> $BASELINE_DIR/summary.txt

    echo ""
    echo "=== Baseline captured ==="
    cat $BASELINE_DIR/summary.txt
    ls -la $BASELINE_DIR/
}

# Run regression test
run_test() {
    echo "=== Running regression test ==="

    if [ ! -d "$BASELINE_DIR" ]; then
        echo "ERROR: No baseline found. Run '$0 baseline' first."
        exit 1
    fi

    echo "Running simulation to frame $STOP_FRAME..."
    ./obj_dir/Vemu --woz $WOZ_IMAGE --screenshot $SCREENSHOT_FRAME --stop-at-frame $STOP_FRAME 2>&1 | tee $TEST_LOG

    echo ""
    echo "=== Comparing results ==="

    # Extract test data
    grep -a "BYTE_COMPLETE_ASYNC" $TEST_LOG > test_bytes.txt
    grep -a "sony_ctl=4\|drive35_track CHANGED\|WOZ_CTRL.*Physical" $TEST_LOG > test_tracks.txt

    PASS=1

    # Compare byte count
    BASELINE_BYTES=$(wc -l < $BASELINE_DIR/bytes.txt)
    TEST_BYTES=$(wc -l < test_bytes.txt)
    if [ "$BASELINE_BYTES" -eq "$TEST_BYTES" ]; then
        echo "PASS: Byte count matches ($TEST_BYTES bytes)"
    else
        echo "FAIL: Byte count differs (baseline=$BASELINE_BYTES, test=$TEST_BYTES)"
        PASS=0
    fi

    # Compare first/last bytes (quick sanity check)
    BASELINE_FIRST=$(head -100 $BASELINE_DIR/bytes.txt | md5)
    TEST_FIRST=$(head -100 test_bytes.txt | md5)
    BASELINE_LAST=$(tail -100 $BASELINE_DIR/bytes.txt | md5)
    TEST_LAST=$(tail -100 test_bytes.txt | md5)

    if [ "$BASELINE_FIRST" = "$TEST_FIRST" ] && [ "$BASELINE_LAST" = "$TEST_LAST" ]; then
        echo "PASS: Byte stream head/tail matches"
    else
        echo "FAIL: Byte stream differs"
        echo "  First 100 bytes: baseline=$BASELINE_FIRST test=$TEST_FIRST"
        echo "  Last 100 bytes: baseline=$BASELINE_LAST test=$TEST_LAST"
        PASS=0
    fi

    # Compare track count
    BASELINE_TRACKS=$(wc -l < $BASELINE_DIR/tracks.txt)
    TEST_TRACKS=$(wc -l < test_tracks.txt)
    if [ "$BASELINE_TRACKS" -eq "$TEST_TRACKS" ]; then
        echo "PASS: Track event count matches ($TEST_TRACKS events)"
    else
        echo "WARN: Track event count differs (baseline=$BASELINE_TRACKS, test=$TEST_TRACKS)"
    fi

    # Compare screenshot (binary diff)
    if cmp -s $BASELINE_DIR/screenshot_frame_0${SCREENSHOT_FRAME}.png screenshot_frame_0${SCREENSHOT_FRAME}.png; then
        echo "PASS: Screenshot matches"
    else
        echo "WARN: Screenshot differs (may need visual inspection)"
    fi

    # Cleanup
    rm -f test_bytes.txt test_tracks.txt

    echo ""
    if [ "$PASS" -eq 1 ]; then
        echo "=== REGRESSION TEST PASSED ==="
        exit 0
    else
        echo "=== REGRESSION TEST FAILED ==="
        exit 1
    fi
}

# Quick test - just check boot milestone
quick_test() {
    echo "=== Quick boot test ==="
    ./obj_dir/Vemu --woz $WOZ_IMAGE --screenshot $SCREENSHOT_FRAME --stop-at-frame $SCREENSHOT_FRAME 2>&1 | tail -20

    if [ -f "screenshot_frame_0${SCREENSHOT_FRAME}.png" ]; then
        echo "Screenshot captured at frame $SCREENSHOT_FRAME"
        if cmp -s $BASELINE_DIR/screenshot_frame_0${SCREENSHOT_FRAME}.png screenshot_frame_0${SCREENSHOT_FRAME}.png; then
            echo "PASS: Screenshot matches baseline"
        else
            echo "WARN: Screenshot differs from baseline"
        fi
    fi
}

case "$1" in
    baseline)
        capture_baseline
        ;;
    test)
        run_test
        ;;
    quick)
        quick_test
        ;;
    *)
        echo "Usage: $0 {baseline|test|quick}"
        echo ""
        echo "  baseline - Capture regression baseline (run once with known-good code)"
        echo "  test     - Run full regression test against baseline"
        echo "  quick    - Quick boot test with screenshot comparison"
        ;;
esac
