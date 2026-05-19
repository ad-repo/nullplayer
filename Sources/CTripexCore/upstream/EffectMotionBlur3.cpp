#include "Platform.h"
#include "effect.h"
#include "error.h"
#include "Actor.h"
#include "TextureData.h"
#include "BezierCurve.h"

template<bool ALT_BLUR> class EffectMotionBlur3T : public Effect
{
public:
	const TextureClass envmap_texture_class =
	{
		"EnvMap",
		{ tex_alien_egg, tex_shiny_sand }
	};

	Camera camera;
	Actor objects[9];
	Actor obj;

	float change = 0.0f;
	float shown;
	int current_effect;
	int next_effect;

	float pos;
	float av_total, av_time;
	float cam_target;
	float speed = 0.0f;
	bool reset;
	float cam_pos;

	ContainedBezierCurve<2> bz;
	Camera cam;

	EffectMotionBlur3T()
		: Effect({ &envmap_texture_class })
		, bz(Vector3(20, 20, 20), -Vector3(20, 20, 20))//, cam(0)
	{
		cam.flags.set(Camera::F_SCREEN_TRANSFORM, false);

		cam_pos = 0.0f;
		av_total = 0;
		av_time = 16;
		cam_target = 110;
		reset = false;
		shown = 0;
		next_effect = -1;
		pos = 0;

		obj.CreateTetrahedron(80.0f);
		current_effect = rand() % 5;

		camera.position.z = -80;//110;

		for (int i = 0; i < 9; i++)
		{
			//		pObj[i].pVertex.SetFormat(D3DFVF_NORMAL | D3DFVF_TEX1);
			objects[i].CreateTorus(30, 5.0, 20, 5);
			objects[i].flags.set(Actor::F_DRAW_TRANSPARENT);
			if (ALT_BLUR) objects[i].flags.set(Actor::F_DO_MIX_EXPOSURE_FACES);
			objects[i].textures[0].type = Actor::TextureType::Lightmap;
			objects[i].exposure = 9;
			objects[i].frame_history = 4.0f;
			if (!ALT_BLUR) objects[i].exposure_light_delta = WideColorRgb(-3, -3, -0);
			objects[i].FindVertexNormals();
		}
	}

	Vector3 GetPos(int effect_idx, int i)
	{
		if (effect_idx == 0)
		{
			if (i < 8)
			{
				float radius = (1 + (i / 4)) * 40.0;
				float x = cosf(i * 3.14159 / 2.0) * radius;//80.0;
				float y = sinf(i * 3.14159 / 2.0) * radius;//80.0;
				return Vector3(x, y, 0);
			}
			else return Vector3::Origin();
		}
		else if (effect_idx == 1)
		{
			if (i == 0) return Vector3(0, 40, 40);
			else if (i == 1) return Vector3(0, -40, 40);
			else if (i == 2) return Vector3(0, 0, 0);
			else if (i == 3) return Vector3(0, 0, 80);
			else if (i == 4) return Vector3(40, 0, 40);
			else if (i == 5) return Vector3(-40, 0, 40);
			else if (i == 6) return Vector3(80, 0, 40);
			else if (i == 7) return Vector3(-80, 0, 40);
			else return Vector3(0, 0, 40);
		}
		else if (effect_idx == 2)
		{
			if (i < 8)
			{
				float radius = (1 + (i / 4)) * 40.0;
				float x = cosf(i * 3.14159 / 2.0) * radius;//80.0;
				float y = sinf(i * 3.14159 / 2.0) * radius;//80.0;
				float z = sinf((1 + (i / 4)) * 3.14159 / 6.0) * 40.0;
				return Vector3(x, y, z);
			}
			else return Vector3::Origin();
		}
		else if (effect_idx == 3)
		{
			float ang = (i % 3) * 2.0 * 3.14159 / 3.0f;
			float len = 120.0f * ((i / 3) + 0.5f) / 4.0f;
			return Vector3(cosf(ang) * len, sinf(ang) * len, 0);
		}
		else //if(nEffect == 2)
		{
			float x = cosf(i * 3.14159 * 2.0 / 9) * 80.0;
			float y = sinf(i * 3.14159 * 2.0 / 9) * 80.0;
			return Vector3(x, y, 0);
		}
	}

	Error* Calculate(const CalculateParams& params) override
	{
		av_total += params.elapsed * params.audio_data.GetIntensity();
		av_time += params.elapsed;

		cam.position.z = -80;

		obj.roll += params.elapsed * 3.14159 / 180.0f;
		obj.pitch += params.elapsed * 2.0f * 3.14159 / 180.0f;
		obj.yaw += params.elapsed * 3.0f * 3.14159 / 180.0f;
		obj.Calculate(params.renderer, &cam, params.elapsed);

		if (av_total > 6 || reset)
		{
			cam_target = -250 + (std::min(1.0f, av_total / av_time) * 190);
			if (reset)
			{
				camera.position.z = cam_target;
				reset = false;
			}
			av_total = 0;
			av_time = 0;
			speed = fabs(camera.position.z - cam_target) / 32.0;
		}

		camera.position.z = StepTo<float>(camera.position.z, cam_target, speed * params.elapsed);// * 2.0 * (-camera.vPosition.k / 250.0));//2);

		cam_pos += params.audio_data.GetIntensity() * params.elapsed * 0.02;
		camera.SetTarget(bz.Calculate(cam_pos));

		if (next_effect != -1)
		{
			change += params.elapsed / 20.0;
			if (change > 1)
			{
				current_effect = next_effect;
				next_effect = -1;
			}
		}
		else
		{
			shown += params.elapsed;
			if (shown > 50)
			{
				next_effect = rand() % 5;
				shown = 0;
				change = 0;
			}
		}

		camera.roll += params.audio_data.GetIntensity() * 3.14159 * 2.0 * params.elapsed / 180.0;

		for (int i = 0; i < 9; i++)
		{
			if (next_effect != -1)
			{
				objects[i].position = (GetPos(current_effect, i) * (1 - change)) + (GetPos(next_effect, i) * change);
			}
			else
			{
				objects[i].position = GetPos(current_effect, i);
			}

			objects[i].roll += params.elapsed * 4.0 * 3.14159 / 180.0;
			objects[i].pitch += params.audio_data.GetIntensity() * params.elapsed * 10.0 * 3.14159 / 180.0;
			objects[i].yaw += (params.audio_data.GetIntensity() + params.audio_data.GetBeat()) * params.elapsed * 7 * 3.14159 / 180.0;
			objects[i].ambient_light_color = ColorRgb::Grey(params.brightness * 48.0f);// / pObj[i].nExposure);
			objects[i].Calculate(params.renderer, &camera, params.elapsed);
		}

		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		for (int i = 0; i < 9; i++)
		{
			Error* error = objects[i].Render(params.renderer);
			if (error) return TraceError(error);
		}
		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		av_time = 16;
		av_total = params.audio_data.GetIntensity() * av_time;
		reset = true;
		Texture* t = params.texture_library.Find(envmap_texture_class);
		for (int i = 0; i < 9; i++) objects[i].textures[0].texture = t;
		return nullptr;
	}
};

EXPORT_EFFECT(MotionBlur3, EffectMotionBlur3T<false>)
EXPORT_EFFECT(MotionBlur3Alt, EffectMotionBlur3T<true>)
