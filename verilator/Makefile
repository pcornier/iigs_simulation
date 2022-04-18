.PHONY: verilator

CFLAGS := $(shell pkg-config sdl2 readline --cflags)
LDFLAGS := $(shell pkg-config sdl2 readline --libs)
SEARCH := $(shell find ../rtl/ -type d -printf '-I%p ')

RTL=../rtl

V_SRC = \
        ../top.v \
        $(RTL)/65C816/P65C816_pkg.sv \
        $(RTL)/65C816/P65C816.sv \
        $(RTL)/65C816/AddrGen.sv \
        $(RTL)/65C816/BCDAdder.v \
        $(RTL)/65C816/AddSubBCD.sv \
        $(RTL)/65C816/ALU.sv \
        $(RTL)/65C816/bit_adder.v \
        $(RTL)/65C816/adder4.v \
        $(RTL)/65C816/mcode.sv \
        $(RTL)/fastram.v \
        $(RTL)/slowram.v \
        $(RTL)/dpram.sv \
        $(RTL)/rom.v \
        $(RTL)/prtc.v \
        $(RTL)/adb.v \
        $(RTL)/vdc.v \
        $(RTL)/video_timing.v \
        $(RTL)/iigs.v


verilator:
	rm -rf ./obj_dir
	verilator -Wall -Irtl -Wno-fatal --cc ./top.v  -y ../ ${V_SRC} --exe tb.cpp --trace --trace-max-width 4 -CFLAGS '${CFLAGS} -g' -LDFLAGS '${LDFLAGS}' vconf.vlt
	make -j -C ./obj_dir -f Vtop.mk Vtop
	cp -R obj_dir ~

roms:
	hexdump -v -n 65536 -e '1/1 "%02X" "\n"' ../doc/APPLE2GS.ROM > ./rom1.mem
	hexdump -v -s 65536 -e '1/1 "%02X" "\n"' ../doc/APPLE2GS.ROM > ./rom2.mem
	hexdump -v -e '1/1 "%02X" "\n"' ../doc/*.chr > ./chr.mem
