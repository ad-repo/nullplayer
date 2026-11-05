#include "e_root.h"

#include "effect_library.h"

#include "../3rdparty/json.h"

#include <algorithm>  // std::sort
#include <string>

using json = nlohmann::ordered_json;

static json config_schema(const Parameter* parameters, uint32_t num_parameters) {
    json s;
    s["type"] = "object";
    for (uint32_t i = 0; i < num_parameters; i++) {
        const Parameter& p = parameters[i];
        if (!p.is_saved) {
            continue;
        }
        s["properties"][p.name] = json::object();
        char* type_name = nullptr;
        switch (p.type) {
            default:
            case AVS_PARAM_INVALID:
            case AVS_PARAM_ACTION:
            case AVS_PARAM_INT_ARRAY:
            case AVS_PARAM_FLOAT_ARRAY:
            case AVS_PARAM_COLOR_ARRAY: continue;
            case AVS_PARAM_LIST: type_name = "array"; break;
            case AVS_PARAM_BOOL: type_name = "boolean"; break;
            case AVS_PARAM_INT: type_name = "number"; break;
            case AVS_PARAM_FLOAT: type_name = "number"; break;
            case AVS_PARAM_COLOR: type_name = "string"; break;
            case AVS_PARAM_STRING: /* set string or list of strings $ref below */ break;
            case AVS_PARAM_SELECT: type_name = "string"; break;
            case AVS_PARAM_RESOURCE: type_name = "string"; break;
        }
        if (type_name != nullptr) {
            s["properties"][p.name]["type"] = type_name;
        }
        if (p.description) {
            s["properties"][p.name]["description"] = p.description;
        }
        if (p.type == AVS_PARAM_INT && p.int_min != p.int_max) {
            if (p.int_min != INT64_MIN) {
                s["properties"][p.name]["minimum"] = p.int_min;
            }
            if (p.int_max != INT64_MAX) {
                s["properties"][p.name]["maximum"] = p.int_max;
            }
        }
        if (p.type == AVS_PARAM_FLOAT && p.float_min != p.float_max) {
            if (p.float_min != -INFINITY) {
                s["properties"][p.name]["minimum"] = p.float_min;
            }
            if (p.float_max != INFINITY) {
                s["properties"][p.name]["maximum"] = p.float_max;
            }
        }
        if (p.type == AVS_PARAM_COLOR) {
            s["properties"][p.name]["pattern"] =
                R"(^(#[0-9a-fA-F]{6}))"
                R"(|(rgb0_8 *\( *\d{1,3} *, *\d{1,3} *, *\d{1,3} *\))$)";
        }
        if (p.type == AVS_PARAM_STRING) {
            s["properties"][p.name]["$ref"] = "#/$defs/type:string-or-list-of-strings";
        }
        if (p.type == AVS_PARAM_SELECT && p.get_options != nullptr) {
            s["properties"][p.name]["enum"] = json::array();
            int64_t length = 0;
            auto options = p.get_options(&length);
            for (int i = 0; i < length; i++) {
                s["properties"][p.name]["enum"].push_back(options[i]);
            }
        }
        if (p.type == AVS_PARAM_LIST) {
            s["properties"][p.name]["items"] =
                config_schema(p.child_parameters, p.num_child_parameters);
            if (p.num_child_parameters_min != p.num_child_parameters_max) {
                s["properties"][p.name]["minItems"] = p.num_child_parameters_min;
                s["properties"][p.name]["maxItems"] = p.num_child_parameters_max;
            }
        }
    }
    s["additionalProperties"] = false;
    return s;
}

