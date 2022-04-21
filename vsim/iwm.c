/*
   GSPLUS - Advanced Apple IIGS Emulator Environment
   Based on the KEGS emulator written by Kent Dickey
   See COPYRIGHT.txt for Copyright information
   See LICENSE.txt for license (GPL v2)
 */

#include "defc.h"
#include "glog.h"

extern int Verbose;
extern word32 g_vbl_count;      // OG change int to word32
extern int g_c036_val_speed;

const byte phys_to_dos_sec[] = {
  0x00, 0x07, 0x0e, 0x06,  0x0d, 0x05, 0x0c, 0x04,
  0x0b, 0x03, 0x0a, 0x02,  0x09, 0x01, 0x08, 0x0f
};

const byte phys_to_prodos_sec[] = {
  0x00, 0x08, 0x01, 0x09,  0x02, 0x0a, 0x03, 0x0b,
  0x04, 0x0c, 0x05, 0x0d,  0x06, 0x0e, 0x07, 0x0f
};


const byte to_disk_byte[] = {
  0x96, 0x97, 0x9a, 0x9b,  0x9d, 0x9e, 0x9f, 0xa6,
  0xa7, 0xab, 0xac, 0xad,  0xae, 0xaf, 0xb2, 0xb3,
/* 0x10 */
  0xb4, 0xb5, 0xb6, 0xb7,  0xb9, 0xba, 0xbb, 0xbc,
  0xbd, 0xbe, 0xbf, 0xcb,  0xcd, 0xce, 0xcf, 0xd3,
/* 0x20 */
  0xd6, 0xd7, 0xd9, 0xda,  0xdb, 0xdc, 0xdd, 0xde,
  0xdf, 0xe5, 0xe6, 0xe7,  0xe9, 0xea, 0xeb, 0xec,
/* 0x30 */
  0xed, 0xee, 0xef, 0xf2,  0xf3, 0xf4, 0xf5, 0xf6,
  0xf7, 0xf9, 0xfa, 0xfb,  0xfc, 0xfd, 0xfe, 0xff
};

int g_track_bytes_35[] = {
  0x200*12,
  0x200*11,
  0x200*10,
  0x200*9,
  0x200*8
};

int g_track_nibs_35[] = {
  816*12,
  816*11,
  816*10,
  816*9,
  816*8
};



int g_fast_disk_emul = 1;
int g_slow_525_emul_wr = 0;
double g_dcycs_end_emul_wr = 0.0;
int g_fast_disk_unnib = 0;
int g_iwm_fake_fast = 0;


int from_disk_byte[256];
int from_disk_byte_valid = 0;

Iwm iwm;

extern int g_c031_disk35;

int g_iwm_motor_on = 0;

int g_check_nibblization = 0;

/* prototypes for IWM special routs */
int iwm_read_data_35(Disk *dsk, int fast_disk_emul, double dcycs);
int iwm_read_data_525(Disk *dsk, int fast_disk_emul, double dcycs);
void iwm_write_data_35(Disk *dsk, word32 val, int fast_disk_emul, double dcycs);
void iwm_write_data_525(Disk *dsk, word32 val, int fast_disk_emul,double dcycs);

void iwm_init_drive(Disk *dsk, int smartport, int drive, int disk_525)      {
  dsk->dcycs_last_read = 0.0;
  dsk->name_ptr = 0;
  dsk->partition_name = 0;
  dsk->partition_num = -1;
  dsk->file = 0;
  dsk->force_size = 0;
  dsk->image_start = 0;
  dsk->image_size = 0;
  dsk->smartport = smartport;
  dsk->disk_525 = disk_525;
  dsk->drive = drive;
  dsk->cur_qtr_track = 0;
  dsk->image_type = 0;
  dsk->vol_num = 254;
  dsk->write_prot = 1;
  dsk->write_through_to_unix = 0;
  dsk->disk_dirty = 0;
  dsk->just_ejected = 0;
  dsk->last_phase = 0;
  dsk->nib_pos = 0;
  dsk->num_tracks = 0;
  dsk->trks = 0;

}

void disk_set_num_tracks(Disk *dsk, int num_tracks)      {
  int i;

  if(dsk->trks != 0) {
    /* This should not be necessary! */
    free(dsk->trks);
    halt_printf("Needed to free dsk->trks: %p\n", dsk->trks);
  }
  dsk->num_tracks = num_tracks;
  dsk->trks = (Trk *)malloc(num_tracks * sizeof(Trk));

  for(i = 0; i < num_tracks; i++) {
    dsk->trks[i].dsk = dsk;
    dsk->trks[i].nib_area = 0;
    dsk->trks[i].track_dirty = 0;
    dsk->trks[i].overflow_size = 0;
    dsk->trks[i].track_len = 0;
    dsk->trks[i].unix_pos = -1;
    dsk->trks[i].unix_len = -1;
  }
}

void iwm_init()      {
  int val;
  int i;

  for(i = 0; i < 2; i++) {
    iwm_init_drive(&(iwm.drive525[i]), 0, i, 1);
    iwm_init_drive(&(iwm.drive35[i]), 0, i, 0);
  }

  for(i = 0; i < MAX_C7_DISKS; i++) {
    iwm_init_drive(&(iwm.smartport[i]), 1, i, 0);
  }

  if(from_disk_byte_valid == 0) {
    for(i = 0; i < 256; i++) {
      from_disk_byte[i] = -1;
    }
    for(i = 0; i < 64; i++) {
      val = to_disk_byte[i];
      from_disk_byte[val] = i;
    }
    from_disk_byte_valid = 1;
  } else {
    halt_printf("iwm_init called twice!\n");
  }

  iwm_reset();
}

// OG  Added shut function to IWM
// Free the memory, and more important free the open handle onto the disk
void iwm_shut()      {
  int i;
  for(i = 0; i < 2; i++) {
    eject_disk(&iwm.drive525[i]);
    eject_disk(&iwm.drive35[i]);
  }

  for(i = 0; i < MAX_C7_DISKS; i++) {
    eject_disk(&iwm.smartport[i]);
  }

  from_disk_byte_valid = 0;
}

void iwm_reset()      {
  iwm.q6 = 0;
  iwm.q7 = 0;
  iwm.motor_on = 0;
  iwm.motor_on35 = 0;
  iwm.motor_off = 0;
  iwm.motor_off_vbl_count = 0;
  iwm.step_direction35 = 0;
  iwm.head35 = 0;
  iwm.drive_select = 0;
  iwm.iwm_mode = 0;
  iwm.enable2 = 0;
  iwm.reset = 0;
  iwm.iwm_phase[0] = 0;
  iwm.iwm_phase[1] = 0;
  iwm.iwm_phase[2] = 0;
  iwm.iwm_phase[3] = 0;
  iwm.previous_write_val = 0;
  iwm.previous_write_bits = 0;

  g_iwm_motor_on = 0;
  g_c031_disk35 = 0;
}

void draw_iwm_status(int line, char *buf)      {
  char    *flag[2][2];
  int apple35_sel;

  flag[0][0] = " ";
  flag[0][1] = " ";
  flag[1][0] = " ";
  flag[1][1] = " ";

  apple35_sel = (g_c031_disk35 >> 6) & 1;
  if(g_iwm_motor_on) {
    flag[apple35_sel][iwm.drive_select] = "*";
  }

        #ifdef ACTIVEGS // OG Pass monitoring info
  {
    extern void ki_loading(int _motorOn,int _slot,int _drive, int _curtrack);
    int curtrack=0;
    if (apple35_sel)
      curtrack = iwm.drive35[iwm.drive_select].cur_qtr_track;
    else
      curtrack = iwm.drive525[iwm.drive_select].cur_qtr_track >> 2;

    ki_loading(g_iwm_motor_on,apple35_sel ? 5 : 6,iwm.drive_select+1,curtrack);
  }
        #endif
/*
  sprintf(buf, "s6d1:%2d%s   s6d2:%2d%s   s5d1:%2d/%d%s   "
          "s5d2:%2d/%d%s fast_disk_emul:%d,%d c036:%02x",
          iwm.drive525[0].cur_qtr_track >> 2, flag[0][0],
          iwm.drive525[1].cur_qtr_track >> 2, flag[0][1],
          iwm.drive35[0].cur_qtr_track >> 1,
          iwm.drive35[0].cur_qtr_track & 1, flag[1][0],
          iwm.drive35[1].cur_qtr_track >> 1,
          iwm.drive35[1].cur_qtr_track & 1, flag[1][1],
          g_fast_disk_emul, g_slow_525_emul_wr, g_c036_val_speed);
*/
  //video_update_status_line(line, buf);
}


void iwm_flush_disk_to_unix(Disk *dsk)      {
  byte buffer[0x4000];
  int num_dirty;
  int j;
  int ret;
  int unix_pos;
  int unix_len;

  if(dsk->disk_dirty == 0 || dsk->write_through_to_unix == 0) {
    return;
  }

  glogf("Writing disk %s to Unix", dsk->name_ptr);
  dsk->disk_dirty = 0;
  num_dirty = 0;

  /* Dirty data! */
  for(j = 0; j < dsk->num_tracks; j++) {

    ret = disk_track_to_unix(dsk, j, &(buffer[0]));

    if(ret != 1 && ret != 0) {
      glogf("iwm_flush_disk_to_unix ret: %d, cannot write image to unix", ret);
      halt_printf("Adjusting image not to write through!\n");
      dsk->write_through_to_unix = 0;
      break;
    }

    if(ret != 1) {
      /* not at an even track, or not dirty */
      continue;
    }
    if((j & 3) != 0 && dsk->disk_525) {
      halt_printf("Valid data on a non-whole trk: %03x\n", j);
      continue;
    }

    num_dirty++;

    /* Write it out */
    unix_pos = dsk->trks[j].unix_pos;
    unix_len = dsk->trks[j].unix_len;
    if(unix_pos < 0 || unix_len < 0x1000) {
      halt_printf("Disk:%s trk:%d, unix_pos:%08x, len:%08x\n",
                  dsk->name_ptr, j, unix_pos, unix_len);
      break;
    }

    ret = fseek(dsk->file, unix_pos, SEEK_SET);
    if(ret != 0) {
      halt_printf("fseek 525: errno: %d\n", errno);
    }

    ret = fwrite(&(buffer[0]), 1, unix_len, dsk->file);
    if(ret != unix_len) {
      glogf("fwrite: %08x, errno:%d, qtrk: %02x, disk: %s", ret, errno, j, dsk->name_ptr);
    }
  }

  if(num_dirty == 0) {
    halt_printf("Drive %s was dirty, but no track was dirty!", dsk->name_ptr);
  }

}

/* Check for dirty disk 3 times a second */

extern byte g_bram[2][256];
extern byte* g_bram_ptr;
extern byte g_temp_boot_slot;
extern byte g_orig_boot_slot;
extern int g_config_gsplus_update_needed;
void iwm_vbl_update(int doit_3_persec)      {
  Disk    *dsk;
  int motor_on;
  int i;

  if(iwm.motor_on && iwm.motor_off) {
    if((word32)iwm.motor_off_vbl_count <= g_vbl_count) {
      glogf("Disk timer expired, drive off: %08x", g_vbl_count);
      iwm.motor_on = 0;
      iwm.motor_off = 0;
      /*
      if (g_temp_boot_slot != 254) {
        // Drive is off, now's a good time to turn off the temp boot slot if it was on.
        g_temp_boot_slot = 254;
        g_bram_ptr[40] = g_orig_boot_slot;
        clk_calculate_bram_checksum();
        g_config_gsplus_update_needed = 1;
      }
      */
    }
  }

  if(!doit_3_persec) {
    return;
  }

  motor_on = iwm.motor_on;
  if(g_c031_disk35 & 0x40) {
    motor_on = iwm.motor_on35;
    /*
    if (g_temp_boot_slot != 254) {
      // Now's a good time to turn off the temp boot slot if it was on.
      g_temp_boot_slot = 254;
      g_bram_ptr[40] = g_orig_boot_slot;
      clk_calculate_bram_checksum();
      g_config_gsplus_update_needed = 1;
    }
	*/
  }

  if(motor_on == 0 || iwm.motor_off) {
    /* Disk not spinning, see if any dirty tracks to flush */
    /*  out to Unix */
    for(i = 0; i < 2; i++) {
      dsk = &(iwm.drive525[i]);
      iwm_flush_disk_to_unix(dsk);
    }
    for(i = 0; i < 2; i++) {
      dsk = &(iwm.drive35[i]);
      iwm_flush_disk_to_unix(dsk);
    }
  }
}


void iwm_show_stats()      {
  glogf("IWM stats: q7,q6: %d, %d, reset,enable2: %d,%d, mode: %02x",
        iwm.q7, iwm.q6, iwm.reset, iwm.enable2, iwm.iwm_mode);
  glogf("motor: %d,%d, motor35:%d drive: %d, c031:%02x phs: %d %d %d %d",
        iwm.motor_on, iwm.motor_off, g_iwm_motor_on,
        iwm.drive_select, g_c031_disk35,
        iwm.iwm_phase[0], iwm.iwm_phase[1], iwm.iwm_phase[2],
        iwm.iwm_phase[3]);
  glogf("iwm.drive525[0].file: %p, [1].file: %p",
        iwm.drive525[0].file, iwm.drive525[1].file);
  glogf("iwm.drive525[0].last_phase: %d, [1].last_phase: %d",
        iwm.drive525[0].last_phase, iwm.drive525[1].last_phase);
}

void iwm_touch_switches(int loc, double dcycs)      {
  Disk    *dsk;
  int phase;
  int on;
  int drive;

  if(iwm.reset) {
    iwm_printf("IWM under reset: %d, enable2: %d\n", iwm.reset,
               iwm.enable2);
  }

  on = loc & 1;
  drive = iwm.drive_select;
  phase = loc >> 1;
  if(g_c031_disk35 & 0x40) {
    dsk = &(iwm.drive35[drive]);
  } else {
    dsk = &(iwm.drive525[drive]);
  }


  if(loc < 8) {
    /* phase adjustments.  See if motor is on */

    iwm.iwm_phase[phase] = on;
    iwm_printf("Iwm phase %d=%d, all phases: %d %d %d %d (%f)\n",
               phase, on, iwm.iwm_phase[0], iwm.iwm_phase[1],
               iwm.iwm_phase[2], iwm.iwm_phase[3], dcycs);

    if(iwm.motor_on) {
      if(g_c031_disk35 & 0x40) {
        if(phase == 3 && on) {
          iwm_do_action35(dcycs);
        }
      } else if(on) {
        /* Move apple525 head */
        iwm525_phase_change(drive, phase);
      }
    }
    /* See if enable or reset is asserted */
    if(iwm.iwm_phase[0] && iwm.iwm_phase[2]) {
      iwm.reset = 1;
      iwm_printf("IWM reset active\n");
    } else {
      iwm.reset = 0;
    }
    if(iwm.iwm_phase[1] && iwm.iwm_phase[3]) {
      iwm.enable2 = 1;
      iwm_printf("IWM ENABLE2 active\n");
    } else {
      iwm.enable2 = 0;
    }
  } else {
    /* loc >= 8 */
    switch(loc) {
      case 0x8:
        iwm_printf("Turning IWM motor off!\n");
        if(iwm.iwm_mode & 0x04) {
          /* Turn off immediately */
          iwm.motor_off = 0;
          iwm.motor_on = 0;
        } else {
          /* 1 second delay */
          if(iwm.motor_on && !iwm.motor_off) {
            iwm.motor_off = 1;
            iwm.motor_off_vbl_count = g_vbl_count
                                      + 60;
          }
        }

        if(g_iwm_motor_on || g_slow_525_emul_wr) {
          /* recalc current speed */
          set_halt(HALT_EVENT);
        }

        g_iwm_motor_on = 0;
        g_slow_525_emul_wr = 0;
        break;
      case 0x9:
        iwm_printf("Turning IWM motor on!\n");
        iwm.motor_on = 1;
        iwm.motor_off = 0;

        if(g_iwm_motor_on == 0) {
          /* recalc current speed */
          set_halt(HALT_EVENT);
        }
        g_iwm_motor_on = 1;

        break;
      case 0xa:
      case 0xb:
        iwm.drive_select = on;
        break;
      case 0xc:
      case 0xd:
        iwm.q6 = on;
        break;
      case 0xe:
      case 0xf:
        iwm.q7 = on;
        break;
      default:
        printf("iwm_touch_switches: loc: %02x unknown!\n", loc);
        exit(2);
    }
  }

  if(!iwm.q7) {
    iwm.previous_write_bits = 0;
  }

  if((dcycs > g_dcycs_end_emul_wr) && g_slow_525_emul_wr) {
    set_halt(HALT_EVENT);
    g_slow_525_emul_wr = 0;
  }
}

void iwm_move_to_track(Disk *dsk, int new_track)      {
  int disk_525;
  int dr;

  disk_525 = dsk->disk_525;

  if(new_track < 0) {
    new_track = 0;
  }
  if(new_track >= dsk->num_tracks) {
    if(disk_525) {
      new_track = dsk->num_tracks - 4;
    } else {
      new_track = dsk->num_tracks - 2 + iwm.head35;
    }

    if(new_track <= 0) {
      new_track = 0;
    }
  }

  if(dsk->cur_qtr_track != new_track) {
    dr = dsk->drive + 1;
    if(disk_525) {
      iwm_printf("s6d%d Track: %d.%02d\n", dr,
                 new_track >> 2, 25* (new_track & 3));
    } else {
      iwm_printf("s5d%d Track: %d Side: %d\n", dr,
                 new_track >> 1, new_track & 1);
    }

    dsk->cur_qtr_track = new_track;
  }
}

void iwm525_phase_change(int drive, int phase)      {
  Disk    *dsk;
  int qtr_track;
  int delta;

  dsk = &(iwm.drive525[drive]);

  qtr_track = dsk->cur_qtr_track;
  int half_track = qtr_track >> 1;

  delta = 0;
  if (iwm.iwm_phase[(half_track + 1) & 3])
    delta += 2;
  if (iwm.iwm_phase[(half_track + 3) & 3])
    delta -= 2;

  qtr_track += delta;
  if(qtr_track < 0) {
#if 1
    printf("💾  ");
#else
    printf("GRIND...");
#endif
    qtr_track = 0;
  }
  if(qtr_track > 4*34) {
    glogf("Disk arm moved past track 34, moving it back");
    qtr_track = 4*34;
  }

  iwm_move_to_track(dsk, qtr_track);

  iwm_printf("Moving drive to qtr track: %04x (trk:%d.%02d), %d, %d, "
             "%d %d %d %d\n", qtr_track, qtr_track>>2, 25*(qtr_track & 3),
             phase, delta, iwm.iwm_phase[0],
             iwm.iwm_phase[1], iwm.iwm_phase[2], iwm.iwm_phase[3]);
}

int iwm_read_status35(double dcycs)     {
  Disk    *dsk;
  int drive;
  int state;
  int tmp;

  drive = iwm.drive_select;
  dsk = &(iwm.drive35[drive]);

  if(iwm.motor_on) {
    /* Read status */
    state = (iwm.iwm_phase[1] << 3) + (iwm.iwm_phase[0] << 2) +
            ((g_c031_disk35 >> 6) & 2) + iwm.iwm_phase[2];

    iwm_printf("Iwm status read state: %02x\n", state);

    switch(state) {
      case 0x00:                /* step direction */
        return iwm.step_direction35;
        break;
      case 0x01:                /* lower head activate */
        /* also return instantaneous data from head */
        iwm.head35 = 0;
        iwm_move_to_track(dsk, (dsk->cur_qtr_track & (-2)));
        return (((int)dcycs) & 1);
        break;
      case 0x02:                /* disk in place */
        /* 1 = no disk, 0 = disk */
        iwm_printf("read disk in place, num_tracks: %d\n",
                   dsk->num_tracks);
        tmp = (dsk->num_tracks <= 0);
        return tmp;
        break;
      case 0x03:                /* upper head activate */
        /* also return instantaneous data from head */
        iwm.head35 = 1;
        iwm_move_to_track(dsk, (dsk->cur_qtr_track | 1));
        return (((int)dcycs) & 1);
        break;
      case 0x04:                /* disk is stepping? */
        /* 1 = not stepping, 0 = stepping */
        return 1;
        break;
      case 0x05:                /* Unknown function of ROM 03? */
        /* 1 = or $20 into 0xe1/f24+drive, 0 = don't */
        return 1;
        break;
      case 0x06:                /* disk is locked */
        /* 0 = locked, 1 = unlocked */
        return (!dsk->write_prot);
        break;
      case 0x08:                /* motor on */
        /* 0 = on, 1 = off */
        return !iwm.motor_on35;
        break;
      case 0x09:                /* number of sides */
        /* 1 = 2 sides, 0 = 1 side */
        return 1;
        break;
      case 0x0a:                /* at track 0 */
        /* 1 = not at track 0, 0 = there */
        tmp = (dsk->cur_qtr_track != 0);
        iwm_printf("Read at track0_35: %d\n", tmp);
        return tmp;
        break;
      case 0x0b:                /* disk ready??? */
        /* 0 = ready, 1 = not ready? */
        tmp = !iwm.motor_on35;
        iwm_printf("Read disk ready, ret: %d\n", tmp);
        return tmp;
        break;
      case 0x0c:                /* disk switched?? */
        /* 0 = not switched, 1 = switched? */
        tmp = (dsk->just_ejected != 0);
        iwm_printf("Read disk switched: %d\n", tmp);
        return tmp;
        break;
      case 0x0d:                /* false read when ejecting disk */
        return 1;
      case 0x0e:                /* tachometer */
        halt_printf("Reading tachometer!\n");
        return (((int)dcycs) & 1);
        break;
      case 0x0f:                /* drive installed? */
        /* 0 = drive exists, 1 = no drive */
        if(drive) {
          /* pretend no drive 1 */
          return 1;
        }
        return 0;
        break;
      default:
        halt_printf("Read 3.5 status, state: %02x\n", state);
        return 1;
    }
  } else {
    iwm_printf("Read 3.5 status with drive off!\n");
    return 1;
  }
}

void iwm_do_action35(double dcycs)      {
  Disk    *dsk;
  int drive;
  int state;

  drive = iwm.drive_select;
  dsk = &(iwm.drive35[drive]);

  if(iwm.motor_on) {
    /* Perform action */
    state = (iwm.iwm_phase[1] << 3) + (iwm.iwm_phase[0] << 2) +
            ((g_c031_disk35 >> 6) & 2) + iwm.iwm_phase[2];
    switch(state) {
      case 0x00:                /* Set step direction inward */
        /* towards higher tracks */
        iwm.step_direction35 = 0;
        iwm_printf("Iwm set step dir35 = 0\n");
        break;
      case 0x01:                /* Set step direction outward */
        /* towards lower tracks */
        iwm.step_direction35 = 1;
        iwm_printf("Iwm set step dir35 = 1\n");
        break;
      case 0x03:                /* reset disk-switched flag? */
        iwm_printf("Iwm reset disk switch\n");
        dsk->just_ejected = 0;
        /* set_halt(1); */
        break;
      case 0x04:                /* step disk */
        if(iwm.step_direction35) {
          iwm_move_to_track(dsk, dsk->cur_qtr_track - 2);
        } else {
          iwm_move_to_track(dsk, dsk->cur_qtr_track + 2);
        }
        break;
      case 0x08:                /* turn motor on */
        iwm_printf("Iwm set motor_on35 = 1\n");
        iwm.motor_on35 = 1;
        break;
      case 0x09:                /* turn motor off */
        iwm_printf("Iwm set motor_on35 = 0\n");
        iwm.motor_on35 = 0;
        break;
      case 0x0d:                /* eject disk */
        eject_disk(dsk);
                        #ifdef ACTIVEGS // OG : pass eject info to the Control (ActiveX specific)
        {
          extern void     ejectDisk(int slot,int disk);
          ejectDisk(dsk->disk_525 ? 6 : 5,dsk->drive+1);
        }
                        #endif
        break;
      case 0x02:
      case 0x07:
      case 0x0b:           /* hacks to allow AE 1.6MB driver to not crash me */
        break;
      default:
        halt_printf("Do 3.5 action, state: %02x\n", state);
        return;
    }
  } else {
    halt_printf("Set 3.5 status with drive off!\n");
    return;
  }
}

int iwm_read_c0ec(double dcycs)     {
  Disk    *dsk;
  int drive;

  printf("read_c0ec: \n");

  iwm.q6 = 0;

  if(iwm.q7 == 0 && iwm.enable2 == 0 && iwm.motor_on) {
    drive = iwm.drive_select;
    if(g_c031_disk35 & 0x40) {
	    printf("read_c0ec: 3.5\n");
      dsk = &(iwm.drive35[drive]);
      return iwm_read_data_35(dsk, g_fast_disk_emul, dcycs);
    } else {
	    printf("read_c0ec: 5.25\n");
      dsk = &(iwm.drive525[drive]);
      return iwm_read_data_525(dsk, g_fast_disk_emul, dcycs);
    }

  }

  return read_iwm(0xc, dcycs);
}


