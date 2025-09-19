# This will run the vsim and snapshop known working hard disks and compare the images
./obj_dir/Vemu --disk totalreplay.hdv --stop-at-frame 200 --screenshot 200 &> totalreplay.txt
diff screenshot_frame_0200.png regression_images/totalreplay_screenshot_frame_0200.png
./obj_dir/Vemu --disk Pitch-Dark-20210331.hdv --stop-at-frame 160 --screenshot 160 &> pitchdark.txt
diff screenshot_frame_0160.png regression_images/pitchdark_screenshot_frame_0160.png
./obj_dir/Vemu --disk gsos.hdv --stop-at-frame 315 --screenshot 315 &> gsos.txt
diff screenshot_frame_0315.png regression_images/gsos_screenshot_frame_0315.png
