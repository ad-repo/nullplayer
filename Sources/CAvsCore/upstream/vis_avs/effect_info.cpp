#include "effect_info.h"

#include "pixel_format.h"

#include "../platform.h"

#include <iostream>
#include <stdexcept>

class load_exception : public std::exception {
    std::string msg;

   public:
    load_exception(const std::string& msg) : msg(msg) {}
    const char* what() const noexcept override { return msg.c_str(); }
};

/**
 * 0x0000000000ffffff -> "rgb0_8(255, 255, 255)"
 *
 * Other formats will be added in the future.
 */
static std::string serialize_color(uint64_t color,
                                   AVS_Pixel_Format pixel_format = AVS_PIXEL_RGB0_8) {
    std::stringstream color_str;
    switch (pixel_format) {
        case AVS_PIXEL_RGB0_8: {
            uint16_t r = (color & 0x00ff0000) >> 16;
            uint16_t g = (color & 0x0000ff00) >> 8;
            uint16_t b = color & 0x000000ff;
            color_str << "rgb0_8(" << r << ", " << g << ", " << b << ")";
            break;
        }
        default: break;
    }
    return color_str.str();
}

static void deserialize_color(const std::string& color_str,
                              uint64_t* color_out,
                              AVS_Pixel_Format* pixel_format_out) {
    std::string pixel_format_str;
    static const size_t num_channels = 4;
    std::string channel_strs[num_channels] = {"0", "0", "0", "0"};
    // parsing state machine:
    //   0        parse color format
    //   1,2,3,4  parse color channels
    size_t state = 0;
    for (auto& c : color_str) {
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            continue;
        }
        if (state == 0) {
            if (c == 'r' || c == 'g' || c == 'b' || c == '0' || c == '_' || c == '8') {
                pixel_format_str += c;
            } else if (c == '(') {
                state = 1;
                continue;
            } else {
                break;
            }
        }
        if (state >= 1 && state <= num_channels) {
            if (c >= '0' && c <= '9') {
                channel_strs[state - 1] += c;
            } else if (c == ',') {
                state += 1;
            } else {
                break;
            }
        }
    }
    if (pixel_format_str == "rgb0_8") {
        *pixel_format_out = AVS_PIXEL_RGB0_8;
        *color_out = ((uint64_t)std::stoi(channel_strs[0]) << 16)
                     | ((uint64_t)std::stoi(channel_strs[1]) << 8)
                     | ((uint64_t)std::stoi(channel_strs[2]));
    } else {
        // A silly fallback, but since it's the only pixel format at the moment...
        *pixel_format_out = AVS_PIXEL_RGB0_8;
        *color_out = 0;
    }
}

static std::string& replace_crlf_newlines_with_lf(std::string& str) {
    for (auto i = str.size(); i >= 2; i--) {
        if (str[i - 2] == '\r') {
            if (str[i - 1] == '\n') {
                str.erase(i - 2, 1);
            } else {
                // unlikely, but if a lone '\r' appears, simply replace by '\n'.
                str[i - 2] = '\n';
            }
        }
    }
    return str;
}

static json split_string_lines(const std::string& str) {
    json lines = json::array();
    std::string line;
    for (auto& c : str) {
        if (c == '\n') {
            lines += line;
            line.clear();
        } else {
            line += c;
        }
    }
    if (!line.empty()) {
        lines += line;
    }
    if (lines.empty() || lines.size() == 1) {
        return str;
    }
    return lines;
}

static std::string& replace_lf_newlines_with_crlf_for_winamp_ui(std::string& str) {
    for (int64_t i = 0; i < str.size(); i++) {
        if (str[i] == '\n') {
            str.insert(i, "\r");
        }
    }
    return str;
}

static std::string join_string_lines(const json& str, const char* nl = "\n") {
    if (str.is_string()) {
        return str;
    } else if (str.is_array()) {
        std::string joined;
        for (auto& line : str) {
            joined += line.get<std::string>() + nl;
        }
        return joined;
    }
    throw load_exception("Expected string or list-of-strings");
}

