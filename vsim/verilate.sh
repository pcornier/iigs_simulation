OPTIMIZE="-O3 --x-assign fast --x-initial fast --noassert"
WARNINGS="-Wno-fatal"
DEFINES="+define+SIMULATION=1 "
echo "verilator -cc --compiler msvc $WARNINGS $OPTIMIZE"
verilator -cc --compiler msvc $WARNINGS $OPTIMIZE \
	--converge-limit 6000 \
	--top-module emu sim.v \
	-I../rtl \
	-I../rtl/JTFRAME \
	-I../rtl/jt49 \
	-I../rtl/jt5205 \
	-I../rtl/tv80 \
	../rtl/65C816/P65C816_pkg.sv \
	../rtl/65C816/P65C816_pkg.sv \
	../rtl/65C816/P65C816.sv \
	../rtl/65C816/AddrGen.sv \
	../rtl/65C816/BCDAdder.v \
	../rtl/65C816/AddSubBCD.sv \
	../rtl/65C816/ALU.sv \
	../rtl/65C816/bit_adder.v \
	../rtl/65C816/adder4.v \
	../rtl/65C816/mcode.sv \
	../top.v

exit
