#pragma once

#include "Edge.h"

struct Face
{
	uint16 vertices[3];

	Face() = default;
	Face(uint16 vtx1, uint16 vtx2, uint16 vtx3);

	void Set(const Face& f);
	void Set(uint16 vtx1, uint16 vtx2, uint16 vtx3);

	void SwapCull();
	bool Contains(uint16 vtx) const;
	bool Contains(const Edge& e) const;
	void Replace(uint16 old_vtx, uint16 new_vtx);
	int IndexOf(uint16 vtx) const;
	Edge GetEdge(int idx) const;

	Face& operator=(const Face& f);

	bool operator==(const Face& f) const;

	uint16& operator[ ](int idx);
	const uint16& operator[ ](int idx) const;
};

#include "Face.inl"
