#include "avs_editor.h"

#include "avs.h"
#include "avs_internal.h"
#include "effect.h"
#include "effect_info.h"
#include "effect_library.h"
#include "handles.h"
#include "instance.h"

#include <stdio.h>
#include <string>
#include <vector>

#ifdef __linux__
#define AVS_EDITOR_API __attribute__((visibility("default")))
#else
#define AVS_EDITOR_API
#endif

Effect_Info* get_effect_from_handle(AVS_Effect_Handle effect) {
    auto effect_search = g_effect_lib.find(effect);
    if (effect_search != g_effect_lib.end()) {
        return effect_search->second;
    }
    return NULL;
}

static bool resolve_handles(AVS_Handle avs,
                            AVS_Effect_Handle effect = 0,
                            AVS_Component_Handle component = 0,
                            AVS_Parameter_Handle parameter = 0,
                            AVS_Instance** instance_out = NULL,
                            Effect_Info** effect_out = NULL,
                            Effect** component_out = NULL,
                            const Parameter** parameter_out = NULL) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == NULL) {
        // error string already set in `get_instance_from_handle()`.
        return false;
    }
    if (instance_out != NULL) {
        *instance_out = instance;
    }
    if (effect_out != NULL) {
        *effect_out = get_effect_from_handle(effect);
        if (*effect_out == NULL) {
            instance->error = "Cannot find effect in effect library";
            return false;
        }
    }
    if (component_out != NULL) {
        *component_out = instance->get_component_from_handle(component);
        if (*component_out == NULL) {
            instance->error = "Cannot find component in preset";
            return false;
        }
    }
    if (parameter_out != NULL) {
        if (effect_out != NULL && *effect_out != NULL) {
            *parameter_out = (*effect_out)->get_parameter_from_handle(parameter);
        } else if (component_out != NULL && *component_out != NULL) {
            *parameter_out =
                (*component_out)->get_info()->get_parameter_from_handle(parameter);
        } else {
            instance->error =
                "Internal error: Wrong call to \"resolve_handles()\":"
                " when resolving parameter handle, effect and/or component handle"
                " required";
            return false;
        }
        if (*parameter_out == NULL) {
            instance->error = "Cannot find parameter in effect";
            return false;
        }
    }
    // This cleans out the instance error message in all editor API calls (all of which
    // use `resolve_handles()`).
    instance->error = "";
    return true;
}

template <typename T>
static inline void set_out(T* length_out, T value) {
    if (length_out != NULL) {
        *length_out = value;
    }
}

static inline std::vector<int64_t> make_parameter_tree_path(uint32_t list_depth,
                                                            int64_t* list_indices) {
    return std::vector<int64_t>(list_indices, list_indices + list_depth);
}

AVS_EDITOR_API
const AVS_Effect_Handle* avs_effect_library(AVS_Handle avs, uint32_t* length_out) {
    (void)avs;  // The library is static but might be instance-specific in the future.
    set_out<uint32_t>(length_out, g_effect_lib_handles_for_api.size());
    return g_effect_lib_handles_for_api.data();
}

AVS_EDITOR_API
bool avs_effect_info(AVS_Handle avs,
                     AVS_Effect_Handle effect,
                     AVS_Effect_Info* info_out) {
    if (info_out == NULL) {
        return false;
    }
    Effect_Info* _effect;
    if (!resolve_handles(avs, effect, 0, 0, NULL, &_effect)) {
        info_out->group = "";
        info_out->name = "";
        info_out->help = "";
        info_out->parameters_length = 0;
        info_out->parameters = NULL;
        info_out->can_have_child_components = false;
        info_out->is_user_creatable = false;
        return false;
    }
    info_out->group = _effect->get_group();
    info_out->name = _effect->get_name();
    info_out->help = _effect->get_help();
    info_out->parameters_length = _effect->get_num_parameters();
    info_out->parameters = _effect->get_parameters_for_api();
    info_out->can_have_child_components = _effect->can_have_child_components();
    info_out->is_user_creatable = _effect->is_createable_by_user();
    return true;
}

AVS_EDITOR_API
AVS_Effect_Handle avs_component_effect(AVS_Handle avs, AVS_Component_Handle component) {
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, NULL, NULL, &_component)) {
        return 0;
    }
    return _component->get_info()->get_handle();
}

AVS_EDITOR_API
AVS_Component_Handle avs_component_root(AVS_Handle avs) {
    AVS_Instance* instance = get_instance_from_handle(avs);
    if (instance == NULL) {
        return 0;
    }
    return instance->root.handle;
}

