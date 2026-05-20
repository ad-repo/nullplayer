#include "Platform.h"
#include "Effect.h"
#include "error.h"
#include "Actor.h"
#include "BezierCurve.h"

class EffectSun : public Effect
{
public:
	static const int RINGS = 5;//3
	static const int EXPOSURE = 3;//5//7//9//15//4//3//7//9
	const float EXPDIV = 5.0f;//4.5//5//7
	static const int EXPFRAMES = 2;//4//10//6//3

	static const int TRI = 10;
	const float PI2 = (PI * 2);
	static const int LAYERS = 3;
	static const int INNER = 30;
	static const int OUTER = (INNER + 30);
	const float ANGSZ = (20.0f * DEG_TO_RAD);

	Actor objects[RINGS];
	Camera camera;
	float as[RINGS][3][2];
	float ps[RINGS][2] = {};
	float ys[RINGS][2] = {};
	float sa;
	ContainedBezierCurve<2> bez, bez2;
	float bez_pos;
	float bez_pos_2;
	double accum = 0;
	float move = 21;

	EffectSun() :
		bez(Vector3(4 * 20, 4 * 20, 70), Vector3(4 * -20, 4 * -20, -60)),
		bez2(Vector3(10, 10, 10), Vector3(-10, -10, -20))
	{
		sa = 0;
		bez_pos = 4;
		bez_pos_2 = 4;

		camera.position = Vector3(0, 0, -70);//-70);

		for (int o = 0; o < RINGS; o++)
		{
			objects[o].vertices.resize((LAYERS * 2 + 1) * TRI * 2);
			objects[o].faces.resize(TRI * 2 * (LAYERS * 2 + 1));

			int base = 0;
			for (int a = -LAYERS; a <= LAYERS; a++)
			{
				float ang = 10 * PI * a / (180 * LAYERS);
				for (int i = 0; i < TRI; i++)
				{
					objects[o].vertices[base + i].position.x = sin(i * PI2 / TRI) * INNER * cos(ang);
					objects[o].vertices[base + i].position.y = cos(i * PI2 / TRI) * INNER * cos(ang);
					objects[o].vertices[base + i].position.z = INNER * sin(ang);

					objects[o].vertices[base + i + TRI].position.x = sin((i * PI2 / TRI) + (PI / TRI)) * OUTER * cos(ang);
					objects[o].vertices[base + i + TRI].position.y = cos((i * PI2 / TRI) + (PI / TRI)) * OUTER * cos(ang);
					objects[o].vertices[base + i + TRI].position.z = OUTER * sin(ang);

					objects[o].faces[base + i][0] = base + i;
					objects[o].faces[base + i][1] = base + ((i + 1) % TRI);
					objects[o].faces[base + i][2] = base + i + TRI;

					objects[o].faces[base + i + TRI][0] = base + i;
					objects[o].faces[base + i + TRI][2] = base + ((i + 1) % TRI);
					objects[o].faces[base + i + TRI][1] = base + i + TRI;
				}
				base += TRI * 2;
			}

			objects[o].flags.set(Actor::F_DRAW_TRANSPARENT);
			objects[o].flags.set(Actor::F_DRAW_Z_BUFFER, false);
			objects[o].exposure = EXPOSURE;
			objects[o].frame_history = EXPFRAMES;
		}

		for (int i = 0; i < RINGS; i++)
		{
			for (int j = 0; j < 3; j++)
			{
				as[i][j][0] = 1.0;
				as[i][j][1] = 1000.0;
			}
		}
	}

	Error* Calculate(const CalculateParams& params) override
	{
		bez_pos += params.elapsed * params.audio_data.GetIntensity() * 0.01f;
		bez_pos_2 += params.elapsed * params.audio_data.GetIntensity() * 0.02f;
		camera.position = Vector3(0, 0, -70);//bez.Calculate(fBezPos);
		camera.SetTarget(bez2.Calculate(bez_pos_2));

		accum += params.elapsed * 1.5;
		move += params.elapsed;
		if (move > 20)
		{
			for (int i = 0; i < RINGS; i++)
			{
				for (int j = 0; j < 3; j++)
				{
					as[i][j][0] = (float)_copysign(1.0f, as[i][j][0]) * (4.0f + (rand() * 4.0f / RAND_MAX)) * DEG_TO_RAD;
					if (rand() > RAND_MAX * 0.75f) as[i][j][0] = -as[i][j][0];
				}
			}
			move -= 20;
		}

		while (accum > 1.0)
		{
			for (int i = 0; i < RINGS; i++)
			{
				for (int j = 0; j < 3; j++)
				{
					as[i][j][1] += as[i][j][0];
				}

				if ((i % 3) == 0)
				{
					objects[i].roll += 0.1f * as[i][0][0];
					objects[i].pitch += params.audio_data.GetDampenedBand(sensitivity, 3.0f / 16.0f, 4.0f / 16.0f) * as[i][1][0];
					objects[i].yaw += params.audio_data.GetDampenedBand(sensitivity, 4.0f / 16.0f, 5.0f / 16.0f) * as[i][2][0];
					objects[i].pitch = Clamp<float>(objects[i].pitch, -ANGSZ, ANGSZ);
					objects[i].yaw = Clamp<float>(objects[i].yaw, -ANGSZ, ANGSZ);
				}
				if ((i % 3) == 1)
				{
					objects[i].roll += params.audio_data.GetDampenedBand(sensitivity, 2.0f / 16.0f, 3.0f / 16.0f) * as[i][0][0];
					objects[i].pitch += 0.1f * as[i][1][0];
					objects[i].yaw += 1.5f * params.audio_data.GetDampenedBand(sensitivity, 2.0f / 16.0f, 4.0f / 16.0f) * as[i][2][0];
				}
				if ((i % 3) == 2)
				{
					objects[i].roll += params.audio_data.GetDampenedBand(sensitivity, 1 / 16.0f, 2 / 16.0f) * as[i][0][0];
					objects[i].pitch += params.audio_data.GetIntensity() * as[i][1][0];
					objects[i].yaw += 0.1f * as[i][2][0];
				}

				int base = 0;
				for (int a = -LAYERS; a <= LAYERS; a++)
				{
					for (int j = 0; j < TRI; j++)
					{
						objects[i].vertices[base + j].diffuse = ColorRgb((uint8)(params.brightness * 128.0f / EXPDIV), (uint8)(params.brightness * 77.0f / EXPDIV), (uint8)(params.brightness * 243.0f / EXPDIV)); //0.6 / 25, 0.5 / 25);
						objects[i].vertices[base + j + TRI].diffuse = ColorRgb(0, (uint8)(params.brightness * 64.0f / EXPDIV), 0);
					}
					base += 2 * TRI;
				}
				objects[i].flags.set(Actor::F_VALID_VERTEX_DIFFUSE);

				objects[i].Calculate(params.renderer, &camera, 1.0);
			}
			accum--;
		}
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		Error* error;
		for (int i = 0; i < RINGS; i++)
		{
			error = objects[i].Render(params.renderer);
			if (error) return TraceError(error);
		}
		return nullptr;
	}
};

EXPORT_EFFECT(Sun, EffectSun)
