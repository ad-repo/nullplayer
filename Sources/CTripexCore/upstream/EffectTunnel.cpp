#include "Platform.h"
#include "VertexGrid.h"
#include "Actor.h"
#include "BezierCurve.h"
#include "effect.h"
#include "TextureData.h"
#include "error.h"

//static double dPos = 0.9; // start position in the first bezier

class EffectTunnel : public Effect
{
public:
	const TextureClass background_texture_class =
	{
		"Background",
		{ tex_flesh, tex_forest }
	};

	static const int TUNNEL_R1 = 50;
	static const int TUNNEL_R2 = 45;
	static const int BEZIERS = 2;
	static const int TUNNEL_L = 30;
	static const int CROSS_SECTION = 10;
	const float SEP_Z = 200.0f;
	//#define TRADIUS 50//50//50
	//#define TRADIUS2 45//45//45
	//#define nBeziers 2
	//#define nTunnelL 30
	//#define nCrossSection 10
	//#define ZSEP 200.0
	//50.0//100.0

	const float RANDCH_A1 = (2.0f * 3.14159f / 2.0f);//5.0)
	const float RANDCH_R1 = 900.0f;//400.0

	const float RANDCH_A2 = (3.14159f / 10.0f);
	const float RANDCH_R2 = 100.0f;

	float pos;
	float len_pos = 0;
	BezierCurve b[2][BEZIERS];
	Actor obj[2];
	Camera camera;
	int pz[4];
	Texture *texture = nullptr;
	bool first_render;
	float prev_ang;
	float t_br;
	float tex_v_ofs = 3;//0.99;1.5;//0.99;

	EffectTunnel()
		: Effect({ &background_texture_class })
	{
		pos = 0.9f;
		prev_ang = 0;
		t_br = 0;
		first_render = true;

		pz[0] = (int)(SEP_Z * 0);
		pz[1] = (int)(SEP_Z * 1);
		pz[2] = (int)(SEP_Z * 3);
		pz[3] = (int)(SEP_Z * 4);

		for(int no = 0; no < 2; no++)
		{
			for(int i = 0; i < BEZIERS; i++)
			{
				b[no][i].Create(4);
				for(int k = 0; k < 4; k++)
				{
					b[no][i][k] = Vector3(0.0f, 0.0f, (float)pz[k]);
				}
			}

			obj[no].flags.set(Actor::F_DRAW_TRANSPARENT);

			for(int j = 0; j < TUNNEL_L - 1; j++)
			{
				int nIndex = j * CROSS_SECTION;
				for(int i = 0; i < CROSS_SECTION - 1; i++)
				{
					obj[no].faces.push_back(Face(nIndex + i, nIndex + (i + 1), nIndex + CROSS_SECTION + i));
					obj[no].faces.push_back(Face(nIndex + (i + 1), nIndex + CROSS_SECTION + (i + 1), nIndex + CROSS_SECTION + i));
				}
			}
			obj[no].vertices.resize(TUNNEL_L * CROSS_SECTION);

			int k = 0;
			for(int j = 0; j < TUNNEL_L; j++)
			{
				for(int i = 0; i < CROSS_SECTION; i++)
				{
					obj[no].vertices[k].tex_coord[0].x = /*(no / 2.0) +*/ float(i) / float(CROSS_SECTION - 1);
					obj[no].vertices[k].tex_coord[0].y = /*(no / 2.0) +*/ float(j) / float(TUNNEL_L);
					k++;
				}
			}
		}
	}

	Vector3 GetBezPos(int j, float t)
	{
		for (int i = 0;; i++)
		{
			assert(i < BEZIERS);
			if (t < 1.0f) return b[j][i].Calculate(t);
			t--;
		}
	}

	float GetRand(float max)
	{
		return ((rand() * max) / RAND_MAX) - (max / 2.0f);
	}

