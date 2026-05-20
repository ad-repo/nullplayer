#include "Platform.h"
#include "error.h"

Error::Error(HRESULT hRes)
{
	char sBuf[100];
	sprintf(sBuf, "Error %08x\n", hRes);
	message = sBuf;
}

Error::Error(std::string message)
{
	this->message = message;
}

Error::~Error()
{
}

Error* Error::AddTrace(const char* file, uint32_t line)
{
	trace.push_back(std::make_pair(file, line));
	return this;
}

std::string Error::GetDescription() const
{
	std::string description = message;
	description += "Trace: ";
	if (trace.size() > 0)
	{
		for (unsigned int i = 0; i < trace.size(); i++)
		{
			if (i > 0)
			{
				description += ", ";
			}

			const char* sPos = strrchr(trace[i].first, '\\');
			if (sPos == nullptr)
			{
				sPos = trace[i].first;
			}
			else
			{
				sPos++;
			}

			char sBuf[256];
			sprintf(sBuf, "%s(%d)", sPos, trace[i].second);
			description += sBuf;
		}
	}
	else
	{
		description += "(none)";
	}
	return description;
}

// ---------------------------------------------------------

Error* TraceErrorImpl(Error* error, const char* file, uint32_t line)
{
	if (error != nullptr)
	{
		error->AddTrace(file, line);
	}
	return error;
}

Error* TraceErrorImpl(HRESULT hRes, const char* file, uint32_t line)
{
	if (FAILED(hRes))
	{
		return TraceErrorImpl(new Error(hRes), file, line);
	}
	else
	{
		return nullptr;
	}
}
