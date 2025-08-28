all: roms


apple2gs.zip: 
	echo "put mame apple2gs.zip into this folder"

apple2gs.chr: apple2gs.zip
	unzip -o apple2gs.zip apple2gs.chr

342-0077-b: apple2gs.zip
	unzip -o -j apple2gs.zip apple2gsr1/342-0077-b

roms: apple2gs.chr 342-0077-b
	hexdump -v -n 65536 -e '1/1 "%02X" "\n"' 342-0077-b > ../vsim/rom1/rom1.mem
	hexdump -v -s 65536 -e '1/1 "%02X" "\n"' 342-0077-b > ../vsim/rom1/rom2.mem
	# FC-FD from 341-0737
	hexdump -v -n 65536 -e '1/1 "%02X" "\n"' "Apple IIGS ROM 3 Banks FC-FD - 341-0737.bin" > ../vsim/rom3/romc.mem
	hexdump -v -s 65536 -e '1/1 "%02X" "\n"' "Apple IIGS ROM 3 Banks FC-FD - 341-0737.bin" > ../vsim/rom3/romd.mem
	# FF-FE from 341-0748: First 64KB=FF bank, Second 64KB=FE bank
	hexdump -v -n 65536 -e '1/1 "%02X" "\n"' "Apple IIGS ROM 3 Banks FF-FE - 341-0748.bin" > ../vsim/rom3/rom2.mem
	hexdump -v -s 65536 -e '1/1 "%02X" "\n"' "Apple IIGS ROM 3 Banks FF-FE - 341-0748.bin" > ../vsim/rom3/rom1.mem
	hexdump -v -e '1/1 "%02X" "\n"' apple2gs.chr > ../rtl/chr.mem
	cp ../rtl/chr.mem ../vsim/
	cp ../rtl/chr.mem ../verilator/
	cp ../rtl/rom?.mem ../vsim/
	cp ../rtl/rom?.mem ../verilator/