int read_iwm(int loc, double dcycs)     {
  Disk    *dsk;
  word32 status;
  double diff_dcycs;
  double dcmp;
  int on;
  int state;
  int drive;
  int val;
printf("read_iwm loc %x drive35 %x\n",loc,g_c031_disk35);
  loc = loc & 0xf;
  on = loc & 1;

  if(loc == 0xc) {
    iwm.q6 = 0;
  } else {
    iwm_touch_switches(loc, dcycs);
  }

  state = (iwm.q7 << 1) + iwm.q6;
  drive = iwm.drive_select;
  if(g_c031_disk35 & 0x40) {
	  printf("read_iwm: 3.5\n");
    dsk = &(iwm.drive35[drive]);
  } else {
	  printf("read_iwm: 5.25\n");
    dsk = &(iwm.drive525[drive]);
  }

  if(on) {
    /* odd address, return 0 */
	  printf("IWM: returning from on is true (0)\n");
    return 0;
  } else {
    /* even address */
    switch(state) {
      case 0x00:                /* q7 = 0, q6 = 0 */
        if(iwm.enable2) {
	  printf("IWM: returning from iwm.enable2, case 0x00\n");
          return iwm_read_enable2(dcycs);
        } else {
          if(iwm.motor_on) {
	  	printf("IWM: returning from iwm.motor_on, case 0x00\n");
            return iwm_read_data(dsk,
                                 g_fast_disk_emul, dcycs);
          } else {
            iwm_printf("read iwm st 0, m off!\n");
/* HACK!!!! */
	  	printf("IWM: returning from else, case 0x00 - return ff\n");
            return 0xff;
            //return (((int)dcycs) & 0x7f) + 0x80;
          }
        }
        break;
      case 0x01:                /* q7 = 0, q6 = 1 */
        /* read IWM status reg */
        if(iwm.enable2) {
          iwm_printf("Read status under enable2: 1\n");
          status = 1;
        } else {
          if(g_c031_disk35 & 0x40) {
            status = iwm_read_status35(dcycs);
          } else {
            status = dsk->write_prot;
          }
        }

        val = (status << 7) + (iwm.motor_on << 5) +
              iwm.iwm_mode;
        iwm_printf("Read status: %02x\n", val);

	  	printf("IWM: case 0x01 - return %x\n",val);
        return val;
        break;
      case 0x02:                /* q7 = 1, q6 = 0 */
        /* read handshake register */
        if(iwm.enable2) {
	  	printf("IWM: read_enable2_handshake\n");
          return iwm_read_enable2_handshake(dcycs);
        } else {
          status = 0xc0;
          diff_dcycs = dcycs - dsk->dcycs_last_read;
          dcmp = 16.0;
          if(dsk->disk_525 == 0) {
            dcmp = 32.0;
          }
          if(diff_dcycs > dcmp) {
            iwm_printf("Write underrun!\n");
            iwm_printf("cur: %f, dc_last: %f\n",
                       dcycs, dsk->dcycs_last_read);
            status = status & 0xbf;
          }
	  	printf("IWM: case 0x02 status: %x\n",status);
          return status;
        }
        break;
      case 0x03:                /* q7 = 1, q6 = 1 */
        halt_printf("read iwm state 3!\n");
	  	printf("IWM: case 0x03 0\n");
        return 0;
        break;
    }

  }
  halt_printf("Got to end of read_iwm, loc: %02x!\n", loc);
	  	printf("got to end of read IWM: case 0x03 0\n");

  return 0;
}

void write_iwm(int loc, int val, double dcycs)      {
  Disk    *dsk;
  int on;
  int state;
  int drive;
  int fast_writes;
printf("write_iwm loc %x val %x drive35 %x\n",loc,val,g_c031_disk35);
  loc = loc & 0xf;
  on = loc & 1;

  iwm_touch_switches(loc, dcycs);

  state = (iwm.q7 << 1) + iwm.q6;
  drive = iwm.drive_select;
  fast_writes = g_fast_disk_emul;
  if(g_c031_disk35 & 0x40) {
    dsk = &(iwm.drive35[drive]);
  } else {
    dsk = &(iwm.drive525[drive]);
    fast_writes = !g_slow_525_emul_wr && fast_writes;
  }

  if(on) {
    /* odd address, write something */
    if(state == 0x03) {
      /* q7, q6 = 1,1 */
      if(iwm.motor_on) {
        if(iwm.enable2) {
          iwm_write_enable2(val, dcycs);
        } else {
          iwm_write_data(dsk, val,
                         fast_writes, dcycs);
        }
      } else {
        /* write mode register */
        val = val & 0x1f;
        iwm.iwm_mode = val;
        if(val != 0 && val != 0x0f && val != 0x07 &&
           val != 0x04 && val != 0x0b) {
          halt_printf("set iwm_mode:%02x!\n",val);
        }
      }
    } else {
      if(iwm.enable2) {
        iwm_write_enable2(val, dcycs);
      } else {
#if 0
// Flobynoid writes to 0xc0e9 causing these messages...
        printf("Write iwm1, st: %02x, loc: %x: %02x\n",
               state, loc, val);
#endif
      }
    }
    return;
  } else {
    /* even address */
    if(iwm.enable2) {
      iwm_write_enable2(val, dcycs);
    } else {
      iwm_printf("Write iwm2, st: %02x, loc: %x: %02x\n",
                 state, loc, val);
    }
    return;
  }

  return;
}



int iwm_read_enable2(double dcycs)     {
  iwm_printf("Read under enable2!\n");
  return 0xff;
}

int g_cnt_enable2_handshake = 0;

int iwm_read_enable2_handshake(double dcycs)     {
  int val;

  iwm_printf("Read handshake under enable2!\n");

  val = 0xc0;
  g_cnt_enable2_handshake++;
  if(g_cnt_enable2_handshake > 3) {
    g_cnt_enable2_handshake = 0;
    val = 0x80;
  }

  return val;
}

void iwm_write_enable2(int val, double dcycs)      {
  iwm_printf("Write under enable2: %02x!\n", val);

  return;
}

int iwm_read_data(Disk *dsk, int fast_disk_emul, double dcycs)     {
  if(dsk->disk_525) {
    return iwm_read_data_525(dsk, fast_disk_emul, dcycs);
  } else {
    return iwm_read_data_35(dsk, fast_disk_emul, dcycs);
  }
}

void iwm_write_data(Disk *dsk, word32 val, int fast_disk_emul, double dcycs)      {
  if(dsk->disk_525) {
    iwm_write_data_525(dsk, val, fast_disk_emul, dcycs);
  } else {
    iwm_write_data_35(dsk, val, fast_disk_emul, dcycs);
  }
}

#undef IWM_READ_ROUT
#undef IWM_WRITE_ROUT
#undef IWM_CYC_MULT
#undef IWM_DISK_525

#define IWM_READ_ROUT           iwm_read_data_35
#define IWM_WRITE_ROUT          iwm_write_data_35
#define IWM_CYC_MULT            1
#define IWM_DISK_525            0

#include "iwm_35_525.h"

#undef IWM_READ_ROUT
#undef IWM_WRITE_ROUT
#undef IWM_CYC_MULT
#undef IWM_DISK_525

#define IWM_READ_ROUT           iwm_read_data_525
#define IWM_WRITE_ROUT          iwm_write_data_525
#define IWM_CYC_MULT            2
#define IWM_DISK_525            1
#include "iwm_35_525.h"

#undef IWM_READ_ROUT
#undef IWM_WRITE_ROUT
#undef IWM_CYC_MULT
#undef IWM_DISK_525





/* c600 */
void sector_to_partial_nib(byte *in, byte *nib_ptr)      {
  byte    *aux_buf;
  byte    *nib_out;
  int val;
  int val2;
  int x;
  int i;

  /* Convert 256(+1) data bytes to 342+1 disk nibbles */

  aux_buf = nib_ptr;
  nib_out = nib_ptr + 0x56;

  for(i = 0; i < 0x56; i++) {
    aux_buf[i] = 0;
  }

  x = 0x55;
  for(i = 0x101; i >= 0; i--) {
    val = in[i];
    if(i >= 0x100) {
      val = 0;
    }
    val2 = (aux_buf[x] << 1) + (val & 1);
    val = val >> 1;
    val2 = (val2 << 1) + (val & 1);
    val = val >> 1;
    nib_out[i] = val;
    aux_buf[x] = val2;
    x--;
    if(x < 0) {
      x = 0x55;
    }
  }
}


int disk_unnib_4x4(Disk *dsk)     {
  int val1;
  int val2;

  val1 = iwm_read_data(dsk, 1, 0);
  val2 = iwm_read_data(dsk, 1, 0);

  return ((val1 << 1) + 1) & val2;
}

int iwm_denib_track525(Disk *dsk, Trk *trk, int qtr_track, byte *outbuf)     {
  byte aux_buf[0x80];
  byte    *buf;
  int sector_done[16];
  int num_sectors_done;
  int track_len;
  int vol, track, phys_sec, log_sec, cksum;
  int val;
  int val2;
  int prev_val;
  int x;
  int my_nib_cnt;
  int save_qtr_track;
  int save_nib_pos;
  int tmp_nib_pos;
  int status;
  int i;

  save_qtr_track = dsk->cur_qtr_track;
  save_nib_pos = dsk->nib_pos;

  iwm_move_to_track(dsk, qtr_track);

  dsk->nib_pos = 0;
  g_fast_disk_unnib = 1;

  track_len = trk->track_len;

  for(i = 0; i < 16; i++) {
    sector_done[i] = 0;
  }

  num_sectors_done = 0;

  val = 0;
  status = -1;
  my_nib_cnt = 0;
  while(my_nib_cnt++ < 2*track_len) {
    /* look for start of a sector */
    if(val != 0xd5) {
      val = iwm_read_data(dsk, 1, 0);
      continue;
    }

    val = iwm_read_data(dsk, 1, 0);
    if(val != 0xaa) {
      continue;
    }

    val = iwm_read_data(dsk, 1, 0);
    if(val != 0x96) {
      continue;
    }

    /* It's a sector start */
    vol = disk_unnib_4x4(dsk);
    track = disk_unnib_4x4(dsk);
    phys_sec = disk_unnib_4x4(dsk);
    if(phys_sec < 0 || phys_sec > 15) {
      printf("Track %02x, read sec as %02x\n", qtr_track>>2,
             phys_sec);
      break;
    }
    if(dsk->image_type == DSK_TYPE_DOS33) {
      log_sec = phys_to_dos_sec[phys_sec];
    } else {
      log_sec = phys_to_prodos_sec[phys_sec];
    }
    cksum = disk_unnib_4x4(dsk);
    if((vol ^ track ^ phys_sec ^ cksum) != 0) {
      /* not correct format */
      printf("Track %02x not DOS 3.3 since hdr cksum, %02x "
             "%02x %02x %02x\n",
             qtr_track>>2, vol, track, phys_sec, cksum);
      break;
    }

    /* see what sector it is */
    if(track != (qtr_track>>2) || (phys_sec < 0)||(phys_sec > 15)) {
      printf("Track %02x bad since track: %02x, sec: %02x\n",
             qtr_track>>2, track, phys_sec);
      break;
    }

    if(sector_done[phys_sec]) {
      printf("Already done sector %02x on track %02x!\n",
             phys_sec, qtr_track>>2);
      break;
    }

    /* So far so good, let's do it! */
    val = 0;
    i = 0;
    while(i < NIBS_FROM_ADDR_TO_DATA) {
      i++;
      if(val != 0xd5) {
        val = iwm_read_data(dsk, 1, 0);
        continue;
      }

      val = iwm_read_data(dsk, 1, 0);
      if(val != 0xaa) {
        continue;
      }

      val = iwm_read_data(dsk, 1, 0);
      if(val != 0xad) {
        continue;
      }

      /* got it, just break */
      break;
    }

    if(i >= NIBS_FROM_ADDR_TO_DATA) {
      printf("No data header, track %02x, sec %02x\n",
             qtr_track>>2, phys_sec);
      printf("nib_pos: %08x\n", dsk->nib_pos);
      break;
    }

    buf = outbuf + 0x100*log_sec;

    /* Data start! */
    prev_val = 0;
    for(i = 0x55; i >= 0; i--) {
      val = iwm_read_data(dsk, 1, 0);
      val2 = from_disk_byte[val];
      if(val2 < 0) {
        printf("Bad data area1, val:%02x,val2:%02x\n",
               val, val2);
        printf(" i:%03x,n_pos:%04x\n", i, dsk->nib_pos);
        break;
      }
      prev_val = val2 ^ prev_val;
      aux_buf[i] = prev_val;
    }

    /* rest of data area */
    for(i = 0; i < 0x100; i++) {
      val = iwm_read_data(dsk, 1, 0);
      val2 = from_disk_byte[val];
      if(val2 < 0) {
        printf("Bad data area2, read: %02x\n", val);
        printf("  nib_pos: %04x\n", dsk->nib_pos);
        break;
      }
      prev_val = val2 ^ prev_val;
      buf[i] = prev_val;
    }

    /* checksum */
    val = iwm_read_data(dsk, 1, 0);
    val2 = from_disk_byte[val];
    if(val2 < 0) {
      printf("Bad data area3, read: %02x\n", val);
      printf("  nib_pos: %04x\n", dsk->nib_pos);
      break;
    }
    if(val2 != prev_val) {
      printf("Bad data cksum, got %02x, wanted: %02x\n",
             val2, prev_val);
      printf("  nib_pos: %04x\n", dsk->nib_pos);
      break;
    }

    /* Got this far, data is good, merge aux_buf into buf */
    x = 0x55;
    for(i = 0; i < 0x100; i++) {
      val = aux_buf[x];
      val2 = (buf[i] << 1) + (val & 1);
      val = val >> 1;
      val2 = (val2 << 1) + (val & 1);
      buf[i] = val2;
      val = val >> 1;
      aux_buf[x] = val;
      x--;
      if(x < 0) {
        x = 0x55;
      }
    }
    sector_done[phys_sec] = 1;
    num_sectors_done++;
    if(num_sectors_done >= 16) {
      status = 0;
      break;
    }
  }

  tmp_nib_pos = dsk->nib_pos;
  iwm_move_to_track(dsk, save_qtr_track);
  dsk->nib_pos = save_nib_pos;
  g_fast_disk_unnib = 0;

  if(status == 0) {
    return 1;
  }

  printf("Nibblization not done, %02x sectors found on track %02x\n",
         num_sectors_done, qtr_track>>2);
  printf("my_nib_cnt: %04x, nib_pos: %04x, trk_len: %04x\n", my_nib_cnt,
         tmp_nib_pos, track_len);
  for(i = 0; i < 16; i++) {
    printf("sector_done[%d] = %d\n", i, sector_done[i]);
  }
  return -1;
}

int iwm_denib_track35(Disk *dsk, Trk *trk, int qtr_track, byte *outbuf)     {
  word32 buf_c00[0x100];
  word32 buf_d00[0x100];
  word32 buf_e00[0x100];
  byte    *buf;
  word32 tmp_5c, tmp_5d, tmp_5e;
  word32 tmp_66, tmp_67;
  int sector_done[16];
  int num_sectors_done;
  int track_len;
  int phys_track, phys_sec, phys_side, phys_capacity, cksum;
  int tmp;
  int track, side;
  int num_sectors;
  int val;
  int val2;
  int x, y;
  int carry;
  int my_nib_cnt;
  int save_qtr_track;
  int save_nib_pos;
  int status;
  int i;

  save_qtr_track = dsk->cur_qtr_track;
  save_nib_pos = dsk->nib_pos;

  iwm_move_to_track(dsk, qtr_track);

  dsk->nib_pos = 0;
  g_fast_disk_unnib = 1;

  track_len = trk->track_len;

  num_sectors = g_track_bytes_35[qtr_track >> 5] >> 9;

  for(i = 0; i < num_sectors; i++) {
    sector_done[i] = 0;
  }

  num_sectors_done = 0;

  val = 0;
  status = -1;
  my_nib_cnt = 0;

  track = qtr_track >> 1;
  side = qtr_track & 1;

  while(my_nib_cnt++ < 2*track_len) {
    /* look for start of a sector */
    if(val != 0xd5) {
      val = iwm_read_data(dsk, 1, 0);
      continue;
    }

    val = iwm_read_data(dsk, 1, 0);
    if(val != 0xaa) {
      continue;
    }

    val = iwm_read_data(dsk, 1, 0);
    if(val != 0x96) {
      continue;
    }

    /* It's a sector start */
    val = iwm_read_data(dsk, 1, 0);
    phys_track = from_disk_byte[val];
    if(phys_track != (track & 0x3f)) {
      printf("Track %02x.%d, read track %02x, %02x\n",
             track, side, phys_track, val);
      break;
    }

    phys_sec = from_disk_byte[iwm_read_data(dsk, 1, 0)];
    if(phys_sec < 0 || phys_sec >= num_sectors) {
      printf("Track %02x.%d, read sector %02x??\n",
             track, side, phys_sec);
      break;
    }
    phys_side = from_disk_byte[iwm_read_data(dsk, 1, 0)];

    if(phys_side != ((side << 5) + (track >> 6))) {
      printf("Track %02x.%d, read side %02x??\n",
             track, side, phys_side);
      break;
    }
    phys_capacity = from_disk_byte[iwm_read_data(dsk, 1, 0)];
    if(phys_capacity != 0x24 && phys_capacity != 0x22) {
      printf("Track %02x.%x capacity: %02x != 0x24/22\n",
             track, side, phys_capacity);
    }
    cksum = from_disk_byte[iwm_read_data(dsk, 1, 0)];

    tmp = phys_track ^ phys_sec ^ phys_side ^ phys_capacity;
    if(cksum != tmp) {
      printf("Track %02x.%d, sector %02x, cksum: %02x.%02x\n",
             track, side, phys_sec, cksum, tmp);
      break;
    }


    if(sector_done[phys_sec]) {
      printf("Already done sector %02x on track %02x.%x!\n",
             phys_sec, track, side);
      break;
    }

    /* So far so good, let's do it! */
    val = 0;
    for(i = 0; i < 38; i++) {
      val = iwm_read_data(dsk, 1, 0);
      if(val == 0xd5) {
        break;
      }
    }
    if(val != 0xd5) {
      printf("No data header, track %02x.%x, sec %02x\n",
             track, side, phys_sec);
      break;
    }

    val = iwm_read_data(dsk, 1, 0);
    if(val != 0xaa) {
      printf("Bad data hdr1,val:%02x trk %02x.%x, sec %02x\n",
             val, track, side, phys_sec);
      printf("nib_pos: %08x\n", dsk->nib_pos);
      break;
    }

    val = iwm_read_data(dsk, 1, 0);
    if(val != 0xad) {
      printf("Bad data hdr2,val:%02x trk %02x.%x, sec %02x\n",
             val, track, side, phys_sec);
      break;
    }

    buf = outbuf + (phys_sec << 9);

    /* check sector again */
    val = from_disk_byte[iwm_read_data(dsk, 1, 0)];
    if(val != phys_sec) {
      printf("Bad data hdr3,val:%02x trk %02x.%x, sec %02x\n",
             val, track, side, phys_sec);
      break;
    }

    /* Data start! */
    tmp_5c = 0;
    tmp_5d = 0;
    tmp_5e = 0;
    y = 0xaf;
    carry = 0;

    while(y > 0) {
/* 626f */
      val = iwm_read_data(dsk, 1, 0);
      val2 = from_disk_byte[val];
      if(val2 < 0) {
        printf("Bad data area1b, read: %02x\n", val);
        printf(" i:%03x,n_pos:%04x\n", i, dsk->nib_pos);
        break;
      }
      tmp_66 = val2;

      tmp_5c = tmp_5c << 1;
      carry = (tmp_5c >> 8);
      tmp_5c = (tmp_5c + carry) & 0xff;

      val = iwm_read_data(dsk, 1, 0);
      val2 = from_disk_byte[val];
      if(val2 < 0) {
        printf("Bad data area2, read: %02x\n", val);
        break;
      }

      val2 = val2 + ((tmp_66 << 2) & 0xc0);

      val2 = val2 ^ tmp_5c;
      buf_c00[y] = val2;

      tmp_5e = val2 + tmp_5e + carry;
      carry = (tmp_5e >> 8);
      tmp_5e = tmp_5e & 0xff;
/* 62b8 */
      val = iwm_read_data(dsk, 1, 0);
      val2 = from_disk_byte[val];
      val2 = val2 + ((tmp_66 << 4) & 0xc0);
      val2 = val2 ^ tmp_5e;
      buf_d00[y] = val2;
      tmp_5d = val2 + tmp_5d + carry;

      carry = (tmp_5d >> 8);
      tmp_5d = tmp_5d & 0xff;

      y--;
      if(y <= 0) {
        break;
      }

/* 6274 */
      val = iwm_read_data(dsk, 1, 0);
      val2 = from_disk_byte[val];
      val2 = val2 + ((tmp_66 << 6) & 0xc0);
      val2 = val2 ^ tmp_5d;
      buf_e00[y+1] = val2;

      tmp_5c = val2 + tmp_5c + carry;
      carry = (tmp_5c >> 8);
      tmp_5c = tmp_5c & 0xff;
    }

/* 62d0 */
    val = iwm_read_data(dsk, 1, 0);
    val2 = from_disk_byte[val];

    tmp_66 = (val2 << 6) & 0xc0;
    tmp_67 = (val2 << 4) & 0xc0;
    val2 = (val2 << 2) & 0xc0;

    val = iwm_read_data(dsk, 1, 0);
    val2 = from_disk_byte[val] + val2;
    if(tmp_5e != (word32)val2) {
      printf("Checksum 5e bad: %02x vs %02x\n", tmp_5e, val2);
      printf("val:%02x trk %02x.%x, sec %02x\n",
             val, track, side, phys_sec);
      break;
    }

    val = iwm_read_data(dsk, 1, 0);
    val2 = from_disk_byte[val] + tmp_67;
    if(tmp_5d != (word32)val2) {
      printf("Checksum 5d bad: %02x vs %02x\n", tmp_5e, val2);
      printf("val:%02x trk %02x.%x, sec %02x\n",
             val, track, side, phys_sec);
      break;
    }

    val = iwm_read_data(dsk, 1, 0);
    val2 = from_disk_byte[val] + tmp_66;
    if(tmp_5c != (word32)val2) {
      printf("Checksum 5c bad: %02x vs %02x\n", tmp_5e, val2);
      printf("val:%02x trk %02x.%x, sec %02x\n",
             val, track, side, phys_sec);
      break;
    }

    /* Whew, got it!...check for DE AA */
    val = iwm_read_data(dsk, 1, 0);
    if(val != 0xde) {
      printf("Bad data epi1,val:%02x trk %02x.%x, sec %02x\n",
             val, track, side, phys_sec);
      printf("nib_pos: %08x\n", dsk->nib_pos);
      break;
    }

    val = iwm_read_data(dsk, 1, 0);
    if(val != 0xaa) {
      printf("Bad data epi2,val:%02x trk %02x.%x, sec %02x\n",
             val, track, side, phys_sec);
      break;
    }

    /* Now, convert buf_c/d/e to output */
/* 6459 */
    y = 0;
    for(x = 0xab; x >= 0; x--) {
      *buf++ = buf_c00[x];
      y++;
      if(y >= 0x200) {
        break;
      }

      *buf++ = buf_d00[x];
      y++;
      if(y >= 0x200) {
        break;
      }

      *buf++ = buf_e00[x];
      y++;
      if(y >= 0x200) {
        break;
      }
    }

    sector_done[phys_sec] = 1;
    num_sectors_done++;
    if(num_sectors_done >= num_sectors) {
      status = 0;
      break;
    }
    val = 0;
  }

  if(status < 0) {
    printf("dsk->nib_pos: %04x, status: %d\n", dsk->nib_pos,
           status);
    for(i = 0; i < num_sectors; i++) {
      printf("sector done[%d] = %d\n", i, sector_done[i]);
    }
  }

  iwm_move_to_track(dsk, save_qtr_track);
  dsk->nib_pos = save_nib_pos;
  g_fast_disk_unnib = 0;

  if(status == 0) {
    return 1;
  }

  printf("Nibblization not done, %02x sectors found on track %02x\n",
         num_sectors_done, qtr_track>>2);
  return -1;



}

/* ret = 1 -> dirty data written out */
/* ret = 0 -> not dirty, no error */
/* ret < 0 -> error */
int disk_track_to_unix(Disk *dsk, int qtr_track, byte *outbuf)     {
  int i;
  Trk     *trk;
  int disk_525;

  disk_525 = dsk->disk_525;

  trk = &(dsk->trks[qtr_track]);

  if(trk->track_len == 0 || trk->track_dirty == 0) {
    return 0;
  }

  trk->track_dirty = 0;

  if((qtr_track & 3) && disk_525) {
    halt_printf("You wrote to phase %02x!  Can't wr bk to unix!\n",
                qtr_track);
    dsk->write_through_to_unix = 0;
    return -1;
  }

  if(disk_525)
  {
    // OG
    // Add support for .nib file
    if (dsk->image_type!=DSK_TYPE_NIB)
      return iwm_denib_track525(dsk, trk, qtr_track, outbuf);
    else
    {
      int len = trk->track_len;
      byte* trk_ptr = trk->nib_area+1;
      byte* nib_ptr = outbuf;
      for(i = 0; i < len; i += 2)
      {
        *nib_ptr++ = *trk_ptr;
        trk_ptr+=2;
      }
      return 1;
    }
  } else {
    return iwm_denib_track35(dsk, trk, qtr_track, outbuf);
  }
}


