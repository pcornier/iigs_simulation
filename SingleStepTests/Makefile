V = verilator
COSIM = n

TOP = --top-module singlesteptests
RTL = ../rtl
V_INC = +incdir+$(RTL)

V_DEFINE = +define+debug=1 +define+SIMULATION=1   -CFLAGS "-I../vsim/sim/vinc -g "  --timescale-override 1ps/1ps -Wno-TIMESCALEMOD -Wno-fatal \
	-I$(RTL)  \
	-I$(RTL)/65C816  \
	-I..

V_DEFINE += --trace

UNAME_S := $(shell uname -s)

CFLAGS += $(CC_OPT) $(CC_DEFINE)
LDFLAGS = $(LIBS)
EXE = ./obj_dir/Vsinglesteptests
#V_OPT = -O3 --x-assign fast --x-initial fast --noassert
V_OPT =  --x-assign fast --x-initial fast --noassert
#CC_OPT = -O
CC_OPT =

V_SRC = \
	singlesteptests.v  \
	$(RTL)/65C816/P65C816_pkg.sv \
	$(RTL)/65C816/P65C816.sv \
	$(RTL)/65C816/AddrGen.sv \
	$(RTL)/65C816/BCDAdder.v \
	$(RTL)/65C816/AddSubBCD.sv \
	$(RTL)/65C816/ALU.sv \
	$(RTL)/65C816/bit_adder.v \
	$(RTL)/65C816/adder4.v \
	$(RTL)/65C816/mcode.sv \

C_SRC = \
	sim_main.cpp

VOUT = obj_dir/Vsinglesteptests.cpp

all: $(EXE)

$(VOUT): $(V_SRC)  Makefile
	$V -cc $(V_OPT) -LDFLAGS "$(LDFLAGS) " -exe  --Mdir ./obj_dir $(V_DEFINE) $(V_INC) $(TOP) -CFLAGS "$(CFLAGS)" $(V_SRC) $(C_SRC)
	#$V -cc $(V_OPT) -LDFLAGS "$(LDFLAGS) " -exe --trace --Mdir ./obj_dir $(V_DEFINE) $(V_INC) $(TOP) -CFLAGS $(CFLAGS) $(V_SRC) $(C_SRC)

$(EXE): $(VOUT) $(C_SRC)
#	(cd obj_dir; make OPT="-fauto-inc-dec -fdce -fdefer-pop -fdse -ftree-ccp -ftree-ch -ftree-fre -ftree-dce -ftree-dse" -f Vsinglesteptests.mk)
	(cd obj_dir; make -f Vsinglesteptests.mk OBJCACHE=)

fast:
	(cd obj_dir; rm -f *.o ; make OPT="-fcompare-elim -fcprop-registers -fguess-branch-probability -fauto-inc-dec -fif-conversion2 -fif-conversion -fipa-pure-const -fdce -fipa-profile -fipa-reference -fmerge-constants -fsplit-wide-types -fdefer-pop -fdse -ftree-ccp -ftree-ch -ftree-fre -ftree-dce -ftree-dse -ftree-builtin-call-dce -ftree-copyrename -ftree-dominator-opts -ftree-forwprop -ftree-phiprop -ftree-sra -ftree-pta -ftree-ter -funit-at-a-time -ftree-bit-ccp -falign-functions  -falign-jumps -falign-loops  -falign-labels -fcaller-saves -fcrossjumping -fcse-follow-jumps -fcse-skip-blocks -fdelete-null-pointer-checks -fdevirtualize -fexpensive-optimizations -fgcse  -fgcse-lm -finline-small-functions -findirect-inlining -fipa-sra -foptimize-sibling-calls -fpartial-inlining -fpeephole2 -fregmove -freorder-blocks  -freorder-functions -frerun-cse-after-loop -fsched-interblock  -fsched-spec -fschedule-insns -fschedule-insns2 -fstrict-aliasing -fstrict-overflow -ftree-switch-conversion -ftree-pre -ftree-vrp" -f Vsinglesteptests.mk)

clean:
	rm -f obj_dir/*
