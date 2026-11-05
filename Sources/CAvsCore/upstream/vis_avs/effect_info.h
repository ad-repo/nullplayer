#pragma once

#include "avs_editor.h"
#include "handles.h"

#include "../3rdparty/json.h"

#include <iomanip>
#include <sstream>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <vector>

using json = nlohmann::ordered_json;

/**
 * This file encapsulates most of the dirty parts around component- and parameter
 * introspection (with effect.h covering the rest).
 *
 * The goal is to abstract away the introspection (which is bound to be hacky, because
 * C++ is not tuned for this) and keep both the external API _and_ the internal code for
 * individual effects as clean and simple as possible. Beyond declaration of the
 * Effect_Info struct, effects should have simple direct access to a struct with basic
 * config parameters, without any further intermediaries like getters/setters. In the
 * other direction the API should be as simple as C allows, with plain numerical
 * handles and arrays.
 *
 * The result is that the Effect_Info structure declaration is the most verbose and
 * fragile part. But it does make sense to make the trade-off this way, because it's
 * only declared statically at compile time once per effect and after that never really
 * touched again by any outside (API) or inside (effect) code.
 */

/**
 * The base for all effects' config structs. Must be empty, because `offsetof` is not
 * strictly supported for structs/classes with inherited members.
 */
struct Effect_Config {};

class Effect;      // defined in effect.h
struct Parameter;  // defined below

/* Function types for various Parameter fields. */
typedef void (*value_change_handler)(Effect* component,
                                     const Parameter* parameter,
                                     const std::vector<int64_t>& parameter_path);
typedef const char* const* (*options_getter)(int64_t* length_out);
typedef size_t (*list_length_getter)(uint8_t* list_address);
typedef Effect_Config* (*list_item_addr_getter)(uint8_t* list_address, int64_t index);
typedef bool (*list_adder)(uint8_t* list_address, uint32_t length_max, int64_t* before);
typedef bool (*list_mover)(uint8_t* list_address, int64_t* from, int64_t* to);
typedef bool (*list_remover)(uint8_t* list_address,
                             uint32_t length_min,
                             int64_t* to_remove);
typedef bool (*list_clearer)(uint8_t* list_address);
typedef void (*list_edit_handler)(Effect* component,
                                  const Parameter* parameter,
                                  const std::vector<int64_t>& parameter_path,
                                  int64_t index1,
                                  int64_t index2);

struct Parameter {
    AVS_Parameter_Handle handle = 0;
    size_t offset = 0;
    AVS_Parameter_Type type = AVS_PARAM_INVALID;
    const char* name = NULL;
    const char* description = NULL;
    bool is_saved = true;
    bool is_global = false;
    value_change_handler on_value_change = NULL;

    options_getter get_options = NULL;

    int64_t int_min = 0;
    int64_t int_max = 0;
    double float_min = 0.0;
    double float_max = 0.0;

    uint32_t num_child_parameters = 0;
    uint32_t num_child_parameters_min = 0;
    uint32_t num_child_parameters_max = 0;
    const Parameter* child_parameters = NULL;
    size_t sizeof_child = 1;

    list_length_getter list_length = NULL;
    list_item_addr_getter list_item_addr = NULL;
    list_adder list_add = NULL;
    list_mover list_move = NULL;
    list_remover list_remove = NULL;
    list_clearer list_clear = NULL;
    list_edit_handler on_list_add = NULL;
    list_edit_handler on_list_move = NULL;
    list_edit_handler on_list_remove = NULL;

    void from_json(const json& config_json, Effect_Config* config) const;
    json to_json(const Effect_Config* config) const;
};

