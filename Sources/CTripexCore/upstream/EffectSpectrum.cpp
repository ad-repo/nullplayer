#include "Platform.h"
#include "effect.h"
#include "Actor.h"
#include "Camera.h"
#include "TextureData.h"
#include "error.h"

class EffectSpectrum : public Effect
{
public:
	const TextureClass envmap_texture_class =
	{
		"EnvMap",
		{ tex_alien_egg, tex_shiny_sand }
	};

	const float ACCELER = 1.0f;
	static const int CUBE_H = 4;//10

	static const int TRAIL_W = 30;//10//30//20
	static const int TRAIL_H = 30;

	const float TRAIL_XS = 20;//20//20//40
	const float CUBE_SIZE = 10;
	const float SPIN_RADIUS = 600;
	const float SPIN_HEIGHT = -300;
	const float CYLINDER_RADIUS = 1200; //500
	const float TRAIL_ANGS = (2.0f * DEG_TO_RAD);
	const float ANG_OFFSET = (10.0f * DEG_TO_RAD);
	const float BAR_SIZE = 5.0f;
	static const int LIMITER_H = 15;//10

	float br_ang;
	Camera camera;
	Actor objects[TRAIL_H];
	Actor limiters[LIMITER_H];
	float ang;
	float rot_ang;
	float heights[TRAIL_H][TRAIL_W];
	float cube_heights[LIMITER_H][TRAIL_W];
	float cube_tops[LIMITER_H][TRAIL_W];
	float cube_times[LIMITER_H][TRAIL_W];

	Texture* texture = nullptr;

	EffectSpectrum()
		: Effect({ &envmap_texture_class })
	{
		ang = 0.0f;
		br_ang = 0;
		rot_ang = 45.0f * DEG_TO_RAD;
		camera.perspective = 300;

		for (int i = 0; i < TRAIL_H; i++)
		{
			objects[i].vertices.resize(TRAIL_W * 4);
			objects[i].faces.resize((TRAIL_W - 1) * 8);
			objects[i].flags.set(Actor::F_DRAW_TRANSPARENT);
			objects[i].flags.set(Actor::F_DRAW_Z_BUFFER, false);

			uint16 v = 0, f = 0;
			for (int j = 0; j < TRAIL_W; j++)
			{
				int n = j * 4;
				static const float s = 0.5f / sqrtf(2.0f);
				objects[i].vertices[n + 0].normal = Vector3(0.0f, -s, -s);
				objects[i].vertices[n + 1].normal = Vector3(0.0f, +s, -s);
				objects[i].vertices[n + 2].normal = Vector3(0.0f, +s, +s);
				objects[i].vertices[n + 3].normal = Vector3(0.0f, -s, +s);

				if (j < TRAIL_W - 1)
				{
					Face* face;
					for (uint16 k = 0; k < 4; k++)
					{
						face = &objects[i].faces[f + k * 2];
						(*face)[0] = (uint16)(v + k);
						(*face)[1] = (uint16)(v + k + 4);
						(*face)[2] = (uint16)(v + ((k + 1) % 4));

						face = &objects[i].faces[f + k * 2 + 1];
						(*face)[0] = (uint16)(v + ((k + 1) % 4));
						(*face)[1] = (uint16)(v + k + 4);
						(*face)[2] = (uint16)(v + 4 + ((k + 1) % 4));
					}
					f += 8;
				}
				v += 4;
			}
		}
		for (int i = 0; i < LIMITER_H; i++)
		{
			limiters[i].vertices.resize(TRAIL_W);
			limiters[i].flags.set(Actor::F_DRAW_TRANSPARENT);
			limiters[i].flags.set(Actor::F_DRAW_Z_BUFFER, false);
			limiters[i].flags.set(Actor::F_DRAW_VERTEX_SPRITES);
			limiters[i].sprite_size = 9.0f;//fRenderAsLights(15.0);

			float mult = ((sinf((CUBE_H + i) * PI / TRAIL_H) * 0.7f) + 0.8f) * TRAIL_XS;
			for (int j = 0; j < TRAIL_W; j++)
			{
				limiters[i].vertices[j].position.x = (j - (TRAIL_W / 2.0f)) * mult;
				cube_times[i][j] = 0;
				cube_tops[i][j] = 0.0;
				cube_heights[i][j] = 0.0;
			}
		}
		ang = 0;
		for (int i = 0; i < TRAIL_H; i++)
		{
			for (int j = 0; j < TRAIL_W; j++)
			{
				heights[i][j] = 0;
			}
		}
	}

