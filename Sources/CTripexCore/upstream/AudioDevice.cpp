#include "AudioDevice.h"
#include "Misc.h"

AudioDevice::~AudioDevice()
{
}

///////////////////////////////////////

WaveOutAudioDevice::WaveOutAudioDevice(std::unique_ptr<AudioSource> in_audio_source)
	: audio_source(std::move(in_audio_source))
	, stream_pos(0)
	, read_pos(0)
{
	for (Packet& packet : packets)
	{
		packet.stream_pos = 0;
		memset(&packet.header, 0, sizeof(packet.header));
		packet.header.dwFlags |= WHDR_DONE;
		packet.buffer_size = (int)(0.1 * AudioSource::SAMPLE_RATE) * AudioSource::NUM_CHANNELS * (AudioSource::SAMPLE_DEPTH / 8);
		packet.buffer = std::make_unique<uint8[]>(packet.buffer_size);
	}
}

WaveOutAudioDevice::~WaveOutAudioDevice()
{
	Destroy();
}

Error* WaveOutAudioDevice::Create()
{
	WAVEFORMATEX format = {};
	format.cbSize = sizeof(format);
	format.wFormatTag = WAVE_FORMAT_PCM;
	format.nChannels = AudioSource::NUM_CHANNELS;
	format.wBitsPerSample = AudioSource::SAMPLE_DEPTH;
	format.nSamplesPerSec = AudioSource::SAMPLE_RATE;
	format.nBlockAlign = format.nChannels * (format.wBitsPerSample / 8);
	format.nAvgBytesPerSec = format.nBlockAlign * format.nSamplesPerSec;

	MMRESULT res = waveOutOpen(&waveout_handle, WAVE_MAPPER, &format, (DWORD_PTR)&WaveOutStaticCallback, (DWORD_PTR)this, CALLBACK_FUNCTION);
	if (res != S_OK) return CreateWaveOutError(res);

	return WriteNextPackets();
}

Error* WaveOutAudioDevice::Destroy()
{
	MMRESULT res = waveOutReset(waveout_handle);
	if (res != S_OK) return CreateWaveOutError(res);

	res = waveOutClose(waveout_handle);
	if (res != S_OK) return CreateWaveOutError(res);

	return nullptr;
}

Error* WaveOutAudioDevice::Tick(float elapsed)
{
	for (Packet& packet : packets)
	{
		if ((packet.header.dwFlags & (WHDR_DONE | WHDR_PREPARED)) == (WHDR_DONE | WHDR_PREPARED))
		{
			MMRESULT res = waveOutUnprepareHeader(waveout_handle, &packet.header, sizeof(packet.header));
			if (res != S_OK) return CreateWaveOutError(res);
		}
	}

	return WriteNextPackets();
}

void WaveOutAudioDevice::Read(void* read_data, size_t read_size)
{
	int packet_idx = next_packet;
	for (int idx = 0; idx < NUM_PACKETS; idx++)
	{
		const Packet& packet = packets[packet_idx];

		if (read_pos < packet.stream_pos)
		{
			read_pos = packet.stream_pos;
		}

		size_t packet_ofs = read_pos - packet.stream_pos;
		if (packet_ofs < packet.buffer_size)
		{
			size_t packet_size = std::min(read_size, packet.buffer_size - packet_ofs);
			memcpy(read_data, packet.buffer.get() + packet_ofs, packet_size);

			read_pos += packet_size;
			read_size -= packet_size;

			if (read_size == 0) break;
		}

		if (++packet_idx == NUM_PACKETS)
		{
			packet_idx = 0;
		}
	}
}

Error* WaveOutAudioDevice::WriteNextPackets()
{
	for (;;)
	{
		Packet& packet = packets[next_packet];
		if ((packet.header.dwFlags & (WHDR_DONE | WHDR_PREPARED)) != WHDR_DONE)
		{
			break;
		}

		packet.stream_pos = stream_pos;
		audio_source->Read(packet.buffer.get(), packet.buffer_size);

		stream_pos += packet.buffer_size;

		memset(&packet.header, 0, sizeof(packet.header));
		packet.header.lpData = (LPSTR)packet.buffer.get();
		packet.header.dwBufferLength = (DWORD)packet.buffer_size;

		MMRESULT res = waveOutPrepareHeader(waveout_handle, &packet.header, sizeof(packet.header));
		if (res != S_OK) return CreateWaveOutError(res);

		res = waveOutWrite(waveout_handle, &packet.header, sizeof(packet.header));
		if (res != S_OK) return CreateWaveOutError(res);

		if (++next_packet == NUM_PACKETS)
		{
			next_packet = 0;
		}
	}

	return nullptr;
}

Error* WaveOutAudioDevice::CreateWaveOutError(MMRESULT res)
{
	char buffer[256];
	waveOutGetErrorTextA(res, buffer, sizeof(buffer));
	return new Error(std::string("Wave out error: ") + std::string(buffer));
}

void CALLBACK WaveOutAudioDevice::WaveOutStaticCallback(HWAVEOUT hwo, UINT uMsg, DWORD_PTR dwInstance, DWORD_PTR dwParam1, DWORD_PTR dwParam2)
{
}
