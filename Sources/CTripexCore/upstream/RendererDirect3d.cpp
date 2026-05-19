#include "Platform.h"
#include "RendererDirect3d.h"
#include <d3dx9.h>
#include "Texture.h"
#include "error.h"
#include <memory>
#include "ComPtr.h"

RendererDirect3d::TextureImpl::TextureImpl(int width, int height, TextureFormat format, const void* data, uint32 data_size, uint32 data_stride, const ColorRgb* palette, TextureFlags flags)
	: Texture(width, height, format, flags)
	, data(data)
	, data_size(data_size)
	, data_stride(data_stride)
	, palette(palette)
{
	d3d_texture = nullptr;
	dirty = false;
}

RendererDirect3d::TextureImpl::~TextureImpl()
{
	if (d3d_texture != nullptr)
	{
		d3d_texture->Release();
		d3d_texture = nullptr;
	}
}

void RendererDirect3d::TextureImpl::SetDirty()
{
	dirty = true;
}

Error* RendererDirect3d::TextureImpl::GetPixelData(std::vector<uint8>& buffer) const
{
	IDirect3DSurface9* pSurface;

	HRESULT hRes = d3d_texture->GetSurfaceLevel(0, &pSurface);
	if (FAILED(hRes)) return TraceError(hRes);

	D3DLOCKED_RECT d3dr;

	hRes = pSurface->LockRect(&d3dr, nullptr, 0);
	if (FAILED(hRes))
	{
		pSurface->Release();
		return TraceError(hRes);
	}

	size_t size = d3dr.Pitch * height;
	buffer.assign((uint8*)d3dr.pBits, (uint8*)d3dr.pBits + size);

	pSurface->UnlockRect();
	pSurface->Release();
	return nullptr;
}

/////// RendererDirect3d ///////

RendererDirect3d::RendererDirect3d()
{
	screen_width = 0;
	screen_height = 0;
	memset(&caps, 0, sizeof(caps));
}

Error* RendererDirect3d::Open(HWND hwnd)
{
	Close();

	d3d = Direct3DCreate9(D3D_SDK_VERSION);
	if (d3d == nullptr) return new Error("Unable to initialize DirectX");

	D3DDISPLAYMODE display_mode;

	HRESULT hRes = d3d->GetAdapterDisplayMode(D3DADAPTER_DEFAULT, &display_mode);
	if (FAILED(hRes)) return TraceError(hRes);

	D3DPRESENT_PARAMETERS present_params;
	ZeroMemory(&present_params, sizeof(present_params));
	present_params.Windowed = TRUE;
	present_params.SwapEffect = D3DSWAPEFFECT_COPY;
	present_params.BackBufferFormat = display_mode.Format;
	present_params.EnableAutoDepthStencil = TRUE;
	present_params.AutoDepthStencilFormat = D3DFMT_D16;
	present_params.hDeviceWindow = hwnd;

	hRes = d3d->CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hwnd, D3DCREATE_SOFTWARE_VERTEXPROCESSING, &present_params, &device);
	if (FAILED(hRes)) return TraceError(hRes);

	ComPtr<IDirect3DSurface9> back_buffer_surface;

	hRes = device->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &back_buffer_surface);
	if (FAILED(hRes)) return TraceError(hRes);

	D3DSURFACE_DESC back_buffer_surface_desc;

	hRes = back_buffer_surface->GetDesc(&back_buffer_surface_desc);
	if (FAILED(hRes)) return TraceError(hRes);

	screen_width = back_buffer_surface_desc.Width;
	screen_height = back_buffer_surface_desc.Height;

	hRes = device->GetDeviceCaps(&caps);
	if (FAILED(hRes)) return TraceError(hRes);

	return nullptr;
}

void RendererDirect3d::Close()
{
	device = nullptr;
	d3d = nullptr;
}

Error* RendererDirect3d::BeginFrame()
{
	HRESULT hRes = device->Clear(0, nullptr, D3DCLEAR_TARGET | D3DCLEAR_ZBUFFER, 0x00000000, 1.0f, 0);
	if (FAILED(hRes)) return TraceError(hRes);

	hRes = device->BeginScene();
	if (FAILED(hRes)) return TraceError(hRes);

	hRes = device->SetFVF(D3DFVF_XYZRHW | D3DFVF_DIFFUSE | D3DFVF_SPECULAR | D3DFVF_TEX1);
	if (FAILED(hRes)) return TraceError(hRes);

	return nullptr;
}

