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
         printf("cycles %x reading %X : %X ack %x\n",cycles,*sd_buff_addr,*sd_buff_dout,*sd_ack );
      } else if(writing && *sd_buff_addr != bytecnt && (*sd_buff_addr< kBLKSZ)) {
      //} else if(writing && (bytecnt < kBLKSZ)) {
  	//printf("writing disk %i at sd_buff_addr %x data %x ack %x\n",i,*sd_buff_addr,*sd_buff_din[i],*sd_ack);
        disk[i].put(*(sd_buff_din[i]));
        *sd_buff_addr = bytecnt;
      } else {
	  *sd_buff_wr=0;

	  if (writing) {
		  if (bytecnt>=kBLKSZ) {
			  writing=0;
			  //printf("writing stopped: bytecnt %x sd_buff_addr %x \n",bytecnt,*sd_buff_addr);
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
      if (!ack_delay) {
        int lba = *(sd_lba[i]);
        if (bitcheck(*sd_rd,i)) {
        	reading = true;
	}
        if (bitcheck(*sd_wr,i)) {
        	writing = true;
	}

        disk[i].clear();
        disk[i].seekg((lba) * kBLKSZ + header_size[i]);
        // Debug output for floppy (index 0) - show track calculation
        if (i == 0) {
            int track = lba / 13;  // 13 sectors per track
            int sector = lba % 13;
            printf("FLOPPY DMA: LBA=%d (track=%d sector=%d) seek=%06X reading=%d writing=%d\n",
                   lba, track, sector, (lba) * kBLKSZ + header_size[i], reading, writing);
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
        }
        sd_buff_wr=NULL;
        img_mounted=NULL;
        img_readonly=NULL;
        img_size=NULL;
}

SimBlockDevice::~SimBlockDevice() {

}
