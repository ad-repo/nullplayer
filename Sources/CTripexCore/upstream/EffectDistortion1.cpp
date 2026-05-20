#include "Platform.h"
#include "VertexGrid.h"
#include "AudioData.h"
#include "effect.h"
#include "error.h"
#include "TextureData.h"

class EffectDistortion1 : public Effect
{
public:
	const TextureClass background_texture_class =
	{
		"Background",
		{ tex_flesh, tex_forest }
	};

	static const int GRW = 80;
	static const int GRH = 50;
	static const int SPIKES = 15;

	VertexGrid grid;
	float xp, yp, t, fac;
	int angle;
	float precalc_atan[(GRW + 1) * (GRH + 1)];
	double br = 0.0;
	bool is_bigbeat = false;
	double bigbeat = 0.0;
	double average = 0.0;
	Texture* tx = nullptr;

	EffectDistortion1()
		: Effect({ &background_texture_class })
		, grid(GRW, GRH)
	{
		xp = yp = 0;
		t = 0;
		fac = 1;
		angle = 0;

		int i = 0;
		for (int x = 0; x <= GRW; x++)
		{
			for (int y = 0; y <= GRH; y++)
			{
				precalc_atan[i] = SPIKES * atan2((y - (GRH / 2.0)) / GRH, (x - (GRW / 2.0)) / GRW);
				i++;
			}
		}
	}

	Error* Calculate(const CalculateParams& params) override
	{
		br = params.brightness;
		xp += 0.015/*08*/ * params.audio_data.GetDampenedBand(sensitivity, 0, 0.25f) * params.elapsed;
		yp += 0.02/*08*/ * params.audio_data.GetDampenedBand(sensitivity, 0.25f, 0.5f) * params.elapsed;
		t += params.elapsed * std::max(0.5, params.audio_data.GetDampenedBand(sensitivity, 2 / 16.0f, 5 / 16.0f) + (3.0 * params.audio_data.GetDampenedBand(sensitivity, 7 / 16.0f, 12 / 16.0f))) * 20 * 3.14159 / 180.0;

		angle += 1 * params.elapsed;
		fac = 0.5 + (0.15 * cos(angle * 3.14159 / 256.0));

		double av = std::max(0.4f, params.audio_data.GetDampenedBand(sensitivity, 0, 1.0f));
		double fx, fy;
		double w2 = grid.width / 2.0, h2 = grid.height / 2.0;
		double rw = 1.0 / grid.width, rh = 1.0 / grid.height;

		ColorRgb color = ColorRgb::Grey(255.0 * params.brightness);

		int i = 0;
		for (int x = 0; x <= grid.width; x++)
		{
			for (int y = 0; y <= grid.height; y++)
			{
				fx = (x - w2) * rw;
				fy = (y - h2) * rh;

				double len = 0.75 + (av * 0.25 * cos(precalc_atan[i] + t));//);

				grid.vertices[i].tex_coords[0].x = (len * fx) + xp;
				grid.vertices[i].tex_coords[0].y = (len * fy) + yp;
				grid.vertices[i].diffuse = color;
				i++;
			}
		}

		grid.update_edges = true;
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		RenderState render_state;
		render_state.blend_mode = BlendMode::Add;
		render_state.depth_mode = DepthMode::Disable;
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

EXPORT_EFFECT(Distortion1, EffectDistortion1)