template <typename T>
size_t list_length(uint8_t* list_address) {
    auto list = (std::vector<T>*)list_address;
    return list->size();
}
template <typename T>
Effect_Config* list_item_addr(uint8_t* list_address, int64_t index) {
    auto list = (std::vector<T>*)list_address;
    if (index < 0) {
        index = list->size() + index;
    }
    if (index < 0 || (size_t)index >= list->size()) {
        return NULL;
    }
    return &(*list)[index];
}
template <typename T>
bool list_add(uint8_t* list_address, uint32_t length_max, int64_t* before) {
    auto list = (std::vector<T>*)list_address;
    if (list->size() >= length_max) {
        return false;
    }
    if (*before < 0) {
        *before = list->size() + *before;
    }
    if (*before < 0) {
        *before = 0;
    }
    if ((size_t)(*before) >= list->size()) {
        list->emplace_back();
        *before = list->size() - 1;
    } else {
        list->emplace(list->begin() + *before);
    }
    return true;
}
template <typename T>
bool list_move(uint8_t* list_address, int64_t* from, int64_t* to) {
    auto list = (std::vector<T>*)list_address;
    if (*from < 0) {
        *from = list->size() - 1;
    }
    if (*to < 0) {
        *to = list->size() - 1;
    }
    if (*from == *to) {
        // Technically correct, but don't run the on_move handler.
        return false;
    }
    if ((size_t)*from >= list->size() || (size_t)*to >= list->size()) {
        return false;
    }
    std::vector<T> new_list;
    bool found_from = false;
    bool found_to = false;
    for (auto e = list->begin(); e != list->end(); e++) {
        if (e == list->begin() + *to + found_from) {
            found_to = true;
            new_list.push_back((*list)[*from]);
        }
        if (e != list->begin() + *from) {
            new_list.push_back(*e);
        } else {
            found_from = true;
        }
    }
    if (!found_to) {
        new_list.push_back((*list)[*from]);
    }
    list->swap(new_list);
    return true;
}
template <typename T>
bool list_remove(uint8_t* list_address, uint32_t length_min, int64_t* to_remove) {
    auto list = (std::vector<T>*)list_address;
    if (list->size() <= length_min) {
        return false;
    }
    if (*to_remove < 0) {
        *to_remove = list->size() + *to_remove;
    }
    if (*to_remove < 0 || (size_t)(*to_remove) >= list->size()) {
        return false;
    }
    list->erase(std::next(list->begin(), *to_remove));
    return true;
}
template <typename T>
bool list_clear(uint8_t* list_address) {
    auto list = (std::vector<T>*)list_address;
    list->clear();
    return true;
}

constexpr Parameter PARAM(size_t offset,
                          AVS_Parameter_Type type,
                          const char* name,
                          const char* description = NULL,
                          value_change_handler on_value_change = NULL,
                          bool is_saved = true) {
    Parameter _param = Parameter();
    _param.handle = Handles::comptime_get(name);
    _param.offset = offset;
    _param.type = type;
    _param.name = name;
    _param.description = description;
    _param.is_saved = is_saved;
    _param.on_value_change = on_value_change;
    return _param;
}
#define PARAM_SIMPLE(TYPE)                                                           \
    constexpr Parameter P_##TYPE(size_t offset,                                      \
                                 const char* name,                                   \
                                 const char* description = NULL,                     \
                                 value_change_handler on_value_change = NULL,        \
                                 bool is_saved = true) {                             \
        return PARAM(                                                                \
            offset, AVS_PARAM_##TYPE, name, description, on_value_change, is_saved); \
    }                                                                                \
    constexpr Parameter P_##TYPE##_X(size_t offset,                                  \
                                     const char* name,                               \
                                     const char* description = NULL,                 \
                                     value_change_handler on_value_change = NULL) {  \
        return PARAM(                                                                \
            offset, AVS_PARAM_##TYPE, name, description, on_value_change, false);    \
    }                                                                                \
    constexpr Parameter P_##TYPE##_G(size_t offset,                                  \
                                     const char* name,                               \
                                     const char* description = NULL,                 \
                                     value_change_handler on_value_change = NULL,    \
                                     bool is_saved = true) {                         \
        Parameter _param =                                                           \
            P_##TYPE(offset, name, description, on_value_change, is_saved);          \
        _param.is_global = true;                                                     \
        return _param;                                                               \
    }                                                                                \
    constexpr Parameter P_##TYPE##_GX(size_t offset,                                 \
                                      const char* name,                              \
                                      const char* description = NULL,                \
                                      value_change_handler on_value_change = NULL) { \
        Parameter _param = P_##TYPE##_X(offset, name, description, on_value_change); \
        _param.is_global = true;                                                     \
        return _param;                                                               \
    }