std::string Effect_Info::load_string(const json& str) { return join_string_lines(str); }
json Effect_Info::save_string(const std::string& str) {
    auto copy = str;
    return split_string_lines(replace_crlf_newlines_with_lf(copy));
}

void Parameter::from_json(const json& config_json, Effect_Config* config) const {
    uint8_t* addr = &((uint8_t*)config)[this->offset];
    switch (this->type) {
        case AVS_PARAM_BOOL:
            parameter_dispatch<bool>::set(this, addr, config_json);
            break;
        case AVS_PARAM_INT:
            parameter_dispatch<int64_t>::set(this, addr, config_json);
            break;
        case AVS_PARAM_FLOAT:
            parameter_dispatch<double>::set(this, addr, config_json);
            break;
        case AVS_PARAM_STRING: {
            parameter_dispatch<const char*>::set(
                this, addr, Effect_Info::load_string(config_json).c_str());
            break;
        }
        case AVS_PARAM_RESOURCE: {
            parameter_dispatch<const char*>::set(
                this, addr, Effect_Info::load_string(config_json).c_str());
            break;
        }
        case AVS_PARAM_COLOR: {
            uint64_t color;
            AVS_Pixel_Format pixel_format;
            deserialize_color(config_json, &color, &pixel_format);
            parameter_dispatch<uint64_t>::set(this, addr, color);
            break;
        }
        case AVS_PARAM_SELECT: {
            if (!config_json.is_string()) {
                throw load_exception("Expected string option for Select parameter");
            }
            int64_t num_options = 0;
            const char* const* options = this->get_options(&num_options);
            int64_t selection = -1;
            for (int64_t i = 0; i < num_options; i++) {
                if (options[i] == config_json) {
                    selection = i;
                    break;
                }
            }
            parameter_dispatch<int64_t>::set(this, addr, selection);
            break;
        }
        case AVS_PARAM_LIST: {
            this->list_clear(addr);
            for (auto& json_child_config : config_json) {
                int64_t at_end = INT64_MAX;
                if (!this->list_add(addr, UINT32_MAX, &at_end)) {
                    break;
                }
                auto new_item_addr = this->list_item_addr(addr, at_end);
                for (size_t j = 0; j < this->num_child_parameters; j++) {
                    auto child_param = this->child_parameters[j];
                    if (json_child_config.contains(child_param.name)) {
                        child_param.from_json(json_child_config[child_param.name],
                                              new_item_addr);
                    }
                }
            }
            break;
        }
        // TODO [feature]: Loadable array parameters. Currently no effect _saves_ these,
        //                 so _loading_ is not needed.
        case AVS_PARAM_INT_ARRAY:
        case AVS_PARAM_FLOAT_ARRAY:
        case AVS_PARAM_COLOR_ARRAY:
        case AVS_PARAM_ACTION:
        case AVS_PARAM_INVALID: [[fallthrough]];
        default: break;
    }
}

