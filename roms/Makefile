all: roms

apple2gs.zip:
	echo "put MAME 0.286 apple2gs.zip into this folder"

342-0077-b: apple2gs.zip
	unzip -o -j apple2gs.zip apple2gsr1/342-0077-b

341-0728: apple2gs.zip
	unzip -o -j apple2gs.zip 341-0728

341-0748: apple2gs.zip
	unzip -o -j apple2gs.zip 341-0748

# ROM3 binary (256KB): banks FC-FD (341-0728) + FE (341-0748 second half) + FF (341-0748 first half)
# MiSTer loads this as boot.rom (ioctl_index[15:6]==0)
../vsim/boot.rom: 341-0728 341-0748
	cat 341-0728 > $@
	dd if=341-0748 bs=65536 skip=1 count=1 >> $@ 2>/dev/null
	dd if=341-0748 bs=65536 count=1 >> $@ 2>/dev/null

# ROM1 binary (128KB): banks FE-FF (342-0077-b)
# MiSTer loads this as boot1.rom (ioctl_index[15:6]==1)
../vsim/boot1.rom: 342-0077-b
	cp 342-0077-b $@

# Character ROM - generated from KEGS font data via gen_chr.py
../vsim/chr.mem: ../vsim/gen_chr.py
	cd ../vsim && python3 gen_chr.py
	mv ../vsim/chr_iigs.mem $@

roms: ../vsim/boot.rom ../vsim/boot1.rom ../vsim/chr.mem

clean:
	rm -f 342-0077-b 341-0728 341-0748
	rm -f ../vsim/boot.rom ../vsim/boot1.rom ../vsim/chr.mem ../vsim/chr_iigs.mem
