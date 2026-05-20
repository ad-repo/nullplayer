#include "Edge.h"

inline Edge::Edge()
	: vertices{ 0, }
{
}

inline Edge::Edge(const Edge& other)
	: vertices{ other.vertices[0], other.vertices[1] }
{
}

inline Edge::Edge(uint16 vtx1, uint16 vtx2)
	: vertices{ vtx1, vtx2 }
{
}

inline void Edge::Set(const Edge& other)
{
	Set(other.vertices[0], other.vertices[1]);
}

inline void Edge::Set(uint16 vtx1, uint16 vtx2)
{
	vertices[0] = vtx1;
	vertices[1] = vtx2;
}

inline Edge Edge::Reverse() const
{
	return Edge(vertices[1], vertices[0]);
}

inline Edge Edge::OrderIndices() const
{
	if (vertices[0] < vertices[1])
	{
		return Edge(vertices[0], vertices[1]);
	}
	else
	{
		return Edge(vertices[1], vertices[0]);
	}
}

inline bool Edge::Contains(uint16 vertex) const
{
	return vertices[0] == vertex || vertices[1] == vertex;
}

inline uint16 Edge::CommonIndex(const Edge& other) const
{
	if (other.Contains(vertices[0]))
	{
		return vertices[0];
	}
	else if (other.Contains(vertices[1]))
	{
		return vertices[1];
	}
	return (uint16)-1;
}

inline bool Edge::operator==(const Edge& other) const
{
	return vertices[0] == other.vertices[0] && vertices[1] == other.vertices[1];
}

inline uint16& Edge::operator[ ](int index)
{
	return vertices[index];
}

inline const uint16& Edge::operator[ ](int index) const
{
	return vertices[index];
}
