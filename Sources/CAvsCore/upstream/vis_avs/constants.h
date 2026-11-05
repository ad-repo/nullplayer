#pragma once

// 64k is the maximum component size in AVS
#define MAX_CODE_LEN       (1 << 16)
// Maximum number of threads
#define MAX_SMP_THREADS    8
// 1 drive letter + 1 colon + 1 backslash + 256 path + 1 terminating null
#define MAX_PATH           260
#define NUM_GLOBAL_BUFFERS 8

#define M_PI 3.14159265358979323846

// Same as MAX_PATH now, but while MAX_PATH could be anything, LEGACY_SAVE_PATH_LEN is
// fixed as part of the legacy preset file format.
#define LEGACY_SAVE_PATH_LEN             260
// Length of the APE ID string which includes trailing null-bytes if any
#define LEGACY_APE_ID_LENGTH             32
#define MAX_LEGACY_PRESET_FILESIZE_BYTES (1024 * 1024)
