#ifndef PARALLEL_CLEMENS_H
#define PARALLEL_CLEMENS_H

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the parallel Clemens memory system
int parallel_clemens_init(void);

// Compare memory read operation
// Returns 1 if match, 0 if mismatch (and logs the difference)
int parallel_clemens_compare_read(unsigned int bank, unsigned int addr, unsigned char verilog_data);

// Compare memory write operation  
// Returns 1 if match, 0 if mismatch (and logs the difference)
int parallel_clemens_compare_write(unsigned int bank, unsigned int addr, unsigned char data);

// Sync Clemens state with our CPU registers
void parallel_clemens_sync_cpu_state(unsigned int pc, unsigned int bank, unsigned int sp, unsigned char flags);

// Provide current IIgs memory control state so the shadow mapper can compute
// the expected Clemens/GS semantics per access.
// All params are raw 8-bit values (0/1 for bools) from the Verilog core.
void parallel_clemens_update_hw(unsigned char RDROM,
                                unsigned char LCRAM2,
                                unsigned char LC_WE,
                                unsigned char VPB,
                                unsigned char SHADOW,
                                unsigned char ALTZP,
                                unsigned char INTCXROM,
                                unsigned char PAGE2,
                                unsigned char RAMRD,
                                unsigned char RAMWRT,
                                unsigned char SLTROMSEL,
                                unsigned char STORE80,
                                unsigned char HIRES_MODE);

// Compare a single access against an expected mapping decision.
// - is_write: 0=read, 1=write
// - actual_physical_bank: high byte of Verilog addr_bus
// - actual_is_rom: 1 if rom1/2 selected
// - actual_is_fast: 1 if to fastram (Bank 00/01/etc.)
// - actual_is_slow: 1 if to slowram (Bank E0/E1)
// Returns 1 if mapping aligns with expected, 0 if mismatch (logs details)
int parallel_clemens_compare_access(unsigned int bank,
                                    unsigned int addr,
                                    unsigned char data,
                                    int is_write,
                                    unsigned int actual_physical_bank,
                                    int actual_is_rom,
                                    int actual_is_fast,
                                    int actual_is_slow,
                                    unsigned int pc,
                                    unsigned int pbr);

// Value-level comparison using a shadow memory mirror modeled on GSplus rules.
// For writes: updates the mirror and optionally validates mapping.
// For reads: computes the expected byte from the mirror and compares to verilog_data.
int parallel_clemens_value_compare_write(unsigned int bank, unsigned int addr, unsigned char data);
int parallel_clemens_value_compare_read(unsigned int bank, unsigned int addr, unsigned char verilog_data);

// Track actual hardware write physical bank for diagnostics (e.g., text/page2 shadow mismatches)
void parallel_clemens_track_hw_write(unsigned int logical_bank,
                                     unsigned int addr,
                                     unsigned int actual_physical_bank,
                                     unsigned char data);

// Optional: retrieve last observed HW physical bank for a given logical Bank 00 address
// Returns 1 if available and fills out_bank; 0 if unknown.
int parallel_clemens_get_last_hw_phys_bank00(unsigned int addr, unsigned int* out_bank);

// Cleanup
void parallel_clemens_cleanup(void);

// Recent activity ring buffer to correlate failures
void parallel_clemens_recent_log_write(unsigned int logical_bank,
                                       unsigned int addr,
                                       unsigned int phys_bank,
                                       unsigned char data);
void parallel_clemens_recent_log_read(unsigned int logical_bank,
                                      unsigned int addr,
                                      unsigned int phys_bank,
                                      unsigned char data);
void parallel_clemens_dump_recent_writes(const char* reason);

#ifdef __cplusplus
}
#endif

#endif // PARALLEL_CLEMENS_H
