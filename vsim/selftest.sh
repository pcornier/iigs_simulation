# Run the selftest 
# 8500 ish is for the flashing error 
# this is for the speed 05 error  - 8840
./obj_dir/Vemu --selftest --no-cpu-log --stop-at-frame 19000 --screenshot 8500,8501,8502,8840,9000,9550,9750,10000,10500,11000,12000,13000,14000,15000,16000,17000,18000,19000 &> selftest2.txt
