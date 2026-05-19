#include "Platform.h"
#include "Actor.h"
#include "effect.h"
#include "error.h"
#include "TextureData.h"

class EffectPhased : public Effect
{
public:
	const TextureClass sprite_texture_class =
	{
		"Sprite",
		{ tex_light }
	};

	static const int DEPTH = 8;
	static const int MAG = 20;

	static const int FRAMEFAC = 50;

	static const int AVERAGES = 10;

	Actor obj;
	Camera camera;

	double accum;
	int lastbeat;
	double a;

	EffectPhased()
		: Effect({ &sprite_texture_class })
	{
		a = 0;
		lastbeat = 0;
		accum = 0;

		obj.vertices.resize(DEPTH * DEPTH * DEPTH);
		obj.frame_history = 5.0f;
		obj.flags.set(Actor::F_DRAW_TRANSPARENT);
		obj.flags.set(Actor::F_DRAW_VERTEX_SPRITES);
		obj.exposure = 6;//3;//4;//6;

		int index = 0;
		for (int x = 0; x < DEPTH; x++)
		{
			for (int y = 0; y < DEPTH; y++)
			{
				for (int z = 0; z < DEPTH; z++)
				{
					obj.vertices[index].position.x = (x - (DEPTH / 2)) * MAG;
					obj.vertices[index].position.y = (y - (DEPTH / 2)) * MAG;
					obj.vertices[index].position.z = (z - (DEPTH / 2)) * MAG;
					index++;
				}
			}
		}
	}

	Error* Calculate(const CalculateParams& params) override
	{
		float elapsed = params.elapsed * 1.5;

		a += elapsed * (params.audio_data.GetIntensity() + 0.1) * 3.14159 / 180.0;

		obj.roll += elapsed * (params.audio_data.GetIntensity() + (params.audio_data.GetBeat() * 2.0)) * 2/*5*//*7*/ * 3.14159 / 180.0;
		obj.pitch += elapsed * (params.audio_data.GetIntensity() + 0.1) * 4/*4*/ /*8*/ * 3.14159 / 180;
		obj.yaw += elapsed * params.audio_data.GetBeat() * 3/*3*//*5*/ * 3.14159 / 180.0;
		obj.ambient_light_color = ColorRgb::Grey(2 * 0.15 * params.brightness * 255.0);//color = D3DRGB(0.15 * brightness, 0.15 * brightness, 0.15 * brightness);
		obj.exposure_light_delta = WideColorRgb(-2, -2, 0);

		obj.Calculate(params.renderer, &camera, elapsed);

		camera.position = Vector3(40 * sin(a) * cos(a * 1.2), 40 * cos(a * 0.7) * sin(a * 0.9), 40 * cos(a * 1.4) * sin(0.7));
		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		Texture* tx = params.texture_library.Find(sprite_texture_class);
		obj.textures[0].Set(Actor::TextureType::Sprite, tx);
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		Error* error = obj.Render(params.renderer);
		if (error) return TraceError(error);

		return nullptr;
	}

	bool CanRenderImpl(float fElapsed)
	{
		return fElapsed > 0.5f;//(fElapsed > 0.5f);
	}
};

EXPORT_EFFECT(Phased, EffectPhased)
