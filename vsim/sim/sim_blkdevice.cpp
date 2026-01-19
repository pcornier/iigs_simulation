#include <iostream>
#include <queue>
#include <string>

#include "sim_blkdevice.h"
#include "sim_console.h"
#include "verilated.h"

#ifndef _MSC_VER
#else
#define WIN32
#endif


static DebugConsole console;

IData* sd_lba[kVDNUM]= {NULL,NULL,NULL,NULL,NULL,
                   NULL,NULL,NULL,NULL,NULL};
SData* sd_rd=NULL;
SData* sd_wr=NULL;
SData* sd_ack=NULL;
SData* sd_buff_addr=NULL;
CData* sd_buff_dout=NULL;
CData* sd_buff_din[kVDNUM]= {NULL,NULL,NULL,NULL,NULL,
                   NULL,NULL,NULL,NULL,NULL};
CData* sd_buff_wr=NULL;
SData* img_mounted=NULL;
CData* img_readonly=NULL;
QData* img_size=NULL;

CData* woz3_track=NULL;


#define bitset(byte,nbit)   ((byte) |=  (1<<(nbit)))
#define bitclear(byte,nbit) ((byte) &= ~(1<<(nbit)))
#define bitflip(byte,nbit)  ((byte) ^=  (1<<(nbit)))
#define bitcheck(byte,nbit) ((byte) &   (1<<(nbit)))


void SimBlockDevice::MountDisk( std::string file, int index) {
	disk[index].open(file.c_str(), std::ios::out | std::ios::in | std::ios::binary | std::ios::ate);
        if (disk[index]) {
           // we shouldn't do the actual mount here..
           disk_size[index]= disk[index].tellg();
           disk[index].seekg(0);
           mountQueue[index]=1;
           printf("BLKDEV: disk %d inserted (%s) size=%ld bytes\n", index, file.c_str(), disk_size[index]);
           if (index == 0) {
               // NIB floppy format check: 232960 = 35 tracks × 6656 bytes/track
               if (disk_size[index] == 232960) {
                   printf("BLKDEV: Detected 5.25\" NIB format (35 tracks × 6656 bytes)\n");
               } else {
                   printf("BLKDEV: WARNING - Floppy size %ld doesn't match expected NIB size 232960\n", disk_size[index]);
               }
           }
        }else {
		fprintf(stderr,"BLKDEV ERROR: Failed to open: %s\n",file.c_str());
	}

}


