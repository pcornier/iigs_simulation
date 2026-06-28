# (b) Burst + line-buffer design for `rtl/sdram.sv`

Goal: let the 65C816 run faster than 2.8 MHz out of fast RAM (banks 00-7F) by amortizing
the SDRAM ACTIVATE+CAS over a multi-word burst and serving most CPU fetches from a small
local line buffer, *without* replacing the controller's existing toggle req/ack shell (the
clock-domain crossing that already works — see `rtl/sdram.sv:46-48`).

Status: DESIGN + **MEASURED PROTOTYPE**. A standalone burst-read controller
(`doc/sdram_accel/sdram_burst.sv`) implements the §0 address remap + burst-8 read and is
verified against the chip model in `vsim/sdram_tb/tb_burst.sv`. The line-buffer/cache
(`sdram_cache.sv`) and the integration into the production `rtl/sdram.sv` are still design only.

### Measured result (cycles/word, sequential reads, chip model timing)
| controller | cycles/word | notes |
|---|---|---|
| single-word (production `rtl/sdram.sv`) | **9.00** | one ACTIVATE+CAS+precharge per word (its 9-state round) |
| burst-8 prototype (`sdram_burst.sv`)    | **2.37** | ~19 cycles per 8-word line; **3.8× faster** |

Both pass full read-back integrity with zero timing-assertion failures. At 114.5 MHz that is
~78.6 ns/word → ~20.7 ns/word. A 14.3 MHz CPU cycle is 70 ns, so single-word (78.6 ns) cannot
sustain 14 MHz but a burst line-fill (amortized ~21 ns/word, 7 of 8 words served from the line
buffer) comfortably can — confirming this doc's premise. Reproduce:
`cd vsim/sdram_tb && ./build_burst.sh && ./obj_dir/Vtb_burst` (and `./build.sh && ./obj_dir/Vtb_sdram` for the baseline).

---

## 0. Why bursting needs an address remap FIRST (blocker)

Current address mapping in `rtl/sdram.sv`:
```
{ba,a} <= addr0;                              // ba = addr[24:23], a = addr[22:1]
STATE_START: SDRAM_A <= a[13:1];              // ROW    = a[13:1]   (low 13 addr bits)
STATE_CONT:  SDRAM_A <= {dqm, 2'b10, a[22:14]};// COLUMN = a[22:14] (high 9 addr bits), A10=1 auto-precharge
```
So incrementing the word address steps the **row**, and a hardware column burst steps
`a[22:14]` — i.e. by 8192 words. A burst here would return garbage-ordered, non-adjacent
words. **Sequential CPU fetch must map to sequential columns in one row.**

Required remap (low bits → column, then bank, then row — pick to taste; column must be the
low bits so a burst walks consecutive words):
```
// proposed: a = addr[22:1]
//   column = a[9:1]    (9 low bits  -> 512-word page; burst walks these)
//   bank   = a[11:10]  (2 bits)     (chip BA)  -- optional placement
//   row    = a[24:12]  (13 bits)
STATE_START: SDRAM_A <= a_row;                 // row = a[24:12] mapped to 13 bits
STATE_CONT:  SDRAM_A <= {dqm, autopre, 1'b0, a_col}; // a_col = a[9:1], 9 bits
```
With the column in the low bits, an 8-word read burst returns the 8 consecutive words of the
aligned line `addr & ~7`. Keep `SDRAM_BA` driven from the bank field as today
(`sdram.sv:218`). This remap is invisible to the rest of the system (it's just how a flat
24-bit address is shredded onto RAS/CAS/BA) **as long as it is a pure bijection** — verify no
address collisions across the 24-bit space.

---

## 1. Architecture: two pieces

```
        clk_sys (28.6 MHz) domain                    114.5 MHz domain
  +-------------------------------------+      +---------------------------+
  | CPU read addr ->  sdram_cache       |      |  rtl/sdram.sv (modified)  |
  |   - N lines x 8 words (regs)        |      |   - ch1 = BURST-8 read    |
  |   - hit  -> mux word, 0 SDRAM ops   |<====>|   - returns 128-bit line  |
  |   - miss -> toggle req1, await ack  | req1 |   - ch0 write unchanged   |
  |   - snoop ch0 writes -> update line | /ack1|   - ch2 upload unchanged  |
  +-------------------------------------+      +---------------------------+
```

