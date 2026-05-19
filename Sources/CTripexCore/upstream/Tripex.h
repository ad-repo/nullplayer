#pragma once

#include "TextureFont.h"
#include "AudioData.h"
#include "Effect.h"
#include "TextureLibrary.h"
#include "GeometryBuffer.h"
#include <bitset>

class Tripex
{
public:
	Tripex(std::shared_ptr<Renderer> renderer);
	~Tripex();

	Error* Startup();
	Error* Render(AudioSource& audio_source);
	void Shutdown();

	void ChangeEffect();
	void MoveToPrevEffect();
	void MoveToNextEffect();
	void ReconfigureEffect();
	void ToggleHoldingEffect();

	void ToggleAudioInfo();
	void ToggleHelp();

private:
	static const int MSG_DISPLAY_TIME = 4000;
	static const int MSG_FADEOUT_TIME = 1000;

	enum
	{
		TXS_VISIBLE_BEATS,
		TXS_RESET_TIMING,
		TXS_CHANGE_EFFECT,
		TXS_IN_FADE,
		TXS_EFFECT_LEFT,
		TXS_EFFECT_RIGHT,
		TXS_RECONFIGURE,
		TXS_HOLD,
		TXS_RESET_TARGET,
		TXS_SHOW_HELP,

		TXS_LAST,
	};

	std::bitset<TXS_LAST> txs;
	std::unique_ptr<AudioData> audio;

	Effect* blank_effect;

	TextureLibrary texture_library;

	GeometryBuffer overlay_background;
	GeometryBuffer overlay_text;
	GeometryBuffer overlay_foreground;

	std::shared_ptr<Renderer> renderer;
	TextureFont tef;
	float effect_frames, fade_pos;
	char status_msg[256];
	uint32 status_time;
	unsigned int id;
	int effect_idx;
	int next_effect_idx;
	std::shared_ptr<Texture> gui;
	uint32 last_time;
	float frames = 0.0f;

	std::vector<std::shared_ptr<Effect>> effects;
	std::vector<std::shared_ptr<Effect>> enabled_effects;

	void ShowStatusMsg(const char* format, ...);

	void DrawMessage(const TextureFont& font, int y, const char* text, float brightness, float back_brightness);
	int GetClippedLineLength(const TextureFont& font, const char* text, int clip_width);

	void AddEffect(std::shared_ptr<Effect>(*fn)(), const char* name, int draw_order, float startup_weight, int preference, int change, int sensitivity, int activity, int speed);
	void CreateEffects();
};
