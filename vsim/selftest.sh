# Run the selftest 
# 8500 ish is for the flashing error 
# this is for the speed 05 error  - 8840
./obj_dir/Vemu --selftest --no-cpu-log --stop-at-frame 11000 --screenshot 8500,8501,8502,8840,9000,9550,9750,10000,10500,11000 &> selftest2.txt
