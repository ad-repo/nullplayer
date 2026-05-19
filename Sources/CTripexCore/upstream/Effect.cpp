#include "Platform.h"
#include "Renderer.h"
#include "Effect.h"

/******** ZEffectBase ************************************/
Effect::Effect()
	: Effect({})
{
}
Effect::Effect(std::initializer_list<const TextureClass*> textures)
	: textures(textures)
{
	bValid = false;
	fBr = 0.0f;
	fProb = 0.0f;
	startup_weight = 0.0f;
	draw_order = 0;
	nLastUsed = 0;

	preference = 0.0f;
	change = 0.0f;
	sensitivity = 0.0f;
	activity = 0.0f;
	speed = 0.0f;
}

Effect::~Effect()
{
}

Error* Effect::Reconfigure(const ReconfigureParams& params)
{
	return nullptr;
}

bool Effect::CanRenderImpl(float fElapsed)
{
	return true;
}

bool Effect::CanRender(float fFrames)
{
	if (fFrames > 3.8)
	{
		return true;
	}
	else
	{
		return CanRenderImpl(GetElapsed(fFrames));
	}
}

float Effect::GetElapsed(float fFrames)
{
	return fFrames * ((1.8f * speed) + 0.1f);
}

std::string Effect::GetCfgItemName() const
{
	std::string sCfgName = "Effects\\";
	for (int i = 0; name[i] != 0; i++)
	{
		if (isalnum(name[i])) sCfgName += name[i];
	}
	return sCfgName;
}

#if false
/******** ZEffectPtr **************************************/
Error* EffectHandler::Calculate(float fElapsed, AudioData& audio_data, Renderer& renderer)
{
	assert(pEffect != nullptr);

	audio_data.SetIntensityBeatScale( fSensitivity * 3.0f );

	EffectBase::CalculateParams params(fBr, GetElapsed(fElapsed), audio_data, renderer);
	Error* error = pEffect->Calculate(params);

	audio_data.SetIntensityBeatScale( 0.0f );
	return error;
}
Error* EffectHandler::Render(Renderer& renderer)
{
	assert(pEffect != nullptr);

	EffectBase::RenderParams params(renderer);
	return pEffect->Render(params);
}
bool EffectHandler::CanRender(float fFrames)
{
	assert(pEffect != nullptr);

	if(fFrames > 3.8) return true;
	else return pEffect->CanRender(GetElapsed(fFrames));
}
#endif
