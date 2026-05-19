#include "Platform.h"
#include "VertexGrid.h"
#include "effect.h"
#include "error.h"
#include "Canvas.h"
#include "Texture.h"
#include "TextureData.h"
#include "Actor.h"

class EffectBumpmapping : public Effect
{
public:
	const TextureClass background_texture_class =
	{
		"Background",
		{ tex_blank, tex_flesh }
	};

	const TextureClass tentacles_texture_class =
	{
		"Tentacles",
		{ tex_alien_egg }
	};

	struct BumpmapData
	{
		Texture* texture;
		std::vector<uint8> bumpmap;
	};

	const float MIN_FRAME_TIME = 0.3f; //1.0//0.4//25
	static const int GRIDW = 30;
	static const int GRIDH = 40;

	const float VPDISTANCE = 0.15f;//2
	const float XM = 0.55f; //0.2
	const float YM = 0.55f; //0.2//5 //0.2

	Texture* light = nullptr;
	Texture* texture = nullptr;

	Canvas pc;
	bool pc_initialized = false;

	VertexGrid grid;
	VertexGrid gridbm;
	float tx, ty;
	uint8 lightmap[256 * 256]{ };
	uint16* current_bumpmap = nullptr;

	std::map<Texture*, std::unique_ptr<uint16[]>> texture_to_bumpmap;

	Actor obj;
	Camera camera;

	float precalc_u[GRIDW + 1][GRIDH + 1];
	float precalc_v[GRIDW + 1][GRIDH + 1];
	float precalc_c[GRIDW + 1][GRIDH + 1];

	float br = 0.0f;
	bool in_brighten = 0.0f;
	float brangle = 0.0f;
	float brcolour = 0.0f;
	float ya;
	float angle;

	float tentacle_ang;
	float tentacle_dir;
	float move_speed = 0.0f;
	float accum;

	EffectBumpmapping()
		: Effect({ &background_texture_class, &tentacles_texture_class })
		, grid(GRIDW, GRIDH)
		, gridbm(GRIDW, GRIDH)
		, pc(256, 256)
	{
		tentacle_ang = 0.0f;
		tentacle_dir = 1.0f;

		accum = 10;

		ya = 0;
		tx = 0;
		ty = 0;

		obj.CreateTentacles(/*25*/ 160, 200, 8);
		obj.FindFaceOrder(Vector3::Origin());
		obj.flags.set(Actor::F_DO_POSITION_DELAY);
		obj.flags.set(Actor::F_DRAW_Z_BUFFER);
		obj.frame_history = 12.0f;
		obj.delay_history = 12.0f;
		obj.frame_time = MIN_FRAME_TIME;//0.2;
		obj.FindDelayValues();

		camera.position.z = -240;

		angle = rand() * 2000.0f / RAND_MAX;

		for (int i = 0; i < 256; i++)
		{
			pc.palette[i] = ColorRgb(i, i, i);
		}

		int lightmap_idx = 0;
		for (int y = 0; y < 256; y++)
		{
			for (int x = 0; x < 256; x++)
			{
				float nx = (x - 128.0f) / 128.0f;
				float ny = (y - 128.0f) / 128.0f;
				float nz = 1.0f - sqrtf(nx * nx + ny * ny);
				int lightmap_br = (int)((nz + (nz * nz * nz * nz)) * 256.0f);
				lightmap[lightmap_idx++] = std::min(std::max(lightmap_br, 0), 255);
			}
		}

		for (int y = 0; y < GRIDH + 1; y++)
		{
			for (int x = 0; x < GRIDW + 1; x++)
			{
				float xc = float(x - (GRIDW / 2.0f)) / GRIDW;
				float yc = float(y - (GRIDH / 2.0f)) / GRIDH;

				Vector3 d = Vector3(xc, yc, VPDISTANCE).Normal();

				float xp = atan2f(xc, VPDISTANCE);
				float yp = asinf(yc / sqrt((xc * xc) + (yc * yc) + (VPDISTANCE * VPDISTANCE)));

				float xpp = xp / PI;
				float ypp = yp / PI;
				float dp = /*1.3 - */1.0f - sqrtf(xpp * xpp + ypp * ypp);

				precalc_u[x][y] = (XM * xp);
				precalc_v[x][y] = (YM * yp);
				precalc_c[x][y] = std::min(std::max(dp, 0.0f), 1.0f);
			}
		}
	}