	Error* Calculate(const CalculateParams& params) override
	{
		rot_ang += params.elapsed * (2.0f * DEG_TO_RAD);
		br_ang += params.elapsed * (2.0f * DEG_TO_RAD);

		ang += params.elapsed * (1.0f * DEG_TO_RAD);
		camera.position.x = -30 + (SPIN_RADIUS * cosf(rot_ang));
		camera.position.y = SPIN_HEIGHT;
		camera.position.z = SPIN_RADIUS * sinf(rot_ang);

		Vector3 dir = Vector3::Origin() - camera.position;
		camera.pitch = dir.GetPitch();
		camera.yaw = dir.GetYaw();

		while (ang >= TRAIL_ANGS)
		{
			for (int i = TRAIL_H - 1; i >= 1; i--)
			{
				for (int j = 0; j < TRAIL_W; j++)
				{
					heights[i][j] = heights[i - 1][j];
				}
			}
			for (int i = 0; i < TRAIL_W; i++)
			{
				heights[0][i] = 0.0f;
			}
			for (int i = 0; i < 256; i++)
			{
				int target = i * TRAIL_W / 256;
				heights[0][target] = std::max(heights[0][target], params.audio_data.GetBand(i));
			}
			for (int i = 0; i < TRAIL_W; i++)
			{
				heights[0][i] = 300.0f * sinf((PI * 0.5f) * heights[0][i]);
			}
			ang -= TRAIL_ANGS;
		}

		for (int j = 0; j < LIMITER_H; j++)
		{
			for (int i = 0; i < TRAIL_W; i++)
			{
				cube_times[j][i] += params.elapsed;
				cube_heights[j][i] = cube_tops[j][i] - (ACCELER * (cube_times[j][i] * cube_times[j][i]) / 2.0f);
				if (heights[CUBE_H + j][i] > cube_heights[j][i])
				{
					cube_tops[j][i] = heights[CUBE_H + j][i];
					cube_times[j][i] = 0.0;
					cube_heights[j][i] = cube_tops[j][i] - (ACCELER * (cube_times[j][i] * cube_times[j][i]) / 2.0f);
				}
				cube_heights[j][i] = std::max(cube_heights[j][i], 0.0f);
			}
		}

		float pos_y_max = -CYLINDER_RADIUS + (CYLINDER_RADIUS * cosf(TRAIL_ANGS * (TRAIL_H * 0.5f) + ANG_OFFSET));
		for (int i = 0; i < TRAIL_H; i++)
		{
			float this_ang = ((i - (TRAIL_H * 0.5f)) * TRAIL_ANGS) + ang + ANG_OFFSET;
			float this_cos = cosf(this_ang);
			float this_sin = sinf(this_ang);
			float pos_y = CYLINDER_RADIUS - (CYLINDER_RADIUS * this_cos);
			float pos_z = (CYLINDER_RADIUS * this_sin);

			float br;
			if (i <= 1)
			{
				br = (i + (ang / TRAIL_ANGS)) * 0.5f;
			}
			else if (i > (TRAIL_H * 0.5f))
			{
				br = 1.0f - fabsf(pos_y / pos_y_max);
			}
			else
			{
				br = 1.0f;
			}

			br = params.brightness * std::min(br * 0.7f, 1.0f);
			br = std::max(br, 0.0f);
			objects[i].ambient_light_color = ColorRgb::Grey((int)(br * 255.0f));

			int n = 0;
			float mult = ((sinf((i + (ang / TRAIL_ANGS)) * PI / TRAIL_H) * 0.9f) + 0.8f) * TRAIL_XS;
			for (int j = 0; j < TRAIL_W; j++)
			{
				float x = (j - (TRAIL_W * 0.5f)) * mult;
				float y = pos_y - (this_cos * heights[i][j]);
				float z = pos_z - (this_sin * heights[i][j]);

				objects[i].vertices[n + 0].position = Vector3(x, y - BAR_SIZE, z - BAR_SIZE);
				objects[i].vertices[n + 1].position = Vector3(x, y + BAR_SIZE, z - BAR_SIZE);
				objects[i].vertices[n + 2].position = Vector3(x, y + BAR_SIZE, z + BAR_SIZE);
				objects[i].vertices[n + 3].position = Vector3(x, y - BAR_SIZE, z + BAR_SIZE);

				n += 4;
			}

			objects[i].Calculate(params.renderer, &camera, params.elapsed);
		}

		for (int i = 0; i < LIMITER_H; i++)
		{
			float cube_ang = ((CUBE_H + i - (TRAIL_H * 0.5f)) * TRAIL_ANGS) + ANG_OFFSET;
			float cube_cos = cosf(cube_ang);
			float cube_sin = sinf(cube_ang);
			float cube_pos_y = CYLINDER_RADIUS - (CYLINDER_RADIUS * cube_cos);
			float cube_pos_z = (CYLINDER_RADIUS * cube_sin);//sin(dThisAng));

			for (int j = 0; j < TRAIL_W; j++)
			{
				limiters[i].vertices[j].position.y = cube_pos_y - (cube_cos * cube_heights[i][j]);
				limiters[i].vertices[j].position.z = cube_pos_z - (cube_sin * cube_heights[i][j]);
			}

			float br = Clamp< float >(0.9f - ((float)i) / LIMITER_H, 0.0f, 1.0f);
			limiters[i].ambient_light_color = ColorRgb::Grey((int)(255.0f * br * params.brightness));
			limiters[i].Calculate(params.renderer, &camera, params.elapsed);
		}

		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		texture = params.texture_library.Find(envmap_texture_class);
		for (int i = 0; i < TRAIL_H; i++)
		{
			objects[i].textures[0].Set(Actor::TextureType::Envmap, texture);
		}
		for (int i = 0; i < LIMITER_H; i++)
		{
			limiters[i].textures[0].Set(Actor::TextureType::Sprite, texture);
		}
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		Error* error;
		for (int i = 0; i < TRAIL_H; i++)
		{
			error = objects[i].Render(params.renderer);
			if (error) return TraceError(error);
		}
		for (int i = 0; i < LIMITER_H; i++)
		{
			error = limiters[i].Render(params.renderer);
			if (error) return TraceError(error);
		}
		return nullptr;
	}
};

EXPORT_EFFECT(Spectrum, EffectSpectrum)
