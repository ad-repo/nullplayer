#pragma once

#include "Misc.h"

struct Edge
{
	uint16 vertices[2];

	Edge();
	Edge(const Edge& other);
	Edge(uint16 vtx1, uint16 vtx2);

	void Set(const Edge& other);
	void Set(uint16 vtx1, uint16 vtx2);

	Edge Reverse() const;
	Edge OrderIndices() const;

	bool Contains(uint16 vtx) const;

	uint16 CommonIndex(const Edge& other) const;

	bool operator==(const Edge& other) const;

	uint16& operator[ ](int idx);
	const uint16& operator[ ](int idx) const;
};

#include "Edge.inl"
