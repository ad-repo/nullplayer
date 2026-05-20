#include "Platform.h"
#include "effect.h"
#include "error.h"
#include "StarModel.h"
#include "Actor.h"
#include "BezierCurve.h"
#include "TextureData.h"
#include <algorithm>

class EffectDotStar : public Effect
{
public:
	const TextureClass sprite_texture_class =
	{
		"Sprite",
		{ tex_bright_light }
	};

	const TextureClass tint_texture_class =
	{
		"Tint",
		{ tex_eyes, tex_flesh, tex_forest, tex_shiny_sand }
	};

	struct DotVertex
	{
		Vector3 position;
		float rhw;
	};

	static const int NUMBEZ = 10;
	const float MAX_TILT = (20.0f * 3.14159f / 180.0f);

	const float TRISIZE = 30.0;

	Texture* texture = nullptr;
	Texture* tint = nullptr;
	std::vector<VertexTL> target_vertices;
	std::vector<Face> target_faces;

	Camera camera;
	Actor obj;
	std::vector<uint8> canvas_buffer;
	std::vector<uint8> canvas_target;
	BezierCurve pb[NUMBEZ];
	float pb_t[NUMBEZ];
	double update_pos;
	double rs = 0, ps = 0, ys = 0;

	ContainedBezierCurve<1> b;
	ContainedBezierCurve<1> b2;

	float bez_pos;
	float bez_pos_2;
	float speed;
	float target;
	float pos;
	float change;
	float total;
	float total_elapsed;
	double brt = 0.0;

	EffectDotStar()
		: Effect({ &sprite_texture_class, &tint_texture_class }) //: camera(0),
		, b(Vector3(-100, -100, 120), Vector3(100, 100, 140))
		, b2(Vector3(-20, -20, -20), Vector3(20, 20, 20))
	{
		camera.flags.set(Camera::F_SCREEN_TRANSFORM, false);

		total_elapsed = 1;
		update_pos = 70;
		bez_pos = 0;
		bez_pos_2 = 0;
		speed = 0;
		target = 0;
		pos = 0;
		change = 0;
		total = 0;

		camera.position.z = -80;
		canvas_buffer.resize(512 * 256);
		canvas_target.resize(128 * 64);

		for (int i = 0; i < NUMBEZ; i++)
		{
			pb[i].Create(4);// = new ZBezier(4);
			pb_t[i] = 3 + (float(i) / NUMBEZ);
		}

		int nIndex = 0;
		obj.vertices.resize(num_star_vertices);
		for (int i = 0; i < num_star_vertices; i++)
		{
			obj.vertices[i].position = Vector3(star_vertices[nIndex], star_vertices[nIndex + 1], star_vertices[nIndex + 2]);
			nIndex += 3;
		}
		nIndex = 0;
		obj.faces.resize(num_star_faces);
		for (int i = 0; i < num_star_faces; i++)
		{
			obj.faces[i] = Face(star_faces[nIndex], star_faces[nIndex + 1], star_faces[nIndex + 2]);
			nIndex += 3;
		}

		obj.flags.set(Actor::F_DO_POSITION_DELAY);

		obj.frame_history = 10.0f;
		obj.delay_history = 10.0f;
		obj.FindDelayValues();
		obj.frame_time = 0.5;
	}

	void DrawTriangle(Vector3* pv1, Vector3* pv2, Vector3* pv3)
	{
		Vector3* pvt;
		if (pv1->y > pv2->y) { pvt = pv1; pv1 = pv2; pv2 = pvt; }
		if (pv2->y > pv3->y) { pvt = pv2; pv2 = pv3; pv3 = pvt; }
		if (pv1->y > pv2->y) { pvt = pv1; pv1 = pv2; pv2 = pvt; }

		int y1 = pv1->y, y2 = pv2->y, y3 = pv3->y;

		float xl = pv1->x;
		float xr = pv1->x;
		float xls = (pv2->x - pv1->x) / (1 + y2 - y1);
		float xrs = (pv3->x - pv1->x) / (1 + y3 - y1);
		int left, right;

		int bPos = y1 * 512;
		for (int y = y1; y <= y3 && y < 256; y++)
		{
			if (y == y2)
			{
				xl = pv2->x;
				xls = (pv3->x - pv2->x) / (1 + y3 - y2);
			}
			if (y >= 0 && y < 256)
			{
				left = std::min(xl, xr);
				right = std::max(xl, xr);
				if (left >= 0 && left < 512) canvas_buffer[bPos + left] = 1;
				if (right >= 0 && right < 512) canvas_buffer[bPos + right] = 1;
			}
			xl += xls;
			xr += xrs;
			bPos += 512;
		}
	}