AVS_EDITOR_API
bool avs_component_can_have_child_components(AVS_Handle avs,
                                             AVS_Component_Handle component) {
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, NULL, NULL, &_component)) {
        return false;
    }
    return _component->can_have_child_components();
}

AVS_EDITOR_API
const AVS_Component_Handle* avs_component_children(AVS_Handle avs,
                                                   AVS_Component_Handle component,
                                                   uint32_t* length_out) {
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, NULL, NULL, &_component)) {
        set_out<uint32_t>(length_out, 0);
        return NULL;
    }
    set_out<uint32_t>(length_out, _component->children.size());
    return _component->get_child_handles_for_api();
}

AVS_EDITOR_API
AVS_Component_Handle avs_component_create(AVS_Handle avs,
                                          AVS_Effect_Handle effect,
                                          AVS_Component_Handle relative_to,
                                          AVS_Component_Position direction) {
    AVS_Instance* instance;
    Effect_Info* _effect;
    if (!resolve_handles(avs, effect, 0, 0, &instance, &_effect)) {
        return 0;
    }
    if (effect == Root_Info::handle) {
        instance->error = "Cannot create a root component";
        return 0;
    }

    Effect* component = component_factory(_effect, instance);
    if (component == NULL) {
        instance->error = "Failed to find internal component class";
        return 0;
    }
    Effect* relative_to_tree = &instance->root;
    Effect::Insert_Direction insert_direction = Effect::INSERT_AFTER;
    if (relative_to == 0) {
        insert_direction = Effect::INSERT_CHILD;
    } else {
        relative_to_tree = instance->get_component_from_handle(relative_to);
        switch (direction) {
            case AVS_COMPONENT_POSITION_BEFORE: {
                if (relative_to_tree == &instance->root) {
                    instance->error =
                        "Invalid direction 'BEFORE', cannot place before root"
                        " component";
                    delete component;
                    return 0;
                }
                insert_direction = Effect::INSERT_BEFORE;
                break;
            }
            case AVS_COMPONENT_POSITION_DONTCARE:
                if (relative_to_tree == &instance->root) {
                    insert_direction = Effect::INSERT_CHILD;
                    break;
                }
                [[fallthrough]];
            case AVS_COMPONENT_POSITION_AFTER: {
                if (relative_to_tree == &instance->root) {
                    instance->error =
                        "Invalid direction 'AFTER', cannot place after root component";
                    delete component;
                    return 0;
                }
                insert_direction = Effect::INSERT_AFTER;
                break;
            }
            case AVS_COMPONENT_POSITION_CHILD: {
                if (!relative_to_tree->can_have_child_components()) {
                    instance->error =
                        "Invalid direction 'CHILD', selected effect cannot have"
                        " children";
                    delete component;
                    return 0;
                }
                insert_direction = Effect::INSERT_CHILD;
                break;
            }
        }
    }
    if (instance->root.insert(component, relative_to_tree, insert_direction) == NULL) {
        instance->error = "Insertion of new component failed";
        delete component;
        return 0;
    }
    return component->handle;
}

AVS_EDITOR_API
bool avs_component_move(AVS_Handle avs,
                        AVS_Component_Handle component,
                        AVS_Component_Handle relative_to,
                        AVS_Component_Position direction) {
    AVS_Instance* instance;
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, &instance, NULL, &_component)) {
        return false;
    }
    Effect* _relative_to = instance->get_component_from_handle(relative_to);
    if (_relative_to == NULL) {
        instance->error = "Cannot find target component in preset";
        return false;
    }
    Effect::Insert_Direction _direction = Effect::INSERT_AFTER;
    switch (direction) {
        case AVS_COMPONENT_POSITION_BEFORE: _direction = Effect::INSERT_BEFORE; break;
        case AVS_COMPONENT_POSITION_DONTCARE:
        case AVS_COMPONENT_POSITION_AFTER: _direction = Effect::INSERT_AFTER; break;
        case AVS_COMPONENT_POSITION_CHILD: _direction = Effect::INSERT_CHILD; break;
    }
    Effect* result = instance->root.move(_component, _relative_to, _direction);
    if (result == NULL) {
        instance->error = "Move failed";
        return false;
    }
    return true;
}

AVS_EDITOR_API
AVS_Component_Handle avs_component_duplicate(AVS_Handle avs,
                                             AVS_Component_Handle component) {
    AVS_Instance* instance;
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, &instance, NULL, &_component)) {
        return 0;
    }
    if (_component == &instance->root) {
        instance->error = "Cannot duplicate root component";
        return 0;
    }
    Effect* duplicate = instance->root.duplicate(_component);
    if (duplicate == NULL) {
        instance->error = "Cannot copy component";
        return 0;
    }
    return duplicate->handle;
}

