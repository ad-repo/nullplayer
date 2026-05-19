#pragma once

#include <string>
#include <set>
#include <memory>
#include "error.h"
#include "AudioData.h"
#include "Renderer.h"
#include "TextureLibrary.h"

enum
{
	// z buffering
	ZORDER_BUMPMAPPING,
	ZORDER_METABALLS,
	ZORDER_ANALYSER,
	ZORDER_WATERGLOBE,
	ZORDER_OSCILLOSCOPE,
	ZORDER_RINGS,
	ZORDER_TUBE,

	// alpha only
	ZORDER_BEZIERCUBE,
	ZORDER_COLLAPSINGSPHERE,
	ZORDER_DISTORTION,
	ZORDER_DISTORTION2,
	ZORDER_DISTORTION2COL,
	ZORDER_DOTSTAR,
	ZORDER_FLOWMAP, 
	ZORDER_LIGHTRING,
	ZORDER_LIGHTSPHERE,
	ZORDER_LIGHTSTAR,
	ZORDER_LIGHTTENTACLES,
	ZORDER_MORPHINGSPHERE,
	ZORDER_MOTIONBLUR,
	ZORDER_MOTIONBLUR2,
	ZORDER_MOTIONBLUR3,
	ZORDER_MOTIONBLUR3ALT,
	ZORDER_PHASED,
	ZORDER_SUN,
	ZORDER_TUNNEL,
	ZORDER_BLANK,
};

class Effect
{
public:
	struct CalculateParams
	{
		float brightness;
		float elapsed;
		const AudioData& audio_data;
		Renderer& renderer;

		CalculateParams(float brightness, float elapsed, const AudioData& audio_data, Renderer& renderer)
			: brightness(brightness)
			, elapsed(elapsed)
			, audio_data(audio_data)
			, renderer(renderer)
		{
		}
	};

	struct ReconfigureParams
	{
		const AudioData& audio_data;
		const TextureLibrary& texture_library;

		ReconfigureParams(const AudioData& audio_data, const TextureLibrary& texture_library)
			: audio_data(audio_data)
			, texture_library(texture_library)
		{
		}
	};

	struct RenderParams
	{
		Renderer& renderer;

		RenderParams(Renderer& renderer)
			: renderer(renderer)
		{
		}
	};

	float fBr;
	bool bValid;
	int nLastUsed;
	float fProb;

	std::string name;
	int draw_order;
	float startup_weight;

	float preference;
	float change;
	float sensitivity;
	float activity;
	float speed;

	const std::vector<const TextureClass*> textures;

	Effect();
	Effect(std::initializer_list<const TextureClass*> textures);
	virtual ~Effect();

	virtual Error* Calculate(const CalculateParams& params) = 0;
	virtual Error* Reconfigure(const ReconfigureParams& params);
	virtual Error* Render(const RenderParams& params) = 0;

	bool CanRender(float fFrames);

	float GetElapsed(float fFrames);
	std::string GetCfgItemName() const;

protected:
	virtual bool CanRenderImpl(float elapsed);
};

#define IMPORT_EFFECT(name) extern std::shared_ptr<Effect> CreateEffect_##name( );
#define EXPORT_EFFECT(name, type) std::shared_ptr<Effect> CreateEffect_##name( ){ return std::make_shared<type>(); }
