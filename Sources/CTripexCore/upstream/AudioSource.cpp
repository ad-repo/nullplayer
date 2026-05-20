#include "AudioSource.h"
#include <mmeapi.h>
#include <assert.h>
#include <algorithm>

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
	if (data_len == 0)
	{
		memset(read_data, 0, read_size);
		return;
	}

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
	if (length < 12)
	{
		fclose(file);
		return new Error("WAV file too small");
	}
	fseek(file, 0, SEEK_SET);
	std::unique_ptr<uint8[]> wav_file_data = std::make_unique<uint8[]>(length);
	if (fread(wav_file_data.get(), 1, length, file) != (size_t)length)
	{
		fclose(file);
		return new Error("Unable to read WAV file");
	}
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

	for (long pos = 12; pos + 8 <= length; )
	{
		const uint8* chunk_header = wav_header + pos;
		uint32 chunk_len = *((const uint32*)(chunk_header + 4));
		long chunk_data_pos = pos + 8;
		if (chunk_len > (uint32)(length - chunk_data_pos))
		{
			return new Error("Invalid WAV chunk length");
		}

		const uint8* chunk_data = chunk_header + 8;
		if (memcmp(chunk_header, "fmt ", 4) == 0)
		{
			if (chunk_len < 16)
			{
				return new Error("Invalid fmt chunk");
			}
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

		pos += 8 + chunk_len + (chunk_len & 1);
	}

	if (num_channels == 0 || sample_rate <= 0 || source_data == nullptr)
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
	if (sample_rate <= 0 || num_channels <= 0)
	{
		return std::make_unique<MemoryAudioSource>(std::shared_ptr<uint8[]>(new uint8[0]), 0);
	}

	size_t input_block_size = num_channels * sizeof(T);
	size_t input_block_count = input_length / input_block_size;
	if (input_block_count == 0)
	{
		return std::make_unique<MemoryAudioSource>(std::shared_ptr<uint8[]>(new uint8[0]), 0);
	}

	size_t r_channel_offset = (num_channels > 1) ? 1 : 0;

	size_t output_block_count = (size_t)((double)input_block_count * SAMPLE_RATE / sample_rate);
	if (output_block_count == 0) output_block_count = 1;

	size_t buffer_len = output_block_count * NUM_CHANNELS * sizeof(int16);
	std::unique_ptr<uint8[]> buffer = std::make_unique<uint8[]>(buffer_len);

	const T* input_samples = (const T*)input_data;
	int16* output_samples = (int16*)buffer.get();

	for (size_t idx = 0; idx < output_block_count; idx++)
	{
		double input_pos = (double)idx * sample_rate / SAMPLE_RATE;
		size_t input_block_idx = std::min((size_t)input_pos, input_block_count - 1);
		size_t next_block_idx = std::min(input_block_idx + 1, input_block_count - 1);
		float block_t = (float)(input_pos - input_block_idx);

		const T* input_l = input_samples + (input_block_idx * num_channels);
		const T* next_l = input_samples + (next_block_idx * num_channels);
		*(output_samples++) = Resample<T>::GetValue(*input_l + (*next_l - *input_l) * block_t);

		const T* input_r = input_l + r_channel_offset;
		const T* next_r = next_l + r_channel_offset;
		*(output_samples++) = Resample<T>::GetValue(*input_r + (*next_r - *input_r) * block_t);
	}

	return std::make_unique<MemoryAudioSource>(std::move(buffer), buffer_len);
}
