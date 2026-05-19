#include "TextureLibrary.h"

void TextureLibrary::Add(const TextureClass& tc, std::shared_ptr<Texture> texture)
{
	std::map<const TextureClass*, std::vector<std::shared_ptr<Texture>>>::iterator it = textures_by_class.find(&tc);
	if (it == textures_by_class.end())
	{
		it = textures_by_class.emplace(&tc, std::vector<std::shared_ptr<Texture>>()).first;
	}
	it->second.push_back(std::move(texture));
}

Texture* TextureLibrary::Find(const TextureClass& tc) const
{
	std::map<const TextureClass*, std::vector<std::shared_ptr<Texture>>>::const_iterator it = textures_by_class.find(&tc);
	if (it == textures_by_class.end())
	{
		return nullptr;
	}

	const std::vector<std::shared_ptr<Texture>>& textures = it->second;
	int index = (int)(((long long)rand() * textures.size()) / (RAND_MAX + 1));

	return textures[index].get();
}

void TextureLibrary::Reset()
{
	textures_by_class.clear();
}
