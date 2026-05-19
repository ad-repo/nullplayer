#include "AudioSource.h"
#include <mmeapi.h>
#include <assert.h>

AudioSource::~AudioSource()
{
}

///////////////////////////////////////////

void RandomAudioSource::Read(void* read_data, size_t read_size)
{
	uint8* read_bytes = (uint8*)read_data;
	for (size_t idx = 0; idx < read_size; idx++)
	{
		read_bytes[idx] = rand();
	}
}

///////////////////////////////////////////

MemoryAudioSource::MemoryAudioSource(std::shared_ptr<uint8[]> in_data, size_t in_data_len)
	: data(in_data)
	, data_pos(0)
	, data_len(in_data_len)
{
}

MemoryAudioSource::~MemoryAudioSource()
{
}

void MemoryAudioSource::Read(void* read_data, size_t read_size)
{
	for (;;)
	{
		size_t chunk_size = std::min(data_len - data_pos, read_size);
		memcpy(read_data, data.get() + data_pos, chunk_size);

		data_pos += chunk_size;
		read_size -= chunk_size;
		read_data = (uint8*)read_data + chunk_size;

		if (read_size == 0)
		{
			break;
		}

		data_pos = 0;
	}
}

Error* MemoryAudioSource::CreateFromWavFile(const char* path, std::unique_ptr<MemoryAudioSource>& out_source)
{
	// Read the raw data into memory
	FILE* file;
	if (fopen_s(&file, path, "rb") != 0)
	{
		return new Error(std::string("Unable to open file: ") + std::string(path));
	}

	fseek(file, 0, SEEK_END);
	long length = ftell(file);
	fseek(file, 0, SEEK_SET);
	std::unique_ptr<uint8[]> wav_file_data = std::make_unique<uint8[]>(length);
	fread(wav_file_data.get(), 1, length, file);
	fclose(file);

	// Parse the WAV file structure
	const uint8* wav_header = wav_file_data.get();
	if (memcmp(wav_header, "RIFF", 4) != 0)
	{
		return new Error("Missing RIFF bytes at start of WAV file");
	}
	if (memcmp(wav_header + 8, "WAVE", 4) != 0)
	{
		return new Error("Missing WAVE section in WAV file");
	}

	int num_channels = 0;
	int sample_rate = 0;
	int bits_per_sample = 0;
	const uint8* source_data = nullptr;
	uint32 source_data_len = 0;

	for (long pos = 12; pos < length; )
	{
		const uint8* chunk_header = wav_header + pos;
		uint32 chunk_len = *((const uint32*)(chunk_header + 4));

		const uint8* chunk_data = chunk_header + 8;
		if (memcmp(chunk_header, "fmt ", 4) == 0)
		{
			const WAVEFORMATEX* format = (const WAVEFORMATEX*)chunk_data;
			if (format->wFormatTag != WAVE_FORMAT_PCM)
			{
				return new Error("Unsupported WAV format; must be PCM encoded");
			}

			num_channels = format->nChannels;
			sample_rate = format->nSamplesPerSec;
			bits_per_sample = format->wBitsPerSample;
		}
		else if (memcmp(chunk_header, "data", 4) == 0)
		{
			source_data = chunk_data;
			source_data_len = chunk_len;
		}

		pos += 8 + chunk_len;
	}

	if (num_channels == 0 || source_data == nullptr)
	{
		return new Error("Missing headers from WAV file");
	}

	// Resample the data to the required format
	if (bits_per_sample == 8)
	{
		out_source = ResampleData<int8>(source_data, source_data_len, num_channels, sample_rate);
		return nullptr;
	}
	else if (bits_per_sample == 16)
	{
		out_source = ResampleData<int16>(source_data, source_data_len, num_channels, sample_rate);
		return nullptr;
	}
	else
	{
		assert(false);
		return new Error("Not supported");
	}
}

template<> struct MemoryAudioSource::Resample<int8>
{
	static int16 GetValue(int8 sample) { return sample << 8; }
};

template<> struct MemoryAudioSource::Resample<int16>
{
	static int16 GetValue(int16 sample) { return sample; }
};

template<typename T> std::unique_ptr<MemoryAudioSource> MemoryAudioSource::ResampleData(const void* input_data, size_t input_length, int num_channels, int sample_rate)
{
	size_t input_block_size = num_channels * sizeof(T);
	size_t input_block_count = input_length / input_block_size;

	size_t r_channel_offset = (num_channels > 1) ? 1 : 0;

	size_t output_block_count = (input_block_count * SAMPLE_RATE) / sample_rate;

	size_t buffer_len = output_block_count * NUM_CHANNELS * sizeof(int16);
	std::unique_ptr<uint8[]> buffer = std::make_unique<uint8[]>(buffer_len);

	const T* input_samples = (const T*)input_data;
	int16* output_samples = (int16*)buffer.get();

	const T* input_block = input_samples;

	size_t block_remainder = 0;
	float block_t_mult = 1.0f / output_block_count;

	for (size_t idx = 0; idx < output_block_count; idx++)
	{
		float block_t = block_remainder * block_t_mult;

		const T* input_l = input_block;
		*(output_samples++) = Resample<T>::GetValue(*input_l + (*(input_l + num_channels) - *input_l) * block_t);

		const T* input_r = input_block + r_channel_offset;
		*(output_samples++) = Resample<T>::GetValue(*input_r + (*(input_r + num_channels) - *input_r) * block_t);

		block_remainder += input_block_count;
		while (block_remainder >= output_block_count)
		{
			input_block += num_channels;
			block_remainder -= output_block_count;
		}
	}

	return std::make_unique<MemoryAudioSource>(std::move(buffer), buffer_len);
}


