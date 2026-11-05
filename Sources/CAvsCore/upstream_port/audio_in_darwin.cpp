// NullPlayer: libavs's own audio capture (upstream audio_in_linux_pipewire.cpp /
// audio_in_windows_wasapi.cpp) is not ported. NullPlayer always initialises AVS with
// AVS_AUDIO_EXTERNAL and feeds its playback audio through avs_audio_set(), so the capture
// entry points only have to exist: there is no input device to start.
#include "vis_avs/audio_in.h"

AVS_Audio_Input* audio_in_start(avs_audio_input_handler, void*) { return nullptr; }
void audio_in_stop(AVS_Audio_Input*) {}
std::vector<std::string> audio_in_devices() { return {}; }
bool audio_in_select_device(uint32_t) { return false; }
