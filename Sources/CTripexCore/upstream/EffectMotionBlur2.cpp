#include "Platform.h"
#include "effect.h"
#include "Actor.h"
#include "BezierCurve.h"
#include "TextureData.h"
#include "error.h"

class EffectMotionBlur2 : public Effect
{
public:
	const TextureClass envmap_texture_class =
	{
		"EnvMap",
		{ tex_alien_egg, tex_shiny_sand }
	};


	const float PIPE_RADIUS = 10.0f;
	static const int PIPE_CIRCUMPOINTS = 6;
	static const int PIPE_TWISTS = 3;
	static const int PIPE_LENGTH = 50;
	const float PIPE_TWISTRADIUS = 30.0f;
	static const int PIPES = 3;
	const float CIRCLE_RADIUS = 60.0f;

	static const int nVertices = PIPE_LENGTH * PIPE_CIRCUMPOINTS;

	const float UPDATETIME = 60.0f;
	const float ANG = (5.0f * 3.14159f / 180.0f);

	Actor objects[PIPES];
	Camera camera;//World *pScene;
	ContainedBezierCurve<1> b;
	float bez_pos;
	float time;
	float pf[2][3];
	float pfa[3] = {};
	float change;

	EffectMotionBlur2()
		: Effect({ &envmap_texture_class })
		, b(Vector3(-100, -100, -20), Vector3(100, 100, 100))
	{
		for (int i = 0; i < 3; i++) pf[1][i] = 0.0f;

		change = 0;
		time = UPDATETIME + 1;
		bez_pos = 0;
		for (int p = 0; p < PIPES; p++)
		{
			objects[p].CreateTetrahedron(100);
			objects[p].vertices.resize(nVertices);
			objects[p].faces.resize(PIPE_LENGTH * PIPE_CIRCUMPOINTS * 2);
			objects[p].flags.set(Actor::F_NO_CULL);
			objects[p].flags.set(Actor::F_DRAW_TRANSPARENT);
			objects[p].frame_history = 4.0f;
			objects[p].exposure = 6;
			objects[p].exposure_light_delta = WideColorRgb(-10, -10, -1);

			int v = 0, f = 0;
			for (int i = 0; i < PIPE_LENGTH; i++)
			{
				double dAng = (i * 2.0 * 3.14159 / PIPE_LENGTH);
				double dTwistAng = (i * PIPE_TWISTS * 2.0 * 3.14159 / PIPE_LENGTH) + (p * 2.0 * 3.14159 / PIPES);
				for (int cp = 0; cp < PIPE_CIRCUMPOINTS; cp++)
				{
					double dCircumAng = cp * 2.0 * 3.14159 / PIPE_CIRCUMPOINTS;

					Vector3 vec;
					vec.x = 0;//(cp - (cp / 2)) * 20;
					vec.y = PIPE_TWISTRADIUS + (PIPE_RADIUS * cos(dCircumAng));
					vec.z = PIPE_TWISTRADIUS + (PIPE_RADIUS * sin(dCircumAng));
					vec *= Matrix44::RotateAroundX(dTwistAng);
					vec.y += CIRCLE_RADIUS;
					vec *= Matrix44::RotateAroundZ(dAng);// = RotateVector3(vec, dAng, 0, 0);
					objects[p].vertices[v + cp].position = vec;

					objects[p].faces[f][0] = v + cp;
					objects[p].faces[f][1] = v + ((cp + 1) % PIPE_CIRCUMPOINTS);
					objects[p].faces[f][2] = (v + cp + PIPE_CIRCUMPOINTS) % nVertices;
					f++;

					objects[p].faces[f][0] = v + ((cp + 1) % PIPE_CIRCUMPOINTS);
					objects[p].faces[f][1] = (v + ((cp + 1) % PIPE_CIRCUMPOINTS) + PIPE_CIRCUMPOINTS) % nVertices;
					objects[p].faces[f][2] = (v + cp + PIPE_CIRCUMPOINTS) % nVertices;
					f++;
				}
				v += PIPE_CIRCUMPOINTS;
			}
			objects[p].FindVertexNormals();
		}
		camera.position.z = -130;
	}

	Error* Calculate(const CalculateParams& params) override
	{
		camera.position = b.Calculate(bez_pos);
		camera.SetTarget(Vector3::Origin());
		bez_pos += 0.02 * params.audio_data.GetIntensity() * params.elapsed;

		time += params.elapsed;
		change = std::min(1.0f, change + (params.elapsed / 3.0f));

		if (time > UPDATETIME)
		{
			for (int i = 0; i < 3; i++) pf[0][i] = pf[1][i];
			pf[1][0] = (rand() * ANG / RAND_MAX) - (ANG / 2.0);
			pf[1][1] = (rand() * ANG / RAND_MAX) - (ANG / 2.0);
			pf[1][2] = (ANG * 1.5) - fabs(pf[1][0]) - fabs(pf[1][1]);
			time -= UPDATETIME;
			change = 0;
		}

		for (int i = 0; i < 3; i++)
		{
			pfa[i] = (pf[0][i] * (1 - change)) + (pf[1][i] * change);
		}

		for (int i = 0; i < 3; i++)
		{
			objects[i].ambient_light_color = ColorRgb::Grey(60.0 * params.brightness);
			objects[i].roll += pfa[0] * params.elapsed * (params.audio_data.GetIntensity() + 0.1);
			objects[i].pitch += pfa[1] * params.elapsed * params.audio_data.GetIntensity();
			objects[i].yaw += pfa[2] * params.elapsed * (params.audio_data.GetIntensity() + 0.2);
			objects[i].Calculate(params.renderer, &camera, params.elapsed);
		}
		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		Texture* pTexture = params.texture_library.Find(envmap_texture_class);//2);
		for (int i = 0; i < PIPES; i++)
		{
			objects[i].textures[0].type = Actor::TextureType::Lightmap;
			objects[i].textures[0].texture = pTexture;
		}
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		for (int i = 0; i < PIPES; i++)
		{
			Error* error = objects[i].Render(params.renderer);
			if (error) return TraceError(error);
		}
		return nullptr;
	}
};

EXPORT_EFFECT(MotionBlur2, EffectMotionBlur2)
