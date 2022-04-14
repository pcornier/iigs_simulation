#include <iostream>
#include <queue>
#include <string>

#include "sim_blkdevice.h"
#include "sim_console.h"
#include "verilated_heavy.h"

#ifndef _MSC_VER
#else
#define WIN32
#endif


static DebugConsole console;

IData* sd_lba[2]= {NULL,NULL};
CData* sd_rd=NULL;
CData* sd_wr=NULL;
CData* sd_ack=NULL;
SData* sd_buff_addr=NULL;
CData* sd_buff_dout=NULL;
CData* sd_buff_din[2]= {NULL,NULL};
CData* sd_buff_wr=NULL;
CData* img_mounted=NULL;
CData* img_readonly=NULL;
QData* img_size=NULL;

void SimBlockDevice::MountDisk( std::string file, int index) {
	disk[index].open(file.c_str(), std::ios::in | std::ios::binary | std::ios::ate);
        if (disk[index]) {
           *img_size = disk[index].tellg();
           *img_mounted = 1;
	   reading=0;
	   writing=0;
	   ack_delay=0;
           disk[index].seekg(0);
           printf("disk inserted\n");
        }

}


void SimBlockDevice::BeforeEval(int cycles)
{
  /*if (*sd_ack && cycles % 4 == 0) {
    *sd_ack = 0;
    *sd_buff_wr= 0;
  }*/
	/*
  if (*sd_buff_wr && cycles % 1 == 0) {
    *sd_buff_wr= 0;
  }
*/
  // send data
  if (ack_delay==1) {
  if (reading && (bytecnt<512)) {
    *sd_buff_dout = disk[0].get();
    *sd_buff_addr = bytecnt++;
    *sd_buff_wr= 1;
    printf("cycles %x reading %X : %X \n",cycles,*sd_buff_addr,*sd_buff_dout );
  } else {
	  *sd_buff_wr=0;
	if (bytecnt==512)
	       reading=writing=0;	
  }
  } else {
	  *sd_buff_wr=0;
  } 

  if (*img_mounted && cycles % 8 == 0) {
      *img_mounted = 0;
  }

  int lba = *(sd_lba[0]);
  // start reading when sd_rd pulses high
  //if (!reading && (old_dsk_rd == 0 && *sd_rd == 1) ) {
  if (*sd_rd == 1 ) {
    if (!ack_delay) {
      reading = true;
      old_lba=lba;
      disk[0].clear();
      disk[0].seekg((lba) * 512);
      printf("seek %06X lba: (%x) (%d,%d)\n", (lba) * 512,lba,lba,512);
      bytecnt = 0;
      ack_delay = 1200;
    }
  }

  *sd_ack = (ack_delay == 1);
  if((ack_delay > 1) || ((ack_delay == 1) && !reading && !writing))
      ack_delay--;

  old_dsk_rd = *sd_rd;
}

void SimBlockDevice::AfterEval()
{
}


SimBlockDevice::SimBlockDevice(DebugConsole c) {
	console = c;
	sd_lba[0] = NULL;
	sd_lba[1] = NULL;
        sd_rd = NULL;
        sd_wr = NULL;
        sd_ack = NULL;
        sd_buff_addr = NULL;
        sd_buff_dout = NULL;
        sd_buff_din[0]=NULL;
        sd_buff_din[1]=NULL;
        sd_buff_wr=NULL;
        img_mounted=NULL;
        img_readonly=NULL;
        img_size=NULL;

}

SimBlockDevice::~SimBlockDevice() {

}
