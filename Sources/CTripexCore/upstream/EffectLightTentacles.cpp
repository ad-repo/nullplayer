#include "Platform.h"
#include "Actor.h"
#include "BezierCurve.h"
#include "effect.h"
#include "error.h"
#include "TextureData.h"

class EffectLightTentacles : public Effect
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

	static const int NMPOINTS = 30;//50//30
	static const int LENGTH = 50;//40
	static const int STEPSIZE = 4;//1

	Actor obj;
	Camera camera;
	BezierCurve b;
	Vector3 points[2][4];
	double brt = 0;
	Texture* tint = nullptr;
	double pos = 2;

	EffectLightTentacles()
		: Effect({ &sprite_texture_class, &tint_texture_class })
		, b(4)
	{
		Actor sphere;
		sphere.CreateGeosphere(1.0, NMPOINTS);

		obj.flags.set(Actor::F_DRAW_VERTEX_SPRITES);
		obj.flags.set(Actor::F_DO_POSITION_DELAY);
		obj.flags.set(Actor::F_DRAW_TRANSPARENT);
		obj.flags.set(Actor::F_VALID_VERTEX_DIFFUSE);
		obj.vertices.resize(LENGTH * NMPOINTS);
		obj.sprite_size = 5;//6;
		obj.exposure = 1;
		obj.frame_history = 3.0f;

		ColorRgb cEdge = ColorRgb(255, 225, 200);//222, 211);

		for (int i = 0; i < NMPOINTS; i++)
		{
			for (int j = 0; j < LENGTH; j++)
			{
				obj.vertices[(i * LENGTH) + j].position = sphere.vertices[i].position * (50 + (j * STEPSIZE));
				double vertex_br = (double(j) / LENGTH);
				vertex_br = 1.0 - (vertex_br * vertex_br);
				obj.vertices[(i * LENGTH) + j].diffuse = ColorRgb::Blend(ColorRgb::White(), cEdge, (float)j / LENGTH) * vertex_br;//Grey(255.0 * dBr);
			}
		}
		obj.frame_history = 11;
		obj.delay_history = 10.0f;
		obj.FindDelayValues();
		camera.position.z = -120;
	}

	Error* Calculate(const CalculateParams& params) override
	{
		brt = params.brightness;

		pos += 0.02 * params.audio_data.GetIntensity();

		if (params.audio_data.GetIntensity() > 0.5)
		{
			obj.roll += ((params.audio_data.GetIntensity() - 0.5) / 0.5) * params.elapsed * 2.0 * 3 * 3.14159 / 180.0;
		}
		if (params.audio_data.GetIntensity() > 0.3)
		{
			obj.pitch += ((params.audio_data.GetIntensity() - 0.3) / 0.7) * params.elapsed * 1.7 * 1.5 * 6.0 * 3.14159 / 180.0;
		}
		obj.yaw += params.audio_data.GetIntensity() * params.elapsed * 4.0 * 3.14159 / 180.0;
		obj.ambient_light_color = ColorRgb::Grey(params.brightness * 255.0);
		//		obj.cAmbientLight = ZWideColour(255, 255, 255);
		obj.Calculate(params.renderer, &camera, params.elapsed);

		while (pos > 1)
		{
			for (int i = 0; i < 2; i++)
			{
				points[i][0] = points[i][3];
				points[i][1] = points[i][3] + (points[i][3] - points[i][2]);

				double r = (i == 0) ? 300 : 50;

				points[i][2].x = ((double(rand()) / RAND_MAX) - 0.5) * r;
				points[i][2].y = ((double(rand()) / RAND_MAX) - 0.5) * r;
				points[i][2].z = ((double(rand()) / RAND_MAX) - 0.5) * r;

				points[i][3].x = ((double(rand()) / RAND_MAX) - 0.5) * r;
				points[i][3].y = ((double(rand()) / RAND_MAX) - 0.5) * r;
				points[i][3].z = ((double(rand()) / RAND_MAX) - 0.5) * r;
			}
			pos--;
		}
		for (int i = 0; i < 4; i++) b[i] = points[0][i];

		camera.position = b.Calculate(pos);//.moveTo(x, y, z);
		for (int i = 0; i < 4; i++) b[i] = points[1][i];//->setPoint(i, px[1][i], py[1][i], pz[1][i]);
		Vector3 v = b.Calculate(pos);//, &x, &y, &z);
		camera.pitch = (v - camera.position).GetPitch();
		camera.yaw = (v - camera.position).GetYaw();
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		Error* error = obj.Render(params.renderer);
		if (error) return TraceError(error);

		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		obj.textures[0].type = Actor::TextureType::Sprite;
		obj.textures[0].texture = params.texture_library.Find(sprite_texture_class);
		tint = params.texture_library.Find(tint_texture_class);
		return nullptr;
	}
};

EXPORT_EFFECT(LightTentacles, EffectLightTentacles)