std::string preset_json_schema(std::string uri_domain) {
    json s;
    s["$schema"] = "https://json-schema.org/draft/2020-12/schema";
    s["$id"] = "https://" + uri_domain + "/specs/avs-preset.v0-0.schema.json";
    s["title"] = "AVS Preset File";
    s["description"] =
        "AVS preset file format including all (known) effects. The schema version has"
        " the format 'Major-Minor', where the major version denotes structural file"
        " format changes, while the minor version denotes changes within presets such"
        " as parameter names, descriptions or allowed values.";
    s["type"] = "object";
    s["properties"]["preset format version"]["type"] = "string";
    s["properties"]["preset format version"]["description"] = "A single rising number";
    s["properties"]["avs version"]["type"] = "string";
    s["properties"]["avs version"]["description"] =
        "Version of AVS used to create the preset";
    Root_Info root_info;
    s["properties"]["config"] =
        config_schema(root_info.get_parameters(), root_info.get_num_parameters());
    s["properties"]["components"]["$ref"] = "#/$defs/effects";
    s["required"] = {"preset format version", "components"};

    s["$defs"]["type:string-or-list-of-strings"]["anyOf"] = json::array();
    s["$defs"]["type:string-or-list-of-strings"]["anyOf"].push_back(json::object());
    s["$defs"]["type:string-or-list-of-strings"]["anyOf"].back()["type"] = "string";
    s["$defs"]["type:string-or-list-of-strings"]["anyOf"].push_back(json::object());
    s["$defs"]["type:string-or-list-of-strings"]["anyOf"].back()["type"] = "array";
    s["$defs"]["type:string-or-list-of-strings"]["anyOf"].back()["items"]["type"] =
        "string";

    s["$defs"]["effects"]["type"] = "array";
    s["$defs"]["effects"]["items"]["type"] = "object";
    s["$defs"]["effects"]["items"]["properties"]["enabled"]["type"] = "boolean";
    s["$defs"]["effects"]["items"]["properties"]["enabled"]["default"] = true;
    s["$defs"]["effects"]["items"]["properties"]["enabled"]["description"] =
        "If false, skip effect during rendering";
    s["$defs"]["effects"]["items"]["properties"]["comment"]["$ref"] =
        "#/$defs/type:string-or-list-of-strings";
    s["$defs"]["effects"]["items"]["properties"]["comment"]["default"] = "";
    s["$defs"]["effects"]["items"]["properties"]["comment"]["description"] =
        "General comment about the effect";
    s["$defs"]["effects"]["items"]["properties"]["effect"]["type"] = "string";
    s["$defs"]["effects"]["items"]["properties"]["effect"]["enum"] = json::array();

    // We have to repeat the conditional fields with just `true` here so that
    // `addtionalProperties=false` doesn't reject them. This does (falsely) allow the
    // "components" field on effects that don't allow children.
    // https://json-schema.org/understanding-json-schema/reference/object#extending
    s["$defs"]["effects"]["items"]["properties"]["config"] = true;
    s["$defs"]["effects"]["items"]["properties"]["components"] = true;
    s["$defs"]["effects"]["items"]["additionalProperties"] = false;

    s["$defs"]["effects"]["items"]["required"] = {"effect"};

    // The schema needs to express
    //   "If effect='Foo' then only allow a 'config' section that's valid for 'Foo'".
    //
    // This is a bit cumbersome in JSON-schema. Use an "allOf-if-then" construct as
    // recommended and explained in the second half of the if-then-else section of the
    // JSON-schema docs:
    // https://json-schema.org/understanding-json-schema/reference/conditionals#ifthenelse
    //
    // The gist is to create a (sorted) list of valid values for "effect" first, then
    // add an "allOf" section with if/then sections for each effect where the if
    // matches the effect name, and the then section contains the schema for the config
    // parameters of that effect:
    //   "properties": {
    //     ...
    //     "effect": {"enum": ["Foo", "Bar", ...]},
    //     "config": true,  // here, only specify that the field may exist
    //     ...
    //   },
    //   "allOf": [
    //     {
    //       "if": {"properties": {"effect": {"const": "Foo"}}},
    //       "then": {"properties": {"config": { "type": "object", "properties": ... }}}
    //     },
    //     ...
    //   ]
    s["$defs"]["effects"]["items"]["allOf"] = json::array();
    std::vector<Effect_Info*> effect_infos;
    for (auto const& entry : g_effect_lib) {
        effect_infos.push_back(entry.second);
    }
    std::sort(effect_infos.begin(), effect_infos.end(), [](auto a, auto b) {
        return std::string(a->get_name()) < b->get_name();
    });
    for (auto const& info : effect_infos) {
        if (info->is_createable_by_user()) {
            auto effect_name = info->get_name();
            s["$defs"]["effects"]["items"]["properties"]["effect"]["enum"].push_back(
                effect_name);
            json if_effect_then_config;
            if_effect_then_config["if"]["properties"]["effect"]["const"] = effect_name;
            if_effect_then_config["then"]["properties"]["config"] =
                config_schema(info->get_parameters(), info->get_num_parameters());
            if (info->can_have_child_components()) {
                if_effect_then_config["then"]["properties"]["components"]["$ref"] =
                    "#/$defs/effects";
            }
            s["$defs"]["effects"]["items"]["allOf"].push_back(if_effect_then_config);
        }
    }
    return s.dump(4);
}
