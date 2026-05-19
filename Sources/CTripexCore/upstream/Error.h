#pragma once

#include "Platform.h"
#include <string>
#include <vector>
#include <Windows.h>

struct Error
{
	std::string message;
	std::vector<std::pair<const char*, uint32_t>> trace;

	Error(HRESULT code);
	Error(std::string message);
	~Error();

	Error* AddTrace(const char* file, uint32_t line);
	std::string GetDescription() const;
};

Error* TraceErrorImpl(Error* error, const char* file, uint32_t line);
Error* TraceErrorImpl(HRESULT hRes, const char* file, uint32_t line);

#define TraceError(x) (TraceErrorImpl(x, __FILE__, __LINE__))