AVS_EDITOR_API
bool avs_component_delete(AVS_Handle avs, AVS_Component_Handle component) {
    AVS_Instance* instance;
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, &instance, NULL, &_component)) {
        return false;
    }
    if (component == instance->root.handle) {
        instance->clear();
        return true;
    }
    instance->root.remove(_component);
    return true;
}

AVS_EDITOR_API
bool avs_component_properties_get(AVS_Handle avs,
                                  AVS_Component_Handle component,
                                  AVS_Component_Properties* properties_out) {
    AVS_Instance* instance;
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, &instance, NULL, &_component)) {
        return false;
    }
    if (properties_out == NULL) {
        instance->error = "Output component properties is NULL";
        return false;
    }
    properties_out->enabled = _component->enabled;
    properties_out->comment = _component->comment.c_str();
    return true;
}
AVS_EDITOR_API
bool avs_component_properties_set(AVS_Handle avs,
                                  AVS_Component_Handle component,
                                  AVS_Component_Properties properties) {
    AVS_Instance* instance;
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, &instance, NULL, &_component)) {
        return false;
    }
    _component->set_enabled(properties.enabled);
    _component->comment = properties.comment;
    return true;
}

AVS_EDITOR_API
bool avs_parameter_info(AVS_Handle avs,
                        AVS_Effect_Handle effect,
                        AVS_Parameter_Handle parameter,
                        AVS_Parameter_Info* info_out) {
    if (info_out == NULL) {
        return false;
    }
    AVS_Instance* instance;
    Effect_Info* _effect;
    const Parameter* _parameter;
    if (!resolve_handles(
            avs, effect, 0, parameter, &instance, &_effect, NULL, &_parameter)) {
        info_out->type = AVS_PARAM_INVALID;
        info_out->name = "";
        info_out->description = "";
        info_out->is_global = false;
        info_out->int_min = 0;
        info_out->int_max = 0;
        info_out->float_min = 0.0;
        info_out->float_max = 0.0;
        info_out->options_length = 0;
        info_out->options = NULL;
        info_out->children_length = 0;
        info_out->children_length_min = 0;
        info_out->children_length_max = 0;
        info_out->children = NULL;
        return false;
    }
    info_out->type = _parameter->type;
    info_out->name = _parameter->name;
    info_out->description = _parameter->description;
    info_out->is_global = _parameter->is_global;
    info_out->int_min = _parameter->int_min;
    info_out->int_max = _parameter->int_max;
    info_out->float_min = _parameter->float_min;
    info_out->float_max = _parameter->float_max;
    if (_parameter->get_options != NULL) {
        info_out->options = _parameter->get_options(&(info_out->options_length));
    } else {
        info_out->options_length = 0;
        info_out->options = NULL;
    }
    info_out->children_length = _parameter->num_child_parameters;
    info_out->children_length_min = _parameter->num_child_parameters_min;
    info_out->children_length_max = _parameter->num_child_parameters_max;
    info_out->children = _effect->get_parameter_children_for_api(_parameter);
    return true;
}

AVS_EDITOR_API
bool avs_parameter_get_bool(AVS_Handle avs,
                            AVS_Component_Handle component,
                            AVS_Parameter_Handle parameter,
                            uint32_t list_depth,
                            int64_t* list_indices) {
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, NULL, NULL, &_component)) {
        return false;
    }
    auto parameter_path = make_parameter_tree_path(list_depth, list_indices);
    return _component->get_bool(parameter, parameter_path);
}
AVS_EDITOR_API
int64_t avs_parameter_get_int(AVS_Handle avs,
                              AVS_Component_Handle component,
                              AVS_Parameter_Handle parameter,
                              uint32_t list_depth,
                              int64_t* list_indices) {
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, NULL, NULL, &_component)) {
        return 0;
    }
    auto parameter_path = make_parameter_tree_path(list_depth, list_indices);
    return _component->get_int(parameter, parameter_path);
}
AVS_EDITOR_API
double avs_parameter_get_float(AVS_Handle avs,
                               AVS_Component_Handle component,
                               AVS_Parameter_Handle parameter,
                               uint32_t list_depth,
                               int64_t* list_indices) {
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, NULL, NULL, &_component)) {
        return 0.0;
    }
    auto parameter_path = make_parameter_tree_path(list_depth, list_indices);
    return _component->get_float(parameter, parameter_path);
}
AVS_EDITOR_API
uint64_t avs_parameter_get_color(AVS_Handle avs,
                                 AVS_Component_Handle component,
                                 AVS_Parameter_Handle parameter,
                                 uint32_t list_depth,
                                 int64_t* list_indices) {
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, NULL, NULL, &_component)) {
        return 0;
    }
    auto parameter_path = make_parameter_tree_path(list_depth, list_indices);
    return _component->get_color(parameter, parameter_path);
}
AVS_EDITOR_API
const char* avs_parameter_get_string(AVS_Handle avs,
                                     AVS_Component_Handle component,
                                     AVS_Parameter_Handle parameter,
                                     uint32_t list_depth,
                                     int64_t* list_indices) {
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, NULL, NULL, &_component)) {
        return "";
    }
    auto parameter_path = make_parameter_tree_path(list_depth, list_indices);
    return _component->get_string(parameter, parameter_path);
}

