#pragma once

template<class T> class ComPtr
{
public:
	ComPtr();
	ComPtr(T* ptr);
	ComPtr(const ComPtr&) = delete;
	ComPtr(ComPtr&& other);
	~ComPtr();

	void Release();

	operator T* ();
	operator T* () const;

	T** operator&();
	T** operator&() const;

	T* operator->();
	T* operator->() const;

	ComPtr& operator=(const ComPtr& other) = delete;
	ComPtr& operator=(ComPtr&& other) noexcept;

private:
	T* ptr;
};

template<class T> inline ComPtr<T>::ComPtr()
{
	ptr = nullptr;
}

template<class T> inline ComPtr<T>::ComPtr(T* ptr)
{
	this->ptr = ptr;
}

template<class T> inline ComPtr<T>::ComPtr(ComPtr&& other)
{
	ptr = other.ptr;
	other.ptr = nullptr;
}

template<class T> inline ComPtr<T>::~ComPtr()
{
	Release();
}

template<class T> inline void ComPtr<T>::Release()
{
	if (ptr != nullptr)
	{
		ptr->Release();
		ptr = nullptr;
	}
}

template<class T> inline ComPtr<T>::operator T* ()
{
	return ptr;
}

template<class T> inline ComPtr<T>::operator T* () const
{
	return ptr;
}

template<class T> inline T** ComPtr<T>::operator&()
{
	return &ptr;
}

template<class T> inline T** ComPtr<T>::operator&() const
{
	return &ptr;
}

template<class T> inline T* ComPtr<T>::operator->()
{
	return ptr;
}

template<class T> inline T* ComPtr<T>::operator->() const
{
	return ptr;
}

template<class T> inline ComPtr<T>& ComPtr<T>::operator=(ComPtr&& other) noexcept
{
	Release();

	ptr = other.ptr;
	other.ptr = nullptr;

	return *this;
}
