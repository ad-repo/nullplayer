#include "Point.h"

template<class T> inline Point<T>::Point()
	: x()
	, y()
{
}

template<class T> inline Point<T>::Point(T x, T y)
	: x(x)
	, y(y)
{
}

template<class T> inline Point<T>::Point(const Point<T>& p)
	: x(p.x)
	, y(p.y)
{
}

template<class T> inline void Point<T>::Set(const Point<T>& other)
{
	Set(other.x, other.y);
}

template<class T> inline void Point<T>::Set(T new_x, T new_y)
{
	x = new_x;
	y = new_y;
}

template<class T> inline Point<T> Point<T>::operator-() const
{
	return Point<T>(-x, -y);
}

template<class T> inline Point<T> Point<T>::operator+() const
{
	return Point<T>(+x, +y);
}

template<class T> inline Point<T> Point<T>::operator-(const Point<T>& p) const
{
	return Point<T>(x - p.x, y - p.y);
}

template<class T> inline Point<T> Point<T>::operator+(const Point<T>& p) const
{
	return Point<T>(x + p.x, y + p.y);
}

template<class T> inline Point<T>& Point<T>::operator-=(const Point<T>& p)
{
	x -= p.x;
	y -= p.y;
	return *this;
}

template<class T> inline Point<T>& Point<T>::operator+=(const Point<T>& p)
{
	x += p.x;
	y += p.y;
	return *this;
}

template<class T> inline Point<T>& Point<T>::operator=(const Point<T>& p)
{
	Set(p);
	return *this;
}

template<class T> inline bool Point<T>::operator==(const Point<T>& p) const
{
	return x == p.x && y == p.y;
}

template<class T> inline bool Point<T>::operator!=(const Point<T>& p) const
{
	return !operator==(p);
}

template<class T> template<class U > inline Point<T>::operator Point<U>() const
{
	return Point<U>((U)x, (U)y);
}