AVS_EDITOR_API
bool avs_parameter_set_bool(AVS_Handle avs,
                            AVS_Component_Handle component,
                            AVS_Parameter_Handle parameter,
                            bool value,
                            uint32_t list_depth,
                            int64_t* list_indices) {
    AVS_Instance* instance;
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, &instance, NULL, &_component)) {
        return false;
    }
    auto parameter_path = make_parameter_tree_path(list_depth, list_indices);
    return _component->set_bool(parameter, value, parameter_path);
}
AVS_EDITOR_API
bool avs_parameter_set_int(AVS_Handle avs,
                           AVS_Component_Handle component,
                           AVS_Parameter_Handle parameter,
                           int64_t value,
                           uint32_t list_depth,
                           int64_t* list_indices) {
    AVS_Instance* instance;
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, &instance, NULL, &_component)) {
        return false;
    }
    auto parameter_path = make_parameter_tree_path(list_depth, list_indices);
    return _component->set_int(parameter, value, parameter_path);
}
AVS_EDITOR_API
bool avs_parameter_set_float(AVS_Handle avs,
                             AVS_Component_Handle component,
                             AVS_Parameter_Handle parameter,
                             double value,
                             uint32_t list_depth,
                             int64_t* list_indices) {
    AVS_Instance* instance;
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, &instance, NULL, &_component)) {
        return false;
    }
    auto parameter_path = make_parameter_tree_path(list_depth, list_indices);
    return _component->set_float(parameter, value, parameter_path);
}
AVS_EDITOR_API
bool avs_parameter_set_color(AVS_Handle avs,
                             AVS_Component_Handle component,
                             AVS_Parameter_Handle parameter,
                             uint64_t value,
                             uint32_t list_depth,
                             int64_t* list_indices) {
    AVS_Instance* instance;
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, &instance, NULL, &_component)) {
        return false;
    }
    auto parameter_path = make_parameter_tree_path(list_depth, list_indices);
    return _component->set_color(parameter, value, parameter_path);
}
AVS_EDITOR_API
bool avs_parameter_set_string(AVS_Handle avs,
                              AVS_Component_Handle component,
                              AVS_Parameter_Handle parameter,
                              const char* value,
                              uint32_t list_depth,
                              int64_t* list_indices) {
    AVS_Instance* instance;
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, &instance, NULL, &_component)) {
        return false;
    }
    auto parameter_path = make_parameter_tree_path(list_depth, list_indices);
    return _component->set_string(parameter, value, parameter_path);
}

AVS_EDITOR_API
const int64_t* avs_parameter_get_int_array(AVS_Handle avs,
                                           AVS_Component_Handle component,
                                           AVS_Parameter_Handle parameter,
                                           uint64_t* length_out,
                                           uint32_t list_depth,
                                           int64_t* list_indices) {
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, NULL, NULL, &_component)) {
        *length_out = 0;
        return NULL;
    }
    auto parameter_path = make_parameter_tree_path(list_depth, list_indices);
    auto array = _component->get_int_array(parameter, parameter_path);
    *length_out = array.size();
    return array.data();
}
AVS_EDITOR_API
const double* avs_parameter_get_float_array(AVS_Handle avs,
                                            AVS_Component_Handle component,
                                            AVS_Parameter_Handle parameter,
                                            uint64_t* length_out,
                                            uint32_t list_depth,
                                            int64_t* list_indices) {
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, NULL, NULL, &_component)) {
        *length_out = 0;
        return NULL;
    }
    auto parameter_path = make_parameter_tree_path(list_depth, list_indices);
    auto array = _component->get_float_array(parameter, parameter_path);
    *length_out = array.size();
    return array.data();
}
AVS_EDITOR_API
const uint64_t* avs_parameter_get_color_array(AVS_Handle avs,
                                              AVS_Component_Handle component,
                                              AVS_Parameter_Handle parameter,
                                              uint64_t* length_out,
                                              uint32_t list_depth,
                                              int64_t* list_indices) {
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, NULL, NULL, &_component)) {
        *length_out = 0;
        return NULL;
    }
    auto parameter_path = make_parameter_tree_path(list_depth, list_indices);
    auto array = _component->get_color_array(parameter, parameter_path);
    *length_out = array.size();
    return array.data();
}

