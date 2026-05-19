#pragma once

#include "Platform.h"
#include "AudioSource.h"
#include "Error.h"
#include <deque>
#include <memory>
#include <mmeapi.h>

class AudioDevice
{
public:
	virtual ~AudioDevice();
	virtual Error* Create() = 0;
	virtual Error* Destroy() = 0;
	virtual Error* Tick(float elapsed) = 0;
};

class WaveOutAudioDevice : public AudioDevice, public AudioSource
{
public:
	WaveOutAudioDevice(std::unique_ptr<AudioSource> in_source);
	~WaveOutAudioDevice();

	virtual Error* Create() override;
	virtual Error* Destroy() override;
	virtual Error* Tick(float elapsed) override;

	virtual void Read(void* read_data, size_t read_size) override;

private:
	static const int NUM_PACKETS = 4;

	struct Packet
	{
		size_t stream_pos;
		WAVEHDR header = {};
		std::unique_ptr<uint8[]> buffer;
		size_t buffer_size = 0;
	};

	size_t stream_pos;
	size_t read_pos;

	HWAVEOUT waveout_handle = nullptr;
	std::unique_ptr<AudioSource> audio_source;

	Packet packets[NUM_PACKETS];
	int next_packet = 0;

	static void CALLBACK WaveOutStaticCallback(HWAVEOUT hwo, UINT uMsg, DWORD_PTR dwInstance, DWORD_PTR dwParam1, DWORD_PTR dwParam2);

	Error* WriteNextPackets();
	Error* CreateWaveOutError(MMRESULT res);
};
