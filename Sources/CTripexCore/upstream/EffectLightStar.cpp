#include "Platform.h"
#include "effect.h"
#include "Actor.h"
#include "error.h"
#include "TextureData.h"

class EffectLightStar : public Effect
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

	Actor obj;
	Camera camera;
	float brt = 0;
	double source_ang[SOURCES];
	double source_speed[SOURCES];
	double source_height[SOURCES];
	double source_radius[SOURCES];
	Texture* tint = nullptr;
	double rad_ang;
	double view_ang;
	int num_spikes;

	EffectLightStar()
		: Effect({ &sprite_texture_class, &tint_texture_class })
	{
		rad_ang = 2 * 3.14159 * 2.0;
		view_ang = 0;
		num_spikes = 8;

		obj.vertices.resize(SOURCES);
		obj.flags.set(Actor::F_DRAW_TRANSPARENT);
		obj.flags.set(Actor::F_DRAW_Z_BUFFER, false);
		obj.flags.set(Actor::F_DRAW_VERTEX_SPRITES);
		obj.textures[0].type = Actor::TextureType::Sprite;
		obj.sprite_size = 7.5;//pObj->fRenderAsLights(15.0);
		camera.position.z = -100;

		for (int i = 0; i < SOURCES; i++)
		{
			source_ang[i] = rand() * (3.14159 * 2.0) / RAND_MAX;
			source_speed[i] = rand() * (2.0 * 3.14159 / 180.0) / RAND_MAX;
			source_height[i] = 35 - (rand() * 70.0 / RAND_MAX);
			source_radius[i] = 100 + (rand() * 60.0 / RAND_MAX);
			source_height[i] = -10.0 + (rand() * 20.0 / RAND_MAX);
		}
	}

	Error* Calculate(const CalculateParams& params) override
	{
		brt = params.brightness;
		rad_ang += (1.0 + (params.elapsed * (6.0 * params.audio_data.GetIntensity()))) * 3.14159 / 128.0;
		if (rad_ang > 3.14159 * 2.0)
		{
			if (params.audio_data.GetIntensity() < 0.2) num_spikes = 0;
			else if (params.audio_data.GetIntensity() < 0.45) num_spikes = 1;
			else if (params.audio_data.GetIntensity() < 0.6) num_spikes = 2;
			else if (params.audio_data.GetIntensity() < 0.75) num_spikes = 3;
			else if (params.audio_data.GetIntensity() < 0.9) num_spikes = 4;
			else num_spikes = 5;

			while (rad_ang > 3.14159 * 2.0) rad_ang -= 3.14159 * 2.0;
		}
		obj.yaw += 1.0f * DEG_TO_RAD;

		view_ang += 3.14159 / 180.0;
		camera.position.z = -50;
		camera.position.y = -120;
		//camera.pointAt(0,0,0);
		Vector3 vDir = Vector3::Origin() - camera.position;
		camera.pitch = vDir.GetPitch();
		camera.yaw = vDir.GetYaw();

		double dRadMult = 50.0 * sin(rad_ang);
		for (int i = 0; i < SOURCES; i++)
		{
			source_ang[i] += source_speed[i] * params.elapsed;
			source_radius[i] = 100 + (dRadMult * sin(source_ang[i] * num_spikes));

			obj.vertices[i].position.x = sin(source_ang[i]) * source_radius[i];
			obj.vertices[i].position.y = source_height[i];
			obj.vertices[i].position.z = cos(source_ang[i]) * source_radius[i];
		}
		obj.ambient_light_color = ColorRgb::Grey(128.0 * params.brightness);//->color = D3DRGB(dBr, dBr, dBr);
		obj.Calculate(params.renderer, &camera, params.elapsed);

		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		Error* error = obj.Render(params.renderer);
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

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		obj.textures[0].texture = params.texture_library.Find(sprite_texture_class);
		tint = params.texture_library.Find(tint_texture_class);
		return nullptr;
	}
};

EXPORT_EFFECT(LightStar, EffectLightStar)
