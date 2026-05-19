#include "Platform.h"
#include "Actor.h"
#include "Effect.h"
#include "BezierCurve.h"
#include "TextureData.h"
#include "VertexGrid.h"

class EffectLightRing : public Effect
{
public:
	const TextureClass sprite_texture_class =
	{
		"Sprite",
		{ tex_light }
	};

	const TextureClass tint_texture_class =
	{
		"Tint",
		{ tex_eyes, tex_flesh, tex_forest, tex_shiny_sand }
	};

	static const int SOURCES = 40;//40//35//50
	static const int FRAMES = 12;
	static const int LENGTH = 1;
	static const int BUFFERSTEP = 100;

	BezierCurve b;
	Vector3 ls[SOURCES][4];
	double position[SOURCES];
	double speed[SOURCES];
	double length[FRAMES][SOURCES] = { };
	double er[SOURCES];
	double ehp[SOURCES];
	double ehps[SOURCES];
	double accum, r, p, y;
	double brt = 0;
	double a2 = 0;
	Texture* tint = nullptr;
	Actor obj;
	Camera camera;

	Texture* texture = nullptr;
	double br = 0;

	EffectLightRing()
		: Effect({ &sprite_texture_class, &tint_texture_class })
	{
		accum = 0;
		r = p = y = 0;

		camera.position.z = -50;
		b.Create(4);
		for (int i = 0; i < SOURCES; i++)
		{
			position[i] = rand() * 2.0 * 3.14159 / RAND_MAX;
			speed[i] = rand() * 20.0 * (3.14159 / 180.0) / RAND_MAX;

			er[i] = rand() * 30.0 / RAND_MAX;
			ehp[i] = rand() * 2.0 * 3.14159 / RAND_MAX;
			ehps[i] = rand() * 3.0 * (3.14159 / 180.0) / RAND_MAX;
		}

		obj.flags.set(Actor::F_DRAW_TRANSPARENT);
		obj.flags.set(Actor::F_DRAW_VERTEX_SPRITES);
		obj.flags.set(Actor::F_DRAW_VERTEX_SPRITE_HISTORY);

		obj.sprite_history_length = 4.0f;
		obj.frame_history = 12.0f;
		obj.sprite_size = 2.0f;//2.0f;
		obj.exposure_light_delta = WideColorRgb(-2, -2, -2);//10, -10, -10);

		obj.vertices.resize(SOURCES);
	}

	Error* Calculate(const CalculateParams& params) override
	{
		brt = params.brightness;
		accum += params.elapsed * 3.0;
		obj.ambient_light_color = ColorRgb::Grey(params.brightness * 255.0);
		for (; accum > 1.0f; accum--)
		{
			float elapsed = 1.0f;
			for (int i = 0; i < SOURCES; i++)
			{
				position[i] += 0.25 * speed[i] * params.audio_data.GetIntensity() * elapsed;
				ehp[i] += 0.25 * ehps[i] * (0.4 + 2 * (params.audio_data.GetIntensity() + params.audio_data.GetBeat())) * elapsed;

				double rad = 2.0 * er[i] * cos(ehp[i]);
				obj.vertices[i].position.x = (46.0 + (rad * sin(ehp[i]))) * sin(position[i]);
				obj.vertices[i].position.z = (46.0 + (rad * cos(ehp[i]))) * cos(position[i]);
				obj.vertices[i].position.y = er[i] * sin(ehp[i]);
			}

			a2 += elapsed * (params.audio_data.GetIntensity() + params.audio_data.GetBeat()) * 3.14159 / 180.0;

			obj.roll += elapsed * 0.25 * params.audio_data.GetIntensity() * 4.0 * 3.14159 / 180.0;
			obj.pitch += elapsed * 0.25 * params.audio_data.GetIntensity() * 3.0 * 3.14159 / 180.0;
			obj.yaw += elapsed * 0.25 * 2.0 * 3.14159 / 180.0;

			obj.textures[0].Set(Actor::TextureType::Sprite, texture);
			obj.Calculate(params.renderer, &camera, elapsed);
		}
		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		texture = params.texture_library.Find(sprite_texture_class);
		tint = params.texture_library.Find(tint_texture_class);
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		Error* error;

		error = obj.Render(params.renderer);
		if (error) return TraceError(error);

		if (tint != nullptr)
		{
			RenderState render_state;
			render_state.blend_mode = BlendMode::Tint;
			render_state.depth_mode = DepthMode::Disable;
			render_state.texture_stages[0].texture = tint;

			params.renderer.DrawSprite(render_state, Point<int>(0, 0), Rect<int>(0, 0, params.renderer.GetWidth(), params.renderer.GetHeight()), ColorRgb::Grey(brt * 255.0));
		}
		return nullptr;
	}

	bool CanRender(double elapsed)
	{
		return (elapsed > 0.1);//1.0);
	}
};

EXPORT_EFFECT(LightRing, EffectLightRing)