1. **Controller change (114.5 MHz):** ch1 becomes a burst-8 read. One ACTIVATE + one
   READ(burst=8, auto-precharge) yields the 8 words of one aligned line; accumulate them into
   a 128-bit register and present on a widened `dout1` when `ack1` toggles. ch0 (writes) and
   ch2 (ROM upload) are untouched and still single-word.
2. **New `sdram_cache` (clk_sys):** a tiny line buffer in front of ch1. CPU reads hit the
   buffer (served next cycle, no SDRAM transaction, no CDC round trip) or miss (one burst
   fill). This is where the speed comes from: sequential code mostly hits.

Putting the buffer in `clk_sys` (not in the controller) is deliberate — a hit must NOT pay
the req/ack CDC latency, which is the very thing that makes 7 MHz tight today.

---

## 2. Controller changes (sketch, against `rtl/sdram.sv`)

### 2a. Mode register: enable burst-8 reads, keep single writes
```verilog
localparam BURST_LENGTH   = 3'd3;   // was 3'd0(=1). 3 => 8 words
localparam BURST_CODE     = 3'b011; // BL=8 sequential
// MODE keeps NO_WRITE_BURST=1 (A9): writes stay single-location
localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_CODE };
```

### 2b. State machine: stream 8 words on a ch1 read
`state` is currently `[3:0]` (0..15). A burst-8 read needs: ACTIVATE(1) + tRCD(3) + READ(1) +
CAS(3) + 8 data beats + tRP. That exceeds 16 states — **widen `state` to `[4:0]`** and bump
the localparams:
```verilog
reg [4:0] state;
localparam [4:0] STATE_IDLE  = 5'd0;
localparam [4:0] STATE_START = 5'd1;                       // ACTIVATE
localparam [4:0] STATE_CONT  = STATE_START + RASCAS_DELAY; // 4: READ/WRITE
// first read word lands CAS_LATENCY+1 after READ; burst occupies 8 beats
localparam [4:0] STATE_DAT0  = STATE_CONT + CAS_LATENCY + 5'd1; // 8
localparam [4:0] STATE_DATL  = STATE_DAT0 + 5'd7;              // 15: last burst word
localparam [4:0] STATE_LAST  = STATE_DATL + 5'd2;             // +tRP guard (>= tRC)
```
Accumulate the burst into a 128-bit line register (reads only; writes use the existing
single-word path at STATE_CONT):
```verilog
reg [127:0] line;
// during data beats (read), capture each 16-bit word:
if (!we && ram_req[1] && state >= STATE_DAT0 && state <= STATE_DATL)
    line[ {state - STATE_DAT0, 4'b0} +: 16 ] <= SDRAM_DQ;
// at end of burst, publish and ack:
if (state == STATE_DATL && ram_req[1]) begin
    dout1_line <= line;        // widened output (see 2c)
    active <= 0; ram_req <= 0;
    ack1   <= req1;
end
```
Only ch1 gets the burst path. Keep ch0/ch2 on the existing 9-state single-word round (they
can share the widened `state`; their STATE_READY stays at old position 8 and jumps to
STATE_IDLE). Drive A10 (auto-precharge) = 1 on the burst READ so the row closes automatically
after 8 beats; that preserves the "no open-row needed" simplicity. (Open-row is a later,
optional enhancement — see §5.)

### 2c. Widen ch1 read return
```verilog
// replace: output [15:0] dout1;
output [127:0] dout1;     // one aligned 8-word line
assign dout1 = dout1_line;
// ch0/ch2 keep narrow dout (writes/upload don't read).
```
128 bits is stable when `ack1` toggles, so the existing toggle handshake carries it across to
`clk_sys` safely — no extra synchronizer needed (data is guaranteed settled before the ack
edge the consumer waits on).

Refresh logic (`sdram.sv:110-164`) is unchanged; bursts are longer so confirm the 850-cycle
refresh interval still never starves (it won't — request density stays < 1 line per CPU cycle
even at 14 MHz).

---

## 3. New module: `sdram_cache` (clk_sys domain)

See `doc/sdram_accel/sdram_cache.sv` for the full sketch. Summary:

- **Geometry:** direct-mapped, `LINES` (start with 4) × 8 words × 16-bit. Line = `addr[24:4]`
  (word-addressed; 8 words = 16 bytes = 4 addr bits below the line). Tag/index split tunable.
- **Read hit:** `valid[idx] && tag[idx]==addr_tag` → return `data[idx][word]` next cycle. No
  req1 toggle. This is the fast path the accelerator depends on.