	Error* Calculate(const CalculateParams& params) override
	{
		Vector3 tunnel_pos[4];

		float pos_change = 0.015f * params.audio_data.GetIntensity() * params.elapsed;

		tex_v_ofs += 0.003f * t_br * params.elapsed;
		while (tex_v_ofs > 0)
		{
			tex_v_ofs--;
		}

		if (params.audio_data.GetIntensity() > t_br)
		{
			t_br += std::min(params.audio_data.GetIntensity() - t_br, 0.05f) * params.elapsed;
		}
		if (params.audio_data.GetIntensity() < t_br)
		{
			t_br += std::max(params.audio_data.GetIntensity() - t_br, -0.05f) * params.elapsed;
		}

		bool reset = false;
		if(first_render)
		{
			pos += 2;
			first_render = false;
		}
		else
		{
			pos += pos_change;
		}

		for(; pos >= 1.0; pos -= 1)
		{
			float ang1 = prev_ang + GetRand(RANDCH_A1 * params.audio_data.GetIntensity( ));
			float ang2 = ang1 + GetRand(RANDCH_A2 * params.audio_data.GetIntensity( ));
			prev_ang = ang2;// + 3.14159;

			for(int j = 0; j < 2; j++)
			{
				for(int i = 0; i < BEZIERS - 1; i++)
				{
					Vector3 v = b[j][i+1][0];
					for(int k = 0; k < 4; k++)
					{
						tunnel_pos[k] = b[j][i+1][k];
						tunnel_pos[k].z -= v.z;
						b[j][i][k] = tunnel_pos[k];
					}
				}

				// 0
				tunnel_pos[0] = tunnel_pos[3];

				// 1
				tunnel_pos[1] = tunnel_pos[3] + (tunnel_pos[3] - tunnel_pos[2]);

				if(j == 1)
				{
					tunnel_pos[2] = b[0][BEZIERS-1][2];
					tunnel_pos[3] = b[0][BEZIERS-1][3];
				}
				else
				{
					tunnel_pos[2].x = tunnel_pos[1].x + (cosf(ang1) * RANDCH_R1);
					tunnel_pos[2].y = tunnel_pos[1].y + (sinf(ang1) * RANDCH_R1);
					tunnel_pos[2].z = tunnel_pos[1].z + (SEP_Z * 2);//cos(dAng1) * RANDCH_R1);

					tunnel_pos[3].x = tunnel_pos[2].x + (cosf(ang2) * RANDCH_R2);
					tunnel_pos[3].y = tunnel_pos[2].y + (sinf(ang2) * RANDCH_R2);
					tunnel_pos[3].z = tunnel_pos[2].z + (SEP_Z * 3);//cos(dAng1) * RANDCH_R1);
				}

				for(int k = 0; k < 4; k++)
				{
					b[j][BEZIERS - 1][k] = tunnel_pos[k];
				}
			}
			reset = true;
		}

		int start = (int)(pos * TUNNEL_L);
		int calc = 0;//fReset? 0 : max(0, (nTunnelL - max(0, nStart - nOldStart)));
		if(calc > 0 && calc < TUNNEL_L)
		{
			for(int no = 0; no < 2; no++)
			{
				memmove(&obj[no].vertices[0].position, &obj[no].vertices[CROSS_SECTION * (TUNNEL_L - calc)].position, calc * CROSS_SECTION * sizeof(Vertex));//pObj[no].pVertex.GetItemSize());
			}
		}

		for(int i = 0; i < TUNNEL_L; i++)
		{
			float this_br = ((start + i + 1) - (pos * TUNNEL_L)) / float(TUNNEL_L + 1);
			this_br = std::min(1.0f, std::max(0.0f, (0.5f / this_br ) - 0.5f));
			this_br = 1.0f - powf(1.0f - this_br, 5.0f);//1.6);

			this_br = 1.0f;

			ColorRgb c = ColorRgb::Grey((int)(255.0f * this_br * params.brightness));
			ColorRgb c2 = ColorRgb::Grey((int)(255.0f * this_br * params.brightness));

			float tex_v = float(start + i) / float(TUNNEL_L);
			int index = i * CROSS_SECTION;
			for(int j = 0; j < CROSS_SECTION; j++)
			{
				obj[0].vertices[index].diffuse = c;
				obj[0].vertices[index].tex_coord[0].y = tex_v;//fvVertex.GetTexture().fV = fTexV;
				index++;
			}
			obj[0].flags.set(Actor::F_VALID_VERTEX_DIFFUSE);

			index = i * CROSS_SECTION;
			for(int j = 0; j < CROSS_SECTION; j++)
			{
				obj[1].vertices[index].diffuse = c2;//.GetDiffuse() = c2;
				obj[1].vertices[index].tex_coord[0].y = tex_v + tex_v_ofs;
				index++;
			}
			obj[1].flags.set(Actor::F_VALID_VERTEX_DIFFUSE);
		}
		for(; calc < TUNNEL_L; calc++)
		{
			int nPos = start + calc;

			for(int no = 0; no < 2; no++)
			{
				float radius = (float)((no == 0)? TUNNEL_R1 : TUNNEL_R2);
				Vector3 v = GetBezPos(0/*no*/, float(nPos) / TUNNEL_L);

				//Vector3 n, v[3];
				Vector3 v2 = GetBezPos(0/*no*/, float(nPos + 0.1f) / float(TUNNEL_L));//, &xp2, &yp2, &zp2);
				Vector3 n = (v2 - v).Normal(1.0);
				tunnel_pos[0] = Vector3(n.z, n.y, -n.x);
				tunnel_pos[1] = Vector3(-n.y, n.z, n.x);
				tunnel_pos[2] = Vector3(n.x, n.y, n.z);

				int index = calc * CROSS_SECTION;
				for(int j = 0; j < CROSS_SECTION; j++)
				{
					float ang = j * PI2 / (CROSS_SECTION - 1);
					float cos_ang = cosf(ang);
					float sin_ang = sinf(ang);

					Vector3 vn;
					vn.x = -((tunnel_pos[0].x * cos_ang) + (tunnel_pos[1].x * sin_ang));
					vn.y = -((tunnel_pos[0].y * cos_ang) + (tunnel_pos[1].y * sin_ang));
					vn.z = -((tunnel_pos[0].z * cos_ang) + (tunnel_pos[1].z * sin_ang));

					obj[no].vertices[index].position = v - (vn * radius);
					index++;
				}
			}
		}

		camera.position = GetBezPos(0, pos + 0.2f);

		Vector3 dir = GetBezPos(0, pos + 0.6f) - camera.position;
		camera.pitch = dir.GetPitch();
		camera.yaw = dir.GetYaw();

		for(int i = 0; i < 2; i++)
		{
			obj[i].Calculate(params.renderer, &camera, params.elapsed);
		}

		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		texture = params.texture_library.Find(background_texture_class);
		obj[0].textures[0].Set(Actor::TextureType::Normal, texture);//SetTexture(tx);
		obj[1].textures[0].Set(Actor::TextureType::Normal, texture);///.pTexture = tx;//SetTexture(tx);
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		for(int i = 0; i < 2; i++)
		{
			Error* error = obj[i].Render(params.renderer);
			if(error) return TraceError(error);
		}
		return nullptr;
	}
};

EXPORT_EFFECT( Tunnel, EffectTunnel )
