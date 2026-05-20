inline void Matrix44::SetRow( int nRow, float fVal0, float fVal1, float fVal2, float fVal3 )
{
	elements[ 0 ][ nRow ] = fVal0;
	elements[ 1 ][ nRow ] = fVal1;
	elements[ 2 ][ nRow ] = fVal2;
	elements[ 3 ][ nRow ] = fVal3;
}

/*---------------------------------------------
* operator*=( ):
---------------------------------------------*/

inline Matrix44 &Matrix44::operator*=( const Matrix44 &m )
{
	*this = operator*(m);
	return *this;
}

/*---------------------------------------------
* operator[ ]( ):
---------------------------------------------*/

inline float *Matrix44::operator[ ]( int nPos )
{
	return elements[ nPos ];
}

inline const float *Matrix44::operator[ ]( int nPos ) const
{
	return elements[ nPos ];
}

/*---------------------------------------------
* Translation( ):
---------------------------------------------*/

inline Matrix44 Matrix44::Translate( const Vector3 &v )
{
	return Translate( v.x, v.y, v.z );
}