PARAM_SIMPLE(BOOL)
PARAM_SIMPLE(INT)
PARAM_SIMPLE(FLOAT)
PARAM_SIMPLE(COLOR)
PARAM_SIMPLE(STRING)
PARAM_SIMPLE(INT_ARRAY)
PARAM_SIMPLE(FLOAT_ARRAY)
PARAM_SIMPLE(COLOR_ARRAY)

constexpr Parameter P_IRANGE(size_t offset,
                             const char* name,
                             int64_t int_min = 0,
                             int64_t int_max = 0,
                             const char* description = NULL,
                             value_change_handler on_value_change = NULL,
                             bool is_saved = true) {
    Parameter _param =
        PARAM(offset, AVS_PARAM_INT, name, description, on_value_change, is_saved);
    _param.int_min = int_min;
    _param.int_max = int_max;
    return _param;
}
constexpr Parameter P_IRANGE_G(size_t offset,
                               const char* name,
                               int64_t int_min = 0,
                               int64_t int_max = 0,
                               const char* description = NULL,
                               value_change_handler on_value_change = NULL,
                               bool is_saved = true) {
    Parameter _param = P_IRANGE(
        offset, name, int_min, int_max, description, on_value_change, is_saved);
    _param.is_global = true;
    return _param;
}

constexpr Parameter P_FRANGE(size_t offset,
                             const char* name,
                             double float_min = 0,
                             double float_max = 0,
                             const char* description = NULL,
                             value_change_handler on_value_change = NULL,
                             bool is_saved = true) {
    Parameter _param =
        PARAM(offset, AVS_PARAM_FLOAT, name, description, on_value_change, is_saved);
    _param.float_min = float_min;
    _param.float_max = float_max;
    return _param;
}
constexpr Parameter P_FRANGE_G(size_t offset,
                               const char* name,
                               double float_min = 0,
                               double float_max = 0,
                               const char* description = NULL,
                               value_change_handler on_value_change = NULL,
                               bool is_saved = true) {
    Parameter _param = P_FRANGE(
        offset, name, float_min, float_max, description, on_value_change, is_saved);
    _param.is_global = true;
    return _param;
}

constexpr Parameter P_SELECT(size_t offset,
                             const char* name,
                             options_getter get_options,
                             const char* description = NULL,
                             value_change_handler on_value_change = NULL,
                             bool is_saved = true) {
    Parameter _param =
        PARAM(offset, AVS_PARAM_SELECT, name, description, on_value_change, is_saved);
    _param.get_options = get_options;
    return _param;
}
constexpr Parameter P_SELECT_X(size_t offset,
                               const char* name,
                               options_getter get_options,
                               const char* description = NULL,
                               value_change_handler on_value_change = NULL) {
    Parameter _param =
        PARAM(offset, AVS_PARAM_SELECT, name, description, on_value_change, false);
    _param.get_options = get_options;
    return _param;
}
constexpr Parameter P_SELECT_G(size_t offset,
                               const char* name,
                               options_getter get_options,
                               const char* description = NULL,
                               value_change_handler on_value_change = NULL,
                               bool is_saved = true) {
    Parameter _param =
        P_SELECT(offset, name, get_options, description, on_value_change, is_saved);
    _param.is_global = true;
    return _param;
}
constexpr Parameter P_SELECT_GX(size_t offset,
                                const char* name,
                                options_getter get_options,
                                const char* description = NULL,
                                value_change_handler on_value_change = NULL) {
    Parameter _param =
        P_SELECT_X(offset, name, get_options, description, on_value_change);
    _param.is_global = true;
    return _param;
}

