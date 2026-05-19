#include "Platform.h"
#include "Actor.h"
#include "TextureData.h"
#include "effect.h"

class EffectTube : public Effect
{
public:
	const TextureClass envmap_texture_class =
	{
		"EnvMap",
		{ tex_alien_egg, tex_shiny_sand }
	};

	const float PTDIST = 15;
	static const int PTCIRCUM = 40;
	static const int PTLENGTH = 20;

	const float HEIGHTST = 30;
	const float HEIGHTM = 0.08f;

	const float CIRADIUS = 40.0f;
	const float CORADIUS = 50.0f;
	const float CANGDIFF = (5.0f * DEG_TO_RAD);
	static const int CLENGTH = 100;

	const float CDIFF = (PTLENGTH * PTDIST / CLENGTH);

	float height[PTLENGTH][PTCIRCUM] = { };
	float accwf[PTCIRCUM] = { };

	Actor obj, coil;
	Camera camera;

	float accum = 1;

	EffectTube()
		: Effect({ &envmap_texture_class })
	{
		coil.vertices.resize(CLENGTH * 4);
		coil.faces.resize((CLENGTH - 1) * 8);
		coil.flags.set(Actor::F_DRAW_TRANSPARENT);
		coil.flags.set(Actor::F_DRAW_Z_BUFFER);
		coil.flags.set(Actor::F_NO_CULL);

		int v = 0;
		for (int i = 0; i < CLENGTH; i++)
		{
			float angle = i * 4.0f * PI2 / CLENGTH;

			coil.vertices[v].position.x = (i - (CLENGTH * 0.5f)) * CDIFF;
			coil.vertices[v].position.y = CORADIUS * sinf(angle - CANGDIFF);
			coil.vertices[v].position.z = CORADIUS * cosf(angle - CANGDIFF);
			v++;

			coil.vertices[v].position.x = (i - (CLENGTH * 0.5f)) * CDIFF;
			coil.vertices[v].position.y = CORADIUS * sinf(angle + CANGDIFF);
			coil.vertices[v].position.z = CORADIUS * cosf(angle + CANGDIFF);
			v++;

			coil.vertices[v].position.x = (i - (CLENGTH * 0.5f)) * CDIFF;
			coil.vertices[v].position.y = CIRADIUS * sinf(angle + CANGDIFF);
			coil.vertices[v].position.z = CIRADIUS * cosf(angle + CANGDIFF);
			v++;

			coil.vertices[v].position.x = (i - (CLENGTH * 0.5f)) * CDIFF;
			coil.vertices[v].position.y = CIRADIUS * sinf(angle - CANGDIFF);
			coil.vertices[v].position.z = CIRADIUS * cosf(angle - CANGDIFF);
			v++;
		}

		int f = 0;
		for (int i = 0; i < CLENGTH - 1; i++)
		{
			for (int j = 0; j < 4; j++)
			{
				coil.faces[f][0] = (i * 4) + j;
				coil.faces[f][2] = ((i + 1) * 4) + j;
				coil.faces[f][1] = (i * 4) + ((j + 1) % 4);
				f++;

				coil.faces[f][0] = ((i + 1) * 4) + j;
				coil.faces[f][2] = ((i + 1) * 4) + ((j + 1) % 4);
				coil.faces[f][1] = (i * 4) + ((j + 1) % 4);
				f++;
			}
		}
		assert(f == coil.faces.size());

		obj.vertices.resize(PTCIRCUM * PTLENGTH);
		obj.faces.resize((PTCIRCUM * 2) * (PTLENGTH - 1));
		obj.flags.set(Actor::F_DRAW_Z_BUFFER);
		obj.flags.set(Actor::F_DRAW_TRANSPARENT);

		f = 0;
		for (int i = 0; i < PTLENGTH - 1; i++)
		{
			for (int j = 0; j < PTCIRCUM; j++)
			{
				obj.faces[f][0] = (i * PTCIRCUM) + j;
				obj.faces[f][2] = ((i + 1) * PTCIRCUM) + j;//(i + 1) * PTCIRCUM) + j;
				obj.faces[f][1] = (i * PTCIRCUM) + ((j + 1) % PTCIRCUM);
				f++;

				obj.faces[f][0] = ((i + 1) * PTCIRCUM) + j;
				obj.faces[f][2] = ((i + 1) * PTCIRCUM) + ((j + 1) % PTCIRCUM);
				obj.faces[f][1] = (i * PTCIRCUM) + ((j + 1) % PTCIRCUM);
				f++;
			}
		}

		for (int i = 0; i < PTLENGTH; i++)
		{
			float br = std::min(1.0f, sinf(i * PI / PTLENGTH) * 1);
			for (int j = 0; j < PTCIRCUM; j++)
			{
				obj.vertices[(i * PTCIRCUM) + j].diffuse = ColorRgb::Grey((int)(br * 255.0f));
			}
		}

		obj.flags.set(Actor::F_VALID_VERTEX_DIFFUSE);
		coil.flags.set(Actor::F_VALID_VERTEX_DIFFUSE);
		assert(f == obj.faces.size());

		camera.position.z = -120;//120;
	}

