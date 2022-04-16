.PHONY: verilator

CFLAGS := $(shell pkg-config sdl2 readline --cflags)
LDFLAGS := $(shell pkg-config sdl2 readline --libs)
SEARCH := $(shell find ../rtl/ -type d -printf '-I%p ')

# verilator:
# 	rm -rf ./obj_dir
# 	verilator -Wall -Irtl -Wno-fatal --cc ./top.v  -y ../ ${SEARCH} --exe tb.cpp --trace --trace-max-width 4 -CFLAGS '${CFLAGS} -g' -LDFLAGS '${LDFLAGS}' vconf.vlt
# 	make -j -C ./obj_dir -f Vtop.mk Vtop
# 	cp -R obj_dir ~

roms:
	hexdump -v -n 65536 -e '1/1 "%02X" "\n"' ../doc/APPLE2GS.ROM > ./rom1.mem
	hexdump -v -s 65536 -e '1/1 "%02X" "\n"' ../doc/APPLE2GS.ROM > ./rom2.mem
