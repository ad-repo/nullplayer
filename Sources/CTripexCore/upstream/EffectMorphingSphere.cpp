#include "Platform.h"
#include "effect.h"
#include "Actor.h"
#include "BezierCurve.h"
#include "TextureData.h"
#include "error.h"

class EffectMorphingSphere : public Effect
{
public:
	const TextureClass envmap_texture_class =
	{
		"EnvMap",
		{ tex_alien_egg, tex_shiny_sand }
	};

	const float HILLSZ = 0.1f;
	static const int LANDSCAPEITER = 2000;

	static const int NOBJ = 4;

	Actor objects[NOBJ + 1];
	Camera camera;
	std::vector<float> angles;
	ContainedBezierCurve<1> b;
	float bez_pos;

	EffectMorphingSphere()
		: Effect({ &envmap_texture_class })
		, b(Vector3(-100, -100, -600), Vector3(100, 100, -200))
	{
		bez_pos = 0;
		objects[NOBJ].CreateTetrahedronGeosphere(1.0, 4);
		objects[NOBJ].FindFaceOrder(Vector3::Origin());
		angles.resize(objects[NOBJ].vertices.size());
		for (int i = 0; i < objects[NOBJ].vertices.size(); i++)
		{
			angles[i] = objects[NOBJ].vertices[i].position.z * PI * 2;
		}
		for (int i = 0; i < LANDSCAPEITER; i++)
		{
			Vector3 v;
			v.x = 0.5 - (float(rand()) / RAND_MAX);
			v.y = 0.5 - (float(rand()) / RAND_MAX);
			v.z = 0.5 - (float(rand()) / RAND_MAX);
			v.Normalize();

			for (int j = 0; j < objects[NOBJ].vertices.size(); j++)
			{
				if (objects[NOBJ].vertices[j].position.Dot(v) < 0)
				{
					angles[j] += 2.0f * DEG_TO_RAD;
				}
				else
				{
					angles[j] -= 2.0f * DEG_TO_RAD;
				}
			}
		}

		for (int i = 0; i < NOBJ; i++)
		{
			objects[i].faces = objects[NOBJ].faces;
			objects[i].vertices.resize(objects[NOBJ].vertices.size());
			objects[i].flags.set(Actor::F_DRAW_TRANSPARENT);
			objects[i].flags.set(Actor::F_NO_CULL);
		}

		camera.position.z = -320;
	}

	Error* Calculate(const CalculateParams& params) override
	{
		bez_pos += params.elapsed * params.audio_data.GetIntensity() * 0.04;
		camera.position = b.Calculate(bez_pos);

		for (int i = 0; i < objects[NOBJ].vertices.size(); i++)
		{
			angles[i] += params.audio_data.GetIntensity() * params.elapsed * 8.0 * 3.14159 / 180.0;
		}
		for (int i = 0; i < NOBJ; i++)
		{
			float fOfs = i * 60.0 * 3.14159 / 180.0;
			float fMult = 1.0 + (i * 1.0 / NOBJ);
			for (int j = 0; j < objects[i].vertices.size(); j++)
			{
				objects[i].vertices[j].position = objects[NOBJ].vertices[j].position * 200.0f * fMult * (1.0f + ((float)HILLSZ * (float)sin(angles[j] + fOfs)));
			}
			objects[i].pitch += params.elapsed * 2.0 * PI / 180.0;
			objects[i].yaw += params.elapsed * 2.0 * PI / 180.0;
			objects[i].flags.set(Actor::F_VALID_VERTEX_NORMALS, false);
			float fBlend = float(i) / NOBJ;
			float fMult2 = (i == 0) ? 1.0f : std::min(1.0, params.audio_data.GetIntensity() * 1.5);//(averagefloat(i) / NOBJ);
			objects[i].ambient_light_color = params.brightness * (ColorRgb::Grey(96 * fMult2 * (1 - (0.4 * float(i) / NOBJ))) - ColorRgb(fBlend * 40.0, fBlend * 40.0, fBlend * 5.0));
			objects[i].Calculate(params.renderer, &camera, params.elapsed);
		}
		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		Texture* tx = params.texture_library.Find(envmap_texture_class);
		for (int i = 0; i < NOBJ; i++)
		{
			objects[i].textures[0].Set(Actor::TextureType::Envmap, tx);
		}
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		for (int i = 0; i < NOBJ; i++)
		{
			Error* error = objects[i].Render(params.renderer);
			if (error) return TraceError(error);
		}

		return nullptr;
	}
};

EXPORT_EFFECT(MorphingSphere, EffectMorphingSphere)
