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


#define bitset(byte,nbit)   ((byte) |=  (1<<(nbit)))
#define bitclear(byte,nbit) ((byte) &= ~(1<<(nbit)))
#define bitflip(byte,nbit)  ((byte) ^=  (1<<(nbit)))
#define bitcheck(byte,nbit) ((byte) &   (1<<(nbit)))


void SimBlockDevice::MountDisk( std::string file, int index) {
	bool was_mounted = disk[index].is_open();
	// Close existing disk if already mounted
	if (was_mounted) {
		printf("BLKDEV: Closing existing disk %d before re-mount\n", index);
		disk[index].close();
	}
	disk[index].open(file.c_str(), std::ios::out | std::ios::in | std::ios::binary | std::ios::ate);
        if (disk[index]) {
           long int new_size = disk[index].tellg();
           disk[index].seekg(0);
           // Store basename for UI display
           std::string basename = file;
           size_t slash = file.find_last_of("/\\");
           if (slash != std::string::npos)
               basename = file.substr(slash + 1);
           disk_name[index] = basename;
           printf("BLKDEV: disk %d inserted (%s) size=%ld bytes\n", index, file.c_str(), new_size);
           if (index == 0) {
               // NIB floppy format check: 232960 = 35 tracks × 6656 bytes/track
               if (new_size == 232960) {
                   printf("BLKDEV: Detected 5.25\" NIB format (35 tracks × 6656 bytes)\n");
               } else {
                   printf("BLKDEV: WARNING - Floppy size %ld doesn't match expected NIB size 232960\n", new_size);
               }
           }
           // MiSTer behavior: single mount pulse with new size, whether fresh or swap
           // For swap, Verilog side handles the rescan via 1-cycle glitch on woz_ctrl_mount
           disk_size[index] = new_size;
           mountQueue[index] = 1;
           header_size[index] = 0;
           if (was_mounted)
               printf("BLKDEV: Disk swap for drive %d (single pulse, size=%ld)\n", index, new_size);
           else
               printf("BLKDEV: Fresh mount for drive %d (size=%ld)\n", index, new_size);
        }else {
		fprintf(stderr,"BLKDEV ERROR: Failed to open: %s\n",file.c_str());
	}

}

void SimBlockDevice::EjectDisk(int index) {
	if (disk[index].is_open()) {
		disk[index].close();
	}
	disk_size[index] = 0;
	mountQueue[index] = 1;  // Triggers mount pulse with size=0, Verilog sees unmount
	disk_name[index].clear();
	printf("BLKDEV: disk %d ejected\n", index);
}

bool SimBlockDevice::IsMounted(int index) {
	return disk[index].is_open();
}


void SimBlockDevice::BeforeEval(int cycles)
{
//
// switch to a new disk if current_disk is -1
// check to see if we need a read or a write or a mount
//

// wait until the computer boots to start mounting, etc
 if (cycles<2000) return;

 for (int i=0; i<kVDNUM;i++)
 {

//fprintf(stderr,"current_disk = %d *sd_rd %x ack_delay %x reading %d writing %d\n",current_disk,*sd_rd,ack_delay,reading,writing);

    if (current_disk == i) {
    // send data
    if (ack_delay==1) {
      if (reading && (*sd_buff_wr==0) &&  (bytecnt<kBLKSZ)) {
         *sd_buff_dout = disk[i].get();
         *sd_buff_addr = bytecnt++;
         *sd_buff_wr= 1;
         //printf("cycles %x reading %X : %X ack %x\n",cycles,*sd_buff_addr,*sd_buff_dout,*sd_ack );
      } else if(writing && *sd_buff_addr != bytecnt && (*sd_buff_addr< kBLKSZ)) {
      //} else if(writing && (bytecnt < kBLKSZ)) {
        if (i == 5 && bytecnt < 8)
            printf("WOZ_SAVE_DMA[%d]: addr=%d bytecnt=%d data=%02X\n", i, *sd_buff_addr, bytecnt, *(sd_buff_din[i]));
        disk[i].put(*(sd_buff_din[i]));
        *sd_buff_addr = bytecnt;
      } else {
	  *sd_buff_wr=0;

	  if (writing) {
		  if (bytecnt>=kBLKSZ) {
			  writing=0;
			  if (i == 4 || i == 5) {
			      printf("WOZ_DMA[%d]: Block write complete (bytecnt=%d)\n", i, bytecnt);
			      disk[i].flush();  // Ensure data reaches disk (survives kill)
			  }
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
    } else {
	  *sd_buff_wr=0;
    } 
    }

    // issue a mount if we aren't doing anything, and the img_mounted has no bits set
    if (!reading && !writing && mountQueue[i] && !*img_mounted) {
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
    } else if (ack_delay==1 && bitcheck(*img_mounted,i)) {
           // Clear mount flag after ack_delay expires - allows next queued mount to proceed
           // Verilog side latches state on rising edge (WOZ) or level (HDD), so pulse is sufficient
           printf("BLKDEV: Mount flag cleared for drive %d\n", i);
        bitclear(*img_mounted,i) ;
    } else { if (!reading && !writing && ack_delay>0) ack_delay--; }

    // start reading when sd_rd pulses high
    if ((current_disk==-1 || current_disk==i) && (bitcheck(*sd_rd,i) || bitcheck(*sd_wr,i) )) {
       // set current disk here..
       current_disk=i;
      if (!ack_delay) {
        int lba = *(sd_lba[i]);
        if (bitcheck(*sd_rd,i)) {
        	reading = true;
	}
        if (bitcheck(*sd_wr,i)) {
        	writing = true;
	}

        disk[i].clear();
        if (writing) {
            disk[i].seekp((lba) * kBLKSZ + header_size[i]);
        } else {
            disk[i].seekg((lba) * kBLKSZ + header_size[i]);
        }
        // Debug output for floppy (index 0) - show track calculation
        if (i == 0) {
            int track = lba / 13;  // 13 sectors per track
            int sector = lba % 13;
            printf("FLOPPY DMA: LBA=%d (track=%d sector=%d) seek=%06X reading=%d writing=%d\n",
                   lba, track, sector, (lba) * kBLKSZ + header_size[i], reading, writing);
        }
        if (i == 4 || i == 5) {
            printf("WOZ_DMA[%d]: LBA=%d seek=0x%06lX %s\n",
                   i, lba, (long)((lba) * kBLKSZ + header_size[i]),
                   writing ? "WRITE" : "READ");
        }
        bytecnt = 0;
        *sd_buff_addr = 0;
        // WOZ drives (index 4=5.25", index 5=3.5") use minimal ack_delay for instant track loading
        // This simulates having all track data pre-cached in memory
        // Using 2 cycles minimum to allow the protocol handshake to work
        ack_delay = (i == 4 || i == 5) ? 2 : 1200;
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
        }
        sd_buff_wr=NULL;
        img_mounted=NULL;
        img_readonly=NULL;
        img_size=NULL;
}

SimBlockDevice::~SimBlockDevice() {

}