void show_hex_data(byte *buf, int count)      {
  int i;

  for(i = 0; i < count; i += 16) {
    printf("%04x: %02x %02x %02x %02x %02x %02x %02x %02x "
           "%02x %02x %02x %02x %02x %02x %02x %02x\n", i,
           buf[i+0], buf[i+1], buf[i+2], buf[i+3],
           buf[i+4], buf[i+5], buf[i+6], buf[i+7],
           buf[i+8], buf[i+9], buf[i+10], buf[i+11],
           buf[i+12], buf[i+13], buf[i+14], buf[i+15]);
  }

}

void disk_check_nibblization(Disk *dsk, int qtr_track, byte *buf, int size)      {
  byte buffer[0x3000];
  Trk     *trk;
  int ret, ret2;
  int i;

  if(size > 0x3000) {
    printf("size %08x is > 0x3000, disk_check_nibblization\n",size);
    exit(3);
  }

  for(i = 0; i < size; i++) {
    buffer[i] = 0;
  }

  trk = &(dsk->trks[qtr_track]);

  if(dsk->disk_525) {
    ret = iwm_denib_track525(dsk, trk, qtr_track, &(buffer[0]));
  } else {
    ret = iwm_denib_track35(dsk, trk, qtr_track, &(buffer[0]));
  }

  ret2 = -1;
  for(i = 0; i < size; i++) {
    if(buffer[i] != buf[i]) {
      printf("buffer[%04x]: %02x != %02x\n", i, buffer[i],
             buf[i]);
      ret2 = i;
      break;
    }
  }

  if(ret != 1 || ret2 >= 0) {
    printf("disk_check_nib ret:%d, ret2:%d for q_track %03x\n",
           ret, ret2, qtr_track);
    show_hex_data(buf, 0x1000);
    show_hex_data(buffer, 0x1000);
    iwm_show_a_track(&(dsk->trks[qtr_track]));

    exit(2);
  }
}


#define TRACK_BUF_LEN           0x2000

void disk_unix_to_nib(Disk *dsk, int qtr_track, int unix_pos, int unix_len,
                      int nib_len) {
  byte track_buf[TRACK_BUF_LEN];
  Trk     *trk;
  int must_clear_track;
  int ret;
  int len;
  int i;

  /* Read track from dsk int track_buf */

  must_clear_track = 0;

  if(unix_len > TRACK_BUF_LEN) {
    printf("diks_unix_to_nib: requested len of image %s = %05x\n",
           dsk->name_ptr, unix_len);
  }

  if(unix_pos >= 0) {
    ret = fseek(dsk->file, unix_pos, SEEK_SET);
    if(ret != 0) {
      printf("fseek of disk %s len 0x%x errno: %d\n",
             dsk->name_ptr, unix_pos, errno);
      must_clear_track = 1;
    }

    len = fread(track_buf, 1, unix_len, dsk->file);
    if(len != unix_len) {
      printf("read of disk %s q_trk %d ret: %d, errno: %d\n",
             dsk->name_ptr, qtr_track, ret, errno);
      must_clear_track = 1;
    }
  }

  if(must_clear_track) {
    for(i = 0; i < TRACK_BUF_LEN; i++) {
      track_buf[i] = 0;
    }
  }

#if 0
  printf("Q_track %02x dumped out\n", qtr_track);

  for(i = 0; i < 4096; i += 32) {
    printf("%04x: %02x%02x%02x%02x%02x%02x%02x%02x "
           "%02x%02x%02x%02x%02x%02x%02x%02x "
           "%02x%02x%02x%02x%02x%02x%02x%02x "
           "%02x%02x%02x%02x%02x%02x%02x%02x\n", i,
           track_buf[i+0], track_buf[i+1], track_buf[i+2],
           track_buf[i+3], track_buf[i+4], track_buf[i+5],
           track_buf[i+6], track_buf[i+7], track_buf[i+8],
           track_buf[i+9], track_buf[i+10], track_buf[i+11],
           track_buf[i+12], track_buf[i+13], track_buf[i+14],
           track_buf[i+15], track_buf[i+16], track_buf[i+17],
           track_buf[i+18], track_buf[i+19], track_buf[i+20],
           track_buf[i+21], track_buf[i+22], track_buf[i+23],
           track_buf[i+24], track_buf[i+25], track_buf[i+26],
           track_buf[i+27], track_buf[i+28], track_buf[i+29],
           track_buf[i+30], track_buf[i+31]);
  }
#endif

  dsk->nib_pos = 0;                     /* for consistency */

  trk = &(dsk->trks[qtr_track]);
  trk->track_dirty = 0;
  trk->overflow_size = 0;
  trk->track_len = 2*nib_len;
  trk->unix_pos = unix_pos;
  trk->unix_len = unix_len;
  trk->dsk = dsk;
  trk->nib_area = (byte *)malloc(trk->track_len);

  /* create nibblized image */

  if(dsk->disk_525 && dsk->image_type == DSK_TYPE_NIB) {
    iwm_nibblize_track_nib525(dsk, trk, track_buf, qtr_track);
  } else if(dsk->disk_525) {
    iwm_nibblize_track_525(dsk, trk, track_buf, qtr_track);
  } else {
    iwm_nibblize_track_35(dsk, trk, track_buf, qtr_track);
  }
}

void iwm_nibblize_track_nib525(Disk *dsk, Trk *trk, byte *track_buf, int qtr_track)      {
  byte    *nib_ptr;
  byte    *trk_ptr;
  int len;
  int i;

  len = trk->track_len;
  trk_ptr = track_buf;
  nib_ptr = &(trk->nib_area[0]);
  for(i = 0; i < len; i += 2) {
    nib_ptr[i] = 8;
    nib_ptr[i+1] = *trk_ptr++;;
  }

  iwm_printf("Nibblized q_track %02x\n", qtr_track);
}

void iwm_nibblize_track_525(Disk *dsk, Trk *trk, byte *track_buf, int qtr_track)      {
  byte partial_nib_buf[0x300];
  word32  *word_ptr;
  word32 val;
  word32 last_val;
  int phys_sec;
  int log_sec;
  int num_sync;
  int i;


  word_ptr = (word32 *)&(trk->nib_area[0]);
#if defined(GSPLUS_LITTLE_ENDIAN) || defined (__LITTLE_ENDIAN__) // OSX needs to calculate endianness mid-compilation, can't be passed on compile command
  val = 0xff08ff08;
#else
  val = 0x08ff08ff;
#endif
  for(i = 0; i < trk->track_len; i += 4) {
    *word_ptr++ = val;
  }


  for(phys_sec = 0; phys_sec < 16; phys_sec++) {
    if(dsk->image_type == DSK_TYPE_DOS33) {
      log_sec = phys_to_dos_sec[phys_sec];
    } else {
      log_sec = phys_to_prodos_sec[phys_sec];
    }

    /* Create sync headers */
    if(phys_sec == 0) {
      num_sync = 70;
    } else {
      num_sync = 14;
    }

    for(i = 0; i < num_sync; i++) {
      disk_nib_out(dsk, 0xff, 10);
    }
    disk_nib_out(dsk, 0xd5, 10);                        /* prolog */
    disk_nib_out(dsk, 0xaa, 8);                         /* prolog */
    disk_nib_out(dsk, 0x96, 8);                         /* prolog */
    disk_4x4_nib_out(dsk, dsk->vol_num);
    disk_4x4_nib_out(dsk, qtr_track >> 2);
    disk_4x4_nib_out(dsk, phys_sec);
    disk_4x4_nib_out(dsk, dsk->vol_num ^ (qtr_track>>2) ^ phys_sec);
    disk_nib_out(dsk, 0xde, 8);                         /* epi */
    disk_nib_out(dsk, 0xaa, 8);                         /* epi */
    disk_nib_out(dsk, 0xeb, 8);                         /* epi */

    /* Inter sync */
    disk_nib_out(dsk, 0xff, 8);
    for(i = 0; i < 5; i++) {
      disk_nib_out(dsk, 0xff, 10);
    }
    disk_nib_out(dsk, 0xd5, 10);                /* data prolog */
    disk_nib_out(dsk, 0xaa, 8);                 /* data prolog */
    disk_nib_out(dsk, 0xad, 8);                 /* data prolog */

    sector_to_partial_nib( &(track_buf[log_sec*256]),
                           &(partial_nib_buf[0]));

    last_val = 0;
    for(i = 0; i < 0x156; i++) {
      val = partial_nib_buf[i];
      disk_nib_out(dsk, to_disk_byte[last_val ^ val], 8);
      last_val = val;
    }
    disk_nib_out(dsk, to_disk_byte[last_val], 8);

    /* data epilog */
    disk_nib_out(dsk, 0xde, 8);                 /* epi */
    disk_nib_out(dsk, 0xaa, 8);                 /* epi */
    disk_nib_out(dsk, 0xeb, 8);                 /* epi */
    disk_nib_out(dsk, 0xff, 8);
    for(i = 0; i < 6; i++) {
      disk_nib_out(dsk, 0xff, 10);
    }
  }

  /* finish nibblization */
  disk_nib_end_track(dsk);

  iwm_printf("Nibblized q_track %02x\n", qtr_track);

  if(g_check_nibblization) {
    disk_check_nibblization(dsk, qtr_track, &(track_buf[0]),0x1000);
  }
}

void iwm_nibblize_track_35(Disk *dsk, Trk *trk, byte *track_buf, int qtr_track)      {
  int phys_to_log_sec[16];
  word32 buf_c00[0x100];
  word32 buf_d00[0x100];
  word32 buf_e00[0x100];
  byte    *buf;
  word32  *word_ptr;
  word32 val;
  int num_sectors;
  int unix_len;
  int log_sec;
  int phys_sec;
  int track;
  int side;
  int interleave;
  int num_sync;
  word32 phys_track, phys_side, capacity, cksum;
  word32 tmp_5c, tmp_5d, tmp_5e, tmp_5f;
  word32 tmp_63, tmp_64, tmp_65;
  word32 acc_hi;
  int carry;
  int x, y;
  int i;

  word_ptr = (word32 *)&(trk->nib_area[0]);
#if defined(GSPLUS_LITTLE_ENDIAN) || defined (__LITTLE_ENDIAN__)
  val = 0xff08ff08;
#else
  val = 0x08ff08ff;
#endif
  if(trk->track_len & 3) {
    halt_printf("track_len: %08x is not a multiple of 4\n",
                trk->track_len);
  }

  for(i = 0; i < trk->track_len; i += 4) {
    *word_ptr++ = val;
  }

  unix_len = trk->unix_len;

  num_sectors = (unix_len >> 9);

  for(i = 0; i < num_sectors; i++) {
    phys_to_log_sec[i] = -1;
  }

  phys_sec = 0;
  interleave = 2;
  for(log_sec = 0; log_sec < num_sectors; log_sec++) {
    while(phys_to_log_sec[phys_sec] >= 0) {
      phys_sec++;
      if(phys_sec >= num_sectors) {
        phys_sec = 0;
      }
    }
    phys_to_log_sec[phys_sec] = log_sec;
    phys_sec += interleave;
    if(phys_sec >= num_sectors) {
      phys_sec -= num_sectors;
    }
  }

  track = qtr_track >> 1;
  side = qtr_track & 1;
  for(phys_sec = 0; phys_sec < num_sectors; phys_sec++) {

    log_sec = phys_to_log_sec[phys_sec];
    if(log_sec < 0) {
      printf("Track: %02x.%x phys_sec: %02x = %d!\n",
             track, side, phys_sec, log_sec);
      exit(2);
    }

    /* Create sync headers */
    if(phys_sec == 0) {
      num_sync = 400;
    } else {
      num_sync = 54;
    }

    for(i = 0; i < num_sync; i++) {
      disk_nib_out(dsk, 0xff, 10);
    }

    disk_nib_out(dsk, 0xd5, 10);                        /* prolog */
    disk_nib_out(dsk, 0xaa, 8);                         /* prolog */
    disk_nib_out(dsk, 0x96, 8);                         /* prolog */

    phys_track = track & 0x3f;
    phys_side = (side << 5) + (track >> 6);
    capacity = 0x22;
    disk_nib_out(dsk, to_disk_byte[phys_track], 8);             /* trk */
    disk_nib_out(dsk, to_disk_byte[log_sec], 8);                /* sec */
    disk_nib_out(dsk, to_disk_byte[phys_side], 8);              /* sides+trk */
    disk_nib_out(dsk, to_disk_byte[capacity], 8);               /* capacity*/

    cksum = (phys_track ^ log_sec ^ phys_side ^ capacity) & 0x3f;
    disk_nib_out(dsk, to_disk_byte[cksum], 8);                  /* cksum*/

    disk_nib_out(dsk, 0xde, 8);                         /* epi */
    disk_nib_out(dsk, 0xaa, 8);                         /* epi */

    /* Inter sync */
    for(i = 0; i < 5; i++) {
      disk_nib_out(dsk, 0xff, 10);
    }
    disk_nib_out(dsk, 0xd5, 10);                /* data prolog */
    disk_nib_out(dsk, 0xaa, 8);                 /* data prolog */
    disk_nib_out(dsk, 0xad, 8);                 /* data prolog */
    disk_nib_out(dsk, to_disk_byte[log_sec], 8);                /* sec again */

    /* do nibblizing! */
    buf = track_buf + (log_sec << 9);

/* 6320 */
    tmp_5e = 0;
    tmp_5d = 0;
    tmp_5c = 0;
    y = 0;
    x = 0xaf;
    buf_c00[0] = 0;
    buf_d00[0] = 0;
    buf_e00[0] = 0;
    buf_e00[1] = 0;
    for(y = 0x4; y > 0; y--) {
      buf_c00[x] = 0;
      buf_d00[x] = 0;
      buf_e00[x] = 0;
      x--;
    }

    while(x >= 0) {
/* 6338 */
      tmp_5c = tmp_5c << 1;
      carry = (tmp_5c >> 8);
      tmp_5c = (tmp_5c + carry) & 0xff;

      val = buf[y];
      tmp_5e = val + tmp_5e + carry;
      carry = (tmp_5e >> 8);
      tmp_5e = tmp_5e & 0xff;

      val = val ^ tmp_5c;
      buf_c00[x] = val;
      y++;
/* 634c */
      val = buf[y];
      tmp_5d = tmp_5d + val + carry;
      carry = (tmp_5d >> 8);
      tmp_5d = tmp_5d & 0xff;
      val = val ^ tmp_5e;
      buf_d00[x] = val;
      y++;
      x--;
      if(x <= 0) {
        break;
      }

/* 632a */
      val = buf[y];
      tmp_5c = tmp_5c + val + carry;
      carry = (tmp_5c >> 8);
      tmp_5c = tmp_5c & 0xff;

      val = val ^ tmp_5d;
      buf_e00[x+1] = val;
      y++;
    }

/* 635f */
    val = ((tmp_5c >> 2) ^ tmp_5d) & 0x3f;
/* 6367 */
    val = (val ^ tmp_5d) >> 2;
/* 636b */
    val = (val ^ tmp_5e) & 0x3f;
/* 636f */
    val = (val ^ tmp_5e) >> 2;
/* 6373 */
    tmp_5f = val;
/* 6375 */
    tmp_63 = 0;
    tmp_64 = 0;
    tmp_65 = 0;
    acc_hi = 0;


    y = 0xae;
    while(y >= 0) {
/* 63e4 */
      /* write out acc_hi */
      val = to_disk_byte[acc_hi & 0x3f];
      disk_nib_out(dsk, val, 8);

/* 63f2 */
      val = to_disk_byte[tmp_63 & 0x3f];
      tmp_63 = buf_c00[y];
      acc_hi = tmp_63 >> 6;
      disk_nib_out(dsk, val, 8);
/* 640b */
      val = to_disk_byte[tmp_64 & 0x3f];
      tmp_64 = buf_d00[y];
      acc_hi = (acc_hi << 2) + (tmp_64 >> 6);
      disk_nib_out(dsk, val, 8);
      y--;
      if(y < 0) {
        break;
      }

/* 63cb */
      val = to_disk_byte[tmp_65 & 0x3f];
      tmp_65 = buf_e00[y+1];
      acc_hi = (acc_hi << 2) + (tmp_65 >> 6);
      disk_nib_out(dsk, val, 8);
    }
/* 6429 */
    val = to_disk_byte[tmp_5f & 0x3f];
    disk_nib_out(dsk, val, 8);

    val = to_disk_byte[tmp_5e & 0x3f];
    disk_nib_out(dsk, val, 8);

    val = to_disk_byte[tmp_5d & 0x3f];
    disk_nib_out(dsk, val, 8);

    val = to_disk_byte[tmp_5c & 0x3f];
    disk_nib_out(dsk, val, 8);

/* 6440 */
    /* data epilog */
    disk_nib_out(dsk, 0xde, 8);                 /* epi */
    disk_nib_out(dsk, 0xaa, 8);                 /* epi */
    disk_nib_out(dsk, 0xff, 8);
  }


  disk_nib_end_track(dsk);

  if(g_check_nibblization) {
    disk_check_nibblization(dsk, qtr_track, &(track_buf[0]),
                            unix_len);
  }
}

void disk_4x4_nib_out(Disk *dsk, word32 val)      {
  disk_nib_out(dsk, 0xaa | (val >> 1), 8);
  disk_nib_out(dsk, 0xaa | val, 8);
}

void disk_nib_out(Disk *dsk, byte val, int size)      {
  Trk     *trk;
  int pos;
  int old_size;
  int track_len;
  int overflow_size;
  int qtr_track;


  qtr_track = dsk->cur_qtr_track;

  track_len = 0;
  trk = 0;
  if(dsk->trks != 0) {
    trk = &(dsk->trks[qtr_track]);
    track_len = trk->track_len;
  }

  if(track_len <= 10) {
    printf("Writing to an invalid qtr track: %02x!\n", qtr_track);
    printf("name: %s, track_len: %08x, val: %08x, size: %d\n",
           dsk->name_ptr, track_len, val, size);
    exit(1);
    return;
  }

  trk->track_dirty = 1;
  dsk->disk_dirty = 1;

  pos = trk->dsk->nib_pos;
  overflow_size = trk->overflow_size;
  if(pos >= track_len) {
    pos = 0;
  }

  old_size = trk->nib_area[pos];


  while(size >= (10 + old_size)) {
    size = size - old_size;
    pos += 2;
    if(pos >= track_len) {
      pos = 0;
    }
    old_size = trk->nib_area[pos];
  }

  if(size > 10) {
    size = 10;
  }

  if((val & 0x80) == 0) {
    val |= 0x80;
  }

  trk->nib_area[pos++] = size;
  trk->nib_area[pos++] = val;
  if(pos >= track_len) {
    pos = 0;
  }

  overflow_size += (size - old_size);
  if((overflow_size > 8) && (size > 8)) {
    overflow_size -= trk->nib_area[pos];
    trk->nib_area[pos++] = 0;
    trk->nib_area[pos++] = 0;
    if(pos >= track_len) {
      pos = 0;
    }
  } else if(overflow_size < -64) {
    halt_printf("overflow_sz:%03x, pos:%02x\n",overflow_size,pos);
  }

  trk->dsk->nib_pos = pos;
  trk->overflow_size = overflow_size;

  if((val & 0x80) == 0 || size < 8) {
    halt_printf("disk_nib_out, wrote %02x, size: %d\n", val, size);
  }
}

void disk_nib_end_track(Disk *dsk)      {
  int qtr_track;

  dsk->nib_pos = 0;
  qtr_track = dsk->cur_qtr_track;
  dsk->trks[qtr_track].track_dirty = 0;

  dsk->disk_dirty = 0;
}

void iwm_show_track(int slot_drive, int track)      {
  Disk    *dsk;
  Trk     *trk;
  int drive;
  int sel35;
  int qtr_track;

  if(slot_drive < 0) {
    drive = iwm.drive_select;
    sel35 = (g_c031_disk35 >> 6) & 1;
  } else {
    drive = slot_drive & 1;
    sel35 = !((slot_drive >> 1) & 1);
  }

  if(sel35) {
    dsk = &(iwm.drive35[drive]);
  } else {
    dsk = &(iwm.drive525[drive]);
  }

  if(track < 0) {
    qtr_track = dsk->cur_qtr_track;
  } else {
    qtr_track = track;
  }
  if(dsk->trks == 0) {
    return;
  }
  trk = &(dsk->trks[qtr_track]);

  if(trk->track_len <= 0) {
    printf("Track_len: %d\n", trk->track_len);
    printf("No track for type: %d, drive: %d, qtrk: 0x%02x\n",
           sel35, drive, qtr_track);
    return;
  }

  printf("Current drive: %d, q_track: 0x%02x\n", drive, qtr_track);

  iwm_show_a_track(trk);
}

void iwm_show_a_track(Trk *trk)      {
  int sum;
  int len;
  int pos;
  int i;

  printf("  Showtrack:dirty: %d, pos: %04x, ovfl: %04x, len: %04x\n",
         trk->track_dirty, trk->dsk->nib_pos,
         trk->overflow_size, trk->track_len);

  len = trk->track_len;
  printf("Track len in bytes: %04x\n", len);
  if(len >= 2*15000) {
    len = 2*15000;
    printf("len too big, using %04x\n", len);
  }

  pos = 0;
  for(i = 0; i < len; i += 16) {
    printf("%04x: %2d,%02x %2d,%02x %2d,%02x %2d,%02x "
           "%2d,%02x %2d,%02x %2d,%02x %2d,%02x\n", pos,
           trk->nib_area[pos], trk->nib_area[pos+1],
           trk->nib_area[pos+2], trk->nib_area[pos+3],
           trk->nib_area[pos+4], trk->nib_area[pos+5],
           trk->nib_area[pos+6], trk->nib_area[pos+7],
           trk->nib_area[pos+8], trk->nib_area[pos+9],
           trk->nib_area[pos+10], trk->nib_area[pos+11],
           trk->nib_area[pos+12], trk->nib_area[pos+13],
           trk->nib_area[pos+14], trk->nib_area[pos+15]);
    pos += 16;
    if(pos >= len) {
      pos -= len;
    }
  }

  sum = 0;
  for(i = 0; i < len; i += 2) {
    sum += trk->nib_area[i];
  }

  printf("bit_sum: %d, expected: %d, overflow_size: %d\n",
         sum, len*8/2, trk->overflow_size);
}


/* AJS */
#include <time.h>

int Verbose=0;
void halt_printf(const char *fmt, ...)      {
  va_list args;

  va_start(args, fmt);
  vprintf(fmt, args);
  va_end(args);

//  set_halt(1);
}

int glog(const char *s) {
  time_t timer;
  char buffer[26];
  struct tm* tm_info;

  time(&timer);
  tm_info = localtime(&timer);

  strftime(buffer, 26, "%Y-%m-%d %H:%M:%S", tm_info);
  printf("%s - %s\n", buffer, s);

  return 0;
}


int glogf(const char *fmt, ...) {

  time_t timer;
  char buffer[26];
  struct tm* tm_info;

  time(&timer);
  tm_info = localtime(&timer);

  strftime(buffer, 26, "%Y-%m-%d %H:%M:%S", tm_info);

  printf("%s - ", buffer);

  va_list ap;
  va_start(ap, fmt);
  vprintf(fmt, ap);
  va_end(ap);
  fputc('\n', stdout);
  return 0;
}

void set_halt_act(int a) {
	printf("set_halt %x\n",a);
}

void iwm_load_disk()
{
//	insert_disk slot 5 drive 0 name TD2.2mg ejected 0 force_size 0 partition_name (null) part_num -1

    //insert_disk(5, 0, "TD2.2mg", 0, 0, NULL, -1);
    insert_disk(6, 0, "A2eDiagnostics_v2.1.dsk", 0, 0, NULL, -1);
}
// BBBB
int g_highest_smartport_unit = -1;
int g_config_gsplus_update_needed = 0;
#define fatal_printf printf

void eject_named_disk(Disk *dsk, const char *name, const char *partition_name)      {

  if(!dsk->file) {
    return;
  }

  /* If name matches, eject the disk! */
  if(!strcmp(dsk->name_ptr, name)) {
    /* It matches, eject it */
    if((partition_name != 0) && (dsk->partition_name != 0)) {
      /* If both have partitions, and they differ, then */
      /*  don't eject.  Otherwise, eject */
      if(strcmp(dsk->partition_name, partition_name) != 0) {
        /* Don't eject */
        return;
      }
    }
    eject_disk(dsk);
  }
}

void eject_disk_by_num(int slot, int drive)      {
  Disk    *dsk;

  dsk = cfg_get_dsk_from_slot_drive(slot, drive);

  eject_disk(dsk);
}