	Error* Calculate(const CalculateParams& params) override
	{
		camera.position = b.Calculate(bez_pos);
		camera.SetTarget(b2.Calculate(bez_pos_2));//ZVector::Origin());
		bez_pos += 0.02 * speed * params.elapsed;
		bez_pos_2 += 0.02 * speed * params.elapsed;

		change += params.elapsed;
		total += params.audio_data.GetIntensity() * params.elapsed;
		if (change > 20)
		{
			target = total / change;
			total = 0;
			change = 0;
		}

		total_elapsed += params.elapsed * 2;
		if (total_elapsed < 1) return nullptr;

		//	fSpeed = 0;
		speed = StepTo<float>(speed, target, 0.02 * params.elapsed);

		brt = params.brightness;
		update_pos += params.elapsed;
		while (update_pos > 60)
		{
			rs = ((params.audio_data.GetIntensity() * 2.0) + 1.0 + (rand() * 5.0 / RAND_MAX)) * 3.14159 / 180.0;
			ps = ((params.audio_data.GetIntensity() * 2.0) + 1.0 + (rand() * 5.0 / RAND_MAX)) * 3.14159 / 180.0;
			ys = ((params.audio_data.GetIntensity() * 2.0) + 1.0 + (rand() * 5.0 / RAND_MAX)) * 3.14159 / 180.0;

			update_pos -= 15;
		}

		pos += params.elapsed * 0.1;
		while (pos >= 1.0f) pos -= 1.0f;

		std::fill(canvas_buffer.begin(), canvas_buffer.end(), 0);

		int nSub = 1.0f * total_elapsed;
		for (int k = 0; k < canvas_target.size(); k++)
		{
			canvas_target[k] = std::max(0, std::min<int>(canvas_target[k], 8) - nSub);//min(pTarget[k], 4) - 1);	
		}
		total_elapsed -= nSub;

		//	pTarget.Fill(0);
	//	ZeroMemory(pBuffer, 256 * 256 * sizeof(unsigned char));
	//	ZeroMemory(pTarget, 64 * 64 * sizeof(unsigned char));
		obj.roll += params.audio_data.GetIntensity() * params.elapsed * 4.0 * 3.14159 / 180.0;//(average + 0.05) * elapsed;// * rs;
		obj.pitch += params.audio_data.GetIntensity() * params.elapsed * 5.0 * 3.14159 / 180.0;//(average + 0.05) * elapsed;// * rs;
		obj.yaw += params.audio_data.GetIntensity() * params.elapsed * 6.0 * 3.14159 / 180.0;//(average + 0.05) * elapsed;// * rs;
		//	obj.fPitch += average * elapsed * ps;
		//	obj.fYaw += 0.5 * elapsed * ys * 3.14159 / 180.0;

		obj.clip_mask = 0;
		obj.Calculate(params.renderer, &camera, params.elapsed);
		//	ZFlexibleVertex fvVertex = obj.pTransVertex[0];
		for (int i = 0; i < obj.transformed_vertices.size(); i++)
		{
			obj.transformed_vertices[i].position.x += 256.0;
			obj.transformed_vertices[i].position.y += 128.0;// - (4 * fPos);
			//		fvVertex++;
		}

		for (int i = 0; i < obj.clipped_faces.size(); i++)
		{
			Face* pf = &obj.clipped_faces[i];
			DrawTriangle(&obj.transformed_vertices[(*pf)[0]].position, &obj.transformed_vertices[(*pf)[1]].position, &obj.transformed_vertices[(*pf)[2]].position);
		}

		int nSrc = 0, nBase = 0, nDst = 0;
		for (int y = 0; y < 256; y++)
		{
			nDst = nBase;
			for (int x = 0; x < 512; x++)
			{
				canvas_target[nDst] += canvas_buffer[nSrc];
				nSrc++;
				if (((x + 1) & 3) == 0) nDst++;
			}
			if (((y + 1) & 3) == 0) nBase += 128;
		}

		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		speed = params.audio_data.GetIntensity();
		texture = params.texture_library.Find(sprite_texture_class);
		tint = params.texture_library.Find(tint_texture_class);
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		Error* error;

		double size = /*1.2 **/ (std::min(params.renderer.GetWidth(), params.renderer.GetHeight()) - 1) / 64.0f;//min(d3d->GetWidth(), d3d->GetHeight()) / 64.0;

		target_vertices.clear();
		target_faces.clear();

		RenderState render_state;
		render_state.blend_mode = BlendMode::Add;
		render_state.depth_mode = DepthMode::Disable;
		render_state.texture_stages[0].texture = texture;

		ColorRgb colors[5];
		for (int k = 0; k < 5; k++)
		{
			colors[k] = ColorRgb::Grey(brt * 200.0f * k / 4);
		}

		int index = 0;
		double dy = (params.renderer.GetHeight() - 1 - (size * (64.0 /*- (2.0 * fPos)*/))) / 2;
		for (int j = 0; j < 64; j++)
		{
			double dx = (params.renderer.GetWidth() - 1 - (size * 128.0)) / 2;
			for (int i = 0; i < 128; i++)
			{
				if (canvas_target[index] != 0)
				{
					int nH = std::min<int>(canvas_target[index], 16);
					float p = size * (16 - nH) / 32.0f;// / 32.0f;  
					double dX1 = dx + p, dX2 = dx + size - p;
					double dY1 = dy + p, dY2 = dy + size - p;

					if (dX1 >= 0 && dY1 >= 0 && dX2 < params.renderer.GetWidth() - 1 && dY2 < params.renderer.GetHeight() - 1)
					{
						uint16 num_vertices = (uint16)target_vertices.size();
						target_vertices.resize(num_vertices + 4);

						VertexTL* vertex = &target_vertices[num_vertices];

						vertex[0].position.x = dX1;//dX + p;
						vertex[0].position.y = dY1;//dY + p;

						vertex[1].position.x = dX2;//dX + dSize - p;
						vertex[1].position.y = dY1;//dY + p;

						vertex[2].position.x = dX2;//dX + dSize - p;
						vertex[2].position.y = dY2;//dY + dSize - p;

						vertex[3].position.x = dX1;//dX + p;
						vertex[3].position.y = dY2;//dY + dSize - p;

						int color_idx = std::min(4, canvas_target[index] / 2);
						for (int k = 0; k < 4; k++)
						{
							vertex[k].position.z = 1.0f;
							vertex[k].rhw = 1.0f;//vPosition.z = 1.0f;
							vertex[k].diffuse = colors[color_idx];
						}
						vertex[0].tex_coords[0].x = 0;
						vertex[0].tex_coords[0].y = 0;

						vertex[1].tex_coords[0].x = 1;
						vertex[1].tex_coords[0].y = 0;

						vertex[2].tex_coords[0].x = 1;
						vertex[2].tex_coords[0].y = 1;

						vertex[3].tex_coords[0].x = 0;
						vertex[3].tex_coords[0].y = 1;

						target_faces.push_back(Face(num_vertices + 0, num_vertices + 1, num_vertices + 3));
						target_faces.push_back(Face(num_vertices + 1, num_vertices + 2, num_vertices + 3));
					}
				}
				dx += size;
				index++;
			}
			dy += size;
		}

		error = params.renderer.DrawIndexedPrimitive(render_state, target_vertices, target_faces);
		if (error) return TraceError(error);

		if (tint != nullptr)
		{
			RenderState tint_render_state;
			tint_render_state.blend_mode = BlendMode::Tint;
			tint_render_state.depth_mode = DepthMode::Disable;
			params.renderer.DrawSprite(tint_render_state, Point<int>(0, 0), Rect<int>(0, 0, params.renderer.GetWidth(), params.renderer.GetHeight()), ColorRgb::Grey(brt * 255.0));
		}

		return nullptr;
	}
};

EXPORT_EFFECT(DotStar, EffectDotStar)
