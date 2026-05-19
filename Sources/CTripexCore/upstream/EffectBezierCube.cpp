#include "Platform.h"
#include "Actor.h"
#include "BezierCurve.h"
#include "AudioData.h"
#include "effect.h"
#include <conio.h>
#include "error.h"
#include "TextureData.h"

class EffectBezierCube : public Effect
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
		{ tex_eyes, tex_flesh, tex_forest }
	};

	static const int BEZIERS = 5;
	static const int BEZIERPOINTS = 50;
	static const int BEZIERHEIGHT = 80;

	static const int TWISTPLANES = 4;
	static const int TWISTPLANEEDGE = 20;
	static const int TWISTPLANECORNERS = (BEZIERS * TWISTPLANEEDGE);

	const float TWISTPLANERADIUS = 30.0f;

	int corner_index[BEZIERS];

	Texture* sprite_texture;
	Texture* tint_texture;
	Actor obj;
	Actor edges[BEZIERS];
	Actor planes[TWISTPLANES];
	Camera camera;
	BezierCurve bcEdge;
	float fAng;

	float plane_roll_speed[TWISTPLANES];
	float plane_pitch_speed[TWISTPLANES];
	float plane_yaw_speed[TWISTPLANES];
	double brt;

	double ang_x, ang_y, ang_z;
	double mult;

	float fel = 0.0f;

	EffectBezierCube()
		: Effect({ &sprite_texture_class, &tint_texture_class })
		, bcEdge(TWISTPLANES)
	{
		brt = 0.0;
		sprite_texture = nullptr;
		tint_texture = nullptr;

		memset(plane_roll_speed, 0, sizeof(plane_roll_speed));
		memset(plane_pitch_speed, 0, sizeof(plane_pitch_speed));
		memset(plane_yaw_speed, 0, sizeof(plane_yaw_speed));

		ang_x = 0;
		ang_y = 0;
		ang_z = 0;
		mult = 0;

		fAng = 0.0f;
		obj.textures[0].type = Actor::TextureType::Sprite;
		obj.flags.set(Actor::F_DRAW_VERTEX_SPRITES);
		obj.flags.set(Actor::F_DRAW_TRANSPARENT);
		obj.frame_history = 8.0f;
		obj.sprite_history_length = 0.3f;

		for (int i = 0; i < TWISTPLANES; i++)
		{
			plane_roll_speed[i] = (3 + (rand() * 10.0 / RAND_MAX)) * DEG_TO_RAD;
			plane_pitch_speed[i] = (3 + (rand() / RAND_MAX)) * DEG_TO_RAD;
			plane_yaw_speed[i] = (3 + (rand() / RAND_MAX)) * DEG_TO_RAD;

			planes[i].flags.set(Actor::F_DRAW_TRANSPARENT);
			planes[i].flags.set(Actor::F_DRAW_VERTEX_SPRITES);
			planes[i].sprite_size = 5.0f;
			planes[i].flags.set(Actor::F_DO_FRAME_HISTORY);

			planes[i].vertices.resize(TWISTPLANECORNERS);
			Vector3 corners[BEZIERS];
			for (int j = 0; j < BEZIERS; j++)
			{
				float radius = TWISTPLANERADIUS;
				if (i != 0 && i != TWISTPLANES - 1)
				{
					radius *= 1.2f;
				}

				float angle = j * 2.0 * PI / BEZIERS;
				corners[j].x = 0;
				corners[j].y = radius * cosf(angle);
				corners[j].z = radius * sinf(angle);
			}
			for (int j = 0; j < TWISTPLANECORNERS; j++)
			{
				float pos = float(j % TWISTPLANEEDGE) / TWISTPLANEEDGE;
				Vector3& v1 = corners[j / TWISTPLANEEDGE];
				Vector3& v2 = corners[((j / TWISTPLANEEDGE) + 1) % BEZIERS];

				planes[i].vertices[j].position = (v1 * (1 - pos)) + (v2 * pos);
			}

			planes[i].textures[0].type = Actor::TextureType::Sprite;
		}
		for (int i = 0; i < BEZIERS; i++)
		{
			corner_index[i] = i * TWISTPLANECORNERS / BEZIERS;
		}
		for (int i = 0; i < BEZIERS; i++)
		{
			edges[i].vertices.resize(BEZIERPOINTS);
			edges[i].flags.set(Actor::F_DRAW_TRANSPARENT);
			edges[i].flags.set(Actor::F_DRAW_VERTEX_SPRITES);
			edges[i].flags.set(Actor::F_NO_TRANSFORM);
			edges[i].sprite_size = 5.0;
			edges[i].frame_history = 1.0f;
			edges[i].sprite_history_length = 60.0f;
			edges[i].textures[0].type = Actor::TextureType::Sprite;
		}
	}

	Error* Calculate(const CalculateParams& params) override
	{
		double mult_dest = 1 - params.audio_data.GetDampenedBand(sensitivity, 0.0f, 1.0f);
		camera.position.z = -110;
		double sm = 1.3 * params.elapsed;

		brt = params.brightness;

		if (mult_dest < mult)
		{
			mult = std::max(mult_dest, mult - 0.01);
		}
		if (mult_dest > mult)
		{
			mult = std::min(mult_dest, mult + 0.01);
		}

		double center = (TWISTPLANES - 1.0) / 2.0;
		for (int i = 0; i < TWISTPLANES; i++)
		{
			planes[i].roll += plane_roll_speed[i] * (params.audio_data.GetIntensity() + 0.1);
			planes[i].yaw += plane_yaw_speed[i] * (params.audio_data.GetIntensity() + 0.1);
			planes[i].pitch += plane_pitch_speed[i] * params.audio_data.GetIntensity();

			planes[i].position.x = -(BEZIERHEIGHT / 2) + (i * BEZIERHEIGHT / (TWISTPLANES - 1.0));
			planes[i].position.z = -60;

			double brightness = params.brightness * 0.2 * (0.1 + (0.9 * fabs((i / center) - 1)));
			planes[i].ambient_light_color = ColorRgb::Grey(255.0 * brightness);
			planes[i].Calculate(params.renderer, &camera, params.elapsed);
		}

		for (int i = 0; i < BEZIERS; i++)
		{
			for (int j = 0; j < TWISTPLANES; j++)
			{
				bcEdge[j] = planes[j].frames[0]->positions[corner_index[i]];
			}
			for (int j = 0; j < BEZIERPOINTS; j++)
			{
				edges[i].vertices[j].position = bcEdge.Calculate(double(j) / BEZIERPOINTS);
			}
			double brightness = params.brightness * 0.2;
			edges[i].ambient_light_color = ColorRgb::Grey(255.0 * brightness);
			edges[i].Calculate(params.renderer, &camera, params.elapsed);
		}

		fel += params.elapsed;
		for (; fel > 1.0; fel--)
		{
			fAng += 8.0f * DEG_TO_RAD;
			obj.vertices.resize(1);
			obj.vertices[0].position.x = 5 * cos(fAng);
			obj.vertices[0].position.y = 5 * sin(fAng);
			obj.vertices[0].position.z = -100;
		}
		obj.Calculate(params.renderer, &camera, params.elapsed);

		mult = params.audio_data.GetDampenedBand(sensitivity, 0, 1.0f);

		ang_x += sm * mult * 9 * DEG_TO_RAD;
		while (ang_x > PI2) ang_x -= PI2;

		ang_y += sm * params.audio_data.GetDampenedBand(sensitivity, 0 / 16.0f, 3 / 16.0f) * 3.4 * DEG_TO_RAD;
		while (ang_y > PI2) ang_y -= PI2;

		ang_z += sm * params.audio_data.GetDampenedBand(sensitivity, 3 / 16.0f, 9 / 16.0f) * 4.2 * DEG_TO_RAD;
		while (ang_z > PI2) ang_z -= PI2;

		camera.roll += sm * params.audio_data.GetIntensity() * 4 * DEG_TO_RAD;
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		Error* error;

		error = planes[0].Render(params.renderer);
		if (error) return TraceError(error);

		error = planes[TWISTPLANES - 1].Render(params.renderer);
		if (error) return TraceError(error);

		for (int i = 0; i < BEZIERS; i++)
		{
			error = edges[i].Render(params.renderer);
			if (error) return TraceError(error);
		}

		if (tint_texture != nullptr)
		{
			RenderState render_state;
			render_state.blend_mode = BlendMode::Tint;
			render_state.depth_mode = DepthMode::Disable;
			render_state.texture_stages[0].texture = tint_texture;

			error = params.renderer.DrawSprite(render_state, Point<int>(0, 0), Rect<int>(0, 0, params.renderer.GetWidth(), params.renderer.GetHeight()), ColorRgb::Grey(brt * 255.0));
			if (error) return TraceError(error);
		}

		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		sprite_texture = params.texture_library.Find(sprite_texture_class);
		obj.textures[0].texture = sprite_texture;
		for (int i = 0; i < TWISTPLANES; i++)
		{
			planes[i].textures[0].texture = sprite_texture;
		}
		for (int i = 0; i < BEZIERS; i++)
		{
			edges[i].textures[0].texture = sprite_texture;
		}

		tint_texture = params.texture_library.Find(tint_texture_class);
		return nullptr;
	}
};

EXPORT_EFFECT(BezierCube, EffectBezierCube)