void eject_disk(Disk *dsk)      {
  int motor_on;
  int i;

  if(!dsk->file) {
    return;
  }

  g_config_gsplus_update_needed = 1;

  motor_on = iwm.motor_on;
  if(g_c031_disk35 & 0x40) {
    motor_on = iwm.motor_on35;
  }
  if(motor_on) {
    halt_printf("Try eject dsk:%s, but motor_on!\n", dsk->name_ptr);
  }

  iwm_flush_disk_to_unix(dsk);

  glogf("Ejecting disk: %s", dsk->name_ptr);

  /* Free all memory, close file */

  /* free the tracks first */
  if(dsk->trks != 0) {
    for(i = 0; i < dsk->num_tracks; i++) {
      if(dsk->trks[i].nib_area) {
        free(dsk->trks[i].nib_area);
      }
      dsk->trks[i].nib_area = 0;
      dsk->trks[i].track_len = 0;
    }
    free(dsk->trks);
  }
  dsk->num_tracks = 0;
  dsk->trks = 0;

  /* close file, clean up dsk struct */
  fclose(dsk->file);

  dsk->image_start = 0;
  dsk->image_size = 0;
  dsk->nib_pos = 0;
  dsk->disk_dirty = 0;
  dsk->write_through_to_unix = 0;
  dsk->write_prot = 1;
  dsk->file = 0;
  dsk->just_ejected = 1;

  /* Leave name_ptr valid */
}
Disk *cfg_get_dsk_from_slot_drive(int slot, int drive)       {
  Disk    *dsk;
  int max_drive;

  /* Get dsk */
  max_drive = 2;
  switch(slot) {
    case 5:
      dsk = &(iwm.drive35[drive]);
      break;
    case 6:
      dsk = &(iwm.drive525[drive]);
      break;
    default:
      max_drive = MAX_C7_DISKS;
      dsk = &(iwm.smartport[drive]);
  }

  if(drive >= max_drive) {
    dsk -= drive;               /* move back to drive 0 effectively */
  }

  return dsk;
}
int cfg_partition_find_by_name_or_num(FILE *file, const char *partnamestr, int part_num,
                                      Disk *dsk) {
  Cfg_dirent *direntptr;
  int match;
  int num_parts;
  int i;

  return -1;
#if 0

  num_parts = cfg_partition_make_list(dsk->name_ptr, file);
  if(num_parts <= 0) {
    return -1;
  }

  for(i = 0; i < g_cfg_partitionlist.last; i++) {
    direntptr = &(g_cfg_partitionlist.direntptr[i]);
    match = 0;
    if((strncmp(partnamestr, direntptr->name, 32) == 0) &&
       (part_num < 0)) {
      //printf("partition, match1, name:%s %s, part_num:%d\n",
      //	partnamestr, direntptr->name, part_num);

      match = 1;
    }
    if((partnamestr == 0) && (direntptr->part_num == part_num)) {
      //printf("partition, match2, n:%s, part_num:%d == %d\n",
      //	direntptr->name, direntptr->part_num, part_num);
      match = 1;
    }
    if(match) {
      dsk->image_start = direntptr->image_start;
      dsk->image_size = direntptr->size;
      //printf("match with image_start: %08x, image_size: "
      //	"%08x\n", dsk->image_start, dsk->image_size);

      return i;
    }
  }

  return -1;
#endif
}

int cfg_get_fd_size(char *filename)     {
  struct stat stat_buf;
  int ret;

  ret = stat(filename, &stat_buf);
  if(ret != 0) {
    fprintf(stderr,"stat %s returned errno: %d\n",
            filename, errno);
    stat_buf.st_size = 0;
  }

  return stat_buf.st_size;
}


void insert_disk(int slot, int drive, const char *name, int ejected, int force_size,
                 const char *partition_name, int part_num) {
  byte buf_2img[512];
  Disk    *dsk;
  char    *name_ptr, *uncomp_ptr, *system_str;
  char    *part_ptr;
  int size;
  int system_len;
  int part_len;
  int cmp_o, cmp_p, cmp_dot;
  int cmp_b, cmp_i, cmp_n;
  int can_write;
  int len = 0;
  int nibs;
  int unix_pos;
  int name_len;
  int image_identified;
  int exp_size;
  int save_track;
  int ret;
  int tmp;
  int i;

  g_config_gsplus_update_needed = 1;

  if((slot < 5) || (slot > 7)) {
    fatal_printf("Invalid slot for inserting disk: %d\n", slot);
    return;
  }
  if(drive < 0 || ((slot == 7) && (drive >= MAX_C7_DISKS)) ||
     ((slot < 7) && (drive > 1))) {
    fatal_printf("Invalid drive for inserting disk: %d\n", drive);
    return;
  }

  dsk = cfg_get_dsk_from_slot_drive(slot, drive);

#if 1
  printf("Inserting disk %s (%s or %d) in slot %d, drive: %d\n", name,
         partition_name, part_num, slot, drive);
#endif

  dsk->just_ejected = 0;
  dsk->force_size = force_size;

  if(!dsk->file) {
    eject_disk(dsk);
  }

  /* Before opening, make sure no other mounted disk has this name */
  /* If so, unmount it */
  if(!ejected) {
    for(i = 0; i < 2; i++) {
      eject_named_disk(&iwm.drive525[i], name,partition_name);
      eject_named_disk(&iwm.drive35[i], name, partition_name);
    }
    for(i = 0; i < MAX_C7_DISKS; i++) {
      eject_named_disk(&iwm.smartport[i],name,partition_name);
    }
  }

  if(dsk->name_ptr != 0) {
    /* free old name_ptr */
    free(dsk->name_ptr);
  }

  name_len = strlen(name);
  name_ptr = (char *)malloc(name_len + 1);
#if defined(_WIN32)
  // On Windows, we need to change backslashes to forward slashes.
  for (i = 0; i < name_len; i++) {
    if (name[i] == '\\') {
      name_ptr[i] = '/';
    } else {
      name_ptr[i] = name[i];
    }
  }
  name_ptr[name_len] = 0;
#else
  strncpy(name_ptr, name, name_len + 1);
#endif
  dsk->name_ptr = name_ptr;

  dsk->partition_name = 0;
  if(partition_name != 0) {
    part_len = strlen(partition_name) + 1;
    part_ptr = (char *)malloc(part_len);
    strncpy(part_ptr, partition_name, part_len);
    dsk->partition_name = part_ptr;
  }
  dsk->partition_num = part_num;

  iwm_printf("Opening up disk image named: %s\n", name_ptr);

  if(ejected) {
    /* just get out of here */
    dsk->file = 0;
    return;
  }

  dsk->file = 0;
  can_write = 1;

  if((name_len > 3) && (strcmp(&name_ptr[name_len - 3], ".gz") == 0)) {

    /* it's gzip'ed, try to gunzip it, then unlink the */
    /*   uncompressed file */

    can_write = 0;

    uncomp_ptr = (char *)malloc(name_len + 1);
    strncpy(uncomp_ptr, name_ptr, name_len + 1);
    uncomp_ptr[name_len - 3] = 0;

    system_len = 2*name_len + 100;
    system_str = (char *)malloc(system_len + 1);
    snprintf(system_str, system_len,
             "set -o noclobber;gunzip -c %c%s%c > %c%s%c",
             0x22, name_ptr, 0x22,
             0x22, uncomp_ptr, 0x22);
    /* 0x22 are " to allow spaces in filenames */
    printf("I am uncompressing %s into %s for mounting\n",
           name_ptr, uncomp_ptr);
    ret = system(system_str);
    if(ret == 0) {
      /* successfully ran */
      dsk->file = fopen(uncomp_ptr, "rb");
      iwm_printf("Opening .gz file %s\n",     uncomp_ptr);

      /* and, unlink the temporary file */
      (void)unlink(uncomp_ptr);
    }
    free(system_str);
    free(uncomp_ptr);
    /* Reduce name_len by 3 so that subsequent compares for .po */
    /*  look at the correct chars */
    name_len -= 3;
  }

  if((!dsk->file) && can_write) {
    dsk->file = fopen(name_ptr, "rb+");
  }

  if((!dsk->file) && can_write) {
    printf("Trying to open %s read-only, errno: %d\n", name_ptr,
           errno);
    dsk->file = fopen(name_ptr, "rb");
    can_write = 0;
  }

  if(!dsk->file) {
    fatal_printf("Disk image %s does not exist!\n", name_ptr);
    return;
  }

  if(can_write != 0) {
    dsk->write_prot = 0;
    dsk->write_through_to_unix = 1;
  } else {
    dsk->write_prot = 1;
    dsk->write_through_to_unix = 0;
  }

  save_track = dsk->cur_qtr_track;              /* save arm position */
  dsk->image_type = DSK_TYPE_PRODOS;
  dsk->image_start = 0;

  /* See if it is in 2IMG format */
  ret = fread((char *)&buf_2img[0], 1, 512, dsk->file);
  size = force_size;
  if(size <= 0) {
    size = cfg_get_fd_size(name_ptr);
  }

  /* Try to guess that there is a Mac Binary header of 128 bytes */
  /* See if image size & 0xfff = 0x080 which indicates extra 128 bytes */
  if((size & 0xfff) == 0x080) {
    printf("Assuming Mac Binary header on %s\n", dsk->name_ptr);
    dsk->image_start += 0x80;
  }
  image_identified = 0;
  if(buf_2img[0] == '2' && buf_2img[1] == 'I' && buf_2img[2] == 'M' &&
     buf_2img[3] == 'G') {
    /* It's a 2IMG disk */
    glogf("Image named %s is in 2IMG format", dsk->name_ptr);
    image_identified = 1;

    if(buf_2img[12] == 0) {
      glog("2IMG is in DOS 3.3 sector order");
      dsk->image_type = DSK_TYPE_DOS33;
    }
    if(buf_2img[19] & 0x80) {
      /* disk is locked */
      glog("2IMG is write protected");
      dsk->write_prot = 1;
      dsk->write_through_to_unix = 0;
    }
    if((buf_2img[17] & 1) && (dsk->image_type == DSK_TYPE_DOS33)) {
      dsk->vol_num = buf_2img[16];
      glogf("Setting DOS 3.3 vol num to %d", dsk->vol_num);
    }
    //	Some 2IMG archives have the size byte reversed
    size = (buf_2img[31] << 24) + (buf_2img[30] << 16) +
           (buf_2img[29] << 8) + buf_2img[28];
    unix_pos = (buf_2img[27] << 24) + (buf_2img[26] << 16) +
               (buf_2img[25] << 8) + buf_2img[24];
    if(size == 0x800c00) {
      //	Byte reversed 0x0c8000
      size = 0x0c8000;
    }
    dsk->image_start = unix_pos;
    dsk->image_size = size;
  }
  exp_size = 800*1024;
  if(dsk->disk_525) {
    exp_size = 140*1024;
  }
  if(!image_identified) {
    /* See if it might be the Mac diskcopy format */
    tmp = (buf_2img[0x40] << 24) + (buf_2img[0x41] << 16) +
          (buf_2img[0x42] << 8) + buf_2img[0x43];
    if((size >= (exp_size + 0x54)) && (tmp == exp_size)) {
      /* It's diskcopy since data size field matches */
      glogf("Image named %s is in Mac diskcopy format", dsk->name_ptr);
      image_identified = 1;
      dsk->image_start += 0x54;
      dsk->image_size = exp_size;
      dsk->image_type = DSK_TYPE_PRODOS;                        /* ProDOS */
    }
  }
  if(!image_identified) {
    /* Assume raw image */
    dsk->image_size = size;
    dsk->image_type = DSK_TYPE_PRODOS;
    if(dsk->disk_525) {
      dsk->image_type = DSK_TYPE_DOS33;
      if(name_len >= 4) {
        cmp_o = dsk->name_ptr[name_len-1];
        cmp_p = dsk->name_ptr[name_len-2];
        cmp_dot = dsk->name_ptr[name_len-3];
        if(cmp_dot == '.' &&
           (cmp_p == 'p' || cmp_p == 'P') &&
           (cmp_o == 'o' || cmp_o == 'O')) {
          dsk->image_type = DSK_TYPE_PRODOS;
        }

        cmp_b = dsk->name_ptr[name_len-1];
        cmp_i = dsk->name_ptr[name_len-2];
        cmp_n = dsk->name_ptr[name_len-3];
        cmp_dot = dsk->name_ptr[name_len-4];
        if(cmp_dot == '.' &&
           (cmp_n == 'n' || cmp_n == 'N') &&
           (cmp_i == 'i' || cmp_i == 'I') &&
           (cmp_b == 'b' || cmp_b == 'B')) {
          dsk->image_type = DSK_TYPE_NIB;
          dsk->write_prot = 1;
          dsk->write_through_to_unix = 0;
        }
      }
    }
  }

  dsk->disk_dirty = 0;
  dsk->nib_pos = 0;
  dsk->trks = 0;

  if(dsk->smartport) {
    g_highest_smartport_unit = MAX(dsk->drive,
                                   g_highest_smartport_unit);

    if(partition_name != 0 || part_num >= 0) {
      ret = cfg_partition_find_by_name_or_num(dsk->file,
                                              partition_name, part_num, dsk);
      printf("partition %s (num %d) mounted, wr_prot: %d\n",
             partition_name, part_num, dsk->write_prot);

      if(ret < 0) {
        fclose(dsk->file);
        dsk->file = 0;
        return;
      }
    }
    iwm_printf("adding smartport device[%d], size:%08x, "
               "img_sz:%08x\n", dsk->drive, dsk->trks[0].unix_len,
               dsk->image_size);
  } else if(dsk->disk_525) {
    unix_pos = dsk->image_start;
    size = dsk->image_size;
    disk_set_num_tracks(dsk, 4*35);
    len = 0x1000;
    nibs = NIB_LEN_525;
    if(dsk->image_type == DSK_TYPE_NIB) {
      len = dsk->image_size / 35;;
      nibs = len;
    }
    if(size != 35*len) {
      glogf("Warning - Disk 5.25 error: size is %d, not 140K.  Will try to mount anyway", size, 35*len);
    }
    for(i = 0; i < 35; i++) {
      iwm_move_to_track(dsk, 4*i);
      disk_unix_to_nib(dsk, 4*i, unix_pos, len, nibs);
      unix_pos += len;
    }
  } else {
    /* disk_35 */
    unix_pos = dsk->image_start;
    size = dsk->image_size;
    if(size != 800*1024) {
      glogf("Warning - Disk 3.5 error: size is %d, not 800K.  Will try to mount anyway", size, 35*len);
    }
    disk_set_num_tracks(dsk, 2*80);
    for(i = 0; i < 2*80; i++) {
      iwm_move_to_track(dsk, i);
      len = g_track_bytes_35[i >> 5];
      nibs = g_track_nibs_35[i >> 5];
      iwm_printf("Trk: %d.%d = unix: %08x, %04x, %04x\n",
                 i>>1, i & 1, unix_pos, len, nibs);
      disk_unix_to_nib(dsk, i, unix_pos, len, nibs);
      unix_pos += len;

      iwm_printf(" trk_len:%05x\n", dsk->trks[i].track_len);
    }
  }

  iwm_move_to_track(dsk, save_track);

}

#if 0
// AAAAA

extern int Verbose;
extern word32 g_vbl_count;
extern Iwm iwm;

extern int g_track_bytes_35[];
extern int g_track_nibs_35[];
extern int g_c031_disk35;

extern int g_cur_a2_stat;
extern byte *g_slow_memory_ptr;
extern byte *g_rom_fc_ff_ptr;
extern byte *g_rom_cards_ptr;
extern double g_cur_dcycs;
extern int g_rom_version;

extern word32 g_adb_repeat_vbl;

extern int g_audio_enable;
extern int g_preferred_rate;
extern int g_fullscreen;
extern int g_highdpi;
extern int g_borderless;
extern int g_resizeable;
extern int g_noaspect;
extern int g_novsync;
extern int g_nohwaccel;
extern int g_fullscreen_desktop;
extern int g_screen_redraw_skip_amt;
extern int g_use_dhr140;
extern int g_use_bw_hires;
extern int g_scanline_simulator;
extern int g_startx;
extern int g_starty;
extern int g_startw;
extern int g_starth;
extern int g_joystick_number;
extern int g_joystick_x_axis;
extern int g_joystick_y_axis;
extern int g_joystick_x2_axis;
extern int g_joystick_y2_axis;
extern int g_joystick_button_0;
extern int g_joystick_button_1;
extern int g_joystick_button_2;
extern int g_joystick_button_3;


extern int g_halt_on_bad_read;
extern int g_ignore_bad_acc;
extern int g_ignore_halts;
extern int g_dbg_enable_port;

extern int halt_sim;
extern int g_limit_speed;
extern int g_force_depth;
extern int g_serial_type[];
extern int g_serial_out_masking;
extern int g_serial_modem[];
extern word32 g_mem_size_base;
extern word32 g_mem_size_exp;
extern int g_video_line_update_interval;
extern int g_video_extra_check_inputs;
extern int g_user_halt_bad;
extern int g_joystick_type;
extern int g_joystick_scale_factor_x;
extern int g_joystick_scale_factor_y;
extern int g_joystick_trim_amount_x;
extern int g_joystick_trim_amount_y;
extern int g_swap_paddles;
extern int g_invert_paddles;
extern int g_ethernet;
extern int g_ethernet_enabled;
extern char * g_ethernet_interface;
extern int g_appletalk_bridging;
extern int g_appletalk_turbo;
extern int g_appletalk_diagnostics;
extern int g_appletalk_network_hint;
extern int g_parallel;
extern int g_parallel_out_masking;
extern int g_printer;
extern int g_printer_dpi;
extern char* g_printer_output;
extern int g_printer_multipage;
extern char* g_printer_font_roman;
extern char* g_printer_font_sans;
extern char* g_printer_font_prestige;
extern char* g_printer_font_courier;
extern char* g_printer_font_script;
extern char* g_printer_font_ocra;
extern int g_printer_timeout;

extern int g_imagewriter;
extern int g_imagewriter_dpi;
extern char* g_imagewriter_output;
extern int g_imagewriter_multipage;
extern int g_imagewriter_timeout;
extern char* g_imagewriter_fixed_font;
extern char* g_imagewriter_prop_font;
extern int g_imagewriter_paper;
extern int g_imagewriter_banner;

#if defined(_WIN32) && !defined(HAVE_SDL)
extern int g_win_show_console_request;
extern int g_win_status_debug_request;
#endif

extern char *g_cfg_host_path;
extern int g_cfg_host_read_only;
extern int g_cfg_host_crlf;
extern int g_cfg_host_merlin;

extern int g_screen_index[];
extern word32 g_full_refresh_needed;
extern word32 g_a2_screen_buffer_changed;
extern int g_a2_new_all_stat[];
extern int g_new_a2_stat_cur_line;
extern byte g_bram[2][256];
extern byte* g_bram_ptr;
extern byte g_temp_boot_slot;
extern byte g_orig_boot_slot;

extern int g_key_down;
extern const char g_gsplus_version_str[];
int g_config_control_panel = 0;
char g_config_gsplus_name[1024];
char g_config_gsplus_screenshot_dir[1024];
char g_cfg_cwd_str[CFG_PATH_MAX] = { 0 };

int g_config_gsplus_auto_update = 1;
int g_config_gsplus_update_needed = 0;

const char *g_config_gsplus_name_list[] = {
  "config.txt", "config.gsp", ".config.gsp",0
};

int g_highest_smartport_unit = -1;
int g_reparse_delay = 0;
int g_user_page2_shadow = 1;

byte g_save_text_screen_bytes[0x800];
int g_save_cur_a2_stat = 0;
char g_cfg_printf_buf[CFG_PRINTF_BUFSIZE];
char g_config_gsplus_buf[CONF_BUF_LEN];

word32 g_cfg_vbl_count = 0;

int g_cfg_curs_x = 0;
int g_cfg_curs_y = 0;
int g_cfg_curs_inv = 0;
int g_cfg_curs_mousetext = 0;
int g_cfg_triggeriwreset = 0;

#define CFG_PG_SCROLL_AMT 15
#define CFG_MAX_OPTS    16
#define CFG_OPT_MAXSTR  100

int g_cfg_opts_vals[CFG_MAX_OPTS];
char g_cfg_opts_strs[CFG_MAX_OPTS][CFG_OPT_MAXSTR];
char g_cfg_opts_strvals[CFG_MAX_OPTS][CFG_OPT_MAXSTR];
char g_cfg_opt_buf[CFG_OPT_MAXSTR];

char *g_cfg_rom_path = "ROM";
const char *g_cfg_file_def_name = "Undefined";
char **g_cfg_file_strptr = 0;
int g_cfg_file_min_size = 1024;
int g_cfg_file_max_size = 2047*1024*1024;

int g_cfg_file_dir_only = 0;

#define MAX_PARTITION_BLK_SIZE          65536

void display_rawnet_menu(const char *name, const char **value);

extern Cfg_menu g_cfg_main_menu[];

#define KNMP(a)         &a, #a, 0

// This first menu is not a menu, but a list of config options that are
// represented here so they will be parsed correctly out of the config files.
Cfg_menu g_cfg_uiless_menu[] = {
  { "", KNMP(g_audio_enable), CFGTYPE_INT },
  { "", KNMP(g_preferred_rate), CFGTYPE_INT },
  { "", KNMP(g_fullscreen), CFGTYPE_INT },
  { "", KNMP(g_highdpi), CFGTYPE_INT },
  { "", KNMP(g_borderless), CFGTYPE_INT },
  { "", KNMP(g_resizeable), CFGTYPE_INT },
  { "", KNMP(g_noaspect), CFGTYPE_INT },
  { "", KNMP(g_novsync), CFGTYPE_INT },
  { "", KNMP(g_nohwaccel), CFGTYPE_INT },
  { "", KNMP(g_fullscreen_desktop), CFGTYPE_INT},
  { "", KNMP(g_screen_redraw_skip_amt), CFGTYPE_INT },
  { "", KNMP(g_use_dhr140), CFGTYPE_INT },
  { "", KNMP(g_use_bw_hires), CFGTYPE_INT },
  { "", KNMP(g_scanline_simulator), CFGTYPE_INT },
  { "", KNMP(g_startx), CFGTYPE_INT },
  { "", KNMP(g_starty), CFGTYPE_INT },
  { "", KNMP(g_startw), CFGTYPE_INT },
  { "", KNMP(g_starth), CFGTYPE_INT },
  { "", KNMP(g_joystick_number), CFGTYPE_INT },
  { "", KNMP(g_joystick_x_axis), CFGTYPE_INT },
  { "", KNMP(g_joystick_y_axis), CFGTYPE_INT },
  { "", KNMP(g_joystick_x2_axis), CFGTYPE_INT },
  { "", KNMP(g_joystick_y2_axis), CFGTYPE_INT },
  { "", KNMP(g_joystick_button_0), CFGTYPE_INT },
  { "", KNMP(g_joystick_button_1), CFGTYPE_INT },
  { "", KNMP(g_joystick_button_2), CFGTYPE_INT },
  { "", KNMP(g_joystick_button_3), CFGTYPE_INT },
  { "", KNMP(g_halt_on_bad_read), CFGTYPE_INT },
  { "", KNMP(g_ignore_bad_acc), CFGTYPE_INT },
  { "", KNMP(g_ignore_halts), CFGTYPE_INT },
  { 0, 0, 0, 0, 0 },
};


Cfg_menu g_cfg_disk_menu[] = {
  { "Disk Configuration", g_cfg_disk_menu, 0, 0, CFGTYPE_MENU },
  { "s5d1 = ", 0, 0, 0, CFGTYPE_DISK + 0x5000 },
  { "s5d2 = ", 0, 0, 0, CFGTYPE_DISK + 0x5010 },
  { "", 0, 0, 0, 0 },
  { "s6d1 = ", 0, 0, 0, CFGTYPE_DISK + 0x6000 },
  { "s6d2 = ", 0, 0, 0, CFGTYPE_DISK + 0x6010 },
  { "", 0, 0, 0, 0 },
  { "s7d1 = ", 0, 0, 0, CFGTYPE_DISK + 0x7000 },
  { "s7d2 = ", 0, 0, 0, CFGTYPE_DISK + 0x7010 },
  { "s7d3 = ", 0, 0, 0, CFGTYPE_DISK + 0x7020 },
  { "s7d4 = ", 0, 0, 0, CFGTYPE_DISK + 0x7030 },
  { "s7d5 = ", 0, 0, 0, CFGTYPE_DISK + 0x7040 },
  { "s7d6 = ", 0, 0, 0, CFGTYPE_DISK + 0x7050 },
  { "s7d7 = ", 0, 0, 0, CFGTYPE_DISK + 0x7060 },
  { "s7d8 = ", 0, 0, 0, CFGTYPE_DISK + 0x7070 },
  { "s7d9 = ", 0, 0, 0, CFGTYPE_DISK + 0x7080 },
  { "s7d10 = ", 0, 0, 0, CFGTYPE_DISK + 0x7090 },
  { "s7d11 = ", 0, 0, 0, CFGTYPE_DISK + 0x70a0 },
  { "", 0, 0, 0, 0 },
  { "Back to Main Config", g_cfg_main_menu, 0, 0, CFGTYPE_MENU },
  { 0, 0, 0, 0, 0 },
};

// OG Use define instead of const for joystick_types
#define STRINGIFY(x) #x
#define TOSTRING(x) STRINGIFY(x)

