#pragma once

#include "Point.h"

template<class T> class Rect
{
public:
	T left, top, right, bottom;

	Rect();
	Rect(T x, T y, T s);
	Rect(T x, T y, T w, T h);
	Rect(const Rect<T>& r);
	Rect(const Point<T>& p1, const Point<T>& p2);
	Rect(const Point<T>& p1, int w, int h);

	void Set(int x, int y, int s);
	void Set(int x, int y, int w, int h);
	void Set(const Rect<T>& r);
	void Set(const Point<T>& p1, const Point<T>& p2);
	void Set(const Point<T>& p1, int w, int h);

	Rect<T> Validated() const;
	void Validate();

	void Move(int x, int y);
	void MoveX(int x);
	void MoveY(int y);

	void SetTopLeft(const Point<T>& p) const;
	void SetTopRight(const Point<T>& p) const;
	void SetBotLeft(const Point<T>& p) const;
	void SetBotRight(const Point<T>& p) const;
	void SetCenter(const Point<T>& p) const;

	Point<T> GetTopLeft() const;
	Point<T> GetTopRight() const;
	Point<T> GetBotLeft() const;
	Point<T> GetBotRight() const;
	Point<T> GetCenter() const;

	T GetWidth() const;
	T GetHeight() const;
	T GetCenterX() const;
	T GetCenterY() const;

	bool IsEmpty() const;
	bool IsValid() const;
	bool Contains(const Point<T>& p) const;
	bool Intersects(const Rect<T>& r) const;
	Rect<T> GetIntersection(const Rect<T>& r) const;

	Rect<T>& operator=(const Rect<T>& r);
	template<class W> operator Rect<W>() const;
	template<class W> bool operator==(const Rect<W>& r) const;
	template<class W> bool operator!=(const Rect<W>& r) const;
	Rect<T> operator+(const Point<T>& p) const;
	Rect<T> operator-(const Point<T>& p) const;
	Rect<T>& operator+=(const Point<T>& p);
	Rect<T>& operator-=(const Point<T>& p);
};

#include "Rect.inl"