- **Read miss:** toggle `req1` with the *line* base address; wait for `ack1`; latch the
  128-bit `dout1` into the line, set tag/valid; serve the requested word. One CDC round trip
  per 8 words.
- **Write snoop (coherency):** CPU writes still go out on **ch0 unchanged** (write-through to
  SDRAM). In the same `clk_sys` block, if the write address hits a valid cached line, update
  that word in the line buffer (or invalidate the line). Because video scans out of BRAM
  (E0/E1), **SDRAM has exactly one other writer — the CPU itself (ch0) and ROM upload (ch2,
  load-time only)** — so a local snoop is sufficient; there is no video/DMA coherency problem.
- **Bypass:** only fast-RAM reads (`fastram_ce`) and ROM reads (`rom_ce`) go through the
  cache. Everything the `clock_divider` marks `slowMem` (E0/E1, I/O, shadowed) bypasses it and
  uses the existing slow/sync path untouched.

---

## 4. Integration points (in `Apple-IIgs.sv` / `rtl/iigs.sv`)

Current read launch (`Apple-IIgs.sv:356-377`) toggles `rd_req` one clk_sys after `phi2_d`.
Replace the direct `rd_req` path for `fastram_ce|rom_ce` reads with the cache:

1. Instantiate `sdram_cache` between the CPU read interface and ch1 of `sdram`.
   - cache `cpu_addr` = `cpu_sdram_addr`; `cpu_rd` = `phi2_d & ~we & (fastram_ce|rom_ce)`.
   - cache `mem_req/mem_ack/mem_addr/mem_line` ↔ `req1/ack1/addr1/dout1` of `sdram`.
   - cache `cpu_data` → feed `sdram_dout` mux (replaces `Apple-IIgs.sv:374`).
   - cache write-snoop inputs = the ch0 write signals (`wr_addr`,`wr_din`,`wr_req` edge).
2. `clock_divider` interaction: a cache **hit** can complete in the fast 5-tick (or fewer)
   cycle with no stall. A cache **miss** must hold the CPU until the line returns. Use the
   already-wired `RDY_IN` (`rtl/iigs.sv:2058-2075`, gate at `P65C816.sv:117`): drive
   `RDY_IN=0` while `cpu_rd & ~hit & ~fill_done`. This is the missing "stall on miss"
   mechanism noted in the original analysis. Today there is none — the 5-tick cycle just
   assumes data arrives; with a real cache + faster clock you MUST stall on miss.
3. Faster clock steps live in `clock_divider.v` (§ separate accelerator work): add 2-tick
   (7.16 MHz) and 1-tick (14.3 MHz) fast modes; a hit serves within them, a miss stalls via
   `RDY_IN`. Hook the speed select to either CYAREG (turbo) or ZipGS $C059-$C05F (see
   `HANDOFF_sdram_accelerator.md` §4 and KEGS `software_emulators/kegs/src/moremem.c`).

---

## 5. Optional later: open-row / page mode

Burst-8 + line buffer already captures spatial locality within a line. Open-row helps when
consecutive *lines* land in the same row (skip ACTIVATE+tRCD on a row hit). To add later:
- Drop auto-precharge (A10=0) on the burst READ; track `open_row[bank]` and `row_valid`.
- On a new ch1 request: if `bank,row == open` → go straight to READ (save ACTIVATE+tRCD ≈ 4
  cycles); else PRECHARGE old row, ACTIVATE new.
- Must precharge before refresh and on a long idle. None of the four reference MiSTer cores
  (NeoGeo/Saturn/PSX/N64) implement this — it is net-new but mechanical.

---

## 6. Risk / validation checklist
- [ ] Address remap is a verified bijection over the used 24-bit space (no aliasing).
- [ ] `state` width bump ([4:0]) doesn't break ch0/ch2 single-word timing or init FSM
      (`sdram.sv:176-205` uses STATE_LAST — re-derive it).
- [ ] tRC/tRP still satisfied with the longer burst round at 114.5 MHz.
- [ ] Refresh never starves with burst-length requests (recompute density).
- [ ] Cache coherency: ch0 write snoop updates/invalidates correctly; ROM upload (ch2)
      either runs before caching is enabled or flushes the cache.
- [ ] `RDY_IN` stall-on-miss verified at each new clock step (7.16, 14.3 MHz).
- [ ] Self-modifying code / bank-switch edge cases (Apple II software does this) — snoop must
      catch writes to currently-cached lines including aux/main and language-card mappings.
- [ ] Validate ALL of the above in the cycle-accurate sim (doc 02) before HW.
```
