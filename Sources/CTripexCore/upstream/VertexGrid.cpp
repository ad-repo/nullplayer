#include "Platform.h"
#include "VertexGrid.h"
#include "error.h"
#include <memory>

VertexGrid::VertexGrid(int width, int height)
{
	pos_x = 0.0f;
	pos_y = 0.0f;
	start_x = 0;
	start_y = 0;
	update_edges = true;

	this->width = width;
	this->height = height;
//	this->nWidth = 3;//nWidth;
//	this->nHeight = 3;//nHeight;
	scr_width = scr_height = -1;
//	this->width = width;
//	this->height = height;
//	this->sWidth = this->sHeight = -1;

//	pVertex.SetFormat(dwVertexFormat);
	vertices.resize((this->width + 1) * (this->height + 1));
//	vertices = (width + 1) * (height + 1);
//	vertex = new D3DTLVERTEX[vertices];
//	pFace.SetLength(this->nWidth * this->nHeight * 2);
//	faces = width * height * 2;
//	face = new WORD[faces*3];

//	pbOut.SetLength((nWidth + 1) * (nHeight + 1));

/*	int f = 0, v = 0;
	for(int x = 0; x < nWidth; x++)
	{
		for(int y = 0; y < nHeight; y++)
		{
			pFace[f++] = ZFace(v, v + nHeight + 1, v + 1);
			pFace[f++] = ZFace(v + 1, v + nHeight + 1, v + 1 + nHeight + 1);
/*			pFace[f + 1] = v + (height+1);
			face[f + 2] = v + 1;//(width+1);

			face[f + 3] = v + 1;
			face[f + 4] = v + (height+1);
			face[f + 5] = v + (height+1) + 1;//(width+1);
*/
//			f += 6;
//			v++;
//		}
//		v++;
//	}
}
/*ZGrid::ZGrid(int width, int height, GridCallbackFunction callback)
{
	this->callback = callback;
	this->coordcallback = nullptr;

	Initialise(width, height);
}
*/
//ZGrid::~ZGrid(void)
//{/
//	delete vertex;
//	delete face;
//}
/*
HRESULT ZGrid::Calculate()
{
	double fx, fy;
	int i = 0;
	if(coordcallback != nullptr)
	{
		for(int x = 0; x <= width; x++)
		{
			for(int y = 0; y <= height; y++)
			{
				coordcallback(x, y, &vertex[i].tu, &vertex[i].tv, &vertex[i].color);
				i++;
			}
		}
	}
	else
	{
		for(int x = 0; x <= width; x++)
		{
			for(int y = 0; y <= height; y++)
			{
				fx = (x - (width/2.0)) / double(width);
				fy = (y - (height/2.0)) / double(height);
	
				callback(fx, fy, &vertex[i].tu, &vertex[i].tv, &vertex[i].color);
				i++;
			}
		}
	}
	return DD_OK;
}
*/
//void ZGrid::SetCallback(GridCallbackFunction fn)
//{
//	callback = fn;
//}
Error* VertexGrid::Render(Renderer& renderer, const RenderState& render_state)
{
	int new_scr_width = renderer.GetWidth();
	int new_scr_height = renderer.GetHeight();
	if(scr_width != new_scr_width || scr_height != new_scr_height)
	{
		scr_width = new_scr_width;
		scr_height = new_scr_height;
//		float fScaleX = nScrWidth / 640.0;
//		float fScaleY = nScrHeight / 480.0;

//		scaleY = scaleX = max(scaleX, scaleY);
		float scale = std::max(scr_width / 640.0f, scr_height / 480.0f);

		int i = 0;
//		ZFlexibleVertex fv(pVertex);
		start_x = -1;
		start_y = -1;

		std::unique_ptr<float[]> pfY = std::make_unique<float[]>(height + 1);
		for(int y = 0; y <= height; y++)
		{
			pfY[y] = (y * 479 * scale / height) + ((scr_height - (480 * scale)) / 2);
			if(start_y == -1 && y > 0 && pfY[y] > 0)
			{
				start_y = y;
				pos_y = pfY[y] / (pfY[y] - pfY[y - 1]);
			}
		}
		std::unique_ptr<float[]> pfX = std::make_unique<float[]>(width + 1);
		for(int x = 0; x <= width; x++)
		{
			pfX[x] = (x * 639 * scale / width) + ((scr_width - (640 * scale)) / 2);
			if(start_x == -1 && x > 0 && pfX[x] > 0)
			{
				start_x = x;
				pos_x = pfX[x] / (pfX[x] - pfX[x - 1]);
			}
		}
		for(int x = 0; x <= width; x++)
		{
			for(int y = 0; y <= height; y++)
			{
				vertices[i].position.x = pfX[x];
				vertices[i].position.y = pfY[y];
				vertices[i].position.z = vertices[i].rhw = 1;
				i++;
			}
		}
		faces.clear();
//		nStartX = nStartY = 3;
//		nStartX+=1;
//		nStartY+=1;
// no limit texas holdem
//		pFace.SetLength(4);//(nWidth - ((nStartX - 1) * 2)) * (nHeight - ((nStartY - 1) * 2)));
//		int nSpan = nHeight - ((nStartY - 1) * 2) + 1;
		int vertex_index = 0;
		i = 0;
		for(int x = 0; x < width; x++)
		{
			for(int y = 0; y <= height; y++)
			{
				if(x >= start_x - 1 && x <= width - start_x && y >= start_y - 1 && y <= height - start_y)
				{
					faces.push_back(Face(vertex_index, vertex_index + height + 1, vertex_index + height + 2));
					faces.push_back(Face(vertex_index, vertex_index + height + 2, vertex_index + 1));
				}
				vertex_index++;
			}
		}
		update_edges = true;
//		assert(i == pFace.GetLength());
	}
	if(update_edges)
	{
		int index1 = (start_x - 1) * (height + 1);
		int index2 = (width - start_x + 1) * (height + 1);
		for(int y = 0; y <= height; y++)
		{
			vertices[index1].position.x = -0.25f;
			vertices[index1].tex_coords[0].x = (pos_x * vertices[index1].tex_coords[0].x) + ((1 - pos_x) * vertices[index1 + (height + 1)].tex_coords[0].x);
			vertices[index1].tex_coords[0].y = (pos_x * vertices[index1].tex_coords[0].y) + ((1 - pos_x) * vertices[index1 + (height + 1)].tex_coords[0].y);
			index1++;

			vertices[index2].position.x = scr_width - 1.25f;
			vertices[index2].tex_coords[0].x = (pos_x * vertices[index2].tex_coords[0].x) + ((1 - pos_x) * vertices[index2 - (height + 1)].tex_coords[0].x);
			vertices[index2].tex_coords[0].y = (pos_x * vertices[index2].tex_coords[0].y) + ((1 - pos_x) * vertices[index2 - (height + 1)].tex_coords[0].y);
			index2++;
		}

		index1 = (start_y - 1);
		index2 = (height - start_y + 1);
		for(int x = 0; x <= width; x++)
		{
			vertices[index1].position.y = -0.25f;
			vertices[index1].tex_coords[0].x = (pos_x * vertices[index1].tex_coords[0].x) + ((1 - pos_x) * vertices[index1 + 1].tex_coords[0].x);
			vertices[index1].tex_coords[0].y = (pos_x * vertices[index1].tex_coords[0].y) + ((1 - pos_x) * vertices[index1 + 1].tex_coords[0].y);
			index1 += height + 1;

			vertices[index2].position.y = scr_height - 1.25f;
			vertices[index2].tex_coords[0].x = (pos_x * vertices[index2].tex_coords[0].x) + ((1 - pos_x) * vertices[index2 - 1].tex_coords[0].x);
			vertices[index2].tex_coords[0].y = (pos_x * vertices[index2].tex_coords[0].y) + ((1 - pos_x) * vertices[index2 - 1].tex_coords[0].y);
			index2 += height + 1;
		}
		update_edges = false;
	}

	Error* error = renderer.DrawIndexedPrimitive(render_state, vertices, faces);
	if(error) return TraceError(error);

	return nullptr;
}