Cfg_menu g_cfg_joystick_menu[] = {
  { "Joystick Configuration", g_cfg_joystick_menu, 0, 0, CFGTYPE_MENU },
  { "Joystick Emulation,"TOSTRING (JOYSTICK_TYPE_KEYPAD)",Keypad Joystick,"TOSTRING (JOYSTICK_TYPE_MOUSE)",Mouse Joystick,"TOSTRING (JOYSTICK_TYPE_NATIVE_1)",Native Joystick 1,"
    TOSTRING(JOYSTICK_TYPE_NATIVE_2) ",Native Joystick 2,"TOSTRING (JOYSTICK_TYPE_NONE)",No Joystick", KNMP(g_joystick_type), CFGTYPE_INT },
  { "Joystick Scale X,0x100,Standard,0x119,+10%,0x133,+20%,"
    "0x150,+30%,0xb0,-30%,0xcd,-20%,0xe7,-10%",
    KNMP(g_joystick_scale_factor_x), CFGTYPE_INT },
  { "Joystick Scale Y,0x100,Standard,0x119,+10%,0x133,+20%,"
    "0x150,+30%,0xb0,-30%,0xcd,-20%,0xe7,-10%",
    KNMP(g_joystick_scale_factor_y), CFGTYPE_INT },
  { "Joystick Trim X", KNMP(g_joystick_trim_amount_x), CFGTYPE_INT },
  { "Joystick Trim Y", KNMP(g_joystick_trim_amount_y), CFGTYPE_INT },
  { "Swap Joystick X and Y,0,Normal operation,1,Paddle 1 and Paddle 0 swapped",
    KNMP(g_swap_paddles), CFGTYPE_INT },
  { "Invert Joystick,0,Normal operation,1,Left becomes right and up becomes down",
    KNMP(g_invert_paddles), CFGTYPE_INT },
  { "", 0, 0, 0, 0 },
  { "Back to Main Config", g_cfg_main_menu, 0, 0, CFGTYPE_MENU },
  { 0, 0, 0, 0, 0 },
};

Cfg_menu g_cfg_rom_menu[] = {
  { "ROM File Selection", g_cfg_rom_menu, 0, 0, CFGTYPE_MENU },
  { "ROM File", KNMP(g_cfg_rom_path), CFGTYPE_FILE },
  { "", 0, 0, 0, 0 },
  { "Back to Main Config", g_cfg_main_menu, 0, 0, CFGTYPE_MENU },
  { 0, 0, 0, 0, 0 },
};


Cfg_menu g_cfg_host_menu[] = {
  { "Host FST Configuration", g_cfg_host_menu, 0, 0, CFGTYPE_MENU },
  { "Shared Host Folder", KNMP(g_cfg_host_path), CFGTYPE_DIR },
  { "Read Only,0,No,1,Yes", KNMP(g_cfg_host_read_only), CFGTYPE_INT },
  { "CR/LF conversion,0,No,1,Yes", KNMP(g_cfg_host_crlf), CFGTYPE_INT },
  { "Merlin conversion,0,No,1,Yes", KNMP(g_cfg_host_merlin), CFGTYPE_INT },
  { "", 0, 0, 0, 0 },
  { "Back to Main Config", g_cfg_main_menu, 0, 0, CFGTYPE_MENU },
  { 0, 0, 0, 0, 0 },
};




Cfg_menu g_cfg_serial_menu[] = {
  { "Serial Port Configuration", g_cfg_serial_menu, 0, 0, CFGTYPE_MENU },
#ifdef HAVE_SDL
  { "Port 0 (slot 1),0,Only use socket 6501,1,Use real port if avail,2,Virtual ImageWriter",
    KNMP(g_serial_type[0]), CFGTYPE_INT },
  { "Port 1 (slot 2),0,Only use socket 6502,1,Use real port if avail,2,Virtual ImageWriter",
    KNMP(g_serial_type[1]), CFGTYPE_INT },
#else
  { "Port 0 (slot 1),0,Only use socket 6501,1,Use real port if avail",
    KNMP(g_serial_type[0]), CFGTYPE_INT },
  { "Port 1 (slot 2),0,Only use socket 6502,1,Use real port if avail",
    KNMP(g_serial_type[1]), CFGTYPE_INT },
#endif
  { "Serial Output,0,Send full 8-bit data,1,Mask off high bit",
    KNMP(g_serial_out_masking), CFGTYPE_INT },
  { "Modem on port 0 (slot 1),0,Simple socket emulation mode,1,Modem with "
    "incoming and outgoing emulation", KNMP(g_serial_modem[0]),
    CFGTYPE_INT },
  { "Modem on port 1 (slot 2),0,Simple socket emulation mode,1,Modem with "
    "incoming and outgoing emulation", KNMP(g_serial_modem[1]),
    CFGTYPE_INT },
  { "", 0, 0, 0, 0 },
  { "Back to Main Config", g_cfg_main_menu, 0, 0, CFGTYPE_MENU },
  { 0, 0, 0, 0, 0 },
};

Cfg_menu g_cfg_parallel_menu[] = {
  { "Parallel Card Configuration", g_cfg_parallel_menu, 0, 0, CFGTYPE_MENU },
  { "Parallel Card in Slot 1,0,Off,1,On",
    KNMP(g_parallel), CFGTYPE_INT },
  { "Parallel Output,0,Send full 8-bit data,1,Mask off high bit",
    KNMP(g_parallel_out_masking), CFGTYPE_INT },
  { "", 0, 0, 0, 0 },
  { "Back to Main Config", g_cfg_main_menu, 0, 0, CFGTYPE_MENU },
  { 0, 0, 0, 0, 0 },
};

#ifdef HAVE_RAWNET
Cfg_menu g_cfg_ethernet_menu[] = {
  { "Ethernet Card Configuration", g_cfg_ethernet_menu, 0, 0, CFGTYPE_MENU },
  { "Interface",
    KNMP(g_ethernet_interface), CFGTYPE_STR_FUNC, display_rawnet_menu },
  { "", 0, 0, 0, 0 },
  { "Uthernet Card in Slot 3,0,Off,1,On",
    KNMP(g_ethernet), CFGTYPE_INT },
#ifdef HAVE_ATBRIDGE
  { "", 0, 0, 0, 0 },
  { "AppleTalk Bridging,0,Off,1,On",
    KNMP(g_appletalk_bridging), CFGTYPE_INT },
  { "AppleTalk Speed,0,Normal (230.4 kbps),1,Turbo",
    KNMP(g_appletalk_turbo), CFGTYPE_INT },
#endif
  { "", 0, 0, 0, 0 },
  { "Back to Main Config", g_cfg_main_menu, 0, 0, CFGTYPE_MENU },
  { 0, 0, 0, 0, 0 },
};
#endif

#ifdef HAVE_SDL
Cfg_menu g_cfg_printer_menu[] = {
  { "Virtual Epson Configuration", g_cfg_printer_menu, 0, 0, CFGTYPE_MENU },
  { "Virtual Printer Type,0,Epson LQ",
    KNMP(g_printer), CFGTYPE_INT },
  { "Printer DPI,60,60x60 dpi,180,180x180 dpi,360,360x360 dpi",
    KNMP(g_printer_dpi), CFGTYPE_INT },
  { "Printer Output Type,bmp,Windows Bitmap,ps,Postscript (B&W),printer,Direct to host printer,text,Text file",
    KNMP(g_printer_output), CFGTYPE_STR },
  { "Multipage Files? (PS and Direct to Host Only),0,No,1,Yes",
    KNMP(g_printer_multipage), CFGTYPE_INT },
  { "Printer Timeout,0,Never,2,2 sec.,15,15 sec.,30,30 sec.,60, 1 min.",
    KNMP(g_printer_timeout), CFGTYPE_INT },
  { "", 0, 0, 0, 0 },
  { "Epson LQ Fonts", 0, 0, 0, 0 },
  { "--------------", 0, 0, 0, 0 },
  { "", 0, 0, 0, 0 },
  { "Roman", KNMP(g_printer_font_roman), CFGTYPE_FILE },
  { "Sans Serif", KNMP(g_printer_font_sans), CFGTYPE_FILE },
  { "Courier", KNMP(g_printer_font_courier), CFGTYPE_FILE },
  { "Prestige", KNMP(g_printer_font_prestige), CFGTYPE_FILE },
  { "Script", KNMP(g_printer_font_script), CFGTYPE_FILE },
  { "OCR A/B", KNMP(g_printer_font_ocra), CFGTYPE_FILE },
  { "", 0, 0, 0, 0 },
  { "Back to Main Config", g_cfg_main_menu, 0, 0, CFGTYPE_MENU },
  { 0, 0, 0, 0, 0 },
};

Cfg_menu g_cfg_imagewriter_menu[] = {
  { "Virtual ImageWriter Configuration", g_cfg_imagewriter_menu, 0, 0, CFGTYPE_MENU },
  { "Virtual Printer Type,0,ImageWriter II,1,ImageWriter LQ",
    KNMP(g_imagewriter), CFGTYPE_INT },
  { "Paper Size,0,US Letter (8.5x11in),1,US Legal (8.5x14in),2,ISO A4 (210 x 297mm),3,ISO B5 (176 x 250mm),4,Wide Fanfold (14 x 11in),5,Ledger (11 x 17in),6,ISO A3 (297 x 420mm)",
    KNMP(g_imagewriter_paper), CFGTYPE_INT },
  { "Printer DPI,360,360x360 dpi (Best for 8-bit software),720,720x720 dpi (Best for GS/OS & IW LQ Modes),1440,1440x1440 dpi",
    KNMP(g_imagewriter_dpi), CFGTYPE_INT },
  { "Banner Printing (Limited To 144x144 dpi Output),0,Banner Printing Off,3,3 Pages Long,4,4 Pages Long,5,5 Pages Long,6,6 Pages Long,7,7 Pages Long,8,8 Pages Long,9,9 Pages Long,10,10 Pages Long",
    KNMP(g_imagewriter_banner), CFGTYPE_INT },
  { "Printer Output Type,bmp,Windows Bitmap,ps,Postscript (B&W),colorps,Postscript (Color),printer,Direct to host printer,text,Text file",
    KNMP(g_imagewriter_output), CFGTYPE_STR },
  { "Multipage Files? (PS and Direct to Host Only),0,No,1,Yes",
    KNMP(g_imagewriter_multipage), CFGTYPE_INT },
  { "Printer Timeout,0,Never,2,2 sec.,15,15 sec.,30,30 sec.,60, 1 min.",
    KNMP(g_imagewriter_timeout), CFGTYPE_INT },
  { "", 0, 0, 0, 0 },
  { "ImageWriter Fonts", 0, 0, 0, 0 },
  { "-----------------", 0, 0, 0, 0 },
  { "", 0, 0, 0, 0 },
  { "Fixed Width Font", KNMP(g_imagewriter_fixed_font), CFGTYPE_FILE },
  { "", 0, 0, 0, 0 },
  { "Proportional Font", KNMP(g_imagewriter_prop_font), CFGTYPE_FILE },
  { "", 0, 0, 0, 0 },
  { "", 0, 0, 0, 0 },
  { "Back to Main Config", g_cfg_main_menu, 0, 0, CFGTYPE_MENU },
  { 0, 0, 0, 0, 0 },
};
#endif

Cfg_menu g_cfg_devel_menu[] = {
  { "Developer Options", g_cfg_devel_menu, 0, 0, CFGTYPE_MENU },
#if defined(_WIN32) && !defined(HAVE_SDL)
  { "Status lines,0,Hide,1,Show", KNMP(g_win_status_debug_request), CFGTYPE_INT },
  { "Console,0,Hide,1,Show", KNMP(g_win_show_console_request), CFGTYPE_INT },
#endif
#ifdef HAVE_ATBRIDGE
  { "", 0, 0, 0, 0 },
  { "Show AppleTalk Diagnostics,0,No,1,Yes", KNMP(g_appletalk_diagnostics), CFGTYPE_INT },
  { "AppleTalk Network Hint", KNMP(g_appletalk_network_hint), CFGTYPE_INT },
#endif
  { "", 0, 0, 0, 0 },
#ifndef _WIN32
  { "Force X-windows display depth", KNMP(g_force_depth), CFGTYPE_INT },
#endif
  { "Code Red Halts,0,Do not stop on bad accesses,1,Enter debugger on bad accesses", KNMP(g_user_halt_bad), CFGTYPE_INT },
  { "3200 Color Enable,0,Auto (Full if fast enough),1,Full (Update every line),8,Off (Update video every 8 lines)", KNMP(g_video_line_update_interval), CFGTYPE_INT },
  { "Keyboard and mouse poll rate,0,60 times per second,1,240 times per second", KNMP(g_video_extra_check_inputs), CFGTYPE_INT },
  { "Enable Text Page 2 Shadow,0,Disabled on ROM 01 (matches real hardware),1,Enabled on ROM 01 and 03", KNMP(g_user_page2_shadow), CFGTYPE_INT },
  { "", 0, 0, 0, 0 },
  { "Back to Main Config", g_cfg_main_menu, 0, 0, CFGTYPE_MENU },
  { 0, 0, 0, 0, 0 },
};

Cfg_menu g_cfg_main_menu[] = {
  { "GSplus Configuration", g_cfg_main_menu, 0, 0, CFGTYPE_MENU },
  { "Disk Configuration", g_cfg_disk_menu, 0, 0, CFGTYPE_MENU },
  { "Joystick Configuration", g_cfg_joystick_menu, 0, 0, CFGTYPE_MENU },
  { "ROM File Selection", g_cfg_rom_menu, 0, 0, CFGTYPE_MENU },
  { "HOST FST Configuration", g_cfg_host_menu, 0, 0, CFGTYPE_MENU },
  { "Serial Port Configuration", g_cfg_serial_menu, 0, 0, CFGTYPE_MENU },
#ifdef HAVE_RAWNET
  { "Ethernet Card Configuration", g_cfg_ethernet_menu, 0, 0, CFGTYPE_MENU },
#endif
  { "Parallel Card Configuration", g_cfg_parallel_menu, 0, 0, CFGTYPE_MENU },
#ifdef HAVE_SDL
  { "Virtual Epson Configuration", g_cfg_printer_menu, 0, 0, CFGTYPE_MENU },
  { "Virtual ImageWriter Configuration", g_cfg_imagewriter_menu, 0, 0, CFGTYPE_MENU },
#endif
  { "Developer Options", g_cfg_devel_menu, 0, 0, CFGTYPE_MENU },
  { "Auto-update configuration file,0,Manual,1,Immediately", KNMP(g_config_gsplus_auto_update), CFGTYPE_INT },
  { "Speed,0,Unlimited,1,1.0MHz,2,2.8MHz,3,8.0MHz (Zip)", KNMP(g_limit_speed), CFGTYPE_INT },
  { "Expansion Mem Size,0,0MB,0x100000,1MB,0x200000,2MB,0x300000,3MB,"
    "0x400000,4MB,0x600000,6MB,0x800000,8MB,0xa00000,10MB,0xc00000,12MB,"
    "0xe00000,14MB", KNMP(g_mem_size_exp), CFGTYPE_INT },
  { "Dump text screen to file", 0, 0, 0, CFGTYPE_FUNC, cfg_text_screen_dump},
#ifdef HAVE_SDL
  { "Reset Virtual ImageWriter", 0, 0, 0, CFGTYPE_FUNC, cfg_iwreset },
#endif
  { "", 0, 0, 0, 0 },
  { "Save changes to configuration file", 0, 0, 0, CFGTYPE_FUNC, config_write_config_gsplus_file },
  { "", 0, 0, 0, 0 },
  { "Exit Config (or press F4)", 0, 0, 0, CFGTYPE_FUNC, cfg_exit },
  { 0, 0, 0, 0, 0 },
};


#define CFG_MAX_DEFVALS 128
Cfg_defval g_cfg_defvals[CFG_MAX_DEFVALS];
int g_cfg_defval_index = 0;

int g_cfg_slotdrive = -1;
int g_cfg_select_partition = -1;
char g_cfg_tmp_path[CFG_PATH_MAX];
char g_cfg_file_path[CFG_PATH_MAX];
char g_cfg_file_cachedpath[CFG_PATH_MAX];
char g_cfg_file_cachedreal[CFG_PATH_MAX];
char g_cfg_file_curpath[CFG_PATH_MAX];
char g_cfg_file_shortened[CFG_PATH_MAX];
char g_cfg_file_match[CFG_PATH_MAX];

Cfg_listhdr g_cfg_dirlist = { 0 };
Cfg_listhdr g_cfg_partitionlist = { 0 };

int g_cfg_file_pathfield = 0;

const char *g_gsplus_rom_names[] = { "ROM", "ROM", "ROM1", "ROM3", "ROM01", "ROM03", "ROM.01", "ROM.03", 0 };
/* First entry is special--it will be overwritten by g_cfg_rom_path */

const char *g_gsplus_c1rom_names[] = { "parallel.rom", 0 };
const char *g_gsplus_c2rom_names[] = { 0 };
const char *g_gsplus_c3rom_names[] = { 0 };
const char *g_gsplus_c4rom_names[] = { 0 };
const char *g_gsplus_c5rom_names[] = { 0 };
const char *g_gsplus_c6rom_names[] = { "c600.rom", "controller.rom", "disk.rom", "DISK.ROM", "diskII.prom", 0 };
const char *g_gsplus_c7rom_names[] = { 0 };

const char **g_gsplus_rom_card_list[8] = {
  0,                      g_gsplus_c1rom_names,
  g_gsplus_c2rom_names,   g_gsplus_c3rom_names,
  g_gsplus_c4rom_names,   g_gsplus_c5rom_names,
  g_gsplus_c6rom_names,   g_gsplus_c7rom_names
};

byte g_rom_c600_rom01_diffs[256] = {
  0x00, 0x00, 0x00, 0x00, 0xc6, 0x00, 0xe2, 0x00,
  0xd0, 0x50, 0x0f, 0x77, 0x5b, 0xb9, 0xc3, 0xb1,
  0xb1, 0xf8, 0xcb, 0x4e, 0xb8, 0x60, 0xc7, 0x2e,
  0xfc, 0xe0, 0xbf, 0x1f, 0x66, 0x37, 0x4a, 0x70,
  0x55, 0x2c, 0x3c, 0xfc, 0xc2, 0xa5, 0x08, 0x29,
  0xac, 0x21, 0xcc, 0x09, 0x55, 0x03, 0x17, 0x35,
  0x4e, 0xe2, 0x0c, 0xe9, 0x3f, 0x9d, 0xc2, 0x06,
  0x18, 0x88, 0x0d, 0x58, 0x57, 0x6d, 0x83, 0x8c,
  0x22, 0xd3, 0x4f, 0x0a, 0xe5, 0xb7, 0x9f, 0x7d,
  0x2c, 0x3e, 0xae, 0x7f, 0x24, 0x78, 0xfd, 0xd0,
  0xb5, 0xd6, 0xe5, 0x26, 0x85, 0x3d, 0x8d, 0xc9,
  0x79, 0x0c, 0x75, 0xec, 0x98, 0xcc, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x77, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x7b, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x39, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x39, 0x00, 0x35, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x4a, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x64, 0x00, 0x00,
  0x6c, 0x44, 0xce, 0x4c, 0x01, 0x08, 0x00, 0x00
};


void config_init_menus(Cfg_menu *menuptr)      {
  void    *voidptr;
  const char *name_str;
  Cfg_defval *defptr;
  char    **str_ptr;
  char    *str;
  int type;
  int pos;
  int val;

  if(menuptr[0].defptr != 0) {
    return;
  }
  menuptr[0].defptr = (void *)1;
  pos = 0;
  while(pos < 100) {
    type = menuptr->cfgtype;
    voidptr = menuptr->ptr;
    name_str = menuptr->name_str;
    if(menuptr->str == 0) {
      break;
    }
    if(name_str != 0) {
      defptr = &(g_cfg_defvals[g_cfg_defval_index++]);
      if(g_cfg_defval_index >= CFG_MAX_DEFVALS) {
        fatal_printf("CFG_MAX_DEFVAL overflow\n");
        my_exit(5);
      }
      defptr->menuptr = menuptr;
      defptr->intval = 0;
      defptr->strval = 0;
      switch(type) {
        case CFGTYPE_INT:
          val = *((int *)voidptr);
          defptr->intval = val;
          menuptr->defptr = &(defptr->intval);
          break;
        case CFGTYPE_STR:
        case CFGTYPE_FILE:
        case CFGTYPE_DIR:
        case CFGTYPE_STR_FUNC:
          str_ptr = (char **)menuptr->ptr;
          str = *str_ptr;
          // We need to malloc this string since all
          //  string values must be dynamically alloced
          defptr->strval = str;                         // this can have a copy
          *str_ptr = gsplus_malloc_str(str);
          menuptr->defptr = &(defptr->strval);
          break;
        default:
          fatal_printf("name_str is %p = %s, but type: "
                       "%d\n", name_str, name_str, type);
          my_exit(5);
      }
    }
    if(type == CFGTYPE_MENU) {
      config_init_menus((Cfg_menu *)voidptr);
    }
    pos++;
    menuptr++;
  }
}

void config_init()      {
  int can_create;

  config_init_menus(g_cfg_main_menu);
  config_init_menus(g_cfg_uiless_menu);

  // Find the configuration file
  g_config_gsplus_name[0] = 0;
  can_create = 1;
  setup_gsplus_file(&g_config_gsplus_name[0], sizeof(g_config_gsplus_name), 0, can_create, &g_config_gsplus_name_list[0]);

  config_parse_config_gsplus_file();
}

void cfg_exit()      {
  if(g_rom_version >= 1) {
    g_config_control_panel = 0;
  }
}

void cfg_toggle_config_panel()      {
  g_config_control_panel = !g_config_control_panel;
  if(g_rom_version < 0) {
    g_config_control_panel = 1;                 /* Stay in config mode */
  }
}

void cfg_text_screen_dump()      {
  char buf[85];
  char    *filename;
  FILE    *ofile;
  int offset;
  int c;
  int pos;
  int i, j;

  filename = "gsplus.screen.dump";
  glogf("Writing text screen to the file %s", filename);
  ofile = fopen(filename, "w");
  if(ofile == 0) {
    fatal_printf("Could not write to file %s, (%d)\n", filename, errno);
    return;
  }

  for(i = 0; i < 24; i++) {
    pos = 0;
    for(j = 0; j < 40; j++) {
      offset = g_screen_index[i] + j;
      if(g_save_cur_a2_stat & ALL_STAT_VID80) {
        c = g_save_text_screen_bytes[0x400+offset];
        c = c & 0x7f;
        if(c < 0x20) {
          c += 0x40;
        }
        buf[pos++] = c;
      }
      c = g_save_text_screen_bytes[offset] & 0x7f;
      if(c < 0x20) {
        c += 0x40;
      }
      buf[pos++] = c;
    }
    while((pos > 0) && (buf[pos-1] == ' ')) {
      /* try to strip out trailing spaces */
      pos--;
    }
    buf[pos++] = '\n';
    buf[pos++] = 0;
    fputs(buf, ofile);
  }
  fclose(ofile);
}
void cfg_iwreset()      {
  imagewriter_feed();
  imagewriter_close();
  imagewriter_init(g_imagewriter_dpi,g_imagewriter_paper,g_imagewriter_banner, g_imagewriter_output,g_imagewriter_multipage);
  return;
}


void config_vbl_update(int doit_3_persec)      {
  if(doit_3_persec) {
    if(g_config_gsplus_auto_update && g_config_gsplus_update_needed) {
      config_write_config_gsplus_file();
    }
  }
  return;
}

void config_parse_option(char *buf, int pos, int len, int line)      {
  Cfg_menu *menuptr;
  Cfg_defval *defptr;
  char    *nameptr;
  char    **strptr;
  int     *iptr;
  int num_equals;
  int type;
  int val;
  int c;
  int i;

// warning: modifies buf (turns spaces to nulls)
// parse buf from pos into option, "=" and then "rest"
  if(pos >= len) {
    /* blank line */
    return;
  }

  if(strncmp(&buf[pos], "bram", 4) == 0) {
    config_parse_bram(buf, pos+4, len);
    return;
  }

  // find "name" as first contiguous string
  glogf("%s line %d, len:%d  \"%s\"", parse_log_prefix_file, line, len, &buf[pos]);

  nameptr = &buf[pos];
  while(pos < len) {
    c = buf[pos];
    if(c == 0 || c == ' ' || c == '\t' || c == '\n') {
      break;
    }
    pos++;
  }
  buf[pos] = 0;
  pos++;

  // Eat up all whitespace and '='
  num_equals = 0;
  while(pos < len) {
    c = buf[pos];
    if((c == '=') && num_equals == 0) {
      pos++;
      num_equals++;
    } else if(c == ' ' || c == '\t') {
      pos++;
    } else {
      break;
    }
  }

  /* Look up nameptr to find type */
  type = -1;
  defptr = 0;
  menuptr = 0;
  for(i = 0; i < g_cfg_defval_index; i++) {
    defptr = &(g_cfg_defvals[i]);
    menuptr = defptr->menuptr;
    if(strcmp(menuptr->name_str, nameptr) == 0) {
      type = menuptr->cfgtype;
      break;
    }
  }

  switch(type) {
    case CFGTYPE_INT:
      /* use strtol */
      val = (int)strtol(&buf[pos], 0, 0);
      iptr = (int *)menuptr->ptr;
      *iptr = val;
      break;
    case CFGTYPE_STR:
    case CFGTYPE_FILE:
    case CFGTYPE_DIR:
    case CFGTYPE_STR_FUNC:
      strptr = (char **)menuptr->ptr;
      if(strptr && *strptr) {
        free(*strptr);
      }
      *strptr = gsplus_malloc_str(&buf[pos]);
      break;
    default:
      glogf("Config file variable %s is unknown type: %d", nameptr, type);
  }

}

