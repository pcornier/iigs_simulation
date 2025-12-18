# MVN/MVP Block Move Bank Bug Analysis

## Summary

Gauntlet crashes with an illegal instruction fetch after MVN completes. The CPU fetches the next instruction from the wrong bank (DBR instead of PBR), causing execution to jump to unintended code and eventually hit a BRK.

## Symptoms

From `gauntlet2.txt` trace:

```
MVN_P2_TRACK: 00:8078 STATE= 5 P[2]=1 IRQ_ACTIVE=0 LAST_CYCLE=0
MVN_P2_TRACK: 00:8075 STATE= 6 P[2]=1 IRQ_ACTIVE=0 LAST_CYCLE=1
00:8075: mvn $00, $01
MVN_P2_TRACK: 00:8075 STATE= 0 P[2]=1 IRQ_ACTIVE=0 LAST_CYCLE=0
01:8075: adc [$00],y     <-- WRONG! Should be 00:8078
01:8077: brk
```

The MVN at 00:8075 moves data from bank $00 to bank $01. When MVN completes:
- Internal PBR is correct: 00
- Internal PC appears to be at 8075 (should be 8078)
- But the address bus outputs 01:8075 (DBR:PC instead of PBR:PC)

## Analysis

### Issue 1: STATE Goes to 6 Instead of 0

The trace shows STATE transitioning from 5 to 6, but MVN's state 5 microcode has `STATE_CTRL = 3'b010` which should make NextState = 0 (since IsBranchCycle1 is false for MVN).

```
STATE_CTRL case 3'b010:
   if (IsBranchCycle1 == 1'b1 & JumpTaken == 1'b1)
      NextState = 4'b0010;
   else
      NextState = 4'b0000;  // Should go here for MVN
```

But STATE goes to 6, which means NextState = STATE + 1, implying STATE_CTRL was actually 3'b000.

**Possible causes:**
1. Wrong microcode entry being selected (indexing bug)
2. MVN microcode definition has wrong STATE_CTRL value
3. Something else overriding the state transition

### Issue 2: Address Bus Uses DBR Instead of PBR

When STATE finally reaches 0 (instruction fetch), the address bus outputs 01:8075 instead of 00:8078.

The ADDR_BUS generation for instruction fetch:
```verilog
case (MC.ADDR_BUS)
   4'b0000:
      ADDR_BUS = {PBR, PC};  // Instruction fetch - uses PBR
   4'b0001:
      ADDR_BUS = (({DBR, 16'h0000}) + ({8'h00, (AA[15:0])}) + ({8'h00, ADDR_INC}));  // Data - uses DBR
```

The fact that 01:8075 appears suggests either:
1. MC.ADDR_BUS is not 4'b0000 when it should be
2. PBR is corrupted to 01 (unlikely since MVN shouldn't touch PBR)
3. The address bus is being set from a different path

### Issue 3: PC Not Advancing to Next Instruction

PC should be at 8078 (MVN_addr + 3) after MVN completes:
- State 0: PC++ -> 8076 (after dest bank)
- State 1: PC++ -> 8077 (after src bank)
- State 4: PC stays (no decrement since A reached $FFFF, CO=0)
- Final PC = 8077... wait, that's still not 8078

Actually, reviewing the MVN microcode flow:
```
State 0: '[PBR:PC]->DBR', 'PC++'     // Read dest bank, PC = MVN+1
State 1: '[PBR:PC]->ABR', 'PC++', 'X->AA', 'X+1->X'  // Read src bank, PC = MVN+2
State 2: '[ABR:AA]->DR', 'Y->AA', 'Y+1->Y'
State 3: 'DR->[DBR:AA]'
State 4: 'ALU(A-1)->A', 'PC-3->PC'   // If CO=1, PC = MVN-1; if CO=0, PC stays
State 5: []  // Empty cycle
```

When MVN completes (CO=0 from A-1 borrow):
- PC should remain at MVN+2 (not decremented)
- But next instruction is at MVN+3!

**This is a potential microcode bug**: MVN may be missing a PC++ when the instruction completes.

## MVN Microcode (mcode.sv lines 769-776)

```
// 54 MVN
{3'b000, 4'b0000, ...}, // State 0: '[PBR:PC]->DBR', 'PC++'
{3'b000, 4'b0000, ...}, // State 1: '[PBR:PC]->ABR', 'PC++', 'X->AA', 'X+1->X'
{3'b000, 4'b0101, ...}, // State 2: '[ABR:AA]->DR', 'Y->AA', 'Y+1->Y'
{3'b000, 4'b0001, ...}, // State 3: 'DR->[DBR:AA]'
{3'b000, 4'b0001, ...}, // State 4: 'ALU(A-1)->A','PC-3->PC'
{3'b010, 4'b0001, ...}, // State 5: [] (STATE_CTRL=010 -> goto state 0)
{3'bXXX, ...},          // State 6: don't care
{3'bXXX, ...},          // State 7: don't care
```

## Key Observations

1. **STATE=6 exists in trace** but MVN only has valid microcode for states 0-5. State 6 has XXX (don't care) values, which could produce unpredictable behavior.

2. **The transition STATE 5 -> 6** contradicts the microcode definition where STATE_CTRL=3'b010 should force NextState=0.

3. **Address bus shows DBR:PC** at the end, but instruction fetch should use PBR:PC (MC.ADDR_BUS=4'b0000).

## Potential Fixes to Investigate

1. **Verify microcode indexing**: Ensure mcode.sv is correctly selecting MVN state 5 microcode with STATE_CTRL=3'b010.

2. **Add PC++ on MVN completion**: When MVN completes, PC needs to advance one more byte to point past the 3-byte instruction.

3. **Check state machine transition**: Investigate why STATE goes from 5 to 6 instead of 5 to 0.

4. **Verify ADDR_BUS selection**: Ensure MC.ADDR_BUS=4'b0000 (PBR:PC) is selected when fetching the next instruction after MVN.

## Files Involved

- `rtl/65C816/P65C816.sv`: CPU state machine, address bus generation (lines 817-959)
- `rtl/65C816/mcode.sv`: MVN microcode definition (lines 769-776)
- `rtl/65C816/AddrGen.sv`: PC handling, LOAD_PC logic (lines 54-80)
- `rtl/iigs.sv`: Memory controller, bank handling

## Test Case

Use Gauntlet disk image with debug tracing enabled:
```bash
./obj_dir/Vemu --disk gauntlet.hdv > gauntlet_trace.txt 2>&1
```

Search for MVN instructions that use cross-bank moves (dest != src):
```bash
grep "mvn \$00, \$01" gauntlet_trace.txt
```