json Parameter::to_json(const Effect_Config* config) const {
    uint8_t* addr = &((uint8_t*)config)[this->offset];
    switch (this->type) {
        case AVS_PARAM_BOOL: return parameter_dispatch<bool>::get(addr);
        case AVS_PARAM_INT: return parameter_dispatch<int64_t>::get(addr);
        case AVS_PARAM_FLOAT: return parameter_dispatch<double>::get(addr);
        case AVS_PARAM_STRING: {
            std::string str = parameter_dispatch<const char*>::get(addr);
            return Effect_Info::save_string(str);
        }
        case AVS_PARAM_RESOURCE: return parameter_dispatch<const char*>::get(addr);
        case AVS_PARAM_COLOR: {
            return serialize_color(parameter_dispatch<uint64_t>::get(addr));
        }
        case AVS_PARAM_SELECT: {
            auto value = parameter_dispatch<int64_t>::get(addr);
            int64_t num_options = 0;
            const char* const* options = this->get_options(&num_options);
            const char* selection = nullptr;
            if (value >= 0 && value < num_options) {
                selection = options[value];
            }
            if (selection == nullptr) {
                selection = "";
            }
            return selection;
        }
        case AVS_PARAM_LIST: {
            auto config_list = (std::vector<Effect_Config>*)addr;
            auto list = json::array();
            size_t list_size =
                config_list->size() * sizeof(Effect_Config) / this->sizeof_child;
            for (size_t i = 0; i < list_size; i++) {
                json json_child_config;
                for (size_t j = 0; j < this->num_child_parameters; j++) {
                    auto child_param = this->child_parameters[j];
                    if (child_param.is_saved) {
                        auto child_config =
                            config_list->data() + i * this->sizeof_child;
                        json_child_config[child_param.name] =
                            child_param.to_json(child_config);
                    }
                }
                list += json_child_config;
            }
            return list;
        }
        case AVS_PARAM_INT_ARRAY: return parameter_dispatch<int64_t>::get_array(addr);
        case AVS_PARAM_FLOAT_ARRAY: return parameter_dispatch<double>::get_array(addr);
        case AVS_PARAM_COLOR_ARRAY: {
            auto values = parameter_dispatch<uint64_t>::get_array(addr);
            auto array = json::array();
            for (auto& value : values) {
                array += serialize_color(value);
            }
            return array;
        }
        case AVS_PARAM_ACTION: [[fallthrough]];
        case AVS_PARAM_INVALID:
        default: return {};
    }
}

void Effect_Info::load_config(Effect_Config* config,
                              Effect_Config* global_config,
                              const json& config_json) const {
    for (size_t i = 0; i < this->get_num_parameters(); i++) {
        auto parameter = this->get_parameters()[i];
        if (parameter.type == AVS_PARAM_INVALID) {
            log_warn(
                "Invalid parameter in %s:"
                "Check its Info struct's `parameters` list length vs `num_parameters`.",
                this->get_name());
            continue;
        }
        if (parameter.is_saved) {
            auto local_or_global_config = parameter.is_global ? global_config : config;
            if (!config_json.contains(parameter.name)) {
                continue;
            }
            try {
                parameter.from_json(config_json[parameter.name],
                                    local_or_global_config);
            } catch (std::exception& e) {
                log_err("Loading config for %s/%s: %s",
                        this->get_name(),
                        parameter.name,
                        e.what());
            }
        }
    }
}

json Effect_Info::save_config(const Effect_Config* config,
                              const Effect_Config* global_config) const {
    json config_save;
    for (size_t i = 0; i < this->get_num_parameters(); i++) {
        auto parameter = this->get_parameters()[i];
        if (parameter.type == AVS_PARAM_INVALID) {
            log_warn(
                "Invalid parameter in %s:"
                "Check its Info struct's `parameters` list length vs `num_parameters`.",
                this->get_name());
            continue;
        }
        if (parameter.is_saved) {
            auto local_or_global_config = parameter.is_global ? global_config : config;
            try {
                auto value = parameter.to_json(local_or_global_config);
                if (!value.empty()) {
                    config_save[parameter.name] = value;
                }
            } catch (std::exception& e) {
                log_err("Exception while saving config for %s/%s: %s",
                        this->get_name(),
                        parameter.name,
                        e.what());
            }
        }
    }
    return config_save;
}

bool operator==(const Effect_Info& a, const Effect_Info& b) {
    return a.get_handle() == b.get_handle();
}
bool operator==(const Effect_Info* a, const Effect_Info& b) {
    return a == nullptr ? false : *a == b;
}
bool operator==(const Effect_Info& a, const Effect_Info* b) {
    return b == nullptr ? false : *b == a;
}
bool operator!=(const Effect_Info& a, const Effect_Info& b) { return !(a == b); }
bool operator!=(const Effect_Info* a, const Effect_Info& b) { return !(a == b); }
bool operator!=(const Effect_Info& a, const Effect_Info* b) { return !(b == a); }