void SimBlockDevice::BeforeEval(int cycles)
{
//
// switch to a new disk if current_disk is -1
// check to see if we need a read or a write or a mount
//

// wait until the computer boots to start mounting, etc
 if (cycles<2000) return;

 // Set WOZ disk ready signals based on mount status
 if (woz3_ready) {
     *woz3_ready = woz_mounted[0] ? 1 : 0;  // 3.5" drive 1
     static int woz3_ready_debug = 0;
     if (woz3_ready_debug < 5 && woz_mounted[0]) {
         printf("WOZ3_READY: Setting woz3_ready=%d (woz_mounted[0]=%d cycles=%d)\n",
                *woz3_ready, woz_mounted[0], cycles);
         woz3_ready_debug++;
     }
 }
 if (woz1_ready) *woz1_ready = woz_mounted[2] ? 1 : 0;  // 5.25" drive 1

 // Provide WOZ bit data directly to IWM
 // 3.5" drive 1 (woz_index 0)
 static int woz3_debug_count = 0;
 static int woz3_last_track = -1;
 static int woz3_last_addr = -1;
 static int woz3_periodic_debug = 0;


 if (woz3_track && woz3_bit_addr && woz3_bit_data && woz3_bit_count) {
     if (woz_mounted[0]) {
         int track = *woz3_track;
         // Periodic debug: print track value every 500k cycles to catch if it ever changes
         if (woz3_periodic_debug < 1000 && (cycles % 500000) < 5000) {
             printf("WOZ3_TRACK_DEBUG: INLOOP cycles=%d woz3_track=%d (raw signal value) bit_addr=%d\n",
                    cycles, track, *woz3_bit_addr);
             woz3_periodic_debug++;
         }
         int byte_addr = *woz3_bit_addr;
         const WOZTrack* woz_track = GetWOZTrack(0, track);
         if (woz_track && woz_track->initialized) {
             *woz3_bit_count = woz_track->bit_count;
             if (byte_addr < (int)woz_track->bits.size()) {
                 *woz3_bit_data = woz_track->bits[byte_addr];
             } else {
                 *woz3_bit_data = 0xFF;  // Out of range padding
             }
             // Debug: log first few data accesses and when track/addr changes
             if (track != woz3_last_track) {
                 // 3.5" IIgs WOZ convention: track is cylinder*2 + side (side is bit0).
                 printf("WOZ3 DATA: Track %d loaded (bit_count=%u, side=%d, physical_track=%d)\n",
                        track, woz_track->bit_count, track & 1, track >> 1);
                 printf("WOZ3 DATA: First 32 bytes: ");
                 for (int i = 0; i < 32 && i < (int)woz_track->bits.size(); i++) {
                     printf("%02X ", woz_track->bits[i]);
                 }
                 printf("\n");
                 // Extra debugging for side 1 tracks (side bit set)
                 if (track & 1) {
                     printf("WOZ3 SIDE1: Track %d (side1/track%d) - detailed dump:\n", track, track >> 1);
                     printf("WOZ3 SIDE1: bits.size()=%zu bit_count=%u initialized=%d\n",
                            woz_track->bits.size(), woz_track->bit_count, woz_track->initialized ? 1 : 0);
                     // Show first 64 bytes in hex dump format
                     printf("WOZ3 SIDE1: First 64 bytes:\n");
                     for (int row = 0; row < 4; row++) {
                         printf("WOZ3 SIDE1: %04X: ", row * 16);
                         for (int col = 0; col < 16; col++) {
                             int idx = row * 16 + col;
                             if (idx < (int)woz_track->bits.size()) {
                                 printf("%02X ", woz_track->bits[idx]);
                             } else {
                                 printf("-- ");
                             }
                         }
                         printf("\n");
                     }
                 }
                 woz3_last_track = track;
                 woz3_last_addr = byte_addr;
                 woz3_debug_count = 0;  // Reset counter on track change
             } else if (woz3_debug_count < 30) {
                 if (byte_addr != woz3_last_addr) {
                     printf("WOZ3 DATA: track=%d addr=%d data=0x%02X bit_count=%u (access #%d)\n",
                            track, byte_addr, *woz3_bit_data, woz_track->bit_count, woz3_debug_count);
                     woz3_debug_count++;
                     woz3_last_addr = byte_addr;
                 }
             }
         } else {
             *woz3_bit_data = 0xFF;
             *woz3_bit_count = 0;
         }
     } else {
         *woz3_bit_data = 0xFF;
         *woz3_bit_count = 0;
     }
 }

 // 5.25" drive 1 (woz_index 2)
 if (woz1_track && woz1_bit_addr && woz1_bit_data && woz1_bit_count) {
     if (woz_mounted[2]) {  // woz_index 2 is 5.25" drive 1
         int track = *woz1_track;
         int byte_addr = *woz1_bit_addr;
         const WOZTrack* woz_track = GetWOZTrack(2, track);
         if (woz_track && woz_track->initialized) {
             *woz1_bit_count = woz_track->bit_count;
             if (byte_addr < (int)woz_track->bits.size()) {
                 *woz1_bit_data = woz_track->bits[byte_addr];
             } else {
                 *woz1_bit_data = 0xFF;  // Out of range padding
             }
         } else {
             *woz1_bit_data = 0xFF;
             *woz1_bit_count = 0;
         }
     } else {
         *woz1_bit_data = 0xFF;
         *woz1_bit_count = 0;
     }
 }

 for (int i=0; i<kVDNUM;i++)
 {

//fprintf(stderr,"current_disk = %d *sd_rd %x ack_delay %x reading %d writing %d\n",current_disk,*sd_rd,ack_delay,reading,writing);

    if (current_disk == i) {
    // send data
    if (ack_delay==1) {
      // Check if this is a WOZ drive (indices 4-7)
      bool is_woz_drive = (i >= WOZ_DRIVE_35_1 && i <= WOZ_DRIVE_525_2);
      int woz_index = i - WOZ_DRIVE_35_1;

      if (is_woz_drive && woz_mounted[woz_index]) {
        // WOZ drive: use HandleWOZRequest to provide data
        if (reading && (*sd_buff_wr==0) && (bytecnt<kBLKSZ)) {
          *sd_buff_addr = bytecnt;
          HandleWOZRequest(woz_index, cycles);
          bytecnt++;
          if (bytecnt <= 8) {
            printf("WOZ DMA: addr=%03X data=%02X\n", *sd_buff_addr, *sd_buff_dout);
          }
        } else {
          *sd_buff_wr = 0;
          if (reading && bytecnt == kBLKSZ) {
            reading = 0;
          }
        }
      } else {
        // Regular file-based drive
        if (reading && (*sd_buff_wr==0) &&  (bytecnt<kBLKSZ)) {
           *sd_buff_dout = disk[i].get();
           *sd_buff_addr = bytecnt++;
           *sd_buff_wr= 1;
           // printf("cycles %x reading %X : %X ack %x\n",cycles,*sd_buff_addr,*sd_buff_dout,*sd_ack );
        } else if(writing && *sd_buff_addr != bytecnt && (*sd_buff_addr< kBLKSZ)) {
          disk[i].put(*(sd_buff_din[i]));
          *sd_buff_addr = bytecnt;
        } else {
	  *sd_buff_wr=0;

	  if (writing) {
		  if (bytecnt>=kBLKSZ) {
			  writing=0;
		  }
		  if (bytecnt<kBLKSZ)
		  	bytecnt++;
	  }
	  else if (reading) {
        	if(bytecnt == kBLKSZ) {
         	 	reading = 0;
        	}
          }
        }
      }
    } else {
	  *sd_buff_wr=0;
    }
    }

    // issue a mount if we aren't doing anything, and the img_mounted has no bits set
    // BUG FIX: Don't wait for !*img_mounted (all drives unmounted) because HDD keeps
    // its mount bit set. Instead, check if THIS drive is unmounted and controller is idle.
    if (!reading && !writing && mountQueue[i] && !ack_delay && !bitcheck(*img_mounted, i)) {
            const size_t extrabytes = disk_size[i] % kBLKSZ;
            if (disk_size[i] >= (kBLKSZ + 64) && extrabytes == 64) {
                    char hdr[4];
                    disk[i].seekg(0);
                    disk[i].read(hdr, 4);
                    if (!memcmp(hdr, "2IMG", 4)) {
                            fprintf(stderr, "Detected \"2IMG\" signature; adjusting sizes\n");
                            header_size[i] = 64;
                            disk_size[i] -= header_size[i];
                    }
            }
           printf("BLKDEV: Mounting drive %d, img_size=%ld, header_offset=%ld\n", i, disk_size[i], header_size[i]);
           if (i == 0) {
               printf("FLOPPY: Mount signal sent - setting img_mounted[0], expecting floppy_track to detect mount\n");
           }
           mountQueue[i]=0;
           *img_size = disk_size[i];
	   *img_readonly=0;
           disk[i].seekg(header_size[i]);
           bitset(*img_mounted,i);
           ack_delay=1200;
    } else if (ack_delay==1 && bitcheck(*img_mounted,i) && i == 0) {
           // Only clear mount flag for floppy (index 0) - floppy uses mount pulse protocol
           // HDD (index 1) should keep mount flag set permanently
           printf("BLKDEV: Mount flag cleared for floppy drive %d\n", i);
        bitclear(*img_mounted,i) ;
        //*img_size = 0;
    } else { if (!reading && !writing && ack_delay>0) ack_delay--; }

    // start reading when sd_rd pulses high
    if ((current_disk==-1 || current_disk==i) && (bitcheck(*sd_rd,i) || bitcheck(*sd_wr,i) )) {
       // set current disk here..
       current_disk=i;
      // If sd_lba changed while a transfer is in progress, cancel the old transfer
      // This prevents the Verilog from receiving data for the wrong LBA
      if (ack_delay > 0 && reading) {
          int lba = *(sd_lba[i]);
          if (lba != current_lba[i]) {
              printf("WOZ_RAW CANCEL: LBA changed from %d to %d during transfer (ack_delay=%d), canceling\n",
                     current_lba[i], lba, ack_delay);
              ack_delay = 0;
              reading = false;
              bitclear(*sd_ack,i);  // Make sure sd_ack is low
          }
      }
      if (!ack_delay) {
        int lba = *(sd_lba[i]);
        current_lba[i] = lba;  // Track which LBA this transfer is for
        // Debug: show when read starts (only for WOZ raw index 5)
        if (i == 5) {
            printf("WOZ_RAW START: ack_delay=0, starting read for lba=%d\n", lba);
        }
        if (bitcheck(*sd_rd,i)) {
        	reading = true;
	}
        if (bitcheck(*sd_wr,i)) {
        	writing = true;
	}

        // Check if this is a WOZ drive (indices 4-7) AND has WOZ data mounted
        bool is_woz_drive = (i >= WOZ_DRIVE_35_1 && i <= WOZ_DRIVE_525_2);
        int woz_index = i - WOZ_DRIVE_35_1;
        bool is_woz_mounted = is_woz_drive && woz_mounted[woz_index];

        if (is_woz_mounted) {
            // WOZ drive: no file seek needed, data is in memory
            int track = (lba >> 5) & 0xFF;
            int block = lba & 0x1F;
            printf("WOZ DMA: LBA=%d (track=%d block=%d) reading=%d\n",
                   lba, track, block, reading);
        } else {
            // Regular file-based drive
            disk[i].clear();
            disk[i].seekg((lba) * kBLKSZ + header_size[i]);
            // Debug output for floppy (index 0) - show track calculation
            if (i == 0) {
                int track = lba / 13;  // 13 sectors per track
                int sector = lba % 13;
                printf("FLOPPY DMA: LBA=%d (track=%d sector=%d) seek=%06X reading=%d writing=%d\n",
                       lba, track, sector, (lba) * kBLKSZ + header_size[i], reading, writing);
            }
            // Debug for WOZ raw file reads (index 5)
            if (i == 5) {
                long seek_pos = (lba) * kBLKSZ + header_size[i];
                printf("WOZ_RAW DMA: index=%d LBA=%d seek=%06lX header_size=%ld reading=%d\n",
                       i, lba, seek_pos, header_size[i], reading);
                // Also print first 8 bytes at seek position
                disk[i].seekg(seek_pos);
                printf("WOZ_RAW DATA: ");
                for (int j = 0; j < 8; j++) {
                    printf("%02X ", (unsigned char)disk[i].get());
                }
                printf("\n");
                disk[i].seekg(seek_pos);  // Seek back for actual read
            }
        }
        bytecnt = 0;
        *sd_buff_addr = 0;
        ack_delay = 1200;
      }
    }

    if (current_disk == i) {
      if (ack_delay==1) {
           bitset(*sd_ack,i);
	   //printf("setting sd_ack: %x\n",*sd_ack);
      } else {
           bitclear(*sd_ack,i);
	   //printf("clearing sd_ack: %x\n",*sd_ack);
      }
      if((ack_delay > 1) || ((ack_delay == 1) && !reading && !writing))
        ack_delay--;
      if (ack_delay==0 && !reading && !writing) 
	current_disk=-1;
    }
  }
}