AVS_EDITOR_API
bool avs_parameter_run_action(AVS_Handle avs,
                              AVS_Component_Handle component,
                              AVS_Parameter_Handle parameter,
                              uint32_t list_depth,
                              int64_t* list_indices) {
    AVS_Instance* instance;
    Effect* _component;
    if (!resolve_handles(avs, 0, component, 0, &instance, NULL, &_component)) {
        return false;
    }
    return _component->run_action(parameter,
                                  make_parameter_tree_path(list_depth, list_indices));
}

AVS_EDITOR_API
int64_t avs_parameter_list_length(AVS_Handle avs,
                                  AVS_Component_Handle component,
                                  AVS_Parameter_Handle parameter,
                                  uint32_t list_depth,
                                  int64_t* list_indices) {
    AVS_Instance* instance;
    Effect* _component;
    const Parameter* _parameter;
    if (!resolve_handles(
            avs, 0, component, parameter, &instance, NULL, &_component, &_parameter)) {
        return -1;
    }
    if (_parameter->type != AVS_PARAM_LIST) {
        instance->error = "Parameter is not of list type";
        return -1;
    }
    size_t length = _component->parameter_list_length(
        parameter, make_parameter_tree_path(list_depth, list_indices));
#if SIZE_MAX > INT64_MAX
    if (length > INT64_MAX) {
        instance->error = "List length clamped";
        return INT64_MAX;
    }
#endif
    return (int64_t)length;
}

AVS_EDITOR_API
bool avs_parameter_list_element_add(AVS_Handle avs,
                                    AVS_Component_Handle component,
                                    AVS_Parameter_Handle parameter,
                                    int64_t before,
                                    uint32_t values_length,
                                    const AVS_Parameter_Value* values,
                                    uint32_t list_depth,
                                    int64_t* list_indices) {
    AVS_Instance* instance;
    Effect* _component;
    const Parameter* _parameter;
    if (!resolve_handles(
            avs, 0, component, parameter, &instance, NULL, &_component, &_parameter)) {
        return false;
    }
    if (_parameter->type != AVS_PARAM_LIST) {
        instance->error = "Parameter is not of list type";
        return false;
    }
    return _component->parameter_list_entry_add(
        parameter,
        before,
        std::vector<AVS_Parameter_Value>(values, values + values_length),
        make_parameter_tree_path(list_depth, list_indices));
}
AVS_EDITOR_API
bool avs_parameter_list_element_move(AVS_Handle avs,
                                     AVS_Component_Handle component,
                                     AVS_Parameter_Handle parameter,
                                     int64_t from_index,
                                     int64_t to_index,
                                     uint32_t list_depth,
                                     int64_t* list_indices) {
    AVS_Instance* instance;
    Effect* _component;
    const Parameter* _parameter;
    if (!resolve_handles(
            avs, 0, component, parameter, &instance, NULL, &_component, &_parameter)) {
        return false;
    }
    if (_parameter->type != AVS_PARAM_LIST) {
        instance->error = "Parameter is not of list type";
        return -1;
    }
    return _component->parameter_list_entry_move(
        parameter,
        from_index,
        to_index,
        make_parameter_tree_path(list_depth, list_indices));
}
AVS_EDITOR_API
bool avs_parameter_list_element_remove(AVS_Handle avs,
                                       AVS_Component_Handle component,
                                       AVS_Parameter_Handle parameter,
                                       int64_t remove_index,
                                       uint32_t list_depth,
                                       int64_t* list_indices) {
    AVS_Instance* instance;
    Effect* _component;
    const Parameter* _parameter;
    if (!resolve_handles(
            avs, 0, component, parameter, &instance, NULL, &_component, &_parameter)) {
        return false;
    }
    if (_parameter->type != AVS_PARAM_LIST) {
        instance->error = "Parameter is not of list type";
        return -1;
    }
    return _component->parameter_list_entry_remove(
        parameter, remove_index, make_parameter_tree_path(list_depth, list_indices));
}
