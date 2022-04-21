/*
  GSPLUS - Advanced Apple IIGS Emulator Environment
  Based on the KEGS emulator written by Kent Dickey
  See COPYRIGHT.txt for Copyright information
	See LICENSE.txt for license (GPL v2)
*/

#define MAX_TRACKS	(2*80)
#define MAX_C7_DISKS	32

#define NIB_LEN_525		0x1900		/* 51072 bits per track */
#define NIBS_FROM_ADDR_TO_DATA	20

#define DSK_TYPE_PRODOS		0
#define DSK_TYPE_DOS33		1
#define DSK_TYPE_NIB		2

typedef struct _Disk Disk;

STRUCT(Trk) {
	Disk	*dsk;
	byte	*nib_area;
	int	track_dirty;
	int	overflow_size;
	int	track_len;
	int	unix_pos;
	int	unix_len;
};

struct _Disk {
	double	dcycs_last_read;
	char	*name_ptr;
	char	*partition_name;
	int	partition_num;
	FILE	*file;
	int	force_size;
	int	image_start;
	int	image_size;
	int	smartport;
	int	disk_525;
	int	drive;
	int	cur_qtr_track;
	int	image_type;
	int	vol_num;
	int	write_prot;
	int	write_through_to_unix;
	int	disk_dirty;
	int	just_ejected;
	int	last_phase;
	int	nib_pos;
	int	num_tracks;
	Trk	*trks;
};


STRUCT(Iwm) {
	Disk	drive525[2];
	Disk	drive35[2];
	Disk	smartport[MAX_C7_DISKS];
	int	motor_on;
	int	motor_off;
	int	motor_off_vbl_count;
	int	motor_on35;
	int	head35;
	int	step_direction35;
	int	iwm_phase[4];
	int	iwm_mode;
	int	drive_select;
	int	q6;
	int	q7;
	int	enable2;
	int	reset;

	word32	previous_write_val;
	int	previous_write_bits;
};


STRUCT(Driver_desc) {
	word16	sig;
	word16	blk_size;
	word32	blk_count;
	word16	dev_type;
	word16	dev_id;
	word32	data;
	word16	drvr_count;
};

STRUCT(Part_map) {
	word16	sig;
	word16	sigpad;
	word32	map_blk_cnt;
	word32	phys_part_start;
	word32	part_blk_cnt;
	char	part_name[32];
	char	part_type[32];
	word32	data_start;
	word32	data_cnt;
	word32	part_status;
	word32	log_boot_start;
	word32	boot_size;
	word32	boot_load;
	word32	boot_load2;
	word32	boot_entry;
	word32	boot_entry2;
	word32	boot_cksum;
	char	processor[16];
	char	junk[128];
};