void config_parse_bram(char *buf, int pos, int len)      {
  int bram_num;
  int offset;
  int val;

  if((len < (pos+5)) || (buf[pos+1] != '[') || (buf[pos+4] != ']')) {
    fatal_printf("While reading configuration file, found malformed bram "
                 "statement: %s\n", buf);
    return;
  }
  bram_num = buf[pos] - '0';
  if(bram_num != 1 && bram_num != 3) {
    fatal_printf("While reading configuration file, found bad bram "
                 "num: %s\n", buf);
    return;
  }

  bram_num = bram_num >> 1;             // turn 3->1 and 1->0

  offset = strtoul(&(buf[pos+2]), 0, 16);
  pos += 5;
  while(pos < len) {
    while(buf[pos] == ' ' || buf[pos] == '\t' || buf[pos] == 0x0a ||
          buf[pos] == 0x0d || buf[pos] == '=') {
      pos++;
    }
    val = strtoul(&buf[pos], 0, 16);
    clk_bram_set(bram_num, offset, val);
    offset++;
    pos += 2;
  }
}

void config_load_roms()      {
  struct stat stat_buf;
  const char **names_ptr;
  int more_than_8mb;
  int changed_rom;
  int len;
  FILE *file;
  int ret;
  int i;

  g_rom_version = -1;

  /* set first entry of g_gsplus_rom_names[] to g_cfg_rom_path so that */
  /*  it becomes the first place searched. */
  g_gsplus_rom_names[0] = g_cfg_rom_path;
  setup_gsplus_file(&g_cfg_tmp_path[0], CFG_PATH_MAX, -1, 0,
                    &g_gsplus_rom_names[0]);

  if(g_cfg_tmp_path[0] == 0) {
    // Just get out, let config interface select ROM
    g_config_control_panel = 1;
    return;
  }
  file = fopen(&g_cfg_tmp_path[0], "rb");
  if(!file) {
    fatal_printf("Open ROM file %s failed; errno:%d\n",
                 &g_cfg_tmp_path[0], errno);
    g_config_control_panel = 1;
    return;
  }

  ret = stat(&g_cfg_tmp_path[0], &stat_buf);
  if(ret != 0) {
    fatal_printf("stat returned %d; errno: %d\n",
                 ret, errno);
    g_config_control_panel = 1;
    return;
  }

  len = stat_buf.st_size;
  if(len == 128*1024) {
    g_rom_version = 1;
    g_mem_size_base = 256*1024;
    memset(&g_rom_fc_ff_ptr[0], 0, 2*65536);
    /* Clear banks fc and fd to 0 */
    ret = fread(&g_rom_fc_ff_ptr[2*65536], 1, len, file);
  } else if(len == 256*1024) {
    g_rom_version = 3;
    g_mem_size_base = 1024*1024;
    ret = fread(&g_rom_fc_ff_ptr[0], 1, len, file);
  } else {
    fatal_printf("The ROM size should be 128K or 256K, this file "
                 "is %d bytes\n", len);
    g_config_control_panel = 1;
    return;
  }

  glogf("Read %d bytes (%dK) of ROM", ret, ret/1024);
  if(ret != len) {
    fatal_printf("errno: %d\n", errno);
    g_config_control_panel = 1;                 // THIS DOESN'T DO ANYTHING?
    return;
  }
  fclose(file);

  memset(&g_rom_cards_ptr[0], 0, 256*16);

  /* initialize c600 rom to be diffs from the real ROM, to build-in */
  /*  Apple II compatibility without distributing ROMs */
  for(i = 0; i < 256; i++) {
    g_rom_cards_ptr[0x600 + i] = g_rom_fc_ff_ptr[0x3c600 + i] ^
                                 g_rom_c600_rom01_diffs[i];
  }
  if(g_rom_version >= 3) {
    /* some patches */
    g_rom_cards_ptr[0x61b] ^= 0x40;
    g_rom_cards_ptr[0x61c] ^= 0x33;
    g_rom_cards_ptr[0x632] ^= 0xc0;
    g_rom_cards_ptr[0x633] ^= 0x33;
  }

  for(i = 1; i < 8; i++) {
    names_ptr = g_gsplus_rom_card_list[i];
    if(names_ptr == 0) {
      continue;
    }
    if(*names_ptr == 0) {
      continue;
    }
    setup_gsplus_file(&g_cfg_tmp_path[0], CFG_PATH_MAX, 1, 0, names_ptr);
    if(g_cfg_tmp_path[0] != 0) {
      file = fopen(&(g_cfg_tmp_path[0]), "rb");
      if(!file) {
        fatal_printf("Open card ROM file %s failed; errno:%d\n",
                     &g_cfg_tmp_path[0], errno);
        continue;
      }

      len = 256;
      ret = fread(&g_rom_cards_ptr[i*0x100], 1, len, file);

      if(ret != len) {
        fatal_printf("While reading card ROM %s, file "
                     "is too short. (%d) Expected %d bytes, "
                     "read %d bytes\n", &g_cfg_tmp_path[0], errno, len, ret);
        continue;
      }
      glogf("Read: %d bytes of ROM in slot %d from file %s.", ret, i, &g_cfg_tmp_path[0]);
      fclose(file);
    }
  }
  more_than_8mb = (g_mem_size_exp > 0x800000);
  /* Only do the patch if users wants more than 8MB of expansion mem */

  changed_rom = 0;
  if(g_rom_version == 1) {
    /* make some patches to ROM 01 */
#if 0
    /* 1: Patch ROM selftest to not do speed test */
    printf("Patching out speed test failures from ROM 01\n");
    g_rom_fc_ff_ptr[0x3785a] = 0x18;
    changed_rom = 1;
#endif

#if 0
    /* 2: Patch ROM selftests not to do tests 2,4 */
    /* 0 = skip, 1 = do it, test 1 is bit 0 of LSByte */
    g_rom_fc_ff_ptr[0x371e9] = 0xf5;
    g_rom_fc_ff_ptr[0x371ea] = 0xff;
    changed_rom = 1;
#endif

    if(more_than_8mb) {
      /* Geoff Weiss patch to use up to 14MB of RAM */
      g_rom_fc_ff_ptr[0x30302] = 0xdf;
      g_rom_fc_ff_ptr[0x30314] = 0xdf;
      g_rom_fc_ff_ptr[0x3031c] = 0x00;
      changed_rom = 1;
    }

    /* Patch ROM selftest to not do ROM cksum if any changes*/
    if(changed_rom) {
      g_rom_fc_ff_ptr[0x37a06] = 0x18;
      g_rom_fc_ff_ptr[0x37a07] = 0x18;
    }
  } else if(g_rom_version == 3) {
    /* patch ROM 03 */
    glog("Patching ROM 03 smartport bug");
    /* 1: Patch Smartport code to fix a stupid bug */
    /*   that causes it to write the IWM status reg into c036, */
    /*   which is the system speed reg...it's "safe" since */
    /*   IWM status reg bit 4 must be 0 (7MHz)..., otherwise */
    /*   it might have turned on shadowing in all banks! */
    g_rom_fc_ff_ptr[0x357c9] = 0x00;
    changed_rom = 1;

#if 0
    /* patch ROM 03 to not to speed test */
    /*  skip fast speed test */
    g_rom_fc_ff_ptr[0x36ad7] = 0x18;
    g_rom_fc_ff_ptr[0x36ad8] = 0x18;
    changed_rom = 1;
#endif

#if 0
    /*  skip slow speed test */
    g_rom_fc_ff_ptr[0x36ae7] = 0x18;
    g_rom_fc_ff_ptr[0x36ae8] = 0x6b;
    changed_rom = 1;
#endif

#if 0
    /* 4: Patch ROM 03 selftests not to do tests 1-4 */
    g_rom_fc_ff_ptr[0x364a9] = 0xf0;
    g_rom_fc_ff_ptr[0x364aa] = 0xff;
    changed_rom = 1;
#endif

    /* ROM tests are in ff/6403-642x, where 6403 = addr of */
    /*  test 1, etc. */

    if(more_than_8mb) {
      /* Geoff Weiss patch to use up to 14MB of RAM */
      g_rom_fc_ff_ptr[0x30b] = 0xdf;
      g_rom_fc_ff_ptr[0x31d] = 0xdf;
      g_rom_fc_ff_ptr[0x325] = 0x00;
      changed_rom = 1;
    }

    if(changed_rom) {
      /* patch ROM 03 selftest to not do ROM cksum */
      g_rom_fc_ff_ptr[0x36cb0] = 0x18;
      g_rom_fc_ff_ptr[0x36cb1] = 0x18;
    }

  }
}

void config_parse_config_gsplus_file()      {
  FILE    *fconf;
  char    *buf;
  char    *ptr;
  char    *name_ptr;
  char    *partition_name;
  int part_num;
  int ejected;
  int line;
  int pos;
  int slot;
  int drive;
  int size;
  int len;
  int ret;
  int i;

  glogf("Parsing configuration file '%s'", g_config_gsplus_name);

  clk_bram_zero();

  g_highest_smartport_unit = -1;

  cfg_get_base_path(&g_cfg_cwd_str[0], g_config_gsplus_name, 0);

  // I think this code is wrong.  It breaks relative config paths on the "-config"
  // option.  ie "./gsplus -config foo/bar.gsp"
  // It's possible it was needed for some of the autodiscovery stuff, but I'm
  // not really a fan of that either and think it should be take out.
  // Especially now that you can pass a filename.

  fconf = fopen(g_config_gsplus_name, "r");
  if(fconf == 0) {
    perror("ERROR");
    fatal_printf("Cannot open configuration file at %s!  Stopping!\n",g_config_gsplus_name);
    my_exit(3);
  }

  line = 0;
  while(1) {
    buf = &g_config_gsplus_buf[0];
    ptr = fgets(buf, CONF_BUF_LEN, fconf);
    if(ptr == 0) {
      iwm_printf("Done reading disk_conf\n");
      break;
    }

    line++;
    /* strip off newline(s) */
    len = strlen(buf);
    for(i = len - 1; i >= 0; i--) {
      if((buf[i] != 0x0d) && (buf[i] != 0x0a)) {
        break;
      }
      len = i;
      buf[i] = 0;
    }

    iwm_printf("disk_conf[%d]: %s\n", line, buf);
    if(len > 0 && buf[0] == '#') {
      iwm_printf("Skipping comment\n");
      continue;
    }

    /* determine what this is */
    pos = 0;

    while(pos < len && (buf[pos] == ' ' || buf[pos] == '\t') ) {
      pos++;
    }
    if((pos + 4) > len || buf[pos] != 's' || buf[pos+2] != 'd' ||
       buf[pos+1] > '9' || buf[pos+1] < '0') {
      config_parse_option(buf, pos, len, line);
      continue;
    }

    slot = buf[pos+1] - '0';
    drive = buf[pos+3] - '0';

    /* skip over slot, drive */
    pos += 4;
    if(buf[pos] >= '0' && buf[pos] <= '9') {
      drive = drive * 10 + buf[pos] - '0';
      pos++;
    }

    /*	make s6d1 mean index 0 */
    drive--;

    while(pos < len && (buf[pos] == ' ' || buf[pos] == '\t' ||
                        buf[pos] == '=') ) {
      pos++;
    }

    ejected = 0;
    if(buf[pos] == '#') {
      /* disk is ejected, but read all the info anyway */
      ejected = 1;
      pos++;
    }

    size = 0;
    if(buf[pos] == ',') {
      /* read optional size parameter */
      pos++;
      while(pos < len && buf[pos] >= '0' && buf[pos] <= '9') {
        size = size * 10 + buf[pos] - '0';
        pos++;
      }
      size = size * 1024;
      if(buf[pos] == ',') {
        pos++;                                  /* eat trailing ',' */
      }
    }

    /* see if it has a partition name */
    partition_name = 0;
    part_num = -1;
    if(buf[pos] == ':') {
      pos++;
      /* yup, it's got a partition name! */
      partition_name = &buf[pos];
      while((pos < len) && (buf[pos] != ':')) {
        pos++;
      }
      buf[pos] = 0;                     /* null terminate partition name */
      pos++;
    }
    if(buf[pos] == ';') {
      pos++;
      /* it's got a partition number */
      part_num = 0;
      while((pos < len) && (buf[pos] != ':')) {
        part_num = (10*part_num) + buf[pos] - '0';
        pos++;
      }
      pos++;
    }

    /* Get filename */
    name_ptr = &(buf[pos]);
    if(name_ptr[0] == 0) {
      continue;
    }

    insert_disk(slot, drive, name_ptr, ejected, size,
                partition_name, part_num);

  }

  ret = fclose(fconf);
  if(ret != 0) {
    fatal_printf("Closing configuration file ret: %d, errno: %d\n", ret,
                 errno);
    my_exit(4);
  }

  iwm_printf("Done parsing disk_conf file\n");
}


Disk *cfg_get_dsk_from_slot_drive(int slot, int drive)       {
  Disk    *dsk;
  int max_drive;

  /* Get dsk */
  max_drive = 2;
  switch(slot) {
    case 5:
      dsk = &(iwm.drive35[drive]);
      break;
    case 6:
      dsk = &(iwm.drive525[drive]);
      break;
    default:
      max_drive = MAX_C7_DISKS;
      dsk = &(iwm.smartport[drive]);
  }

  if(drive >= max_drive) {
    dsk -= drive;               /* move back to drive 0 effectively */
  }

  return dsk;
}

void config_generate_config_gsplus_name(char *outstr, int maxlen, Disk *dsk,
                                        int with_extras) {
  char    *str;

  str = outstr;

  if(with_extras && (!dsk->file)) {
    snprintf(str, maxlen - (str - outstr), "#");
    str = &outstr[strlen(outstr)];
  }
  if(with_extras && dsk->force_size > 0) {
    snprintf(str, maxlen - (str - outstr), ",%d,", dsk->force_size);
    str = &outstr[strlen(outstr)];
  }
  if(with_extras && dsk->partition_name != 0) {
    snprintf(str, maxlen - (str - outstr), ":%s:",
             dsk->partition_name);
    str = &outstr[strlen(outstr)];
  } else if(with_extras && dsk->partition_num >= 0) {
    snprintf(str, maxlen - (str - outstr), ";%d:",
             dsk->partition_num);
    str = &outstr[strlen(outstr)];
  }
  snprintf(str, maxlen - (str - outstr), "%s", dsk->name_ptr);
}

void config_write_config_gsplus_file()      {
  FILE    *fconf;
  Disk    *dsk;
  Cfg_defval *defptr;
  Cfg_menu *menuptr;
  char    *curstr, *defstr;
  int defval, curval;
  int type;
  int slot, drive;
  int i;

  glogf("Writing configuration file to %s", g_config_gsplus_name);

  fconf = fopen(g_config_gsplus_name, "w+");
  if(fconf == 0) {
    halt_printf("cannot open %s!  Stopping!\n",g_config_gsplus_name);
    return;
  }

  fprintf(fconf, "# GSplus configuration file version %s\n",
          g_gsplus_version_str);

  for(i = 0; i < MAX_C7_DISKS + 4; i++) {
    slot = 7;
    drive = i - 4;
    if(i < 4) {
      slot = (i >> 1) + 5;
      drive = i & 1;
    }
    if(drive == 0) {
      fprintf(fconf, "\n");                     /* an extra blank line */
    }

    dsk = cfg_get_dsk_from_slot_drive(slot, drive);
    if(dsk->name_ptr == 0 && (i > 4)) {
      /* No disk, not even ejected--just skip */
      continue;
    }
    fprintf(fconf, "s%dd%d = ", slot, drive + 1);
    if(dsk->name_ptr == 0) {
      fprintf(fconf, "\n");
      continue;
    }
    config_generate_config_gsplus_name(&g_cfg_tmp_path[0],
                                       CFG_PATH_MAX, dsk, 1);
    fprintf(fconf, "%s\n", &g_cfg_tmp_path[0]);
  }

  fprintf(fconf, "\n");

  /* See if any variables are different than their default */
  for(i = 0; i < g_cfg_defval_index; i++) {
    defptr = &(g_cfg_defvals[i]);
    menuptr = defptr->menuptr;
    defval = defptr->intval;
    type = menuptr->cfgtype;

    switch (type) {
      case CFGTYPE_INT:
        curval = *((int *)menuptr->ptr);
        if(curval != defval) {
          fprintf(fconf, "%s = %d\n", menuptr->name_str,
                  curval);
        }
        break;
      case CFGTYPE_STR:
      case CFGTYPE_FILE:
      case CFGTYPE_DIR:
      case CFGTYPE_STR_FUNC:
        curstr = *((char **)menuptr->ptr);
        defstr = *((char **)menuptr->defptr);
        if(strcmp(curstr, defstr) != 0) {
          fprintf(fconf, "%s = %s\n", menuptr->name_str,
                  curstr);
        }
        break;
    }
  }

  fprintf(fconf, "\n");

  /* write bram state */
  clk_write_bram(fconf);

  fclose(fconf);

  g_config_gsplus_update_needed = 0;
}

void eject_named_disk(Disk *dsk, const char *name, const char *partition_name)      {

  if(!dsk->file) {
    return;
  }

  /* If name matches, eject the disk! */
  if(!strcmp(dsk->name_ptr, name)) {
    /* It matches, eject it */
    if((partition_name != 0) && (dsk->partition_name != 0)) {
      /* If both have partitions, and they differ, then */
      /*  don't eject.  Otherwise, eject */
      if(strcmp(dsk->partition_name, partition_name) != 0) {
        /* Don't eject */
        return;
      }
    }
    eject_disk(dsk);
  }
}

void eject_disk_by_num(int slot, int drive)      {
  Disk    *dsk;

  dsk = cfg_get_dsk_from_slot_drive(slot, drive);

  eject_disk(dsk);
}

void eject_disk(Disk *dsk)      {
  int motor_on;
  int i;

  if(!dsk->file) {
    return;
  }

  g_config_gsplus_update_needed = 1;

  motor_on = iwm.motor_on;
  if(g_c031_disk35 & 0x40) {
    motor_on = iwm.motor_on35;
  }
  if(motor_on) {
    halt_printf("Try eject dsk:%s, but motor_on!\n", dsk->name_ptr);
  }

  iwm_flush_disk_to_unix(dsk);

  glogf("Ejecting disk: %s", dsk->name_ptr);

  /* Free all memory, close file */

  /* free the tracks first */
  if(dsk->trks != 0) {
    for(i = 0; i < dsk->num_tracks; i++) {
      if(dsk->trks[i].nib_area) {
        free(dsk->trks[i].nib_area);
      }
      dsk->trks[i].nib_area = 0;
      dsk->trks[i].track_len = 0;
    }
    free(dsk->trks);
  }
  dsk->num_tracks = 0;
  dsk->trks = 0;

  /* close file, clean up dsk struct */
  fclose(dsk->file);

  dsk->image_start = 0;
  dsk->image_size = 0;
  dsk->nib_pos = 0;
  dsk->disk_dirty = 0;
  dsk->write_through_to_unix = 0;
  dsk->write_prot = 1;
  dsk->file = 0;
  dsk->just_ejected = 1;

  /* Leave name_ptr valid */
}

int cfg_get_fd_size(char *filename)     {
  struct stat stat_buf;
  int ret;

  ret = stat(filename, &stat_buf);
  if(ret != 0) {
    fprintf(stderr,"stat %s returned errno: %d\n",
            filename, errno);
    stat_buf.st_size = 0;
  }

  return stat_buf.st_size;
}

int cfg_partition_read_block(FILE *file, void *buf, int blk, int blk_size)     {
  int ret;

  ret = fseek(file, blk * blk_size, SEEK_SET);
  if(ret != 0) {
    printf("fseek: wanted: %08x, errno: %d\n",
           blk * blk_size, errno);
    return 0;
  }

  ret = fread((char *)buf, 1, blk_size, file);
  if(ret != blk_size) {
    printf("ret: %08x, wanted %08x, errno: %d\n", ret, blk_size,
           errno);
    return 0;
  }
  return ret;
}

int cfg_partition_find_by_name_or_num(FILE *file, const char *partnamestr, int part_num,
                                      Disk *dsk) {
  Cfg_dirent *direntptr;
  int match;
  int num_parts;
  int i;

  num_parts = cfg_partition_make_list(dsk->name_ptr, file);

  if(num_parts <= 0) {
    return -1;
  }

  for(i = 0; i < g_cfg_partitionlist.last; i++) {
    direntptr = &(g_cfg_partitionlist.direntptr[i]);
    match = 0;
    if((strncmp(partnamestr, direntptr->name, 32) == 0) &&
       (part_num < 0)) {
      //printf("partition, match1, name:%s %s, part_num:%d\n",
      //	partnamestr, direntptr->name, part_num);

      match = 1;
    }
    if((partnamestr == 0) && (direntptr->part_num == part_num)) {
      //printf("partition, match2, n:%s, part_num:%d == %d\n",
      //	direntptr->name, direntptr->part_num, part_num);
      match = 1;
    }
    if(match) {
      dsk->image_start = direntptr->image_start;
      dsk->image_size = direntptr->size;
      //printf("match with image_start: %08x, image_size: "
      //	"%08x\n", dsk->image_start, dsk->image_size);

      return i;
    }
  }

  return -1;
}

int cfg_partition_make_list(char *filename, FILE *file)     {
  Driver_desc *driver_desc_ptr;
  Part_map *part_map_ptr;
  word32  *blk_bufptr;
  word32 start;
  word32 len;
  word32 data_off;
  word32 data_len;
  word32 sig;
  int size;
  int image_start, image_size;
  int is_dir;
  int block_size;
  int map_blks;
  int cur_blk;

  block_size = 512;

  cfg_free_alldirents(&g_cfg_partitionlist);

  blk_bufptr = (word32 *)malloc(MAX_PARTITION_BLK_SIZE);

  cfg_partition_read_block(file, blk_bufptr, 0, block_size);

  driver_desc_ptr = (Driver_desc *)blk_bufptr;
  sig = GET_BE_WORD16(driver_desc_ptr->sig);
  block_size = GET_BE_WORD16(driver_desc_ptr->blk_size);
  if(block_size == 0) {
    block_size = 512;
  }
  if(sig != 0x4552 || block_size < 0x200 ||
     (block_size > MAX_PARTITION_BLK_SIZE)) {
    cfg_printf("Partition error: No driver descriptor map found\n");
    free(blk_bufptr);
    return 0;
  }

  map_blks = 1;
  cur_blk = 0;
  size = cfg_get_fd_size(filename);
  cfg_file_add_dirent(&g_cfg_partitionlist, "None - Whole image",
                      is_dir=0, size, 0, -1);

  while(cur_blk < map_blks) {
    cur_blk++;
    cfg_partition_read_block(file, blk_bufptr, cur_blk, block_size);
    part_map_ptr = (Part_map *)blk_bufptr;
    sig = GET_BE_WORD16(part_map_ptr->sig);
    if(cur_blk <= 1) {
      map_blks = MIN(20,
                     GET_BE_WORD32(part_map_ptr->map_blk_cnt));
    }
    if(sig != 0x504d) {
      printf("Partition entry %d bad signature:%04x\n",
             cur_blk, sig);
      free(blk_bufptr);
      return g_cfg_partitionlist.last;
    }

    /* found it, check for consistency */
    start = GET_BE_WORD32(part_map_ptr->phys_part_start);
    len = GET_BE_WORD32(part_map_ptr->part_blk_cnt);
    data_off = GET_BE_WORD32(part_map_ptr->data_start);
    data_len = GET_BE_WORD32(part_map_ptr->data_cnt);
    if(data_off + data_len > len) {
      printf("Poorly formed entry\n");
      continue;
    }

    if(data_len < 10 || start < 1) {
      printf("Poorly formed entry %d, datalen:%d, "
             "start:%08x\n", cur_blk, data_len, start);
      continue;
    }

    image_size = data_len * block_size;
    image_start = (start + data_off) * block_size;
    is_dir = 2*(image_size < 800*1024);
#if 0
    printf(" partition add entry %d = %s %d %08x %08x\n",
           cur_blk, part_map_ptr->part_name, is_dir,
           image_size, image_start);
#endif

    cfg_file_add_dirent(&g_cfg_partitionlist,
                        part_map_ptr->part_name, is_dir, image_size,
                        image_start, cur_blk);
  }

  free(blk_bufptr);
  return g_cfg_partitionlist.last;
}

int cfg_maybe_insert_disk(int slot, int drive, const char *namestr)     {
  int num_parts;
  FILE *file;

  file = fopen(namestr, "rb");
  if(!file) {
    fatal_printf("Cannot open disk image: %s\n", namestr);
    return 0;
  }

  num_parts = cfg_partition_make_list((char*)namestr, file);
  fclose(file);

  if(num_parts > 0) {
    printf("Choose a partition\n");
    g_cfg_select_partition = 1;
  } else {
    insert_disk(slot, drive, namestr, 0, 0, 0, -1);
    return 1;
  }
  return 0;
}