	Error* Calculate(const CalculateParams& params) override
	{
		Error* error;
		br = params.brightness;

		tx += /*4*/1 * params.elapsed;
		ty += params.elapsed * sinf(ya) * cosf(ya * 1.2f) * sinf(ya * 1.5f) * 0.4f;

		ya += params.elapsed * DEG_TO_RAD;

		if (texture != nullptr)
		{
			if (!pc_initialized)
			{
				error = pc.Create(params.renderer);
				if (error) return TraceError(error);

				pc_initialized = true;
			}

			int index = 0;
			for (int x = 0; x <= grid.width; x++)
			{
				for (int y = 0; y <= grid.height; y++)
				{
					grid.vertices[index].tex_coords[0].x = gridbm.vertices[index].tex_coords[0].x = precalc_u[x][y] + (tx / 256.0f);
					grid.vertices[index].tex_coords[0].y = gridbm.vertices[index].tex_coords[0].y = precalc_v[x][y] + (ty / 256.0f);

					float brav = precalc_c[x][y] * br * params.audio_data.GetIntensity();//min(average, 1);
					brav *= 1.6f;
					gridbm.vertices[index].diffuse = ColorRgb::Grey((int)(255.0f * br));//max(0.2, min(brav, 1)) * 255.0);//gridbm->vertex[i].color = D3DRGB(brav, brav, brav);
					grid.vertices[index].diffuse = ColorRgb::Grey((int)(br * precalc_c[(int)(x + tx) % GRIDW][y % GRIDH] * 255.0f));
					index++;
				}
			}

			uint8* data = pc.GetDataPtr();
			if (current_bumpmap == nullptr)
			{
				memset(data, 0, 256 * 256);
			}
			else
			{
				unsigned char lx = (unsigned char)tx;
				for (index = 0; index < 256 * 256; index++)
				{
					data[index] = lightmap[(unsigned short)(current_bumpmap[index] + lx)];
				}
			}

			error = pc.UploadTextures(params.renderer);
			if (error) return TraceError(error);
		}

		// TENTACLES
		obj.ambient_light_color = ColorRgb::Grey((int)(params.brightness * 205.0f));
		if (params.audio_data.IsBeat() && params.audio_data.GetBeat() > 0.9f)
		{
			tentacle_dir = -tentacle_dir;
		}

		for (float pos = 0;;)
		{
			float next = pos + MIN_FRAME_TIME;
			bool is_last = next > params.elapsed;

			float spd = std::min(MIN_FRAME_TIME, params.elapsed - pos);
			obj.roll += spd * tentacle_dir * DEG_TO_RAD * 5.0f * (params.audio_data.GetIntensity() + 0.1f);
			obj.pitch += spd * tentacle_dir * DEG_TO_RAD * 20.0f * params.audio_data.GetIntensity();
			obj.yaw += spd * tentacle_dir * DEG_TO_RAD * 10.0f * (params.audio_data.GetIntensity() + 0.1f);
			angle += params.audio_data.GetIntensity() * move_speed * spd * DEG_TO_RAD;

			obj.position.x = 200.0f * cosf(angle) * sinf(angle * 1.3f) * cosf(angle * 2.3f) * sinf(angle * 0.6f);
			obj.position.y = 100.0f * cosf(angle * 0.2f) * sinf(angle * 1.1f) * cosf(angle * 1.6f) * sinf(angle * 1.2f);
			obj.position.z = 150.0f * cosf(angle * 1.6f) * sinf(angle * 0.5f) * cosf(angle * 1.1f) * sinf(angle * 1.2f);

			if (texture == nullptr) obj.position.z = (obj.position.z / 2) - 50;

			obj.exposure = is_last ? 1 : 0;
			obj.Calculate(params.renderer, &camera, spd);

			if (is_last) break;
			pos = next;
		}
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		Error* error;

		if (texture != nullptr)
		{
			{
				RenderState render_state;
				render_state.depth_mode = DepthMode::Disable;
				render_state.texture_stages[0].texture = texture;

				error = grid.Render(params.renderer, render_state);
				if (error) return TraceError(error);
			}

			{
				RenderState render_state;
				render_state.blend_mode = BlendMode::Add;
				render_state.depth_mode = DepthMode::Disable;
				render_state.texture_stages[0].texture = pc.GetTexture(0, 0);

				error = gridbm.Render(params.renderer, render_state);
				if (error) return TraceError(error);
			}
		}

		error = obj.Render(params.renderer);
		if (error) return TraceError(error);

		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		obj.textures[0].type = Actor::TextureType::Envmap;
		obj.textures[0].texture = params.texture_library.Find(tentacles_texture_class);//ENVIRONMENTMAP));
		move_speed = 1.0f + (rand() * 4.0f / RAND_MAX);

		texture = params.texture_library.Find(background_texture_class);
		if (texture != nullptr)
		{
			std::map<Texture*, std::unique_ptr<uint16[]>>::iterator it = texture_to_bumpmap.find(texture);
			if (it != texture_to_bumpmap.end())
			{
				current_bumpmap = it->second.get();
			}
			else if (texture->width == 256 && texture->height == 256 && texture->format == TextureFormat::X8R8G8B8)
			{
				std::vector<uint8> pixel_data;

				Error* error = texture->GetPixelData(pixel_data);
				if (error) return TraceError(error);

				// Compute the average intensity of each pixel
				std::unique_ptr<uint8[]> intensity(new uint8[256 * 256]);

				unsigned char* pixel_in = (unsigned char*)pixel_data.data();
				unsigned char* intensity_out = intensity.get();
				for (int y = 0; y < 256; y++)
				{
					for (int x = 0; x < 256; x++)
					{
						*(intensity_out++) = ((unsigned)pixel_in[0] + (unsigned)pixel_in[1] + (unsigned)pixel_in[2]) / 3;
						pixel_in += 4;
					}
				}

				// Create the bumpmap from that
				std::unique_ptr<uint16[]> pb(new uint16[256 * 256]);

				int index = 0;
				for (int y = 0; y < 256; y++)
				{
					for (int x = 0; x < 256; x++)
					{
						int bump_x = (int)intensity[(index + 1) & 0xffff] - (int)intensity[(index - 1) & 0xffff] + 128 - x;
						int bump_y = (int)intensity[(index + 256) & 0xffff] - (int)intensity[(index - 256) & 0xffff] + 128 - y;
						pb[index] = (((unsigned char)bump_y) << 8) | ((unsigned char)bump_x);
						index++;
					}
				}

				current_bumpmap = pb.get();
				texture_to_bumpmap[texture] = std::move(pb);
			}
		}
		return nullptr;
	}
};

EXPORT_EFFECT(Bumpmapping, EffectBumpmapping)
