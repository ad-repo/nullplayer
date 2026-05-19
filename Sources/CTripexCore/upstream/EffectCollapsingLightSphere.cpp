#include "Platform.h"
#include "effect.h"
#include <conio.h>
#include "Actor.h"
#include "error.h"
#include "TextureData.h"
#include <algorithm>

class EffectCollapsingLightSphere : public Effect
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

	static const int SOURCES = 512;

	const float SPREAD = 50;
	const float RADIUS = 160;
	const float SPEEDSPREAD = 20;
	const float FOREGROUNDBR = 0.5f;

	double source_ang[SOURCES];
	double source_y_pos[SOURCES];
	double source_tilt[SOURCES];
	double source_radius[SOURCES];
	double source_speed[SOURCES];
	Texture *tint = nullptr;
	double wait_time;
	double tilt;
	Actor obj;
	Camera camera;

	// 0 - contracted
	// 1 - moving out
	// 2 - out
	// 3 - moving in
	int current_stage;
	double brt = 0.0;

	EffectCollapsingLightSphere()
		: Effect({ &sprite_texture_class, &tint_texture_class })
	{
		wait_time = 0;
		tilt = 0;

		current_stage = 0;
		obj.vertices.resize(SOURCES);
		obj.flags.set( Actor::F_DRAW_TRANSPARENT );
		obj.flags.set( Actor::F_DRAW_VERTEX_SPRITES );
		obj.exposure_light_delta = WideColorRgb(-60, -60, -60);
		obj.exposure = 3;
		obj.sprite_size = 7.0;
		obj.frame_history = 2.0;
		camera.position.z = -240;

		for(int i = 0; i < SOURCES; i++)
		{
			source_ang[i] = rand() * PI2 / RAND_MAX;
			source_speed[i] = SPEEDSPREAD * (rand() * (SPEEDSPREAD / 2.0) * DEG_TO_RAD / RAND_MAX);
			source_tilt[i] = rand() * PI2 / RAND_MAX;
			source_radius[i] = rand() * RADIUS / RAND_MAX;
			source_y_pos[i] = (SPREAD / 2.0) - (double(rand()) * SPREAD / RAND_MAX);
		}
	}
	Error* Calculate(const CalculateParams& params) override
	{
		brt = params.brightness;
		if(current_stage == 0) wait_time += params.elapsed * params.audio_data.GetDampenedBand( sensitivity, 0.0f, 1.0f);
		else if(current_stage == 1) tilt += params.elapsed * 1.5 * DEG_TO_RAD;
		else if(current_stage == 2) wait_time += params.elapsed * params.audio_data.GetDampenedBand(sensitivity, 0.0f, 1.0f);
		else if(current_stage == 3) tilt -= params.elapsed * 1.5 * DEG_TO_RAD;

		if((tilt < 0) || (tilt > 3.141592 / 2.0) || (wait_time > 40.0 && params.audio_data.GetIntensity( ) > 0.6))
		{
			current_stage = (current_stage + 1) & 3;
			wait_time = 0.0;
			tilt = std::min(std::max(tilt, 0.0), 3.14159 / 2.0);
		}

		float twist_mult = sinf(tilt);// * 3.14159 / 128.0);
		float multp = (tilt * params.audio_data.GetIntensity( )) + (1 - tilt) + 0.1;

		obj.vertices.resize(SOURCES);
		for(int i = 0; i < SOURCES; i++)
		{
			float x = cosf(source_ang[i]) * source_radius[i];
			float y = source_y_pos[i];
			float z = -100 + (sinf(source_ang[i]) * source_radius[i]);

			float sin_t = sinf(source_tilt[i] * twist_mult);
			float cos_t = cosf(source_tilt[i] * twist_mult);

			obj.vertices[i].position.x = (y * cos_t) + (x * sin_t);
			obj.vertices[i].position.y = (y * sin_t) + (x * cos_t);
			obj.vertices[i].position.z = z;

			source_ang[i] += params.elapsed * multp * (params.audio_data.GetIntensity( ) + 0.1) * source_speed[i] * 3.14159 / 180.0;
			source_tilt[i] += (params.audio_data.GetIntensity( ) + 0.1) * params.elapsed * multp * 1 * 3.14159 / 180.0;

			float trans_mult = FOREGROUNDBR + ((z / -100.0) * (1 - FOREGROUNDBR));
			float br = params.brightness * trans_mult / 2.0;

			obj.vertices[i].diffuse = ColorRgb::Grey(0.6 * br * 255.0);
		}
		obj.flags.set( Actor::F_VALID_VERTEX_DIFFUSE );
		obj.Calculate(params.renderer, &camera, params.elapsed);
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		Error* error;

		error = obj.Render(params.renderer);
		if (error) return TraceError(error);

		if(tint != nullptr)
		{
			RenderState render_state;
			render_state.blend_mode = BlendMode::Tint;
			render_state.depth_mode = DepthMode::Disable;
			render_state.texture_stages[0].texture = tint;

			params.renderer.DrawSprite(render_state, Point<int>(0, 0), params.renderer.GetViewportRect(), ColorRgb::Grey(brt * 255.0));
		}
		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		obj.textures[0].Set(Actor::TextureType::Sprite, params.texture_library.Find(sprite_texture_class));
		tint = params.texture_library.Find(tint_texture_class);
		return nullptr;
	}
};

EXPORT_EFFECT( CollapsingLightSphere, EffectCollapsingLightSphere )

