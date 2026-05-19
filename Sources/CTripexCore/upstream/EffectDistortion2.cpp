#include "Platform.h"
#include "VertexGrid.h"
#include "effect.h"
#include "error.h"
#include "BezierCurve.h"
#include "TextureData.h"

template<bool WITH_LIGHTS> class EffectDistortion2T : public Effect
{
public:
	const TextureClass background_texture_class =
	{
		"Background",
		WITH_LIGHTS ? std::vector<const uint32*>{ tex_flesh } : std::vector<const uint32*>{ tex_eyes, tex_flesh, tex_forest }
	};

	static const int GRW = 80;
	static const int GRH = 50;
	static const int SPIKES = 15;

	static const int NSPIKES = 8;//15
	static const int NCENTRES = 5;

	BezierCurve pb[NCENTRES];
	double pb_t[NCENTRES];

	VertexGrid grid;
	float xp, yp, t, fac;
	int angle;
	float precalc_atan[(GRW + 1) * (GRH + 1)] = { };

	ColorRgb pc[NCENTRES];
	float centre_ang[NCENTRES];
	float centre_ang_speed[NCENTRES];
	Vector3 centre_pos[NCENTRES];
	double br = 0.0;
	Texture* tx = nullptr;

	EffectDistortion2T()
		: Effect({ &background_texture_class })
		, grid(GRW, GRH)
	{
		xp = yp = 0;
		t = 0;
		fac = 1;
		angle = 0;

		for (int i = 0; i < NCENTRES; i++)
		{
			pb[i].Create(4);
			pb_t[i] = 2 + rand() * 1.0 / RAND_MAX;
			centre_ang[i] = i * 20.0 * 3.14159 / 180.0;
			centre_ang_speed[i] = 0.25 * ((rand() * 40.0 / RAND_MAX) - 20) * 3.14159 / 180.0;

			if ((i % 3) == 0)
			{
				pc[i] = ColorRgb(255, 255, 0);
			}
			else if ((i % 3) == 1)
			{
				pc[i] = ColorRgb(255, 0, 255);
			}
			else
			{
				pc[i] = ColorRgb(0, 255, 255);
			}
		}
	}

	Error* Calculate(const CalculateParams& params) override
	{
		float elapsed = params.elapsed * 1.5;

		br = params.brightness;
		xp += 0.008 * std::max(0.1f, params.audio_data.GetDampenedBand(sensitivity, 0, 0.2f)) * elapsed;
		yp += 0.008 * std::max(0.1f, params.audio_data.GetDampenedBand(sensitivity, 0.15f, 0.5f) + params.audio_data.GetBeat()) * elapsed;
		t += elapsed * std::max(0.5f, params.audio_data.GetDampenedBand(sensitivity, 0, 1.0f)) * 20 * 3.14159 / 180.0;

		angle += 1 * elapsed;
		fac = 0.5 + (0.15 * cos(angle * 3.14159 / 256.0));

		int i = 0;
		for (i = 0; i < NCENTRES; i++)
		{
			Vector3 v1, v2;
			for (pb_t[i] += 0.02 * elapsed * (0.3 + (0.7 * params.audio_data.GetIntensity())); pb_t[i] >= 1.0; pb_t[i] -= 1.0)
			{
				pb[i][0] = pb[i][3];
				pb[i][1] = pb[i][3] + (pb[i][3] - pb[i][2]);
				pb[i][2] = Vector3(rand() * GRW / RAND_MAX, rand() * GRH / RAND_MAX, 0);
				pb[i][3] = Vector3(rand() * GRW / RAND_MAX, rand() * GRH / RAND_MAX, 0);
			}
			centre_ang[i] += (params.audio_data.GetIntensity() /*+ 0.001*/) * centre_ang_speed[i] * elapsed;
			centre_pos[i] = pb[i].Calculate(pb_t[i]);
		}

		i = 0;
		float delta = 1.0f / std::max(grid.width, grid.height);
		float grid_pos_x = xp;
		const float mul_x = 1.0f / GRW;
		const float mul_y = 1.0f / GRH;
		for (int x = 0; x <= grid.width; x++)
		{
			grid_pos_x += delta;

			float grid_pos_y = yp;
			for (int y = 0; y <= grid.height; y++)
			{
				grid_pos_y += delta;

				float locbr = 0;
				float tex_xp = grid_pos_x;
				float tex_yp = grid_pos_y;

				WideColorRgb cCol(0, 0, 0);
				for (int j = 0; j < NCENTRES; j++)
				{
					float pos_x = x - centre_pos[j].x;
					float pos_y = y - centre_pos[j].y;
					float norm_x = pos_x * mul_x;//(1.0f / GRW);
					float norm_y = pos_y * mul_y;//(1.0f / GRH);

					float rad = std::min(1.0, 100.0 / fabs(pos_x * pos_x + pos_y * pos_y));
					locbr += rad;
					float ang = atan2(norm_y, norm_x);
					float len = rad * (0.75 + (0.5 * cos((ang * NSPIKES) + t + centre_ang[j])));
					tex_xp += len * norm_x;
					tex_yp += len * norm_y;

					float col_mult = params.brightness * 0.5 * std::max(0.0f, 1.0f - (sqrtf(pos_x * pos_x + pos_y * pos_y) / 30.0f));
					cCol.r += pc[j].r * col_mult;
					cCol.g += pc[j].g * col_mult;
					cCol.b += pc[j].b * col_mult;
				}

				grid.vertices[i].tex_coords[0].x = tex_xp;
				grid.vertices[i].tex_coords[0].y = tex_yp;

				ColorRgb cGrey = ColorRgb::Grey(std::min(1.0f, params.brightness * locbr) * 255.0);
				if (WITH_LIGHTS)
				{
					grid.vertices[i].specular = cCol * params.brightness * locbr * 0.5;
					grid.vertices[i].diffuse = ColorRgb::Blend(cGrey, (ColorRgb)cCol, 0.2f);//ZColour::Grey(255);
				}
				else
				{
					grid.vertices[i].diffuse = cGrey;
					grid.vertices[i].specular = ColorRgb::Black();
				}
				i++;
			}
		}

		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		RenderState render_state;
		render_state.blend_mode = BlendMode::Add;
		render_state.depth_mode = DepthMode::Disable;
		render_state.enable_specular = true;
		render_state.texture_stages[0].texture = tx;

		Error* error = grid.Render(params.renderer, render_state);
		if (error) return TraceError(error);

		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		tx = params.texture_library.Find(background_texture_class);
		return nullptr;
	}
};

EXPORT_EFFECT(Distortion2, EffectDistortion2T< false >)
EXPORT_EFFECT(Distortion2Col, EffectDistortion2T< true >)

