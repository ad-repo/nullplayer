#include "Platform.h"
#include "Actor.h"
#include "error.h"
#include "effect.h"
#include "TextureData.h"
#include <algorithm>

class EffectWaterGlobe : public Effect
{
private:
	const TextureClass envmap_texture_class =
	{
		"EnvMap",
		{ tex_alien_egg, tex_shiny_sand }
	};

	class GeoEdge : public Edge
	{
	public:
		int split;
	};

	const float accelFac = 0.9f;
	double accum = 2;

	static const int IPOINTS = 10;
	const float MINHEIGHT = 0.0f;
	const float BEHEIGHT = 50.0f; //30, 50, 80 are nice
	const float MAXHEIGHT = 80.0f;

	const float AVSZ = 1.0f;

	const float DAMPCHANGE = 0.001f;

	class WaterObj : public Actor
	{
	public:
		const float MINSZ = -0.8f;
		const float MAXSZ = 0.4f;

		int pos = 0;
		float damping =0.0f;
		std::vector<Vector3> dir;
		std::vector<float> positions, velocities;
		std::vector<std::unique_ptr<uint16[]>> adjacent;
		float size = 0.0f;
		float angle = 0.0f;
		float average = 0.0f;

		WaterObj() : Actor()
		{
		}

		void Start()
		{
			pos = 0;

			CreateTetrahedronGeosphere(200, 5);
			FindVertexFaceList();

			adjacent.resize(vertices.size());

			std::vector<uint16> indices;
			for(int i = 0; i < vertices.size(); i++)
			{
				indices.clear();
				for(int j = 0; vertex_face_list[i][j] != WORD_INVALID_INDEX; j++)
				{
					const Face &f = faces[vertex_face_list[i][j]];
					for(int k = 0; k < 3; k++)
					{
						if(f[k] != i && std::find(indices.begin(), indices.end(), f[k]) == indices.end())
						{
							indices.push_back(f[k]);
						}
					}
				}
				indices.push_back(WORD_INVALID_INDEX);

				std::unique_ptr<uint16[]> index_array = std::make_unique<uint16[]>(indices.size());
				memcpy(index_array.get(), indices.data(), indices.size() * sizeof(indices[0]));

				adjacent[i] = std::move(index_array);
			}

			damping = 1.0f;
			dir.resize(vertices.size());
			for(int i = 0; i < vertices.size(); i++)
			{
				dir[i] = vertices[i].position;
			}
			positions.resize(vertices.size());
			velocities.resize(vertices.size());
		}

		void Update()
		{
			if(angle > 360.0f)
			{
				angle = 0.0f;
				pos = rand() * (int)vertices.size() / RAND_MAX;
				size = average * 0.5f;
			}
			angle += 20.0f;//= 3.14159 / 180.0;
			for(int i = 0; i < vertices.size(); i++)
			{
				float accel = 0;
				int j;
				for(j = 0; adjacent[i][j] != WORD_INVALID_INDEX; j++)
				{
					accel += positions[adjacent[i][j]];
				}
				accel /= j;
				velocities[i] += accel - positions[i];
			}
			for(int i = 0; i < vertices.size(); i++)
			{
				positions[i] += velocities[i];
				positions[i] *= damping;
			}
			positions[pos] = sinf(angle * DEG_TO_RAD) * size;
		}

		void Create()
		{
			for(int i = 0; i < vertices.size(); i++)
			{
				vertices[i].position = dir[i] * (1 + Clamp<float>(positions[i], MINSZ, MAXSZ));
			}
		}

		void ResetPoint(int point)
		{
			float fPos = 0;
			int i;
			for(i = 0; vertex_face_list[point][i] != WORD_INVALID_INDEX; i++)
			{
				fPos += positions[vertex_face_list[point][i]];
			}	
			positions[point] = fPos / i;
		}

		float AverageHeight()
		{
			float fHeight = 0;
			for(int i = 0; i < vertices.size(); i++) 
			{
				fHeight += positions[i];
			}
			return fHeight / vertices.size();
		}
	};

	WaterObj obj;

public:
	Camera camera;

	EffectWaterGlobe()
		: Effect({ &envmap_texture_class })
	{
		obj.Start();
		obj.flags.set(Actor::F_DRAW_Z_BUFFER);
		obj.angle = 10000;

		camera.position = Vector3(0, 0, -320);
	}

	Error* Calculate(const CalculateParams& params) override
	{
		accum += params.elapsed;

		while(accum >= 1)
		{
			obj.damping = 0.98f;//95
			obj.average = params.audio_data.GetIntensity( );
			obj.Update();
	
			obj.pitch += 2.0f * DEG_TO_RAD;
			obj.yaw += 1.5f * DEG_TO_RAD;
			obj.ambient_light_color = ColorRgb::Grey((int)(255.0f * params.brightness));

			accum--;
		}
		obj.flags.reset(Actor::F_VALID_VERTEX_NORMALS);

		obj.Create();
		obj.Calculate(params.renderer, &camera, params.elapsed);
		return nullptr;
	}

	Error* Reconfigure(const ReconfigureParams& params) override
	{
		obj.textures[0].Set(Actor::TextureType::Envmap, params.texture_library.Find(envmap_texture_class));
		return nullptr;
	}

	Error* Render(const RenderParams& params) override
	{
		Error* error;
		obj.flags.set(Actor::F_DRAW_TRANSPARENT);

		error = obj.Render(params.renderer);
		if(error) return TraceError(error);

		return nullptr;
	}
};

EXPORT_EFFECT(WaterGlobe, EffectWaterGlobe)