constexpr Parameter P_RESOURCE(size_t offset,
                               const char* name,
                               options_getter get_options,
                               const char* description = NULL,
                               value_change_handler on_value_change = NULL,
                               bool is_saved = true) {
    Parameter _param =
        PARAM(offset, AVS_PARAM_RESOURCE, name, description, on_value_change, is_saved);
    _param.get_options = get_options;
    return _param;
}
constexpr Parameter P_RESOURCE_X(size_t offset,
                                 const char* name,
                                 options_getter get_options,
                                 const char* description = NULL,
                                 value_change_handler on_value_change = NULL) {
    Parameter _param =
        PARAM(offset, AVS_PARAM_RESOURCE, name, description, on_value_change, false);
    _param.get_options = get_options;
    return _param;
}
constexpr Parameter P_RESOURCE_G(size_t offset,
                                 const char* name,
                                 options_getter get_options,
                                 const char* description = NULL,
                                 value_change_handler on_value_change = NULL,
                                 bool is_saved = true) {
    Parameter _param =
        P_RESOURCE(offset, name, get_options, description, on_value_change, is_saved);
    _param.is_global = true;
    return _param;
}
constexpr Parameter P_RESOURCE_GX(size_t offset,
                                  const char* name,
                                  options_getter get_options,
                                  const char* description = NULL,
                                  value_change_handler on_value_change = NULL) {
    Parameter _param =
        P_RESOURCE_X(offset, name, get_options, description, on_value_change);
    _param.is_global = true;
    return _param;
}

template <typename Subtype>
constexpr Parameter P_LIST(size_t offset,
                           const char* name,
                           const Parameter* list,
                           uint32_t length,
                           uint32_t length_min = 0,
                           uint32_t length_max = 0,
                           const char* description = NULL,
                           list_edit_handler on_add = NULL,
                           list_edit_handler on_move = NULL,
                           list_edit_handler on_remove = NULL,
                           bool is_saved = true) {
    Parameter _param = PARAM(offset, AVS_PARAM_LIST, name, description, NULL, is_saved);
    _param.num_child_parameters = length;
    _param.num_child_parameters_min = length_min;
    _param.num_child_parameters_max =
        (length_max == length_min && length_max == 0) ? UINT32_MAX : length_max;
    _param.child_parameters = list;
    _param.sizeof_child = sizeof(Subtype);
    _param.list_length = list_length<Subtype>;
    _param.list_item_addr = list_item_addr<Subtype>;
    _param.list_add = list_add<Subtype>;
    _param.list_move = list_move<Subtype>;
    _param.list_remove = list_remove<Subtype>;
    _param.list_clear = list_clear<Subtype>;
    _param.on_list_add = on_add;
    _param.on_list_move = on_move;
    _param.on_list_remove = on_remove;
    return _param;
}
template <typename Subtype>
constexpr Parameter P_LIST_G(size_t offset,
                             const char* name,
                             const Parameter* list,
                             uint32_t length,
                             uint32_t length_min = 0,
                             uint32_t length_max = 0,
                             const char* description = NULL,
                             list_edit_handler on_add = NULL,
                             list_edit_handler on_move = NULL,
                             list_edit_handler on_remove = NULL,
                             bool is_saved = true) {
    Parameter _param = P_LIST<Subtype>(offset,
                                       name,
                                       list,
                                       length,
                                       length_min,
                                       length_max,
                                       description,
                                       on_add,
                                       on_move,
                                       on_remove,
                                       is_saved);
    _param.is_global = true;
    return _param;
}

constexpr Parameter P_ACTION(const char* name,
                             value_change_handler on_run,
                             const char* description = NULL) {
    return PARAM(0, AVS_PARAM_ACTION, name, description, on_run, false);
}