void SimBlockDevice::AfterEval()
{
}


SimBlockDevice::SimBlockDevice(DebugConsole c) {
	console = c;
        current_disk=-1;

        sd_rd = NULL;
        sd_wr = NULL;
        sd_ack = NULL;
        sd_buff_addr = NULL;
        sd_buff_dout = NULL;
	for (int i=0;i<kVDNUM;i++) {
           sd_lba[i] = NULL;
	   sd_buff_din[i] = NULL;
           mountQueue[i]=0;
           current_lba[i] = -1;  // Initialize to invalid LBA
        }
        sd_buff_wr=NULL;
        img_mounted=NULL;
        img_readonly=NULL;
        img_size=NULL;

	// Initialize WOZ state
	for (int i = 0; i < 4; i++) {
		woz_mounted[i] = false;
		woz_current_track[i] = -1;
		woz_block_offset[i] = 0;
	}

	// Initialize WOZ bit interface pointers
	woz3_track = NULL;
	woz3_bit_addr = NULL;
	woz3_bit_data = NULL;
	woz3_bit_count = NULL;
	woz1_track = NULL;
	woz1_bit_addr = NULL;
	woz1_bit_data = NULL;
	woz1_bit_count = NULL;
	woz3_ready = NULL;
	woz1_ready = NULL;
}

