#pragma once

#include <memory>
#include <vector>
#include "Error.h"

class AudioSource
{
public:
	static const int NUM_CHANNELS = 2;
	static const int SAMPLE_RATE = 44100;
	static const int SAMPLE_DEPTH = 16;

	virtual ~AudioSource();
	virtual void Read(void* read_data, size_t read_size) = 0;
};

class RandomAudioSource : public AudioSource
{
public:
	virtual void Read(void* read_data, size_t read_size) override;
};

class MemoryAudioSource : public AudioSource
{
public:
	std::shared_ptr<uint8[]> data;
	size_t data_pos;
	const size_t data_len;

	MemoryAudioSource(std::shared_ptr<uint8[]> data, size_t data_len);
	virtual ~MemoryAudioSource();
	virtual void Read(void* read_data, size_t read_size) override;

	static Error* CreateFromWavFile(const char* path, std::unique_ptr<MemoryAudioSource>& out_source);

private:
	template<typename T> struct Resample;
	template<typename T> static std::unique_ptr<MemoryAudioSource> ResampleData(const void* input_data, size_t input_length, int num_channels, int sample_rate);
};
