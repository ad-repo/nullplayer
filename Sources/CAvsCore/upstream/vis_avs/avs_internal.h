#pragma once

#include "avs.h"

#include <unordered_map>

class AVS_Instance;  // Declared in `instance.h`

extern std::unordered_map<AVS_Handle, AVS_Instance*> g_instances;

AVS_Instance* get_instance_from_handle(AVS_Handle avs);