bool SimBlockDevice::MountWOZ(const std::string& file, int woz_index) {
	if (woz_index < 0 || woz_index >= 4) {
		fprintf(stderr, "WOZ: Invalid woz_index %d (must be 0-3)\n", woz_index);
		return false;
	}

	int err = woz_load(file.c_str(), &woz_disk[woz_index]);
	if (err != WOZ_OK) {
		fprintf(stderr, "WOZ: Failed to load %s (error %d)\n", file.c_str(), err);
		return false;
	}

	woz_mounted[woz_index] = true;
	woz_current_track[woz_index] = -1;
	woz_block_offset[woz_index] = 0;

	// NOTE: The C++ WOZ path provides bit data directly to the IWM via
	// woz3_bit_data/woz3_bit_count pointers. It does NOT use the SD block
	// interface (indices 4-7). Do NOT set mountQueue here - that would
	// trigger floppy35_track_1 which conflicts with woz_floppy_controller.
	// The Verilog woz_floppy_controller uses a separate raw file mount at
	// index 5 (via MountDisk in sim_main.cpp).

	printf("WOZ: Mounted %s as WOZ drive %d (C++ bit-level path)\n",
	       file.c_str(), woz_index);
	printf("WOZ: Disk type: %s, bit timing: %d ns, tracks: %d\n",
	       woz_disk[woz_index].disk_type == WOZ_DISK_TYPE_525 ? "5.25\"" : "3.5\"",
	       woz_disk[woz_index].bit_timing_ns,
	       woz_disk[woz_index].track_count);

	return true;
}

