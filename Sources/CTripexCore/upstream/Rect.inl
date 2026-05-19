#include "Rect.h"

template<class T> inline Rect<T>::Rect()
	: left()
	, top()
	, right()
	, bottom()
{
}

template<class T> inline Rect<T>::Rect(T x, T y, T s)
	: Rect(x, y, s, s)
{
}

template<class T> inline Rect<T>::Rect(T x, T y, T w, T h)
	: left(x)
	, top(y)
	, right(x + w)
	, bottom(y + h)
{
}

template<class T> inline Rect<T>::Rect(const Rect<T>& r)
	: left(r.left)
	, top(r.top)
	, right(r.right)
	, bottom(r.bottom)
{
}

template<class T> inline Rect<T>::Rect(const Point<T>& p1, const Point<T>& p2)
	: Rect()
{
	this->Set(p1, p2);
}

template<class T> inline Rect<T>::Rect(const Point<T>& p1, int w, int h)
	: Rect(p1.x, p1.y, w, h)
{
}

template<class T> inline void Rect<T>::Set(int nX, int nY, int nS)
{
	Set(nX, nY, nS, nS);
}

template<class T> inline void Rect<T>::Set(int nX, int nY, int nW, int nH)
{
	Set(Point<T>(nX, nY), Point<T>(nX + nW, nY + nH));
}

template<class T> inline void Rect<T>::Set(const Rect<T>& r)
{ 
	left = r.left;
	top = r.top;
	right = r.right;
	bottom = r.bottom;
}

template<class T> inline void Rect<T>::Set(const Point<T>& p1, const Point<T>& p2)
{
	left = p1.x;
	top = p1.y;
	right = p2.x;
	bottom = p2.y;
}

template<class T> inline void Rect<T>::Set(const Point<T>& p1, int nW, int nH)
{
	Set(p1, Point<T>(p1.x + nW, p1.y + nH));
}

template<class T> inline Rect<T> Rect<T>::Validated() const
{
	return Rect<T>(Point<T>(std::min(left, right), std::min(top, bottom)), Point<T>(std::max(left, right), std::max(top, bottom)));
}

template<class T> inline void Rect<T>::Validate()
{
	operator=(Validated());
}

template<class T> inline void Rect<T>::Move(int nX, int nY)
{
	MoveX(nX);
	MoveY(nY);
}

template<class T> inline void Rect<T>::MoveX(int nX)
{
	left += nX;
	right += nX;
}

template<class T> inline void Rect<T>::MoveY(int nY)
{
	top += nY;
	bottom += nY;
}

template<class T> inline void Rect<T>::SetTopLeft(const Point<T>& p) const
{
	operator+=(Point<T>(p) - GetTopLeft());
}

template<class T> inline void Rect<T>::SetTopRight(const Point<T>& p) const
{
	operator+=(Point<T>(p) - GetTopRight());
}

template<class T> inline void Rect<T>::SetBotLeft(const Point<T>& p) const
{
	operator+=(Point<T>(p) - GetBotLeft());
}

template<class T> inline void Rect<T>::SetBotRight(const Point<T>& p) const
{
	operator+=(Point<T>(p) - GetBotRight());
}

template<class T> inline void Rect<T>::SetCenter(const Point<T>& p) const
{
	operator+=(Point<T>(p) - GetCenter());
}

template<class T> inline Point<T> Rect<T>::GetTopLeft() const
{
	return Point<T>(left, top);
}

template<class T> inline Point<T> Rect<T>::GetTopRight() const
{
	return Point<T>(right, top);
}

template<class T> inline Point<T> Rect<T>::GetBotLeft() const
{
	return Point<T>(left, bottom);
}

template<class T> inline Point<T> Rect<T>::GetBotRight() const
{
	return Point<T>(right, bottom);
}

template<class T> inline Point<T> Rect<T>::GetCenter() const
{
	return Point<T>(GetCenterX(), GetCenterY());
}

template<class T> inline T Rect<T>::GetWidth() const
{
	return right - left;
}

template<class T> inline T Rect<T>::GetHeight() const
{
	return bottom - top;
}

template<class T> inline T Rect<T>::GetCenterX() const
{
	return (right + left) / 2;
}

template<class T> inline T Rect<T>::GetCenterY() const
{
	return (bottom + top) / 2;
}

template<class T> inline bool Rect<T>::IsEmpty() const
{
	return bottom == top || right == left;
}

template<class T> inline bool Rect<T>::IsValid() const
{
	return bottom > top && right > left;
}

template<class T> inline bool Rect<T>::Contains(const Point<T>& p) const
{
	return p.x >= left && p.x < right && p.y >= top && p.y < bottom;
}

template<class T> inline bool Rect<T>::Intersects(const Rect<T>& r) const
{
	return GetIntersection(r).IsValid();
}

template<class T> inline Rect<T> Rect<T>::GetIntersection(const Rect<T>& r) const
{
	return Rect<T>(Point<T>(std::max(left, r.left), std::max(top, r.top)), Point<T>(std::min(right, r.right), std::min(bottom, r.bottom)));
}

template<class T> inline Rect<T>& Rect<T>::operator=(const Rect<T>& r)
{
	Set(r);
	return *this;
}

template<class T> template <class W > inline Rect<T>::operator Rect<W>() const
{
	return Rect<W>((Point<W>)GetTopLeft(), (Point<W>)GetBotRight());
}

template<class T> template <class W> inline bool Rect<T>::operator==(const Rect<W>& r) const
{
	return left == r.left && right == r.right && top == r.top && bottom == r.bottom;
}

template<class T> template <class W> inline bool Rect<T>::operator!=(const Rect<W>& r) const
{
	return !operator==(r);
}

template<class T> inline Rect<T> Rect<T>::operator+(const Point<T>& p) const
{
	return Rect<T>(GetTopLeft() + p, GetBotRight() + p);
}

template<class T> inline Rect<T> Rect<T>::operator-(const Point<T>& p) const
{
	return Rect<T>(GetTopLeft() - p, GetBotRight() - p);
}

template<class T> inline Rect<T>& Rect<T>::operator+=(const Point<T>& p)
{
	operator=(operator+(p));
	return *this;
}

template<class T> inline Rect<T>& Rect<T>::operator-=(const Point<T>& p)
{
	operator=(operator-(p));
	return *this;
}