int cfg_stat(char *path, struct stat *sb)     {
  int removed_slash;
  int len;
  int ret;

  removed_slash = 0;
  len = 0;

#ifdef _WIN32
  /* Windows doesn't like to stat paths ending in a /, so remove it */
  len = strlen(path);
  if((len > 1) && (path[len - 1] == '/') ) {
    path[len - 1] = 0;                  /* remove the slash */
    removed_slash = 1;
  }
#endif

  ret = stat(path, sb);

#ifdef _WIN32
  /* put the slash back */
  if(removed_slash) {
    path[len - 1] = '/';
  }
#endif

  return ret;
}

void cfg_htab_vtab(int x, int y)      {
  if(x > 79) {
    x = 0;
  }
  if(y > 23) {
    y = 0;
  }
  g_cfg_curs_x = x;
  g_cfg_curs_y = y;
  g_cfg_curs_inv = 0;
  g_cfg_curs_mousetext = 0;
}

void cfg_home()      {
  int i;

  cfg_htab_vtab(0, 0);
  for(i = 0; i < 24; i++) {
    cfg_cleol();
  }
}

void cfg_cleol()      {
  g_cfg_curs_inv = 0;
  g_cfg_curs_mousetext = 0;
  cfg_putchar(' ');
  while(g_cfg_curs_x != 0) {
    cfg_putchar(' ');
  }
}

void cfg_putchar(int c)      {
  int offset;
  int x, y;

  if(c == '\n') {
    cfg_cleol();
    return;
  }
  if(c == '\b') {
    g_cfg_curs_inv = !g_cfg_curs_inv;
    return;
  }
  if(c == '\t') {
    g_cfg_curs_mousetext = !g_cfg_curs_mousetext;
    return;
  }
  y = g_cfg_curs_y;
  x = g_cfg_curs_x;

  offset = g_screen_index[g_cfg_curs_y];
  if((x & 1) == 0) {
    offset += 0x10000;
  }
  if(g_cfg_curs_inv) {
    if(c >= 0x40 && c < 0x60) {
      c = c & 0x1f;
    }
  } else {
    c = c | 0x80;
  }
  if(g_cfg_curs_mousetext) {
    c = (c & 0x1f) | 0x40;
  }
  set_memory_c(0xe00400 + offset + (x >> 1), c, 0);
  x++;
  if(x >= 80) {
    x = 0;
    y++;
    if(y >= 24) {
      y = 0;
    }
  }
  g_cfg_curs_y = y;
  g_cfg_curs_x = x;
}

void cfg_puts(const char *str, int nl) {
  for(;*str; ++str) cfg_putchar(*str);
    if (nl) cfg_putchar('\n');
}

void cfg_printf(const char *fmt, ...)      {
  va_list ap;
  int c;
  int i;

  va_start(ap, fmt);
  (void)vsnprintf(g_cfg_printf_buf, CFG_PRINTF_BUFSIZE, fmt, ap);
  va_end(ap);

  for(i = 0; i < CFG_PRINTF_BUFSIZE; i++) {
    c = g_cfg_printf_buf[i];
    if(c == 0) {
      return;
    }
    cfg_putchar(c);
  }
}

void cfg_print_num(int num, int max_len)      {
  char buf[64];
  char buf2[64];
  int len;
  int cnt;
  int c;
  int i, j;

  /* Prints right-adjusted "num" in field "max_len" wide */
  snprintf(&buf[0], 64, "%d", num);
  len = strlen(buf);
  for(i = 0; i < 64; i++) {
    buf2[i] = ' ';
  }
  j = max_len + 1;
  buf2[j] = 0;
  j--;
  cnt = 0;
  for(i = len - 1; (i >= 0) && (j >= 1); i--) {
    c = buf[i];
    if(c >= '0' && c <= '9') {
      if(cnt >= 3) {
        buf2[j--] = ',';
        cnt = 0;
      }
      cnt++;
    }
    buf2[j--] = c;
  }
  cfg_printf(&buf2[1]);
}

void cfg_get_disk_name(char *outstr, int maxlen, int type_ext, int with_extras)      {
  Disk    *dsk;
  int slot, drive;

  slot = type_ext >> 8;
  drive = type_ext & 0xff;
  dsk = cfg_get_dsk_from_slot_drive(slot, drive);

  outstr[0] = 0;
  if(dsk->name_ptr == 0) {
    return;
  }

  config_generate_config_gsplus_name(outstr, maxlen, dsk, with_extras);
}

void cfg_parse_menu(Cfg_menu *menuptr, int menu_pos, int highlight_pos, int change)      {
  char valbuf[CFG_OPT_MAXSTR];
  char    **str_ptr;
  const char *menustr;
  char    *curstr, *defstr;
  char    *str;
  char    *outstr;
  int     *iptr;
  int val;
  int num_opts;
  int opt_num;
  int bufpos, outpos;
  int curval, defval;
  int type;
  int type_ext;
  int opt_get_str;
  int separator;
  int len;
  int c;
  int i;

  g_cfg_opt_buf[0] = 0;

  num_opts = 0;
  opt_get_str = 0;
  separator = ',';

  menuptr += menu_pos;                  /* move forward to entry menu_pos */

  menustr = menuptr->str;
  type = menuptr->cfgtype;
  type_ext = (type >> 4);
  type = type & 0xf;
  len = strlen(menustr) + 1;

  bufpos = 0;
  outstr = &(g_cfg_opt_buf[0]);

  outstr[bufpos++] = ' ';
  outstr[bufpos++] = ' ';
  outstr[bufpos++] = '\t';
  outstr[bufpos++] = '\t';
  outstr[bufpos++] = ' ';
  outstr[bufpos++] = ' ';

  if(menu_pos == highlight_pos) {
    outstr[bufpos++] = '\b';
  }

  opt_get_str = 2;
  i = -1;
  outpos = bufpos;
#if 0
  printf("cfg menu_pos: %d str len: %d\n", menu_pos, len);
#endif
  while(++i < len) {
    c = menustr[i];
    if(c == separator) {
      if(i == 0) {
        continue;
      }
      c = 0;
    }
    outstr[outpos++] = c;
    outstr[outpos] = 0;
    if(outpos >= CFG_OPT_MAXSTR) {
      fprintf(stderr, "CFG_OPT_MAXSTR exceeded\n");
      my_exit(1);
    }
    if(c == 0) {
      if(opt_get_str == 2) {
        outstr = &(valbuf[0]);
        bufpos = outpos - 1;
        opt_get_str = 0;
      } else if(opt_get_str) {
#if 0
        if(menu_pos == highlight_pos) {
          printf("menu_pos %d opt %d = %s=%d\n",
                 menu_pos, num_opts,
                 g_cfg_opts_strs[num_opts],
                 g_cfg_opts_vals[num_opts]);
        }
#endif
        num_opts++;
        outstr = &(valbuf[0]);
        opt_get_str = 0;
        if(num_opts >= CFG_MAX_OPTS) {
          fprintf(stderr, "CFG_MAX_OPTS oflow\n");
          my_exit(1);
        }
      } else {
        if (type == CFGTYPE_INT)
        {
          val = strtoul(valbuf, 0, 0);
          g_cfg_opts_vals[num_opts] = val;
        }

        if (type == CFGTYPE_STR)
        {
          strncpy(&(g_cfg_opts_strvals[num_opts][0]),&(valbuf[0]),CFG_OPT_MAXSTR);
        }
        outstr = &(g_cfg_opts_strs[num_opts][0]);
        opt_get_str = 1;
      }
      outpos = 0;
      outstr[0] = 0;
    }
  }

  if(menu_pos == highlight_pos) {
    g_cfg_opt_buf[bufpos++] = '\b';
  }

  g_cfg_opt_buf[bufpos] = 0;

  // Figure out if we should get a checkmark
  curval = -1;
  defval = -1;
  curstr = 0;

  switch(type) {

    case CFGTYPE_INT:
      iptr = (int*)menuptr->ptr;                        // OG Added cast
      curval = *iptr;
      iptr = (int*)menuptr->defptr;                   // OG Added cast
      defval = *iptr;
      if(curval == defval) {
        g_cfg_opt_buf[3] = 'D';                         /* checkmark */
        g_cfg_opt_buf[4] = '\t';
      }
      break;
    case CFGTYPE_STR:
    case CFGTYPE_FILE:
    case CFGTYPE_DIR:
    case CFGTYPE_STR_FUNC:
      str_ptr = (char **)menuptr->ptr;
      curstr = *str_ptr;
      str_ptr = (char **)menuptr->defptr;
      defstr = *str_ptr;
      if(strcmp(curstr,defstr) == 0) {
        g_cfg_opt_buf[3] = 'D';                         /* checkmark */
        g_cfg_opt_buf[4] = '\t';
      }
      break;



    // If it's a menu, give it a special menu indicator
    case CFGTYPE_MENU:
      g_cfg_opt_buf[1] = '\t';
      g_cfg_opt_buf[2] = 'M';                           /* return-like symbol */
      g_cfg_opt_buf[3] = '\t';
      g_cfg_opt_buf[4] = ' ';
      break;
  }



  // Decide what to display on the "right" side
  str = 0;
  opt_num = -1;

  switch(type) {

    case CFGTYPE_INT:
    case CFGTYPE_FILE:
    case CFGTYPE_DIR:
    case CFGTYPE_STR_FUNC:
      g_cfg_opt_buf[bufpos++] = ' ';
      g_cfg_opt_buf[bufpos++] = '=';
      g_cfg_opt_buf[bufpos++] = ' ';
      g_cfg_opt_buf[bufpos] = 0;
      for(i = 0; i < num_opts; i++) {
        if(curval == g_cfg_opts_vals[i]) {
          opt_num = i;
          break;
        }
      }
      break;

    case CFGTYPE_STR:
      g_cfg_opt_buf[bufpos++] = ' ';
      g_cfg_opt_buf[bufpos++] = '=';
      g_cfg_opt_buf[bufpos++] = ' ';
      g_cfg_opt_buf[bufpos] = 0;
      for(i = 0; i < num_opts; i++) {
        if(!strcmp(curstr,g_cfg_opts_strvals[i])) {
          opt_num = i;
          break;
        }
      }
      break;
  }

  if(change != 0) {
    if(type == CFGTYPE_INT) {
      if(num_opts > 0) {
        opt_num += change;
        if(opt_num >= num_opts) {
          opt_num = 0;
        }
        if(opt_num < 0) {
          opt_num = num_opts - 1;
        }
        curval = g_cfg_opts_vals[opt_num];
      } else {
        curval += change;
        /* HACK: min_val, max_val testing here */
      }
      iptr = (int *)menuptr->ptr;
      *iptr = curval;
    }
    if(type == CFGTYPE_STR) {
      if(num_opts > 0) {
        opt_num += change;
        if(opt_num >= num_opts) {
          opt_num = 0;
        }
        if(opt_num < 0) {
          opt_num = num_opts - 1;
        }
        curstr = g_cfg_opts_strvals[opt_num];
      } else {
        //curstr += change;
        /* HACK: min_val, max_val testing here */
      }
      str_ptr = (char **)menuptr->ptr;
      *str_ptr = curstr;
    }
    g_config_gsplus_update_needed = 1;
  }

#if 0
  if(menu_pos == highlight_pos) {
    printf("menu_pos %d opt_num %d\n", menu_pos, opt_num);
  }
#endif

  if(opt_num >= 0) {
    str = &(g_cfg_opts_strs[opt_num][0]);
  } else {
    switch(type) {
      case CFGTYPE_INT:
        str = &(g_cfg_opts_strs[0][0]);
        snprintf(str, CFG_OPT_MAXSTR, "%d", curval);
        break;
      case CFGTYPE_STR:
      case CFGTYPE_STR_FUNC:
        str = &(g_cfg_opts_strs[0][0]);
        //printf("curstr is: %s str is: %s\n", curstr,str);
        snprintf(str, CFG_OPT_MAXSTR, "%s", curstr);
        break;
      case CFGTYPE_DISK:
        str = &(g_cfg_opts_strs[0][0]),
        cfg_get_disk_name(str, CFG_OPT_MAXSTR, type_ext, 1);
        str = cfg_shorten_filename(str, 68);
        break;
      case CFGTYPE_FILE:
      case CFGTYPE_DIR:
        str = &(g_cfg_opts_strs[0][0]);
        snprintf(str, CFG_OPT_MAXSTR, "%s", curstr);
        str = cfg_shorten_filename(str, 68);
        break;
      default:
        str = "";
    }
  }

#if 0
  if(menu_pos == highlight_pos) {
    printf("menu_pos %d buf_pos %d, str is %s, %02x, %02x, "
           "%02x %02x\n",
           menu_pos, bufpos, str, g_cfg_opt_buf[bufpos-1],
           g_cfg_opt_buf[bufpos-2],
           g_cfg_opt_buf[bufpos-3],
           g_cfg_opt_buf[bufpos-4]);
  }
#endif

  g_cfg_opt_buf[bufpos] = 0;
  strncpy(&(g_cfg_opt_buf[bufpos]), str, CFG_OPT_MAXSTR - bufpos - 1);
  g_cfg_opt_buf[CFG_OPT_MAXSTR-1] = 0;
}

void cfg_get_base_path(char *pathptr, const char *inptr, int go_up)      {
  const char *tmpptr;
  char    *slashptr;
  char    *outptr;
  int add_dotdot, is_dotdot;
  int len;
  int c;

  /* Take full filename, copy it to pathptr, and truncate at last slash */
  /* inptr and pathptr can be the same */
  /* if go_up is set, then replace a blank dir with ".." */
  /* but first, see if path is currently just ../ over and over */
  /* if so, just tack .. onto the end and return */
  //printf("cfg_get_base start with %s\n", inptr);

  g_cfg_file_match[0] = 0;
  tmpptr = inptr;
  is_dotdot = 1;
  while(1) {
    if(tmpptr[0] == 0) {
      break;
    }
    if(tmpptr[0] == '.' && tmpptr[1] == '.' && tmpptr[2] == '/') {
      tmpptr += 3;
    } else {
      is_dotdot = 0;
      break;
    }
  }
  slashptr = 0;
  outptr = pathptr;
  c = -1;
  while(c != 0) {
    c = *inptr++;
    if(c == '/') {
      if(*inptr != 0) {                         /* if not a trailing slash... */
        slashptr = outptr;
      }
    }
    *outptr++ = c;
  }
  if(!go_up) {
    /* if not go_up, copy chopped part to g_cfg_file_match*/
    /* copy from slashptr+1 to end */
    tmpptr = slashptr+1;
    if(slashptr == 0) {
      tmpptr = pathptr;
    }
    strncpy(&g_cfg_file_match[0], tmpptr, CFG_PATH_MAX);
    /* remove trailing / from g_cfg_file_match */
    len = strlen(&g_cfg_file_match[0]);
    if((len > 1) && (len < (CFG_PATH_MAX - 1)) &&
       g_cfg_file_match[len - 1] == '/') {
      g_cfg_file_match[len - 1] = 0;
    }
    //printf("set g_cfg_file_match to %s\n", &g_cfg_file_match[0]);
  }
  if(!is_dotdot && (slashptr != 0)) {
    slashptr[0] = '/';
    slashptr[1] = 0;
    outptr = slashptr + 2;
  }
  add_dotdot = 0;
  if(pathptr[0] == 0 || is_dotdot) {
    /* path was blank, or consisted of just ../ pattern */
    if(go_up) {
      add_dotdot = 1;
    }
  } else if(slashptr == 0) {
    /* no slashes found, but path was not blank--make it blank */
    if(pathptr[0] == '/') {
      pathptr[1] = 0;
    } else {
      pathptr[0] = 0;
    }
  }

  if(add_dotdot) {
    --outptr;
    outptr[0] = '.';
    outptr[1] = '.';
    outptr[2] = '/';
    outptr[3] = 0;
  }

  //printf("cfg_get_base end with %s, is_dotdot:%d, add_dotdot:%d\n",
  //		pathptr, is_dotdot, add_dotdot);
}

void cfg_file_init()      {
  int slot, drive;
  int i;

  if(g_cfg_slotdrive < 0xfff) {
    cfg_get_disk_name(&g_cfg_tmp_path[0], CFG_PATH_MAX,
                      g_cfg_slotdrive, 0);

    slot = g_cfg_slotdrive >> 8;
    drive = g_cfg_slotdrive & 1;
    for(i = 0; i < 6; i++) {
      if(g_cfg_tmp_path[0] != 0) {
        break;
      }
      /* try to get a starting path from some mounted drive */
      drive = !drive;
      if(i & 1) {
        slot++;
        if(slot >= 8) {
          slot = 5;
        }
      }
      cfg_get_disk_name(&g_cfg_tmp_path[0], CFG_PATH_MAX,
                        (slot << 8) + drive, 0);
    }
  } else {
    // Just use g_cfg_file_def_name
    strncpy(&g_cfg_tmp_path[0], g_cfg_file_def_name, CFG_PATH_MAX);
  }

  cfg_get_base_path(&g_cfg_file_curpath[0], &g_cfg_tmp_path[0], 0);
  g_cfg_dirlist.invalid = 1;
}

void cfg_free_alldirents(Cfg_listhdr *listhdrptr)      {
  int i;

  if(listhdrptr->max > 0) {
    // Free the old directory listing
    for(i = 0; i < listhdrptr->last; i++) {
      free(listhdrptr->direntptr[i].name);
    }
    free(listhdrptr->direntptr);
  }

  listhdrptr->direntptr = 0;
  listhdrptr->last = 0;
  listhdrptr->max = 0;
  listhdrptr->invalid = 0;

  listhdrptr->topent = 0;
  listhdrptr->curent = 0;
}


void cfg_file_add_dirent(Cfg_listhdr *listhdrptr, const char *nameptr, int is_dir,
                         int size, int image_start, int part_num) {
  Cfg_dirent *direntptr;
  char    *ptr;
  int inc_amt;
  int namelen;

  namelen = strlen(nameptr);
  if(listhdrptr->last >= listhdrptr->max) {
    // realloc
    inc_amt = MAX(64, listhdrptr->max);
    inc_amt = MIN(inc_amt, 1024);
    listhdrptr->max += inc_amt;
    listhdrptr->direntptr = (Cfg_dirent*)realloc(listhdrptr->direntptr,
                                                 listhdrptr->max * sizeof(Cfg_dirent));
  }
  ptr = (char*)malloc(namelen+1+is_dir);       // OG Added cast
  strncpy(ptr, nameptr, namelen+1);
  if(is_dir) {
    strcat(ptr, "/");
  }
#if 0
  printf("...file entry %d is %s\n", g_cfg_dirlist.last, ptr);
#endif
  direntptr = &(listhdrptr->direntptr[listhdrptr->last]);
  direntptr->name = ptr;
  direntptr->is_dir = is_dir;
  direntptr->size = size;
  direntptr->image_start = image_start;
  direntptr->part_num = part_num;
  listhdrptr->last++;
}

/* Called by qsort to sort directory listings */
int cfg_dirent_sortfn(const void *obj1, const void *obj2)     {
  const Cfg_dirent *direntptr1, *direntptr2;
  int ret;

  // all systems sort the file list case-insensitively
  direntptr1 = (const Cfg_dirent *)obj1;
  direntptr2 = (const Cfg_dirent *)obj2;
  ret = strcasecmp(direntptr1->name, direntptr2->name);
  return ret;
}

void cfg_file_readdir(const char *pathptr)      {

  struct dirent *direntptr;
  struct stat stat_buf;
  DIR     *dirptr;
  mode_t fmt;
  char    *str;
  const char *tmppathptr;
  int size;
  int ret;
  int is_dir, is_gz;
  int len;
  int i;

  if(!strncmp(pathptr, &g_cfg_file_cachedpath[0], CFG_PATH_MAX) &&
     (g_cfg_dirlist.last > 0) && (g_cfg_dirlist.invalid==0)) {
    return;
  }
  // No match, must read new directory

  // Free all dirents that were cached previously
  cfg_free_alldirents(&g_cfg_dirlist);

  strncpy(&g_cfg_file_cachedpath[0], pathptr, CFG_PATH_MAX);
  strncpy(&g_cfg_file_cachedreal[0], pathptr, CFG_PATH_MAX);

  str = &g_cfg_file_cachedreal[0];

  for(i = 0; i < 200; i++) {
    len = strlen(str);
    if(len <= 0) {
      break;
    } else if(len < CFG_PATH_MAX-2) {
      if(str[len-1] != '/') {
        // append / to make various routines work
        str[len] = '/';
        str[len+1] = 0;
      }
    }
    ret = cfg_stat(str, &stat_buf);
    is_dir = 0;
    if(ret == 0) {
      fmt = stat_buf.st_mode & S_IFMT;
      if(fmt == S_IFDIR) {
        /* it's a directory */
        is_dir = 1;
      }
    }
    if(is_dir) {
      break;
    } else {
      // user is entering more path, use base for display
      cfg_get_base_path(str, str, 0);
    }
  }
  tmppathptr = str;
  if(str[0] == 0) {
    tmppathptr = ".";
  }
  cfg_file_add_dirent(&g_cfg_dirlist, "..", 1, 0, -1, -1);
  dirptr = opendir(tmppathptr);
  if(dirptr == 0) {
    printf("Could not open %s as a directory\n", tmppathptr);
    return;
  }
  while(1) {
    direntptr = readdir(dirptr);
    if(direntptr == 0) {
      break;
    }
    if(!strcmp(".", direntptr->d_name)) {
      continue;
    }
    if(!strcmp("..", direntptr->d_name)) {
      continue;
    }
    // Else, see if it is a directory or a file
    snprintf(&g_cfg_tmp_path[0], CFG_PATH_MAX, "%s%s",
             &g_cfg_file_cachedreal[0], direntptr->d_name);
    ret = cfg_stat(&g_cfg_tmp_path[0], &stat_buf);
    len = strlen(g_cfg_tmp_path);
    is_dir = 0;
    is_gz = 0;
    if((len > 3) && (strcmp(&g_cfg_tmp_path[len - 3], ".gz") == 0)) {
      is_gz = 1;
    }
    if(ret != 0) {
      printf("stat %s ret %d, errno:%d\n", &g_cfg_tmp_path[0],
             ret, errno);
      stat_buf.st_size = 0;
      continue;                         /* skip it */
    } else {
      fmt = stat_buf.st_mode & S_IFMT;
      size = stat_buf.st_size;
      if(fmt == S_IFDIR) {
        // it's a directory
        is_dir = 1;
      } else if((fmt == S_IFREG) && (is_gz == 0)) {
        if(g_cfg_slotdrive < 0xfff) {
          if(size < 140*1024) {
            continue;                                           /* skip it */
          }
        } else {
          // see if there are size limits
          if((size < g_cfg_file_min_size) ||
             (size > g_cfg_file_max_size)) {
            continue;                                           /* skip it */
          }
        }
      }
    }
    if (g_cfg_file_dir_only && !is_dir) continue;

    cfg_file_add_dirent(&g_cfg_dirlist, direntptr->d_name, is_dir,
                        stat_buf.st_size, -1, -1);
  }
  // always sort the results, all systems
  qsort(&(g_cfg_dirlist.direntptr[0]), g_cfg_dirlist.last, sizeof(Cfg_dirent), cfg_dirent_sortfn);
  g_cfg_dirlist.curent = g_cfg_dirlist.last - 1;
  for(i = g_cfg_dirlist.last - 1; i >= 0; i--) {
    ret = strcasecmp(&g_cfg_file_match[0], g_cfg_dirlist.direntptr[i].name);
    if(ret <= 0) {
      // set curent to closest filename to the match name
      g_cfg_dirlist.curent = i;
    }
  }
}

void cfg_inspect_maybe_insert_file(char *filename, int should_boot)      {
/*
   Take a look at a file.  Based on its size, guess a slot/drive to insert it into.
   Used for blind operations like dragging/dropping files.
   Optionally boot from that slot.
 */
  int rc = 0;
  int slot = 0;
  rc = cfg_guess_image_size(filename);
  switch (rc)
  {
    case 0: slot = 7; break;
    case 1: slot = 6; break;
    case 2: slot = 5; break;
    case 3: slot = 7; break;
    default: break;
  }
  if (slot > 0)
  {
    insert_disk(slot,0,filename,0,0,0,-1);
    glogf("Inserted disk in slot %d, drive 1.  Filename: %s", slot, filename);
    if (should_boot) {
      g_temp_boot_slot = slot;
      glog("That slot has been set to boot.");
    }
  }
  else
    glogf("Unable to determine appropriate place to insert file %s.",filename);
}