Error* RendererDirect3d::EndFrame()
{
	HRESULT hRes = device->EndScene();
	if (FAILED(hRes)) return TraceError(hRes);

	hRes = device->Present(nullptr, nullptr, nullptr, nullptr);
	if (FAILED(hRes)) return TraceError(hRes);

	return nullptr;
}

Rect<int> RendererDirect3d::GetViewportRect() const
{
	return Rect<int>(0, 0, screen_width, screen_height);
}

Rect<float> RendererDirect3d::GetClipRect() const
{
	Rect<float> rect;
	rect.left = std::min(-0.25f, caps.GuardBandLeft);
	rect.right = std::max(screen_width - 0.25f, caps.GuardBandRight);
	rect.top = std::min(-0.25f, caps.GuardBandTop);
	rect.bottom = std::max(screen_height - 0.25f, caps.GuardBandBottom);
	return rect;
}

D3DTEXTUREADDRESS RendererDirect3d::GetD3DTEXTUREADDRESS(TextureAddress address)
{
	switch (address)
	{
	case TextureAddress::Clamp:
		return D3DTADDRESS_CLAMP;
	case TextureAddress::Wrap:
		return D3DTADDRESS_WRAP;
	}

	assert(false);
	return D3DTADDRESS_CLAMP;
}

TextureFormat RendererDirect3d::GetTextureFormat(D3DFORMAT format)
{
	switch (format)
	{
	case D3DFMT_R8G8B8:
	case D3DFMT_X8R8G8B8:
	case D3DFMT_A8R8G8B8:
		return TextureFormat::X8R8G8B8;
	case D3DFMT_P8:
		return TextureFormat::P8;
	}

	assert(false);
	return TextureFormat::Unknown;
}

D3DFORMAT RendererDirect3d::GetD3DFORMAT(TextureFormat format)
{
	switch (format)
	{
	case TextureFormat::X8R8G8B8:
		return D3DFMT_X8R8G8B8;
	case TextureFormat::P8:
		return D3DFMT_P8;
	}

	assert(false);
	return D3DFMT_UNKNOWN;
}

Error* RendererDirect3d::CreateTexture(int width, int height, TextureFormat format, const void* data, uint32 data_size, uint32 data_stride, const ColorRgb* palette, TextureFlags flags, std::shared_ptr<Texture>& out_texture)
{
	// Create the texture object, only retaining the data and palette pointers if it's a dynamic texture
	std::shared_ptr<TextureImpl> texture;
	if ((flags & TextureFlags::Dynamic) == TextureFlags::None)
	{
		texture = std::make_shared<TextureImpl>(width, height, format, nullptr, data_size, data_stride, nullptr, flags);
	}
	else
	{
		texture = std::make_shared<TextureImpl>(width, height, format, data, data_size, data_stride, palette, flags);
	}

	// Create the actual texture
	uint32 nMipLevels = ((flags & TextureFlags::CreateMips) == TextureFlags::CreateMips) ? 0 : 1;
	uint32 nUsage = 0;// ((flags & TextureFlags::Dynamic) == TextureFlags::Dynamic) ? D3DUSAGE_DYNAMIC : 0;

	D3DFORMAT d3dformat = GetD3DFORMAT(format);

	HRESULT hRes = D3DXCreateTexture(device, 256, 256, nMipLevels, nUsage, d3dformat, D3DPOOL_MANAGED, &texture->d3d_texture);
	if (FAILED(hRes))
	{
		return TraceError(hRes);
	}

	// Create the d3d texture instance
	PALETTEENTRY palette_entries[256];
	PALETTEENTRY* palette_entries_ptr = nullptr;
	if (palette != nullptr)
	{
		palette_entries_ptr = palette_entries;

		for (int idx = 0; idx < 256; idx++)
		{
			palette_entries[idx].peRed = palette[idx].r;
			palette_entries[idx].peGreen = palette[idx].g;
			palette_entries[idx].peBlue = palette[idx].b;
			palette_entries[idx].peFlags = 0xff;
		}

		device->SetPaletteEntries(0, palette_entries_ptr);
		device->SetCurrentTexturePalette(0);
	}

	// Upload the new data
	Error* error = UploadTexture(texture->d3d_texture, width, height, d3dformat, data, data_size, data_stride, palette_entries_ptr);
	if (error) return TraceError(error);

	out_texture = std::move(texture);
	return nullptr;
}

