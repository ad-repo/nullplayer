#pragma once

#include "avs_editor.h"
#include "avs_internal.h"
#include "effect_info.h"

#include <unordered_map>
#include <vector>

extern std::unordered_map<AVS_Effect_Handle, Effect_Info*> g_effect_lib;
extern std::unordered_map<int32_t, AVS_Effect_Handle> g_legacy_builtin_effect_lib;
extern std::unordered_map<std::string, AVS_Effect_Handle> g_legacy_ape_effect_lib;
extern std::vector<AVS_Effect_Handle> g_effect_lib_handles_for_api;

class Effect;  // effect.h

bool make_effect_lib();
Effect* component_factory(const Effect_Info* effect, AVS_Instance* avs);
Effect* component_factory_by_name(const std::string& name, AVS_Instance* avs);
Effect* component_factory_legacy(int legacy_effect_id,
                                 char* legacy_effect_ape_id,
                                 AVS_Instance* avs);
