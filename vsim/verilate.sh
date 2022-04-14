OPTIMIZE="-O3 --x-assign fast --x-initial fast --noassert"
WARNINGS="-Wno-fatal"
DEFINES="+define+SIMULATION=1 "
echo "verilator -cc --compiler msvc $WARNINGS $OPTIMIZE"
verilator -cc --compiler msvc $WARNINGS $OPTIMIZE \
--converge-limit 6000 \
--top-module emu sim.v \
../rtl/fdc.v \
	../rtl/6847/mc6847.v \
	../rtl/reset_de.v \
-I../rtl \
-I../rtl/JTFRAME \
-I../rtl/jt49 \
-I../rtl/jt5205 \
-I../rtl/tv80


exit