Error* RendererDirect3d::CreateTextureFromImage(const void* data, uint32 data_size, std::shared_ptr<Texture>& out_texture)
{
	ComPtr<IDirect3DTexture9> d3d_texture;

	HRESULT hRes = D3DXCreateTextureFromFileInMemory(device, data, data_size, &d3d_texture);
	if (FAILED(hRes)) return TraceError(hRes);

	ComPtr<IDirect3DSurface9> d3d_surface;

	hRes = d3d_texture->GetSurfaceLevel(0, &d3d_surface);
	if (FAILED(hRes)) return TraceError(hRes);

	D3DSURFACE_DESC d3d_surface_desc;

	hRes = d3d_surface->GetDesc(&d3d_surface_desc);
	if (FAILED(hRes)) return TraceError(hRes);

	TextureFormat format = GetTextureFormat(d3d_surface_desc.Format);

	std::shared_ptr<TextureImpl> texture = std::make_shared<TextureImpl>(d3d_surface_desc.Width, d3d_surface_desc.Height, format, nullptr, 0, 0, nullptr, TextureFlags::CreateMips | TextureFlags::Filter);
	texture->d3d_texture = std::move(d3d_texture);

	out_texture = std::move(texture);
	return nullptr;
}

Error* RendererDirect3d::DrawIndexedPrimitive(const RenderState& render_state, size_t num_vertices, const VertexTL* vertices, size_t num_faces, const Face* faces)
{
	assert(num_vertices < 32768);

	device->SetRenderState(D3DRS_CULLMODE, render_state.enable_culling? D3DCULL_CCW : D3DCULL_NONE);
	device->SetRenderState(D3DRS_SHADEMODE, render_state.enable_shading ? D3DSHADE_GOURAUD : D3DSHADE_FLAT);
	device->SetRenderState(D3DRS_SPECULARENABLE, render_state.enable_specular ? TRUE : FALSE);

	switch (render_state.depth_mode)
	{
	case DepthMode::Disable:
		device->SetRenderState(D3DRS_ZENABLE, FALSE);
		device->SetRenderState(D3DRS_ZWRITEENABLE, FALSE);
		break;
	case DepthMode::Normal:
		device->SetRenderState(D3DRS_ZENABLE, TRUE);
		device->SetRenderState(D3DRS_ZFUNC, D3DCMP_LESS);
		device->SetRenderState(D3DRS_ZWRITEENABLE, TRUE);
		break;
	case DepthMode::Stencil:
		device->SetRenderState(D3DRS_ZENABLE, TRUE);
		device->SetRenderState(D3DRS_ZFUNC, D3DCMP_EQUAL);
		device->SetRenderState(D3DRS_ZWRITEENABLE, FALSE);
		break;
	}

	switch (render_state.blend_mode)
	{
	case BlendMode::NoOp:
		device->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
		device->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_ZERO);
		device->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_ONE);
		break;
	case BlendMode::Replace:
		device->SetRenderState(D3DRS_ALPHABLENDENABLE, FALSE);
		break;
	case BlendMode::Add:
		device->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
		device->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_ONE);
		device->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_ONE);
		break;
	case BlendMode::Tint:
		device->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
		device->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_DESTCOLOR);
		device->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_ONE);
		break;
	case BlendMode::OverlayBackground:
		device->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
		device->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_ZERO);
		device->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_INVSRCCOLOR);
		break;
	case BlendMode::OverlayForeground:
		device->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
		device->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_ONE);
		device->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_INVSRCCOLOR);
		break;
	default:
		assert(false);
	}

	for (int stage = 0; stage < RenderState::NUM_TEXTURE_STAGES; stage++)
	{
		TextureImpl* texture = (TextureImpl*)render_state.texture_stages[stage].texture;
		if (texture == nullptr)
		{
			device->SetTexture(stage, nullptr);
		}
		else
		{
			if (texture->dirty)
			{
				D3DFORMAT d3dformat = GetD3DFORMAT(texture->format);

				Error* error = UploadTexture(texture->d3d_texture, texture->width, texture->height, d3dformat, texture->data, texture->data_size, texture->data_stride, (PALETTEENTRY*)texture->palette);
				if (error) return TraceError(error);

				texture->dirty = false;
			}

			device->SetTexture(stage, texture->d3d_texture);

			if ((texture->flags & TextureFlags::CreateMips) == TextureFlags::CreateMips)
			{
				if (caps.TextureFilterCaps & D3DPTFILTERCAPS_MIPFPOINT)
				{
					device->SetSamplerState(stage, D3DSAMP_MIPFILTER, D3DTEXF_POINT);
				}
				else if (caps.TextureFilterCaps & D3DPTFILTERCAPS_MIPFLINEAR)
				{
					device->SetSamplerState(stage, D3DSAMP_MIPFILTER, D3DTEXF_LINEAR);
				}
			}
			else
			{
				device->SetSamplerState(stage, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
			}

			if ((texture->flags & TextureFlags::Filter) == TextureFlags::Filter)
			{
				if (caps.TextureFilterCaps & D3DPTFILTERCAPS_MINFLINEAR)
				{
					device->SetSamplerState(stage, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);
				}
				if (caps.TextureFilterCaps & D3DPTFILTERCAPS_MAGFLINEAR)
				{
					device->SetSamplerState(stage, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
				}
			}
			else
			{
				if (caps.TextureFilterCaps & D3DPTFILTERCAPS_MINFPOINT)
				{
					device->SetSamplerState(stage, D3DSAMP_MINFILTER, D3DTEXF_POINT);
				}
				if (caps.TextureFilterCaps & D3DPTFILTERCAPS_MAGFPOINT)
				{
					device->SetSamplerState(stage, D3DSAMP_MAGFILTER, D3DTEXF_POINT);
				}
			}
		}

		device->SetSamplerState(stage, D3DSAMP_ADDRESSU, GetD3DTEXTUREADDRESS(render_state.texture_stages[stage].address_u));
		device->SetSamplerState(stage, D3DSAMP_ADDRESSV, GetD3DTEXTUREADDRESS(render_state.texture_stages[stage].address_v));
	}

	HRESULT hRes = device->DrawIndexedPrimitiveUP(D3DPT_TRIANGLELIST, 0, (UINT)num_vertices, (UINT)num_faces, faces, D3DFMT_INDEX16, vertices, sizeof(VertexTL));
	if (FAILED(hRes)) return TraceError(hRes);

	return nullptr;
}

Error* RendererDirect3d::UploadTexture(IDirect3DTexture9* d3d_texture, int width, int height, D3DFORMAT format, const void* data, uint32 data_size, uint32 data_stride, const PALETTEENTRY* palette)
{
	int32 num_mips = d3d_texture->GetLevelCount();
	for (int32 i = 0; i < num_mips; i++)
	{
		ComPtr<IDirect3DSurface9> surface;

		HRESULT hRes = d3d_texture->GetSurfaceLevel(i, &surface);
		if (FAILED(hRes)) return TraceError(hRes);

		D3DSURFACE_DESC surface_desc;

		hRes = surface->GetDesc(&surface_desc);
		if (FAILED(hRes)) return TraceError(hRes);

		D3DLOCKED_RECT locked_rect;
		if (surface_desc.Width == (uint32)width && surface_desc.Height == (uint32)height && surface_desc.Format == D3DFMT_P8)
		{
			hRes = surface->LockRect(&locked_rect, nullptr, 0);
			if (FAILED(hRes)) return TraceError(hRes);

			const uint8* input_data = (const uint8*)data;
			uint8* output_data = (uint8*)locked_rect.pBits;

			for (int row = 0; row < 256; row++)
			{
				memcpy(output_data, input_data, 256);
				output_data += locked_rect.Pitch;
				input_data += data_stride;
			}

			hRes = surface->UnlockRect();
			if (FAILED(hRes)) return TraceError(hRes);
		}
		else
		{
			RECT src_rect = { 0, 0, width, height };

			hRes = D3DXLoadSurfaceFromMemory( surface, nullptr, nullptr, data, format, data_stride, palette, &src_rect, D3DX_FILTER_TRIANGLE | D3DX_FILTER_DITHER, 0 );
			if( FAILED( hRes ) ) return TraceError( hRes );
		}
	}
	return nullptr;
}