struct Effect_Info {
    static constexpr AVS_Effect_Handle handle = 0;
    virtual uint32_t get_handle() const = 0;
    virtual const char* get_group() const = 0;
    virtual const char* get_name() const = 0;
    virtual const char* get_help() const = 0;
    virtual int32_t get_legacy_id() const = 0;
    virtual const char* get_legacy_ape_id() const = 0;
    static constexpr uint32_t num_parameters = 0;
    static constexpr Parameter* parameters = nullptr;
    virtual uint32_t get_num_parameters() const { return 0; }
    virtual const Parameter* get_parameters() const { return nullptr; }
    virtual const AVS_Parameter_Handle* get_parameters_for_api() const {
        return nullptr;
    }
    virtual bool can_have_child_components() const { return false; }
    virtual bool is_createable_by_user() const { return true; }
    const Parameter* get_parameter_from_handle(AVS_Parameter_Handle to_find) {
        return Effect_Info::_get_parameter_from_handle(
            this->get_num_parameters(), this->get_parameters(), to_find);
    }
    static const Parameter* _get_parameter_from_handle(uint32_t num_parameters,
                                                       const Parameter* parameters,
                                                       AVS_Parameter_Handle to_find) {
        for (uint32_t i = 0; i < num_parameters; i++) {
            if (parameters[i].handle == to_find) {
                return &parameters[i];
            }
            if (parameters[i].type == AVS_PARAM_LIST) {
                const Parameter* subtree_result =
                    Effect_Info::_get_parameter_from_handle(
                        parameters[i].num_child_parameters,
                        parameters[i].child_parameters,
                        to_find);
                if (subtree_result != nullptr) {
                    return subtree_result;
                }
            }
        }
        return nullptr;
    }
    /**
     * This is the heart of ugliness around parameter introspection. It makes use of
     * `sizeof` and `offsetof`, both recorded in each field's Parameter struct, to find
     * and return the data address for a specific parameter in the config struct.
     */
    static uint8_t* get_config_address(Effect_Config* config,
                                       const Parameter* parameter,
                                       uint32_t num_params,
                                       const Parameter* param_list,
                                       const std::vector<int64_t>& parameter_path,
                                       uint32_t cur_depth) {
        for (uint32_t i = 0; i < num_params; i++) {
            uint8_t* config_data = (uint8_t*)config;
            uint8_t* parameter_address = &config_data[param_list[i].offset];
            if (param_list[i].type == AVS_PARAM_LIST
                && cur_depth < parameter_path.size()) {
                auto child_config = param_list[i].list_item_addr(
                    parameter_address, parameter_path[cur_depth]);
                auto subtree_result =
                    Effect_Info::get_config_address(child_config,
                                                    parameter,
                                                    param_list[i].num_child_parameters,
                                                    param_list[i].child_parameters,
                                                    parameter_path,
                                                    cur_depth + 1);
                if (subtree_result != NULL) {
                    return subtree_result;
                }
            }
            if (parameter->handle == param_list[i].handle) {
                return parameter_address;
            }
        }
        return NULL;
    }

    /**
     * In the case of nested parameters, the child handles have to be returned as a
     * plain array in the API. But the handles are inside the Parameter's children
     * structs. So, upon first request, cache all child handles in a vector in the
     * global 'h_parameter_children' map, keyed by their parent parameter's handle.
     * Finally, return the plain C array from the vector.
     */
    const AVS_Parameter_Handle* get_parameter_children_for_api(
        const Parameter* parameter,
        bool reset = false) const {
        if (parameter->type != AVS_PARAM_LIST) {
            return NULL;
        }
        if (h_parameter_children.find(parameter->handle) == h_parameter_children.end()
            || reset) {
            h_parameter_children[parameter->handle].clear();
            for (uint32_t i = 0; i < parameter->num_child_parameters; i++) {
                h_parameter_children[parameter->handle].push_back(
                    parameter->child_parameters[i].handle);
            }
        }
        return h_parameter_children[parameter->handle].data();
    }

    void load_config(Effect_Config* config,
                     Effect_Config* global_config,
                     const json& config_json) const;

    json save_config(const Effect_Config* config,
                     const Effect_Config* global_config) const;
    static std::string load_string(const json& str);
    static json save_string(const std::string& str);
};

/**
 * Equality operators.
 */

bool operator==(const Effect_Info& a, const Effect_Info& b);
bool operator==(const Effect_Info* a, const Effect_Info& b);
bool operator==(const Effect_Info& a, const Effect_Info* b);
bool operator!=(const Effect_Info& a, const Effect_Info& b);
bool operator!=(const Effect_Info* a, const Effect_Info& b);
bool operator!=(const Effect_Info& a, const Effect_Info* b);

/**
 * Every struct inheriting from Effect_Info should add this macro to the bottom of the
 * effect's info-struct declaration. This macro defines all the accessor methods to the
 * static members an Effect_Info subclass should define.
 * We need these constructs because static members in the child class cannot be accessed
 * by automatically inherited virtual functions. So we need to explicitly override each
 * one in each child class.
 */
