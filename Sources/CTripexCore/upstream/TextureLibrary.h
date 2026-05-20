#pragma once

#include "Texture.h"
#include <set>
#include <map>
#include <vector>
#include <memory>

struct TextureClass
{
	const char* name;
	std::vector<const uint32*> internal_textures;
};

class TextureLibrary
{
public:
	void Add(const TextureClass& tc, std::shared_ptr<Texture> texture);
	Texture* Find(const TextureClass& tc) const;
	void Reset();

private:
	std::map<const TextureClass*, std::vector<std::shared_ptr<Texture>>> textures_by_class;
};