	Error* Calculate(const CalculateParams& params) override
	{
		for (int i = 0; i < 128; i++)
		{
			accwf[i * PTCIRCUM / 128] += params.audio_data.GetSample(i * 4) * 128.0f * 4.0f * params.elapsed * (PTCIRCUM / 128.0f);
		}

		accum += params.elapsed;

		while (accum > 1.0)
		{
			for (int i = 0; i < CLENGTH; i++)
			{
				double br = std::min(1.0, sin(i * 3.14159 / CLENGTH) * 5) * params.brightness;
				for (int j = 0; j < 4; j++)
				{
					coil.vertices[(i * 4) + j].diffuse = ColorRgb::Grey((int)(255.0f * br));
				}
			}
			for (int i = 0; i < PTLENGTH; i++)
			{
				double br = std::min(1.0, sin(i * 3.14159 / PTLENGTH) * 1) * params.brightness;

				for (int j = 0; j < PTCIRCUM; j++)
				{
					obj.vertices[(i * PTCIRCUM) + j].diffuse = ColorRgb::Grey((int)(255.0f * br));
				}
			}

			for (int i = PTLENGTH - 1; i > 0; i--)
			{
				for (int j = 0; j < PTCIRCUM; j++)
				{
					height[i][j] = height[i - 1][j];
				}
			}

			for (int j = 0; j < PTCIRCUM; j++)
			{
				height[0][j] = HEIGHTST + (accwf[j] * HEIGHTM);
			}

			int k = 0;
			for (int i = 0; i < PTLENGTH; i++)
			{
				float fPos = 1.0f - fabs(((PTLENGTH / 2) - i) / (PTLENGTH / 2.0f));
				float fLenMult = 0.8f + 0.4f * sin(fPos * PI / 2.0f);
				for (int j = 0; j < PTCIRCUM; j++)
				{
					float angle = j * PI2 / PTCIRCUM;

					obj.vertices[k].position.x = (i - (PTLENGTH * 0.5f)) * PTDIST;
					obj.vertices[k].position.y = height[i][j] * fLenMult * sinf(angle);
					obj.vertices[k].position.z = height[i][j] * fLenMult * cosf(angle);

					k++;
				}
			}

			obj.pitch += 2.0f * DEG_TO_RAD;//2 * 3.14159 / 180.0;
			obj.yaw += 1.5f * DEG_TO_RAD;//1.5 * 3.14159 / 180.0;
			coil.pitch += 2.0f * DEG_TO_RAD;//2 * 3.14159 / 180.0;
			coil.yaw += 1.5f * DEG_TO_RAD;//1.5 * 3.14159 / 180.0;

			accum--;
			obj.flags.set(Actor::F_VALID_VERTEX_NORMALS, false);
		}

		for (int i = 0; i < PTCIRCUM; i++)
		{
			accwf[i] = 0;
		}

		obj.Calculate(params.renderer, &camera, params.elapsed);
		coil.Calculate(params.renderer, &camera, params.elapsed);
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		Error* error;

		error = obj.Render(params.renderer);
		if (error) return TraceError(error);

		error = coil.Render(params.renderer);
		if (error) return TraceError(error);

		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		Texture* texture = params.texture_library.Find(envmap_texture_class);
		coil.textures[0].Set(Actor::TextureType::Envmap, texture);
		obj.textures[0].Set(Actor::TextureType::Envmap, texture);

		for (int i = 0; i < PTLENGTH; i++)
		{
			for (int j = 0; j < PTCIRCUM; j++)
			{
				height[i][j] = 0;
			}
		}
		return nullptr;
	}
};

EXPORT_EFFECT(Tube, EffectTube)