// Use this first one only for effects that have no parameters, i.e. only "enable".
// Use EFFECT_INFO_GETTERS for all other effects.
#define EFFECT_INFO_GETTERS_NO_PARAMETERS                             \
    static constexpr AVS_Effect_Handle handle = COMPTIME_HANDLE;      \
    virtual uint32_t get_handle() const { return this->handle; }      \
    virtual const char* get_group() const { return this->group; }     \
    virtual const char* get_name() const { return this->name; }       \
    virtual const char* get_help() const { return this->help; }       \
    virtual int32_t get_legacy_id() const { return this->legacy_id; } \
    virtual const char* get_legacy_ape_id() const { return this->legacy_ape_id; }

#define EFFECT_INFO_GETTERS                                                      \
    EFFECT_INFO_GETTERS_NO_PARAMETERS                                            \
    virtual uint32_t get_num_parameters() const { return this->num_parameters; } \
    virtual const Parameter* get_parameters() const { return this->parameters; } \
    virtual const AVS_Parameter_Handle* get_parameters_for_api() const {         \
        static Parameter_Handle_List<num_parameters> parameter_handles_for_api(  \
            parameters);                                                         \
        return parameter_handles_for_api.handles;                                \
    }

/**
 * Another glorious C++ trick: A constexpr-(a.k.a. compile-time-)array, initialized not
 * by a `{ ... }`-literal, but from data in another array. `get_parameters_for_api()`
 * used to contain a static `AVS_Parameter_Handle[]` array instead of this, which was
 * filled when calling the method. However, this loop ran on each call and additionally
 * some compilers are not happy about static arrays with constexpr but non-literal
 * length.
 *
 * This way the looping can happen at compile time and the array is stored in the static
 * Parameter_Handle_List-typed variable in `get_parameters_for_api()`
 */
template <int N>
struct Parameter_Handle_List {
    AVS_Parameter_Handle handles[N] = {};
    constexpr Parameter_Handle_List(const Parameter* parameters) {
        for (size_t i = 0; i < N; i++) {
            handles[i] = parameters[i].handle;
        }
    }
};

/**
 * This is needed by the `Configurable_Effect` template class, but it's here since it
 * fits the context better, and effect.h shouldn't be _too_ messy.
 *
 * Every parameter type needs a `get()`, `set()` and `zero()` method. By explicitly
 * specializing a template struct for this collection of methods, but only for each of
 * the allowed scalar parameter types, the correct value and return types for these
 * methods can be checked in `Configurable_Effect`'s `get()` and `set()` at compile
 * time.
 */
template <typename T>
struct parameter_dispatch;

template <>
struct parameter_dispatch<bool> {
    static bool get(const uint8_t* config_data) { return *(bool*)config_data; }
    static void set(const Parameter*, uint8_t* addr, bool value) {
        *(bool*)addr = value;
    }
    static bool zero() { return false; }
    static std::string trace(const Parameter*, bool value, uint8_t* config_data) {
        std::stringstream output;
        output << "set to " << std::boolalpha << value;
        auto actual_value = get(config_data);
        if (actual_value != value) {
            output << ", but corrected to " << std::boolalpha << value;
        }
        return output.str();
    }
};

template <>
struct parameter_dispatch<int64_t> {
    static int64_t get(const uint8_t* config_data) { return *((int64_t*)config_data); }
    static void set(const Parameter* parameter, uint8_t* addr, int64_t value) {
        auto _min = parameter->int_min;
        auto _max = parameter->int_max;
        if (_min != _max) {
            value = value < _min ? _min : value > _max ? _max : value;
        }
        *(int64_t*)addr = value;
    }
    static std::vector<int64_t>& get_array(const uint8_t* config_data) {
        return *(std::vector<int64_t>*)config_data;
    }
    static int64_t zero() { return 0; }
    static std::string trace(const Parameter* parameter,
                             int64_t value,
                             uint8_t* config_data) {
        std::stringstream output;
        const char* option = nullptr;
        if (parameter->type == AVS_PARAM_SELECT) {
            int64_t length = -1;
            auto options = parameter->get_options(&length);
            if (value >= 0 && value < length) {
                option = options[value];
            }
        }
        if (option) {
            output << "set to " << option;
        } else {
            output << "set to " << value;
        }
        auto actual_value = get(config_data);
        if (actual_value != value) {
            output << ", but corrected to ";
            if (parameter->type == AVS_PARAM_SELECT) {
                auto actual_option = parameter->get_options(nullptr)[actual_value];
                output << actual_option;
            } else {
                output << actual_value;
            }
        }
        return output.str();
    }
};

