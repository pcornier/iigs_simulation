all: roms

apple2gs.zip: 
	echo "put MAME 0.286 apple2gs.zip into this folder"

344s0047.bin : apple2gs.zip
	unzip -o apple2gs.zip 344s0047.bin

342-0077-b: apple2gs.zip
	unzip -o -j apple2gs.zip apple2gsr1/342-0077-b

341-0728: apple2gs.zip
	unzip -o -j apple2gs.zip 341-0728

341-0748: apple2gs.zip
	unzip -o -j apple2gs.zip 341-0748

roms: 344s0047.bin 342-0077-b 341-0728 341-0748
	hexdump -v -e '1/1 "%02X" "\n"' 342-0077-b > ../vsim/rom1/boot.rom
	# FC-FD from 341-0737
	hexdump -v -e '1/1 "%02X" "\n"' 341-0728 > ../vsim/rom3/boot.rom
	# FF-FE from 341-0748: First 64KB=FF bank, Second 64KB=FE bank
	hexdump -v -s 65536 -e '1/1 "%02X" "\n"' 341-0748 >>  ../vsim/rom3/boot.rom
	hexdump -v -n 65536 -e '1/1 "%02X" "\n"' 341-0748 >> ../vsim/rom3/boot.rom
	hexdump -v -n 4096 -e '1/1 "%02X" "\n"' 344s0047.bin > ../rtl/chr.mem
	mkdir -p ../rom1 ../rom3
	cp ../vsim/rom1/boot.rom ../rom1/boot.rom
	cp ../vsim/rom3/boot.rom ../rom3/boot.rom
	cp ../rtl/chr.mem ../vsim/
	cp ../rtl/chr.mem ../verilator/
