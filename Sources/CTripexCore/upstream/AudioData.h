#pragma once

#include "AudioSource.h"
#include "Fourier.h"
#include "GeometryBuffer.h"

class AudioData
{
protected:
	static const int INTERNAL_SAMPLE_RATE = AudioSource::SAMPLE_RATE;

	static const int FREQ_HISTORY_SIZE = 20;
	static const int FREQ_BANDS = 256;
	static const int BEATHISTORY = 5;

	static const float FREQ_BAND_POWER;

	std::vector<int16> mono_samples;
	std::vector<int16> stereo_samples;
	float freq_history[FREQ_HISTORY_SIZE][16];
	Fourier fourier;

	int band_idx[FREQ_BANDS];
	float band_mul[FREQ_BANDS];
	float bands[FREQ_BANDS] = {};

	float beat_history[BEATHISTORY] = {};

	float intensity;
	float beat;
	float intensity_beat_scale;
	bool is_beat;

public:
	const int num_samples;

	AudioData(int num_samples);
	~AudioData();

	void Update(float elapsed, float sensitivity, AudioSource& audio_source);
	void Render(GeometryBuffer& overlay_back, GeometryBuffer& overlay, float overlay_back_mult) const;

	float GetIntensity() const;
	float GetBeat() const;
	bool IsBeat() const;
	float GetRandomSample() const;
	void SetIntensityBeatScale(float scale);
	float GetDampenedBand(float dampen, float min, float max) const;

	float GetSample(int sample_idx) const;
	float GetSample(int channel_idx, int sample_idx) const;

	float GetBand(int idx) const;

private:
	float block_pos = 0;

	static void DrawLineBar(GeometryBuffer& geom, int x, int y, int h, float p);
	static void DrawHorizontalBar(GeometryBuffer& geom, int x, int y, int w, int h, float p);
};