template <>
struct parameter_dispatch<double> {
    static double get(const uint8_t* config_data) { return *(double*)config_data; }
    static void set(const Parameter* parameter, uint8_t* addr, double value) {
        auto _min = parameter->float_min;
        auto _max = parameter->float_max;
        if (_min != _max) {
            value = value < _min ? _min : value > _max ? _max : value;
        }
        *(double*)addr = value;
    }
    static std::vector<double>& get_array(const uint8_t* config_data) {
        return *(std::vector<double>*)config_data;
    }
    static double zero() { return 0.0; }
    static std::string trace(const Parameter*, double value, uint8_t* config_data) {
        // create output stream with fixed representation and 3 decimal precision
        std::stringstream output;
        output.precision(3);
        output << "set to " << std::fixed << value;
        auto actual_value = get(config_data);
        if (actual_value != value) {
            output << ", but corrected to " << std::fixed << actual_value;
        }
        return output.str();
    }
};

template <>
struct parameter_dispatch<uint64_t> {
    static uint64_t get(const uint8_t* config_data) {
        return *((uint64_t*)config_data);
    }
    static void set(const Parameter*, uint8_t* addr, uint64_t value) {
        *(uint64_t*)addr = value;
    }
    static std::vector<uint64_t>& get_array(const uint8_t* config_data) {
        return *(std::vector<uint64_t>*)config_data;
    }
    static uint64_t zero() { return 0; }
    static std::string trace(const Parameter*, uint64_t value, uint8_t* config_data) {
        std::stringstream output;
        output << "set to 0x" << std::hex << std::setfill('0') << std::setw(8) << value;
        auto actual_value = get(config_data);
        if (actual_value != value) {
            output << ", but corrected to 0x" << std::hex << std::setfill('0')
                   << std::setw(8) << actual_value;
        }
        return output.str();
    }
};

template <>
struct parameter_dispatch<const char*> {
    static const char* get(const uint8_t* config_data) {
        return ((std::string*)config_data)->c_str();
    }
    static void set(const Parameter* parameter, uint8_t* addr, const char* value) {
        if (parameter->type == AVS_PARAM_RESOURCE) {
            bool value_is_in_options = false;
            int64_t options_length = -1;
            const char* const* options = parameter->get_options(&options_length);
            for (int64_t i = 0; i < options_length; ++i) {
                // Yes, compare pointers. If the string is directly from the options
                // list this is a quick check (since the strings are const).
                if (value == options[i]) {
                    value_is_in_options = true;
                    break;
                }
            }
            if (!value_is_in_options) {
                // If not, we have to try the proper way.
                std::string str_value = value;
                for (int64_t i = 0; i < options_length; ++i) {
                    if (str_value == options[i]) {
                        value_is_in_options = true;
                        break;
                    }
                }
            }
            if (!value_is_in_options) {
                return;
            }
        }
        *(std::string*)addr = value;
    }

    static const char* zero() { return ""; }
    static std::string trace(const Parameter*,
                             const char* value,
                             uint8_t* config_data) {
        std::stringstream output;
        const size_t max_len = 20;
        std::string str_value(value);
        if (str_value.size() > max_len) {
            output << "set to " << str_value.substr(0, max_len - 3) << "...";
        } else {
            output << "set to " << value;
        }
        auto actual_value = (std::string*)config_data;
        if (*actual_value != value) {
            output << ", but corrected to ";
            if (actual_value->size() > max_len) {
                output << actual_value->substr(0, max_len - 3) << "...";
            } else {
                output << actual_value;
            }
        }
        return output.str();
    }
};
