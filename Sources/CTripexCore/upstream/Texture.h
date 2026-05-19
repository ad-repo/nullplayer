#pragma once

#include "Error.h"
#include "Misc.h"
#include <vector>

enum class TextureFlags
{
	None = 0,
	Dynamic = 1,
	CreateMips = 2,
	Filter = 4,
};

enum class TextureFormat
{
	X8R8G8B8,
	P8,
	Unknown
};

class Texture
{
public:
	const int width;
	const int height;
	const TextureFormat format;
	const TextureFlags flags;

	Texture(int width, int height, TextureFormat format, TextureFlags flags);
	virtual ~Texture();
	virtual void SetDirty() = 0;
	virtual Error* GetPixelData(std::vector<uint8>& buffer) const = 0;
};

IMPLEMENT_ENUM_FLAGS(TextureFlags)