const WOZTrack* SimBlockDevice::GetWOZTrack(int woz_index, int track) {
	if (woz_index < 0 || woz_index >= 4) return nullptr;
	if (!woz_mounted[woz_index]) return nullptr;
	return woz_get_track(&woz_disk[woz_index], track);
}

const WOZDisk* SimBlockDevice::GetWOZDisk(int woz_index) const {
	if (woz_index < 0 || woz_index >= 4) return nullptr;
	if (!woz_mounted[woz_index]) return nullptr;
	return &woz_disk[woz_index];
}

void SimBlockDevice::HandleWOZRequest(int woz_index, int cycles) {
	// This handles SD block requests for WOZ drives
	// Protocol:
	//   sd_lba[sd_index] = LBA where LBA encodes track and block
	//   LBA format: bits [12:5] = track number (0-159), bits [4:0] = block within track
	//   Response blocks:
	//     Block 0, bytes 0-3: track bit_count (32-bit LE)
	//     Block 0, bytes 4-7: track byte_count (32-bit LE)
	//     Block 0, bytes 8-511: first 504 bytes of track bits
	//     Block N (N>0): next 512 bytes of track bits

	int sd_index = WOZ_DRIVE_35_1 + woz_index;
	if (!woz_mounted[woz_index]) return;
	if (!sd_lba[sd_index]) return;

	// Decode LBA to get track and block number
	uint32_t lba = *(sd_lba[sd_index]);
	int track = (lba >> 5) & 0xFF;  // Track in bits [12:5]
	int block = lba & 0x1F;         // Block in bits [4:0]

	const WOZTrack* woz_track = GetWOZTrack(woz_index, track);
	if (!woz_track || !woz_track->initialized) {
		// Track doesn't exist - provide empty data
		*sd_buff_dout = 0xFF;
		*sd_buff_wr = 1;
		return;
	}

	// Track has changed, log it
	if (track != woz_current_track[woz_index]) {
		woz_current_track[woz_index] = track;
		printf("WOZ: Loading track %d (bit_count=%u, byte_count=%u)\n",
		       track, woz_track->bit_count, woz_track->byte_count);
	}

	// Calculate byte offset into track data
	// Block 0: bytes 0-7 are metadata, 8-511 are track data
	// Block N>0: bytes are track data
	int buf_addr = *sd_buff_addr;
	int data_offset;

	if (block == 0) {
		// Block 0: metadata + first 504 bytes
		if (buf_addr < 4) {
			// Bytes 0-3: bit_count (32-bit LE)
			*sd_buff_dout = (woz_track->bit_count >> (buf_addr * 8)) & 0xFF;
		} else if (buf_addr < 8) {
			// Bytes 4-7: byte_count (32-bit LE)
			*sd_buff_dout = (woz_track->byte_count >> ((buf_addr - 4) * 8)) & 0xFF;
		} else {
			// Bytes 8-511: first 504 bytes of track data
			data_offset = buf_addr - 8;
			if (data_offset < (int)woz_track->bits.size()) {
				*sd_buff_dout = woz_track->bits[data_offset];
			} else {
				*sd_buff_dout = 0xFF;  // Padding
			}
		}
	} else {
		// Block N>0: next 512 bytes
		data_offset = 504 + (block - 1) * 512 + buf_addr;
		if (data_offset < (int)woz_track->bits.size()) {
			*sd_buff_dout = woz_track->bits[data_offset];
		} else {
			*sd_buff_dout = 0xFF;  // Padding
		}
	}
	*sd_buff_wr = 1;
}

SimBlockDevice::~SimBlockDevice() {

}
