#include "Platform.h"
#include "Effect.h"
#include <d3d9.h>

class EffectBlank : public Effect
{
public:
	Error* Calculate(const CalculateParams& params) override
	{
		return nullptr;
	};
	Error* Render(const RenderParams& params) override
	{
		return nullptr;
	}
};

EXPORT_EFFECT(Blank, EffectBlank)