int cfg_guess_image_size(char *filename)     {
/*
   Guess the image size.  Return values:
   -1 : invalid/unknown.  Can't guess.
   0 : Less than 140k; might be ram disk image.
   1 : 140k, 5.25" image.
   2 : 800k, 3.5" image.
   3 : Something bigger.
 */
  struct stat stat_buf;
  int rc = -1;
  int len;
  rc = stat(filename, &stat_buf);
  if(rc < 0)
  {
    glogf("Can't get statistics on file %s; errno: %d",     filename, errno);
    rc = -1;
  } else {
    len = stat_buf.st_size;
    if (len <  140 * 1024) {
      /* Not enough for a 140k image */
      glogf("Found file %s, size %d; guessing small ProDOS image.",   filename, len);
      rc = 0;
    } else if (len <  140 * 1024 + 256 + 1) {
      /* Reasonable size for 140k image, maybe in 2mg format */
      glogf("Found file %s, size %d; guessing a 5-1/4\" image.",      filename, len);
      rc = 1;
    } else if (len < 800 * 1024 + 256 + 1) {
      /* Reasonable size for 800k image, maybe in 2mg format */
      glogf("Found file %s, size %d; guessing a 3-1/2\" image.",      filename, len);
      rc = 2;
    } else {
      /* Let's pretend it's an HDV image */
      glogf("Found file %s, size %d; guessing a hard drive image.",   filename, len);
      rc = 3;
    }
  }
  return rc;
}

char *cfg_shorten_filename(const char *in_ptr, int maxlen)       {
  char    *out_ptr;
  int len;
  int c;
  int i;
  /* Warning: uses a static string, not reentrant! */
  out_ptr = &(g_cfg_file_shortened[0]);
  len = strlen(in_ptr);
  maxlen = MIN(len, maxlen);
  for(i = 0; i < maxlen; i++) {
    c = in_ptr[i] & 0x7f;
    if(c < 0x20) {
      c = '*';
    }
    out_ptr[i] = c;
  }
  out_ptr[maxlen] = 0;
  if(len > maxlen) {
    for(i = 0; i < (maxlen/2); i++) {
      c = in_ptr[len-i-1] & 0x7f;
      if(c < 0x20) {
        c = '*';
      }
      out_ptr[maxlen-i-1] = c;
    }
    out_ptr[(maxlen/2) - 1] = '.';
    out_ptr[maxlen/2] = '.';
    out_ptr[(maxlen/2) + 1] = '.';
  }
  return out_ptr;
}
void cfg_fix_topent(Cfg_listhdr *listhdrptr)      {
  int num_to_show;
  num_to_show = listhdrptr->num_to_show;
  /* Force curent and topent to make sense */
  if(listhdrptr->curent >= listhdrptr->last) {
    listhdrptr->curent = listhdrptr->last - 1;
  }
  if(listhdrptr->curent < 0) {
    listhdrptr->curent = 0;
  }
  if(abs(listhdrptr->curent - listhdrptr->topent) >= num_to_show) {
    listhdrptr->topent = listhdrptr->curent - (num_to_show/2);
  }
  if(listhdrptr->topent > listhdrptr->curent) {
    listhdrptr->topent = listhdrptr->curent - (num_to_show/2);
  }
  if(listhdrptr->topent < 0) {
    listhdrptr->topent = 0;
  }
}
void cfg_file_draw()      {
  Cfg_listhdr *listhdrptr;
  Cfg_dirent *direntptr;
  char    *str, *fmt;
  int num_to_show;
  int yoffset;
  int x, y;
  int i;
  cfg_file_readdir(&g_cfg_file_curpath[0]);
  for(y = 0; y < 21; y++) {
    cfg_htab_vtab(0, y);
    cfg_printf("\tZ\t");
    for(x = 1; x < 79; x++) {
      cfg_htab_vtab(x, y);
      cfg_putchar(' ');
    }
    cfg_htab_vtab(79, y);
    cfg_printf("\t_\t");
  }
  cfg_htab_vtab(1, 0);
  cfg_putchar('\b');
  for(x = 1; x < 79; x++) {
    cfg_putchar(' ');
  }
  if(g_cfg_slotdrive < 0xfff) {
    cfg_htab_vtab(30, 0);
    cfg_printf("\bSelect image for s%dd%d\b",
               (g_cfg_slotdrive >> 8), (g_cfg_slotdrive & 0xff) + 1);
  } else {
    cfg_htab_vtab(5, 0);
    cfg_printf("\bSelect file to use as %-40s\b",
               cfg_shorten_filename(g_cfg_file_def_name, 40));
  }
  cfg_htab_vtab(2, 1);
  cfg_printf("Configuration file path: %-40s",
             cfg_shorten_filename(&g_config_gsplus_name[0], 40));
  cfg_htab_vtab(2, 2);
  cfg_printf("Current directory: %-50s",
             cfg_shorten_filename(&g_cfg_cwd_str[0], 50));
  cfg_htab_vtab(2, 3);
  str = "";
  if(g_cfg_file_pathfield) {
    str = "\b \b";
  }
  cfg_printf("Path: %s%s",
             cfg_shorten_filename(&g_cfg_file_curpath[0], 68), str);
  cfg_htab_vtab(0, 4);
  cfg_printf(" \t");
  for(x = 1; x < 79; x++) {
    cfg_putchar('\\');
  }
  cfg_printf("\t ");

  /* Force curent and topent to make sense */
  listhdrptr = &g_cfg_dirlist;
  num_to_show = CFG_NUM_SHOWENTS;
  yoffset = 5;
  if(g_cfg_select_partition > 0) {
    listhdrptr = &g_cfg_partitionlist;
    num_to_show -= 2;
    cfg_htab_vtab(2, yoffset);
    cfg_printf("Select partition of %-50s\n",
               cfg_shorten_filename(&g_cfg_file_path[0], 50), str);
    yoffset += 2;
  }
  listhdrptr->num_to_show = num_to_show;
  cfg_fix_topent(listhdrptr);
  for(i = 0; i < num_to_show; i++) {
    y = i + yoffset;
    if(listhdrptr->last > (i + listhdrptr->topent)) {
      direntptr = &(listhdrptr->
                    direntptr[i + listhdrptr->topent]);
      cfg_htab_vtab(2, y);
      if(direntptr->is_dir) {
        cfg_printf("\tXY\t ");
      } else {
        cfg_printf("   ");
      }
      if(direntptr->part_num >= 0) {
        cfg_printf("%3d: ", direntptr->part_num);
      }
      str = cfg_shorten_filename(direntptr->name, 45);
      fmt = "%-45s";
      if(i + listhdrptr->topent == listhdrptr->curent) {
        if(g_cfg_file_pathfield == 0) {
          fmt = "\b%-45s\b";
        } else {
          fmt = "%-44s\b \b";
        }
      }
      cfg_printf(fmt, str);
      if(!direntptr->is_dir) {
        cfg_print_num(direntptr->size, 13);
      }
    }
  }
  cfg_htab_vtab(1, 5 + CFG_NUM_SHOWENTS);
  cfg_putchar('\t');
  for(x = 1; x < 79; x++) {
    cfg_putchar('L');
  }
  cfg_putchar('\t');
}

void cfg_partition_selected()      {
  char    *str;
  const char *part_str;
  char    *part_str2;
  int pos;
  int part_num;
  pos = g_cfg_partitionlist.curent;
  str = g_cfg_partitionlist.direntptr[pos].name;
  part_num = -2;
  part_str = 0;
  if(str[0] == 0 || (str[0] >= '0' && str[0] <= '9')) {
    part_num = g_cfg_partitionlist.direntptr[pos].part_num;
  } else {
    part_str = str;
  }
  part_str2 = 0;
  if(part_str != 0) {
    part_str2 = (char *)malloc(strlen(part_str)+1);
    strcpy(part_str2, part_str);
  }
  insert_disk(g_cfg_slotdrive >> 8, g_cfg_slotdrive & 0xff,
              &(g_cfg_file_path[0]), 0, 0, part_str2, part_num);
  if(part_str2 != 0) {
    free(part_str2);
  }
  g_cfg_slotdrive = -1;
  g_cfg_select_partition = -1;
}
void cfg_file_update_ptr(char *str)      {
  char    *newstr;
  int len;
  len = strlen(str) + 1;
  newstr = (char*)malloc(len);
  memcpy(newstr, str, len);
  if(g_cfg_file_strptr) {
    if(*g_cfg_file_strptr) {
      free(*g_cfg_file_strptr);
    }
  }
  *g_cfg_file_strptr = newstr;
  if(g_cfg_file_strptr == &(g_cfg_rom_path)) {
    glog("Updated ROM file");
    load_roms_init_memory();
  }
  g_config_gsplus_update_needed = 1;
}
void cfg_file_selected(int select_dir)      {
  struct stat stat_buf;
  char    *str;
  int fmt;
  int ret;
  if(g_cfg_select_partition > 0) {
    cfg_partition_selected();
    return;
  }
  if(g_cfg_file_pathfield == 0) {
    // in file section area of window
    str = g_cfg_dirlist.direntptr[g_cfg_dirlist.curent].name;
    if(!strcmp(str, "../")) {
      /* go up one directory */
      cfg_get_base_path(&g_cfg_file_curpath[0],
                        &g_cfg_file_curpath[0], 1);
      return;
    }
    snprintf(&g_cfg_file_path[0], CFG_PATH_MAX, "%s%s",
             &g_cfg_file_cachedreal[0], str);
  } else {
    // just use cfg_file_curpath directly
    strncpy(&g_cfg_file_path[0], &g_cfg_file_curpath[0],
            CFG_PATH_MAX);
  }
  ret = cfg_stat(&g_cfg_file_path[0], &stat_buf);
  fmt = stat_buf.st_mode & S_IFMT;
        #if 0
  cfg_printf("Stat'ing %s, st_mode is: %08x\n", &g_cfg_file_path[0],
             (int)stat_buf.st_mode);
        #endif
  if(ret != 0) {
    glogf("stat %s returned %d, errno: %d", &g_cfg_file_path[0], ret, errno);
  } else {
    if(fmt == S_IFDIR && !select_dir) {
      /* it's a directory */
      strncpy(&g_cfg_file_curpath[0], &g_cfg_file_path[0],
              CFG_PATH_MAX);
    } else {
      /* select it */
      if(g_cfg_slotdrive < 0xfff) {
        ret = cfg_maybe_insert_disk(g_cfg_slotdrive>>8,
                                    g_cfg_slotdrive & 0xff,
                                    &g_cfg_file_path[0]);
        if(ret > 0) {
          g_cfg_slotdrive = -1;
        }
      } else {
        cfg_file_update_ptr(&g_cfg_file_path[0]);
        g_cfg_slotdrive = -1;
      }
    }
  }
}

void cfg_file_handle_key(int key) {
  Cfg_listhdr *listhdrptr;
  int len;
  if(g_cfg_file_pathfield) {
    if(key >= 0x20 && key < 0x7f) {
      len = strlen(&g_cfg_file_curpath[0]);
      if(len < CFG_PATH_MAX-4) {
        g_cfg_file_curpath[len] = key;
        g_cfg_file_curpath[len+1] = 0;
      }
      return;
    }
  }
  listhdrptr = &g_cfg_dirlist;
  if(g_cfg_select_partition > 0) {
    listhdrptr = &g_cfg_partitionlist;
  }

  if( (g_cfg_file_pathfield == 0) && isalnum(key)) {
    /* jump to file starting with this letter */
    g_cfg_file_match[0] = key;
    g_cfg_file_match[1] = 0;
    g_cfg_dirlist.invalid = 1;                  /* re-read directory */
  } else {
    switch(key) {
      case KEY_ESC:
        if(g_cfg_slotdrive < 0xfff) {
          eject_disk_by_num(g_cfg_slotdrive >> 8, g_cfg_slotdrive & 0xff);
        }
        g_cfg_slotdrive = -1;
        g_cfg_select_partition = -1;
        g_cfg_dirlist.invalid = 1;
        break;
      case KEY_DOWN_ARROW:          /* down arrow */
        if(g_cfg_file_pathfield == 0) {
          listhdrptr->curent++;
          cfg_fix_topent(listhdrptr);
        }
        break;
      case KEY_UP_ARROW:          /* up arrow */
        if(g_cfg_file_pathfield == 0) {
          listhdrptr->curent--;
          cfg_fix_topent(listhdrptr);
        }
        break;
      case KEY_PAGE_DOWN:     /* pg dn */
        if(g_cfg_file_pathfield == 0) {
          listhdrptr->curent += CFG_PG_SCROLL_AMT;
          cfg_fix_topent(listhdrptr);
        }
        break;
      case KEY_PAGE_UP:     /* pg up */
        if(g_cfg_file_pathfield == 0) {
          listhdrptr->curent -= CFG_PG_SCROLL_AMT;
          cfg_fix_topent(listhdrptr);
        }
        break;
      case KEY_RETURN:          /* return */
        cfg_file_selected(0);
        break;
      case KEY_TAB:          /* tab */
        g_cfg_file_pathfield = !g_cfg_file_pathfield;
        break;
      case KEY_RIGHT_ARROW:
        glogf("You can't go right!"); /* eggs - DB */
        break;
      case KEY_LEFT_ARROW:          /* left arrow */
      case KEY_DELETE:          /* delete key */
        if(g_cfg_file_pathfield) {
          len = strlen(&g_cfg_file_curpath[0]) - 1;
          if(len >= 0) {
            g_cfg_file_curpath[len] = 0;
          }
        }
        break;
      case ' ':     /* space -- selects file/directory */
        cfg_file_selected(g_cfg_file_dir_only);
        break;
      default:
        glogf("Unhandled file config key: 0x%02x", key);
    }
  }
}


static int config_read_key(void) {
    int key = -1;
    int mods;
    while(g_config_control_panel & !(halt_sim&HALT_WANTTOQUIT)) {
      video_update();
      key = adb_read_c000();
      if(key & 0x80) {
        key = key & 0x7f;
        mods = adb_read_c025();
        (void)adb_access_c010();
        //printf("key: %02x modifiers: %02x\n", key, mods);
        // Fkeys have the keypad bit set (but so do numbers) */
        if ((mods & 0x10) && key > 0x3f) key |= 0x1000;
        return key;
      }
      micro_sleep(1.0/60.0);
      g_cfg_vbl_count++;
    }
    return -1;
}

void config_display_file_menu(void) {

  int key;
  cfg_file_init();
  while (g_cfg_slotdrive >= 0) {
    cfg_file_draw();

    cfg_htab_vtab(0, 23);
    cfg_printf("Move: \tJ\t \tK\t Change: \tH\t \tU\t \tM");
    if (g_cfg_slotdrive < 0xfff) cfg_printf("\t   Eject: \bESC\b");

    key = config_read_key();
    if (key < 0) break;
    cfg_file_handle_key(key);
  }

}

void config_control_panel() {
  const char *str;
  Cfg_menu *menuptr;
  void    *ptr;
  void    *cookie;
  int line;
  int type;
  int menu_line;
  int menu_inc;
  int max_line;
  int min_line;
  int key;
  int i, j;
  // First, save important text screen state
  g_save_cur_a2_stat = g_cur_a2_stat;
  for(i = 0; i < 0x400; i++) {
    g_save_text_screen_bytes[i] = g_slow_memory_ptr[0x400+i];
    g_save_text_screen_bytes[0x400+i] =g_slow_memory_ptr[0x10400+i];
  }
  g_cur_a2_stat = ALL_STAT_TEXT | ALL_STAT_VID80 | ALL_STAT_ANNUNC3 |
                  (0xf << BIT_ALL_STAT_TEXT_COLOR) | ALL_STAT_ALTCHARSET;
  g_a2_new_all_stat[0] = g_cur_a2_stat;
  g_new_a2_stat_cur_line = 0;
  for(i = 0; i < 20; i++) {
    // Toss any queued-up keypresses
    if(adb_read_c000() & 0x80) {
      (void)adb_access_c010();
    }
  }
  g_adb_repeat_vbl = 0;
  g_cfg_vbl_count = 0;
  // HACK: Force adb keyboard (and probably mouse) to "normal"...
  g_full_refresh_needed = -1;
  g_a2_screen_buffer_changed = -1;
  cfg_home();
  j = 0;
  menuptr = g_cfg_main_menu;
  if(g_rom_version < 0) {
    /* Must select ROM file */
    menuptr = g_cfg_rom_menu;
  }
  menu_line = 1;
  menu_inc = 1;
  g_cfg_slotdrive = -1;
  g_cfg_select_partition = -1;
  while(g_config_control_panel & !(halt_sim&HALT_WANTTOQUIT)) {
    cfg_home();
    line = 1;
    cfg_printf("%s\n\n", menuptr[0].str);

    /* calc max/min items */
    max_line = 0;
    min_line = 0;
    for (i = 0;;++i) {
      const char *cp = menuptr[i].str;
      if (!cp) break;
      if (!*cp) continue; /* place holder */
      if (!min_line) min_line = i;
      max_line = i;
    }

    /* menu advancement */
    if (menu_inc > 0) {
      if (menu_line > max_line) menu_line = max_line;
      for( ; menu_line < max_line; ++menu_line) {
        const char *cp = menuptr[menu_line].str;
        if (*cp) break;
      }
      menu_inc = 0;
    }

    if (menu_inc < 0) {
      if (menu_line < min_line) menu_line = min_line;
      for( ; menu_line > min_line; --menu_line) {
        const char *cp = menuptr[menu_line].str;
        if (*cp) break;
      }
      menu_inc = 0;
    }

    while(line < 24) {
      str = menuptr[line].str;
      type = menuptr[line].cfgtype;
      ptr = menuptr[line].ptr;
      if(str == 0) {
        break;
      }

      cfg_parse_menu(menuptr, line, menu_line, 0);

      cfg_printf("%s\n", g_cfg_opt_buf);
      line++;
    }

    if(g_rom_version < 0) {
      cfg_htab_vtab(0, 21);
      cfg_printf("\bYOU MUST SELECT A VALID ROM FILE\b\n");
    }
    cfg_htab_vtab(0, 23);
    cfg_printf("Move: \tJ\t \tK\t Change: \tH\t \tU\t \tM");
    type = menuptr[menu_line].cfgtype;
    if ((type & 0x0f) == CFGTYPE_DISK) {
      cfg_printf("\t   Eject: E");
    }
#if 0
    cfg_htab_vtab(0, 22);
    cfg_printf("menu_line: %d line: %d, vbl:%d, adb:%d key_dn:%d\n",
               menu_line, line, g_cfg_vbl_count, g_adb_repeat_vbl,
               g_key_down);
#endif

#ifdef HAVE_RAWNET

#endif



    key = config_read_key();
    if (key < 0) break;

    // Normal menu system
    switch(key) {
      case KEY_DOWN_ARROW:                 /* down arrow */
        if (menu_line < max_line) menu_line++;
        menu_inc = 1;
        break;
      case KEY_UP_ARROW:                 /* up arrow */
        if (menu_line > 1) --menu_line;
        menu_inc = -1;
        break;
      case KEY_PAGE_DOWN:                 /* pg dn */
        menu_line += CFG_PG_SCROLL_AMT;
        menu_inc = 1;
        break;
      case KEY_PAGE_UP:                 /* pg up */
        menu_line -= CFG_PG_SCROLL_AMT;
        menu_inc = -1;
        break;
      case KEY_RIGHT_ARROW:                 /* right arrow */
        cfg_parse_menu(menuptr, menu_line,menu_line,1);
        break;
      case KEY_LEFT_ARROW:                 /* left arrow */
        cfg_parse_menu(menuptr,menu_line,menu_line,-1);
        break;
      case KEY_RETURN:
        type = menuptr[menu_line].cfgtype;
        ptr = menuptr[menu_line].ptr;
        str = menuptr[menu_line].str;
        cookie = menuptr[menu_line].cookie;
        switch(type & 0xf) {
          case CFGTYPE_MENU:
            menuptr = (Cfg_menu *)ptr;
            menu_line = 1;

#ifdef HAVE_SDL
            /*If user enters the Virtual Imagewriter control panel, flag it so we can
               automatically apply changes on exit.*/
            if(menuptr == g_cfg_imagewriter_menu) {
              g_cfg_triggeriwreset = 1;
            }
#endif
            break;

          case CFGTYPE_FUNC: {
            void (*fn)(void);
            fn = (void (*)(void))cookie;
            if (fn) fn();
            adb_all_keys_up();                           //Needed otherwise menu function will continue to repeat until we move selection up or down
            break;
          }

          case CFGTYPE_DISK:
            g_cfg_slotdrive = type >> 4;
            g_cfg_file_dir_only = 0;
            config_display_file_menu();
            break;
          case CFGTYPE_FILE:
            g_cfg_slotdrive = 0xfff;
            g_cfg_file_def_name = str /* *((char **)ptr) */;                           // was ptr
            g_cfg_file_strptr = (char **)ptr;
            g_cfg_file_dir_only = 0;
            config_display_file_menu();
            break;
          case CFGTYPE_DIR:
            g_cfg_slotdrive = 0xfff;
            g_cfg_file_def_name = str /* *((char **)ptr) */;                           // was ptr
            g_cfg_file_strptr = (char **)ptr;
            g_cfg_file_dir_only = 1;
            config_display_file_menu();
            break;

          case CFGTYPE_STR_FUNC: {
            void (*fn)(const char *, char **);
            fn = (void (*)(const char *, char **))cookie;
            if (fn) fn(str, (char **)ptr);
            adb_all_keys_up();
            break;
          }

        }
        break;
      case KEY_ESC:
        // Jump to last menu entry
        menu_line = max_line;
        break;
      case 'e':
      case 'E':
        type = menuptr[menu_line].cfgtype;
        if((type & 0xf) == CFGTYPE_DISK) {
          eject_disk_by_num(type >> 12,
                            (type >> 4) & 0xff);
        }
        break;
      default:
        glogf("Unhandled config key: 0x%02x", key);
    }
  }
  for(i = 0; i < 0x400; i++) {
    set_memory_c(0xe00400+i, g_save_text_screen_bytes[i], 0);
    set_memory_c(0xe10400+i, g_save_text_screen_bytes[0x400+i], 0);
  }
  // And quit
  if (g_cfg_triggeriwreset)
  {
    g_cfg_triggeriwreset = 0;
    cfg_iwreset();             //Reset the virtual Imagewriter if the user was in the control panel.
  }
  g_config_control_panel = 0;
  g_adb_repeat_vbl = g_vbl_count + 60;
  g_cur_a2_stat = g_save_cur_a2_stat;
  change_display_mode(g_cur_dcycs);
  g_full_refresh_needed = -1;
  g_a2_screen_buffer_changed = -1;
}

void x_clk_setup_bram_version() {
  if(g_rom_version < 3) {
    g_bram_ptr = (&g_bram[0][0]);               // ROM 01
  } else {
    g_bram_ptr = (&g_bram[1][0]);               // ROM 03
  }
}


#ifdef HAVE_RAWNET

void display_rawnet_menu(const char *name, const char **value) {

  char *entries[20];
  int i;
  int index = -1;
  int count = 0;
  char *ppname = NULL;
  char *ppdes = NULL;

  memset(entries, 0, sizeof(entries));

  if (rawnet_enumadapter_open()) {
    count = 0;
    while(rawnet_enumadapter(&ppname,&ppdes)) {
      entries[count] = ppname;
      free(ppdes);

      if (index < 0 && !strcmp(*value, ppname)) index = count;
      ++count;
      if (count == 20) break;
    }
    rawnet_enumadapter_close();
  }

  if (index < 0) index = 0;

  for(;;) {
    int key;

    cfg_home();
    cfg_puts(name, 1);
    for (i = 0; i < 20; ++i) {
      char *cp = entries[i];
      if (!cp) break;

      cfg_htab_vtab(4, i + 2);
      if (i == index) cfg_putchar('\b'); /* inverse */
      cfg_puts(cp, 1);
      if (i == index) cfg_putchar('\b');
    }

    cfg_htab_vtab(0, 23);
    cfg_puts("Move: \tJ\t \tK\t Change: \tM",1);

    key = config_read_key();
    switch(key) {
      case KEY_UP_ARROW:
        if (index) --index;
        break;
      case KEY_DOWN_ARROW:
        if (index < count - 1) ++index;
        break;
      case KEY_PAGE_UP:
        index -= CFG_PG_SCROLL_AMT;
        if (index < 0) index = 0;
        break;
      case KEY_PAGE_DOWN:
        index += CFG_PG_SCROLL_AMT;
        if (index >= count) index = count - 1;
        break;
      case KEY_RETURN:
        if (index < count) {
          *value = strdup(entries[index]);
        }
        key = -1;
        break;
      case KEY_ESC:
        key = -1;
        break;
    }
    if (key < 0) break;
  }

  for (i = 0; i < 20; ++i) free(entries[i]);
}


void cfg_get_tfe_name()      {
  int i = 0;
  char *ppname = NULL;
  char *ppdes = NULL;
  cfg_htab_vtab(0,11);
  if (rawnet_enumadapter_open())
  {
    cfg_printf("Interface List:\n---------------");
    while(rawnet_enumadapter(&ppname,&ppdes))
    {
      cfg_htab_vtab(0, 13+i);
      cfg_printf("%2d: %s",i,ppdes);
      i++;
      free(ppname);
      free(ppdes);
    }
    rawnet_enumadapter_close();
  }
  else
  {
#if defined(_WIN32)
    cfg_printf("ERROR: Install/Enable WinPcap for Ethernet Support!!");
#else
    cfg_printf("ERROR: Install/Enable LibPcap for Ethernet Support!!");
#endif
  }
  return;
}
#endif
#endif
