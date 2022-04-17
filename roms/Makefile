all: roms


apple2gs.zip: 
	echo "put mame apple2gs.zip into this folder"

apple2gs.chr: apple2gs.zip
	unzip -o apple2gs.zip apple2gs.chr

342-0077-b: apple2gs.zip
	unzip -o -j apple2gs.zip apple2gsr1/342-0077-b

roms: apple2gs.chr 342-0077-b
	hexdump -v -n 65536 -e '1/1 "%02X" "\n"' 342-0077-b > ../rtl/rom1.mem
	hexdump -v -s 65536 -e '1/1 "%02X" "\n"' 342-0077-b > ../rtl/rom2.mem
	hexdump -v -e '1/1 "%02X" "\n"' apple2gs.chr > ../rtl/chr.mem
	cp ../rtl/chr.mem ../vsim/
	cp ../rtl/chr.mem ../verilator/
	cp ../rtl/rom?.mem ../vsim/
	cp ../rtl/rom?.mem ../verilator/
