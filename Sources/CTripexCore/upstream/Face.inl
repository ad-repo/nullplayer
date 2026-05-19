#include "Face.h"

inline Face::Face(uint16 vtx1, uint16 vtx2, uint16 vtx3)
{
	Set(vtx1, vtx2, vtx3);
}

inline void Face::Set(const Face& f)
{
	Set(f.vertices[0], f.vertices[1], f.vertices[2]);
}

inline void Face::Set(uint16 vtx1, uint16 vtx2, uint16 vtx3)
{
	vertices[0] = vtx1;
	vertices[1] = vtx2;
	vertices[2] = vtx3;
}

inline void Face::SwapCull()
{
	std::swap(vertices[0], vertices[1]);
}

inline bool Face::Contains(uint16 vtx) const
{
	return vertices[0] == vtx || vertices[1] == vtx || vertices[2] == vtx;
}
inline bool Face::Contains(const Edge& e) const
{
	return Contains(e[0]) && Contains(e[1]);
}

inline void Face::Replace(uint16 old_vtx, uint16 new_vtx)
{
	for (int i = 0; i < 3; i++)
	{
		if (vertices[i] == old_vtx) vertices[i] = new_vtx;
	}
}

inline int Face::IndexOf(uint16 vtx) const
{
	for (int i = 0; i < 3; i++)
	{
		if (vertices[i] == vtx) return i;
	}
	return -1;
}

inline Edge Face::GetEdge(int idx) const
{
	static const int next_idx[3] = { 1, 2, 0 };
	assert(idx >= 0 && idx <= 2);
	return Edge(vertices[idx], vertices[next_idx[idx]]);
}

inline Face& Face::operator=(const Face& f)
{
	Set(f.vertices[0], f.vertices[1], f.vertices[2]);
	return *this;
}

inline bool Face::operator==(const Face& f) const
{
	return vertices[0] == f.vertices[0] && vertices[1] == f.vertices[1] && vertices[2] == f.vertices[2];
}

inline uint16& Face::operator[ ](int idx)
{
	return vertices[idx];
}

inline const uint16& Face::operator[ ](int idx) const
{
	return vertices[idx];
}
