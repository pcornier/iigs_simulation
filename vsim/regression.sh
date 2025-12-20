#!/bin/bash
# This will run the vsim and snapshot known working hard disks and compare the images

# Check for required disk images
MISSING_DISKS=0
for disk in totalreplay.hdv Pitch-Dark-20210331.hdv gsos.hdv arkanoid.hdv "Total Replay II v1.0-alpha.4.hdv"; do
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
    echo "  - arkanoid.hdv"
    echo "  - Total Replay II v1.0-alpha.4.hdv"
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
./obj_dir/Vemu --disk totalreplay.hdv --stop-at-frame 155 --screenshot 155 &> totalreplay.txt
if [ -f "regression_images/totalreplay_screenshot_frame_0155.png" ]; then
    if diff screenshot_frame_0155.png regression_images/totalreplay_screenshot_frame_0155.png > /dev/null 2>&1; then
        echo "  PASS: Total Replay"
    else
        echo "  FAIL: Total Replay - screenshot differs"
        FAILED=1
    fi
else
    echo "  SKIP: Total Replay - missing reference image"
fi

echo "Running Pitch Dark test..."
./obj_dir/Vemu --disk Pitch-Dark-20210331.hdv --stop-at-frame 159 --screenshot 159 &> pitchdark.txt
if [ -f "regression_images/pitchdark_screenshot_frame_0159.png" ]; then
    if diff screenshot_frame_0159.png regression_images/pitchdark_screenshot_frame_0159.png > /dev/null 2>&1; then
        echo "  PASS: Pitch Dark"
    else
        echo "  FAIL: Pitch Dark - screenshot differs"
        FAILED=1
    fi
else
    echo "  SKIP: Pitch Dark - missing reference image"
fi

echo "Running GS/OS test..."
./obj_dir/Vemu --disk gsos.hdv --stop-at-frame 320 --screenshot 320 &> gsos.txt
if [ -f "regression_images/gsos_screenshot_frame_0320.png" ]; then
    if diff screenshot_frame_0320.png regression_images/gsos_screenshot_frame_0320.png > /dev/null 2>&1; then
        echo "  PASS: GS/OS"
    else
        echo "  FAIL: GS/OS - screenshot differs"
        FAILED=1
    fi
else
    echo "  SKIP: GS/OS - missing reference image"
fi

echo "Running Arkanoid test..."
./obj_dir/Vemu --disk arkanoid.hdv --stop-at-frame 485 --screenshot 485 &> arkanoid.txt
if [ -f "regression_images/arkanoid_screenshot_frame_0485.png" ]; then
    if diff screenshot_frame_0485.png regression_images/arkanoid_screenshot_frame_0485.png > /dev/null 2>&1; then
        echo "  PASS: Arkanoid"
    else
        echo "  FAIL: Arkanoid - screenshot differs"
        FAILED=1
    fi
else
    echo "  SKIP: Arkanoid - missing reference image"
fi

echo "Running Total Replay II test..."
./obj_dir/Vemu --disk "Total Replay II v1.0-alpha.4.hdv" --stop-at-frame 156 --screenshot 156 &> totalreplay2.txt
if [ -f "regression_images/totalreplay2_screenshot_frame_0156.png" ]; then
    if diff screenshot_frame_0156.png regression_images/totalreplay2_screenshot_frame_0156.png > /dev/null 2>&1; then
        echo "  PASS: Total Replay II"
    else
        echo "  FAIL: Total Replay II - screenshot differs"
        FAILED=1
    fi
else
    echo "  SKIP: Total Replay II - missing reference image"
fi

echo "Running BASIC boot (reset) test..."
./obj_dir/Vemu --reset-at-frame 240 --stop-at-frame 295 --screenshot 295 &> basic_boot.txt
if [ -f "regression_images/basic_boot_screenshot_frame_0295.png" ]; then
    if diff screenshot_frame_0295.png regression_images/basic_boot_screenshot_frame_0295.png > /dev/null 2>&1; then
        echo "  PASS: BASIC boot"
    else
        echo "  FAIL: BASIC boot - screenshot differs"
        FAILED=1
    fi
else
    echo "  SKIP: BASIC boot - missing reference image"
fi

echo ""
if [ $FAILED -eq 0 ]; then
    echo "All regression tests passed!"
    exit 0
else
    echo "Some regression tests failed."
    exit 1
fi
