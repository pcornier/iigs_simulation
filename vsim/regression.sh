#!/bin/bash
# This will run the vsim and snapshot known working hard disks and compare the images

# Check for required disk images
MISSING_DISKS=0
for disk in totalreplay.hdv Pitch-Dark-20210331.hdv gsos.hdv; do
    if [ ! -f "$disk" ]; then
        echo "ERROR: Missing disk image: $disk"
        MISSING_DISKS=1
    fi
done

if [ $MISSING_DISKS -eq 1 ]; then
    echo ""
    echo "Please ensure all required disk images are in the vsim directory:"
    echo "  - totalreplay.hdv"
    echo "  - Pitch-Dark-20210331.hdv"
    echo "  - gsos.hdv"
    exit 1
fi

# Check for Vemu binary
if [ ! -f "./obj_dir/Vemu" ]; then
    echo "ERROR: Vemu binary not found. Run 'make' first."
    exit 1
fi

# Run regression tests
FAILED=0

echo "Running Total Replay test..."
./obj_dir/Vemu --disk totalreplay.hdv --stop-at-frame 200 --screenshot 200 &> totalreplay.txt
if [ -f "regression_images/totalreplay_screenshot_frame_0200.png" ]; then
    if diff screenshot_frame_0200.png regression_images/totalreplay_screenshot_frame_0200.png > /dev/null 2>&1; then
        echo "  PASS: Total Replay"
    else
        echo "  FAIL: Total Replay - screenshot differs"
        FAILED=1
    fi
else
    echo "  SKIP: Total Replay - missing reference image"
fi

echo "Running Pitch Dark test..."
./obj_dir/Vemu --disk Pitch-Dark-20210331.hdv --stop-at-frame 160 --screenshot 160 &> pitchdark.txt
if [ -f "regression_images/pitchdark_screenshot_frame_0160.png" ]; then
    if diff screenshot_frame_0160.png regression_images/pitchdark_screenshot_frame_0160.png > /dev/null 2>&1; then
        echo "  PASS: Pitch Dark"
    else
        echo "  FAIL: Pitch Dark - screenshot differs"
        FAILED=1
    fi
else
    echo "  SKIP: Pitch Dark - missing reference image"
fi

echo "Running GS/OS test..."
./obj_dir/Vemu --disk gsos.hdv --stop-at-frame 315 --screenshot 315 &> gsos.txt
if [ -f "regression_images/gsos_screenshot_frame_0315.png" ]; then
    if diff screenshot_frame_0315.png regression_images/gsos_screenshot_frame_0315.png > /dev/null 2>&1; then
        echo "  PASS: GS/OS"
    else
        echo "  FAIL: GS/OS - screenshot differs"
        FAILED=1
    fi
else
    echo "  SKIP: GS/OS - missing reference image"
fi

echo ""
if [ $FAILED -eq 0 ]; then
    echo "All regression tests passed!"
    exit 0
else
    echo "Some regression tests failed."
    exit 1
fi
