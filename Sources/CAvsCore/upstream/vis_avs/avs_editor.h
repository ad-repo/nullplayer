/**
 * This is the (much more involved) editor API for AVS. For the basic player API see
 * "avs.h".
 *
 * This file provides data types and functions to edit the current preset of an AVS
 * instance at runtime.
 *
 * But first, some terminology:
 *
 *   "Effect":
 *     A type of visual effect that can be used in a preset. This is kind of like a type
 *     in programming. A "Component" is of an "Effect" type. AVS has a list of available
 *     Effects, that you can query with `avs_effect_library()`. Effects are described by
 *     their name, group and parameters.
 *
 *   "Component":
 *     An instance of an "Effect". Every Component has a pointer to its Effect struct.
 *     You can query it for information about the names and types of the available
 *     parameters, and use the `avs_parameter_get_*` and `-set_*` methods to read and
 *     write the Component's parameter values.
 *
 *   "Preset":
 *     A tree of "Components".
 */
#pragma once

#include "avs.h"

#ifdef __cplusplus
extern "C" {
#endif

/** A reference to a unique component within a preset. 0 is the invalid handle. */
typedef uint32_t AVS_Component_Handle;
/** A reference to an effect type in AVS. 0 is the invalid handle. */
typedef uint32_t AVS_Effect_Handle;
/** A reference to a parameter of an effect. 0 is the invalid handle. */
typedef uint32_t AVS_Parameter_Handle;

/**
 * Possible types of a parameter's value.
 */
typedef enum {
    /**
     * Uninitialized or otherwise invalid parameters may have this type. Indicates an
     * error.
     */
    AVS_PARAM_INVALID = -1,

    /**
     * A list of several sets of child parameters. The size/index of the list is a
     * signed(!) 64-bit integer.
     */
    AVS_PARAM_LIST = 0,
    /**
     * An effect-defined function to run. Has no value and cannot be read from. Use
     * `avs_parameter_run_action()` to trigger the action.
     */
    AVS_PARAM_ACTION = 1,

    /** =0 false, ≠0 true. */
    AVS_PARAM_BOOL = 2,
    /** Signed 64-bit integer. */
    AVS_PARAM_INT = 3,
    /** 64-bit float (a.k.a. "double"). */
    AVS_PARAM_FLOAT = 4,
    /** 64-bit RGBA16 unsigned integer. */
    AVS_PARAM_COLOR = 5,
    /** A const zero-terminated C string. */
    AVS_PARAM_STRING = 6,
    /**
     * A value from a list of possible options. Available strings can be listed through
     * the `options` list of the `AVS_Parameter_Info` struct.
     * The value of a SELECT parameter is a signed 64-bit integer index into the
     * `options` list of strings. `AVS_PARAM_SELECT` option lists tends to be static
     * shorter lists, like blend modes. Expect and handle out-of-range indices, esp. -1
     * for "no selection".
     * When getting or setting a parameter of this type use the `_int()` getter/setter
     * flavors.
     */
    AVS_PARAM_SELECT = 7,
    /**
     * Similar to `AVS_PARAM_SELECT`, but string-valued. `AVS_PARAM_RESOURCE` values
     * refer to any kind of outside resource (e.g. files or fonts) which may change,
     * even at runtime.
     * It's possible the value string is _not_ in the list of available options (e.g. a
     * missing resource file) or is empty ("no selection") and you should expect and
     * handle these cases, for example by showing a missing entry in a different
     * style.
     * When getting or setting a parameter of this type use the `_string()` getter/
     * setter flavors.
     */
    AVS_PARAM_RESOURCE = 8,
    /**
     * A read-only array of integers. The length is provided when calling
     * `avs_parameter_get_int_array()`.
     */
    AVS_PARAM_INT_ARRAY = 100,
    /**
     * A read-only array of floats. The length is provided when calling
     * `avs_parameter_get_float_array()`.
     */
    AVS_PARAM_FLOAT_ARRAY = 101,
    /** A read-only array of colors. The length is provided when calling
     * `avs_parameter_get_color_array()`.
     */
    AVS_PARAM_COLOR_ARRAY = 102,
} AVS_Parameter_Type;

/**
 * The position to choose when creating/moving components. Always in relation to a
 * reference component, e.g. the currently selected one.
 */
typedef enum {
    /**
     * The position in relation to the reference component is not important. Use this
     * to document no-preference in _your_ code. Currently, this has the same behavior
     * as `AVS_COMPONENT_POSITION_AFTER`, but obviously don't depend on this.
     */
    AVS_COMPONENT_POSITION_DONTCARE = -1,
    /** A component is created/moved before the reference component. */
    AVS_COMPONENT_POSITION_BEFORE = 0,
    /** A component is created/moved after the reference component. */
    AVS_COMPONENT_POSITION_AFTER = 1,
    /**
     * A component is created/moved inside the reference component. This is only valid
     * when the reference can have children. If it can, the new/moved component will be
     * placed at the end of the list of children.
     */
    AVS_COMPONENT_POSITION_CHILD = 2,
} AVS_Component_Position;

/**
 * The built-in properties of every component.
 */
typedef struct {
    /** The effect is enabled for rendering or other processing. */
    bool enabled;
    /** A comment related to the component. May be NULL or empty to unset it. */
    const char* comment;
} AVS_Component_Properties;

/**
 * Metadata for an effect.
 *
 * Populate this struct by calling `avs_effect_info()`.
 */
typedef struct {
    /**
     * `group` is one of "Render", "Trans" or "Misc", rarely something else. No group,
     * i.e. "", is possible.
     */
    const char* group;
    /** `name` is never empty. */
    const char* name;
    /** The help text can be empty, short or several paragraphs long. */
    const char* help;
    /**
     * The number of (top-level) parameters for the effect. May be 0.
     * Note that due to nested parameter lists, the total number of parameters may be
     * greater than `parameters_length`. If you do need the total number (you usually
     * don't), descend into `AVS_PARAM_LIST`-type parameters recursively.
     */
    uint32_t parameters_length;
    /**
     * The list of parameters for the effect. If `parameters_length` is 0 `parameters`
     * will be NULL.
     */
    const AVS_Parameter_Handle* parameters;
    /**
     * Is `true` if the components created from this effect can have child components.
     * Most effects cannot have children, but a few do, such as Root and Effect List.
     */
    bool can_have_child_components;
    /**
     * Is `true` if the effect can be added to a preset by the user. A few effects are
     * only ever created by AVS internally:
     * - "Root", the root of the preset tree,
     * - "Unknown Effect", when a preset is loaded with an effect not known to AVS,
     * - "Transition", for animating the switch to another preset.
     * This flag is helpful if you want to filter for effects that users can actually
     * add to a preset.
     */
    bool is_user_creatable;
} AVS_Effect_Info;

/**
 * Metadata for one of an effect's parameters.
 *
 * Populate this struct by calling `avs_parameter_info()`.
 */
typedef struct {
    /**
     * The value type of the parameter. If this is AVS_PARAM_INVALID, the rest of the
     * fields will have zero values.
     */
    AVS_Parameter_Type type;
    /** `name` is never empty. */
    const char* name;
    /** `description` may be empty. */
    const char* description;
    /**
     * If `is_global` is `true` then this parameter is shared across all components of
     * this effect within a preset. Changing the value of this parameter will change it
     * for all components.
     */
    bool is_global;
    /** The minimum value if `type` is `AVS_PARAM_INT`, 0 otherwise. */
    int64_t int_min;
    /** The maximum value if `type` is `AVS_PARAM_INT`, 0 otherwise. */
    int64_t int_max;
    /** The minimum value if `type` is `AVS_PARAM_FLOAT`, 0.0 otherwise. */
    double float_min;
    /** The maximum value if `type` is `AVS_PARAM_FLOAT`, 0.0 otherwise. */
    double float_max;
    /** The number of options if `type` is `AVS_PARAM_SELECT`. 0 otherwise. */
    int64_t options_length;
    /** The list of option labels if `type` is `AVS_PARAM_SELECT`. `NULL` otherwise. */
    const char* const* options;
    /** The number of child parameters if `type` is `AVS_PARAM_LIST`. 0 otherwise. */
    uint32_t children_length;
    /**
     * The minimum number of child parameters if `type` is `AVS_PARAM_LIST`.
     * 0 otherwise.
     */
    uint32_t children_length_min;
    /**
     * The maximum number of child parameters if `type` is `AVS_PARAM_LIST`.
     * 0 otherwise.
     */
    uint32_t children_length_max;
    /** The list of child parameters if `type` is `AVS_PARAM_LIST`. 0 otherwise. */
    const AVS_Parameter_Handle* children;
} AVS_Parameter_Info;

/**
 * Query available effects in AVS.
 *
 * Note that effects' names are globally unique, not just within their group. Groups
 * exist purely as categories for better overview.
 */
const AVS_Effect_Handle* avs_effect_library(AVS_Handle avs, uint32_t* length_out);

/**
 * Query information about a specific effect.
 *
 * Returns `false` if any of the handles cannot be found or another error occurred.
 */
bool avs_effect_info(AVS_Handle avs,
                     AVS_Effect_Handle effect,
                     AVS_Effect_Info* info_out);

/**
 * Retrieve the Effect information handle for a specific component.
 *
 * Returns 0 on error.
 */
AVS_Effect_Handle avs_component_effect(AVS_Handle avs, AVS_Component_Handle component);

/**
 * Get the root of the current preset's component tree.
 *
 * Returns 0 on error.
 */
AVS_Component_Handle avs_component_root(AVS_Handle avs);

/**
 * To traverse the current preset's component tree, use the following methods to
 * retrieve a component's list of children.
 *
 * Each time a component is added to, moved in or removed from the parent `component`,
 * any previously returned array address for that specific `component` is invalidated,
 * and only regenerated when calling this method. The simple rule to remember is: Always
 * call this function before iterating over children of a component.
 *
 * `avs_component_can_have_child_components()` helps if you quickly want to distinguish
 * between "leaf"- and "tree"-type components. Note: The overwhelming majority of
 * effects/components cannot have child components.
 *
 * `avs_component_children()` will return 0 both on error and if the component has no
 * children.
 */
bool avs_component_can_have_child_components(AVS_Handle avs,
                                             AVS_Component_Handle component);
const AVS_Component_Handle* avs_component_children(AVS_Handle avs,
                                                   AVS_Component_Handle component,
                                                   uint32_t* length_out);

/**
 * Add a new component of the type given by `effect`. The component is added near an
 * existing `relative_to` component in the given `direction`. Note that you cannot
 * create a new component with the "root" effect type.
 *
 * The `direction` may be either `AVS_COMPONENT_POSITION_BEFORE`,
 * `AVS_COMPONENT_POSITION_AFTER` or `AVS_COMPONENT_POSITION_CHILD`. The child
 * direction is only valid if the `relative_to` component's effect type supports
 * children. It's intended use is as disambiguation when creating the first child of a
 * component, where `AFTER` could mean both actually after or inside. If `relative_to`
 * already has children, you should instead call this function with an existing child
 * within that component as `relative_to`. But in case you don't, the new component will
 * be created as the new last child.
 *
 * `relative_to` may be 0, in which case the component is created as the last child
 * of the preset root. The `direction` is ignored in this case, but you may explicitly
 * use `AVS_COMPONENT_POSITION_DONTCARE` to highlight this fact. Note that it is the
 * same as `AVS_COMPONENT_POSITION_AFTER`.
 *
 * Returns a handle to the new component. Returns 0 if the `effect` is invalid, doesn't
 * allow creation by users, `relative_to` is not 0 but doesn't exist, or `direction` is
 * invalid or another error occurred.
 */
AVS_Component_Handle avs_component_create(AVS_Handle avs,
                                          AVS_Effect_Handle effect,
                                          AVS_Component_Handle relative_to,
                                          AVS_Component_Position direction);

/**
 * Move an existing component from one place in the component tree to another.
 *
 * Returns `false` if the `component` or the `relative_to` cannot be found, the
 * `direction` is invalid (e.g. before/after the root element) or another error
 * occurred.
 */
bool avs_component_move(AVS_Handle avs,
                        AVS_Component_Handle component,
                        AVS_Component_Handle relative_to,
                        AVS_Component_Position direction);

/**
 * Duplicate the given `component` and return the new duplicate. The new component will
 * be placed after the original.
 *
 * Returns 0 if the operation fails for some reason.
 */
AVS_Component_Handle avs_component_duplicate(AVS_Handle avs,
                                             AVS_Component_Handle component);

/**
 * Remove the given component. If the root component is removed the preset will be
 * cleared and a new default root component (with a new handle!) will be added
 * automatically. There's always a root component.
 *
 * Returns `false` if any of the handles cannot be found or another error occurred.
 */
bool avs_component_delete(AVS_Handle avs, AVS_Component_Handle component);

/**
 * Use `avs_component_properties_get()` to query a component's built-in properties,
 * listed in `AVS_Component_Properties`.
 *
 * The return value is `true` on success, and `false` on error (e.g. the `component`
 * wasn't found). Use `avs_error_str()` to find out what went wrong.
 */
bool avs_component_properties_get(AVS_Handle avs,
                                  AVS_Component_Handle component,
                                  AVS_Component_Properties* properties_out);

/**
 * Use `avs_component_properties_set()` to change a component's built-in properties,
 * listed in `AVS_Component_Properties`.
 *
 * The return value is `true` if the state was set successfully, and `false` on error.
 * Use `avs_error_str()` to find out what went wrong.
 */
bool avs_component_properties_set(AVS_Handle avs,
                                  AVS_Component_Handle component,
                                  AVS_Component_Properties properties);

/**
 * Query information about an effect's parameters.
 *
 * Returns `false` if any of the handles cannot be found or another error occurred.
 * The fields of `info_out` will be filled with meaningful zero values. Lists will be
 * NULL pointers, but strings will be the empty string, not NULL.
 */
bool avs_parameter_info(AVS_Handle avs,
                        AVS_Effect_Handle effect,
                        AVS_Parameter_Handle parameter,
                        AVS_Parameter_Info* info_out);

/**
 * Use these methods to retrieve parameter values from components.
 *
 * If parameter lookup fails, a default zero value will be returned by all `get`
 * methods. It's `0` for all numerical types, `false` for booleans, and `""` for
 * strings.
 *
 * If the zero value was returned you should check `avs_error_str()`. It will return the
 * empty string `""` if the last call to a `get` method succeeded, or an error message
 * otherwise.
 */
bool avs_parameter_get_bool(AVS_Handle avs,
                            AVS_Component_Handle component,
                            AVS_Parameter_Handle parameter,
                            uint32_t list_depth,
                            int64_t* list_indices);
int64_t avs_parameter_get_int(AVS_Handle avs,
                              AVS_Component_Handle component,
                              AVS_Parameter_Handle parameter,
                              uint32_t list_depth,
                              int64_t* list_indices);
double avs_parameter_get_float(AVS_Handle avs,
                               AVS_Component_Handle component,
                               AVS_Parameter_Handle parameter,
                               uint32_t list_depth,
                               int64_t* list_indices);
uint64_t avs_parameter_get_color(AVS_Handle avs,
                                 AVS_Component_Handle component,
                                 AVS_Parameter_Handle parameter,
                                 uint32_t list_depth,
                                 int64_t* list_indices);
const char* avs_parameter_get_string(AVS_Handle avs,
                                     AVS_Component_Handle component,
                                     AVS_Parameter_Handle parameter,
                                     uint32_t list_depth,
                                     int64_t* list_indices);

/**
 * Use these methods to set new parameter values for components.
 *
 * The `set` methods all return `true` on success or `false` otherwise.
 *
 * Note: Parameters may internally have on-change handler functions registered for them.
 * Setting a value will invoke that function if present. Only a minority of parameters
 * make use of this. But consider that some parameters' setters might not always return
 * quite as instantaneously as most do.
 */
bool avs_parameter_set_bool(AVS_Handle avs,
                            AVS_Component_Handle component,
                            AVS_Parameter_Handle parameter,
                            bool value,
                            uint32_t list_depth,
                            int64_t* list_indices);
bool avs_parameter_set_int(AVS_Handle avs,
                           AVS_Component_Handle component,
                           AVS_Parameter_Handle parameter,
                           int64_t value,
                           uint32_t list_depth,
                           int64_t* list_indices);
bool avs_parameter_set_float(AVS_Handle avs,
                             AVS_Component_Handle component,
                             AVS_Parameter_Handle parameter,
                             double value,
                             uint32_t list_depth,
                             int64_t* list_indices);
bool avs_parameter_set_color(AVS_Handle avs,
                             AVS_Component_Handle component,
                             AVS_Parameter_Handle parameter,
                             uint64_t value,
                             uint32_t list_depth,
                             int64_t* list_indices);
bool avs_parameter_set_string(AVS_Handle avs,
                              AVS_Component_Handle component,
                              AVS_Parameter_Handle parameter,
                              const char* value,
                              uint32_t list_depth,
                              int64_t* list_indices);

/**
 * Array-type parameters are read-only. The length of the array is written to the
 * `length_out` argument.
 */
const int64_t* avs_parameter_get_int_array(AVS_Handle avs,
                                           AVS_Component_Handle component,
                                           AVS_Parameter_Handle parameter,
                                           uint64_t* length_out,
                                           uint32_t list_depth,
                                           int64_t* list_indices);
const double* avs_parameter_get_float_array(AVS_Handle avs,
                                            AVS_Component_Handle component,
                                            AVS_Parameter_Handle parameter,
                                            uint64_t* length_out,
                                            uint32_t list_depth,
                                            int64_t* list_indices);
const uint64_t* avs_parameter_get_color_array(AVS_Handle avs,
                                              AVS_Component_Handle component,
                                              AVS_Parameter_Handle parameter,
                                              uint64_t* length_out,
                                              uint32_t list_depth,
                                              int64_t* list_indices);

/**
 * Run the action associated with an AVS_PARAM_ACTION parameter.
 *
 * Returns `false` if the arguments are invalid. Does _not_ check for the success of the
 * action function.
 */
bool avs_parameter_run_action(AVS_Handle avs,
                              AVS_Component_Handle component,
                              AVS_Parameter_Handle parameter,
                              uint32_t list_depth,
                              int64_t* list_indices);

/**
 *   Parameter Lists
 *
 * Parameter lists are rare but they allow effects to have a variable-length list of
 * items with a set of multiple parameters. The `AVS_Effect_Info`- and
 * `AVS_Parameter_Info` API around this can be a bit complex. First let's start with
 * changing the value of a nested parameter.
 *
 *
 *   Accessing Nested Parameters
 *
 * Consider an AVS effect "Foo" with two parameters, one regular, "Awesome", the other a
 * list of the same set of sub-parameters, "Things". In JSON the component may look a
 * bit like this:
 *
 *     {
 *         "type" : "Foo",
 *         "config": {
 *             "Awesome": true,
 *             "Things": [
 *                 {
 *                     "Bar": true,
 *                     "Baz": 3.14
 *                 },
 *                 {
 *                     "Bar": false,
 *                     "Baz": -1.0
 *                 }
 *             ]
 *         }
 *     }
 *
 * Remember these are the specific values for this component _instance_. How do you know
 * that "Awesome" has a `bool` type, and "things" is a list, and "Baz" inside "things"
 * should be a floating-point number? This is where the `AVS_Effect_Info` data comes in.
 *
 * You know the `AVS_Effect_Info` for a specific effect from the list of available
 * effects given to you by `avs_effect_library()`. In that list you will find one
 * `AVS_Effect_Info` struct that has its `name` property set to "Foo". If you have a
 * specific component object, you can also directly get the corresponding
 * `AVS_Effect_Info` through `avs_component_effect()`. Its parameters and parameter
 * types are recorded within. So a (shortened) JSON representation of the
 * `AVS_Effect_Info` struct may look like below. Note that this is the _general_
 * parameter description for _all_ components that have type "Foo":
 *
 *     {
 *         "group": "Render",
 *         "name": "Foo",
 *         "parameters" [
 *             {
 *                 "name": "Awesome",
 *                 "type": "bool"
 *             },
 *             {
 *                 "name": "things",
 *                 "type": "list",
 *                 "parameters": [
 *                     {
 *                         "name": "bar",
 *                         "type": "bool"
 *                     },
 *                     {
 *                         "name": "Baz",
 *                         "type": "float"
 *                     }
 *                 ]
 *             }
 *         ]
 *     }
 *
 * Take a second to compare this JSON representation with the `AVS_Effect_Info` and
 * `AVS_Parameter_Info` structs at the beginning of this file to see how you may get at
 * the desired `AVS_Parameter_Info` reference which you will need to set the component's
 * parameter.
 *
 * For example: To set the second "Thing"'s "Baz" value of a "Foo" component `my_foo` to
 * some value you have to query for `my_foo`'s `AVS_Effect_Info` struct, then get the
 * `AVS_Parameter_Info` structs for "Thing", then its child "Baz". Then check the type
 * of "Things" > "Baz" and find it to be `AVS_PARAM_FLOAT`.
 * Together with an AVS instance referenced by the `AVS_Handle`, `avs`, and your your
 * freshly discovered `AVS_Component_Handle` `foo` and nested `AVS_Parameter_Info`
 * `baz`, you then call the setter for the correct type.
 *
 *     // Find a parameter handle and info by name, in either an effect
 *     // (parent_info==NULL) or a list parameter (effect_info==NULL).
 *     AVS_Parameter_Handle find_parameter(AVS_Handle avs,
 *                                         AVS_Effect_Handle effect,
 *                                         AVS_Effect_Info* effect_info,
 *                                         AVS_Parameter_Info* parent_info,
 *                                         const char* name,
 *                                         AVS_Parameter_Info* info_out) {
 *         AVS_Parameter_Handle parameter_out = 0;
 *         uint32_t parameters_length = 0;
 *         const AVS_Parameter_Handle* parameters = NULL;
 *         if (effect_info) {
 *             parameters_length = effect_info->parameters_length;
 *             parameters = effect_info->parameters;
 *         } else if (parent_info) {
 *             parameters_length = parent_info->children_length;
 *             parameters = parent_info->children;
 *         }
 *         for (int i = 0; i < parameters_length; ++i) {
 *             if (!avs_parameter_info(avs, effect, parameters[i], info_out)) {
 *                 printf("error getting parameter info: %s\n", avs_error_str(avs));
 *                 return false;
 *             }
 *             if (strncmp(info_out->name, name, 512) == 0) {
 *                 parameter_out = parameters[i];
 *                 break;
 *             }
 *         }
 *         return parameter_out;
 *     }
 *
 *     // Now the (a bit contrived) function to update the parameter to a fixed value:
 *     bool update_things_baz(AVS_Handle avs,
 *                            AVS_Component_Handle my_foo,
 *                            double value) {
 *         AVS_Effect_Handle foo = avs_component_effect(avs, my_foo);
 *         if (foo == 0) {
 *             printf("error getting effect for my_foo component\n");
 *             return false;
 *         }
 *         AVS_Effect_Info foo_info;
 *         if(avs_effect_info(avs, foo, &foo_info)) {
 *             printf("error getting effect info: %s\n", avs_error_str(avs));
 *             return false;
 *         }
 *         AVS_Parameter_Info things_info;
 *         AVS_Parameter_Handle things =
 *             find_parameter(avs, foo, &foo_info, NULL, "Things", &things_info);
 *         if (things == 0) {
 *             printf("error: parameter 'Things' not found\n");
 *             return false;
 *         }
 *         AVS_Parameter_Info baz_info;
 *         AVS_Parameter_Handle baz =
 *             find_parameter(avs, foo, NULL, &things_info, "Baz", &baz_info);
 *         if (baz == 0) {
 *             printf("error: nested parameter 'Baz' not found\n");
 *             return false;
 *         }
 *
 *         // "Baz" must be a floating point value!
 *         assert(baz_info.type == AVS_PARAM_FLOAT);
 *
 *         // A "path" of length 1 which selects the *second* element (index 1) from
 *         // "Things".
 *         uint32_t depth = 1;
 *         int64_t path[1] = {1};
 *
 *         // Finally set our new value! Note that the reference handle to "Things",
 *         // `things` is not needed! `baz` alone is sufficient.
 *         if (!avs_parameter_set_float(avs, foo, baz, value, depth, path)) {
 *             printf("error: setting value failed: %s\n", avs_error_str(avs));
 *         }
 *
 *         // Validate that this actually worked:
 *         double check = avs_parameter_get_float(avs, my_foo, baz, depth, path);
 *         assert(check == value);
 *
 *         return true;
 *     }
 *
 * In actual code you might do things slightly differently, such as caching the
 * `AVS_Effect_Info` struct for a component instead of querying it every time, and
 * dispatching the type of value to set based on the type of the parameter, etc.
 *
 *
 *   Manipulating a List of Parameters
 *
 * To add new elements to the list simply call `avs_parameter_list_element_add()`. You
 * have to first specify the usual suspects as above: AVS instance, component and
 * parameter handles. Next you need a reference index `before` which to place the new
 * one. If the reference index is negative, it will count from the back (i.e. -1 places
 * it before the last element). All positive indices ≥ the length of the list are
 * interpreted as "at the end", so simply use a huge index to append to the list.
 *
 * You can (but don't have to) add initial values for some or all of the child
 * parameters of the new list element. If a child parameter doesn't get an explicit
 * initial value it will get the default value specified in the effect. To add initial
 * values for a parameter create an `AVS_Parameter_Value` list.
 *
 * Note that all `list_depth` and `list_indices` arguments to the
 * `avs_parameter_list_*()` functions point to the _list_ parameter, not any of its
 * children. That means if the list is not itself inside another list then these two
 * arguments will always be `0` and `NULL` respectively.
 *
 *     bool add_with_two_initial_values(AVS_Handle avs,
 *                                      AVS_Component_Handle component,
 *                                      AVS_Parameter_Handle list_param,
 *                                      AVS_Parameter_Handle child_one,
 *                                      AVS_Parameter_Handle child_two) {
 *         uint32_t values_length = 2;
 *         AVS_Parameter_Value values[2];
 *         // Let's assume we _know_ that the type is AVS_PARAM_INT.
 *         values[0].parameter = child_one;
 *         values[0].value.i = 1000;
 *         // Let's also assume we know that the other one is an AVS_PARAM_COLOR.
 *         values[1].parameter = child_two;
 *         values[1].value.c = 0xffa300;  // A pleasant orange
 *
 *         return avs_parameter_list_element_add(
 *             avs, component, list_param, 0, values_length, values, 0, NULL);
 *     }
 *
 * The order of the values in the array doesn't matter. If there are duplicates, the
 * last one wins, but the on-change handler will be called for all of them!
 */

typedef union {
    bool b;
    int64_t i;
    double f;
    uint64_t c;
    const char* s;
} AVS_Value;

typedef struct {
    AVS_Parameter_Handle parameter;
    AVS_Value value;
} AVS_Parameter_Value;

int64_t avs_parameter_list_length(AVS_Handle avs,
                                  AVS_Component_Handle component,
                                  AVS_Parameter_Handle parameter,
                                  uint32_t list_depth,
                                  int64_t* list_indices);
bool avs_parameter_list_element_add(AVS_Handle avs,
                                    AVS_Component_Handle component,
                                    AVS_Parameter_Handle parameter,
                                    int64_t before,
                                    uint32_t values_length,
                                    const AVS_Parameter_Value* values,
                                    uint32_t list_depth,
                                    int64_t* list_indices);
bool avs_parameter_list_element_move(AVS_Handle avs,
                                     AVS_Component_Handle component,
                                     AVS_Parameter_Handle parameter,
                                     int64_t from_index,
                                     int64_t to_index,
                                     uint32_t list_depth,
                                     int64_t* list_indices);
bool avs_parameter_list_element_remove(AVS_Handle avs,
                                       AVS_Component_Handle component,
                                       AVS_Parameter_Handle parameter,
                                       int64_t remove_index,
                                       uint32_t list_depth,
                                       int64_t* list_indices);

#ifdef __cplusplus
}
#endif
