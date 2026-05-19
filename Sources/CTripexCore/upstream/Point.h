#pragma once

template<class T> class Point
{
public:
	T x, y;

	Point();
	Point(T nX, T nY);
	Point(const Point<T>& p);

	void Set(const Point<T>& other);
	void Set(T x, T y);

	Point<T> operator-() const;
	Point<T> operator+() const;
	Point<T> operator-(const Point<T>& p) const;
	Point<T> operator+(const Point<T>& p) const;
	Point<T>& operator-=(const Point<T>& p);
	Point<T>& operator+=(const Point<T>& p);
	Point<T>& operator=(const Point<T>& p);
	
	bool operator==(const Point<T>& p) const;
	bool operator!=(const Point<T>& p) const;

	template<class U> operator Point<U>() const;
};

#include "Point.inl"
