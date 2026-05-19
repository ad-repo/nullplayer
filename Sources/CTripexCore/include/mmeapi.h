#ifndef TRIPEX_PORT_MMEAPI_STUB_H
#define TRIPEX_PORT_MMEAPI_STUB_H
// AudioSource.cpp references WAVEFORMATEX once to decode WAV file headers.
#include "win_compat.h"

typedef struct _TripexWAVEFORMATEX {
    WORD  wFormatTag;
    WORD  nChannels;
    DWORD nSamplesPerSec;
    DWORD nAvgBytesPerSec;
    WORD  nBlockAlign;
    WORD  wBitsPerSample;
    WORD  cbSize;
} WAVEFORMATEX;

#endif
