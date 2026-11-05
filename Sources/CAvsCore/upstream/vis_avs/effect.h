#pragma once

#include "avs_editor.h"
#include "effect_info.h"
#include "effect_library.h"
#include "render_context.h"

#include "../platform.h"

#include <algorithm>  // std::remove
#include <memory>     // std::shared_ptr, std::weak_ptr
#include <set>
#include <stdint.h>
#include <string.h>
#include <string>
#include <type_traits>  // std::is_same<T1, T2>
#include <vector>

class AVS_Instance;

class Effect {
   public:
    enum Insert_Direction {
        INSERT_BEFORE,
        INSERT_AFTER,
        INSERT_CHILD,
    };
    AVS_Component_Handle handle;
    AVS_Instance* avs;

    bool enabled;
    std::string comment;
    std::vector<Effect*> children;
    AVS_Component_Handle* child_handles_for_api = nullptr;
    Effect(AVS_Instance* avs) : handle(h_components.get()), avs(avs), enabled(true) {}
    virtual ~Effect();
    Effect(const Effect&);
    Effect& operator=(const Effect&);
    Effect(Effect&&) noexcept;
    Effect& operator=(Effect&&) noexcept;
    Effect* insert(Effect* to_insert, Effect* relative_to, Insert_Direction direction);
    Effect* lift(Effect* to_lift);
    Effect* move(Effect* to_move,
                 Effect* relative_to,
                 Insert_Direction direction,
                 bool insert_if_not_found = false);
    void remove(Effect* to_remove);
    Effect* duplicate(Effect* to_duplicate);
    bool is_ancestor_of(Effect* descendent);
    void set_enabled(bool enabled);
    virtual void on_enable(bool enabled) { (void)enabled; }
    Effect* find_by_handle(AVS_Component_Handle handle);
    const AVS_Component_Handle* get_child_handles_for_api();

    virtual Effect* clone() = 0;
    virtual bool can_have_child_components() = 0;
    virtual Effect_Info* get_info() const = 0;
    virtual size_t parameter_list_length(
        AVS_Parameter_Handle parameter,
        const std::vector<int64_t>& parameter_path) = 0;
    virtual bool parameter_list_entry_add(
        AVS_Parameter_Handle parameter,
        int64_t before,
        std::vector<AVS_Parameter_Value>,
        const std::vector<int64_t>& parameter_path) = 0;
    virtual bool parameter_list_entry_move(
        AVS_Parameter_Handle parameter,
        int64_t from,
        int64_t to,
        const std::vector<int64_t>& parameter_path) = 0;
    virtual bool parameter_list_entry_remove(
        AVS_Parameter_Handle parameter,
        int64_t to_remove,
        const std::vector<int64_t>& parameter_path) = 0;
    virtual bool run_action(AVS_Parameter_Handle parameter,
                            const std::vector<int64_t>& parameter_path = {}) = 0;

#define GET_SET_PARAMETER_ABSTRACT(AVS_TYPE, TYPE)                                    \
    virtual TYPE get_##AVS_TYPE(AVS_Parameter_Handle parameter,                       \
                                const std::vector<int64_t>& parameter_path = {}) = 0; \
    virtual bool set_##AVS_TYPE(AVS_Parameter_Handle parameter,                       \
                                TYPE value,                                           \
                                const std::vector<int64_t>& parameter_path = {}) = 0
    GET_SET_PARAMETER_ABSTRACT(bool, bool);
    GET_SET_PARAMETER_ABSTRACT(int, int64_t);
    GET_SET_PARAMETER_ABSTRACT(float, double);
    GET_SET_PARAMETER_ABSTRACT(color, uint64_t);
    GET_SET_PARAMETER_ABSTRACT(string, const char*);

#define GET_ARRAY_PARAMETER_ABSTRACT(AVS_TYPE, TYPE)  \
    virtual std::vector<TYPE> get_##AVS_TYPE##_array( \
        AVS_Parameter_Handle parameter,               \
        const std::vector<int64_t>& parameter_path = {}) = 0
    GET_ARRAY_PARAMETER_ABSTRACT(int, int64_t);
    GET_ARRAY_PARAMETER_ABSTRACT(float, double);
    GET_ARRAY_PARAMETER_ABSTRACT(color, uint64_t);

    // render api
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h) {
        (void)visdata, (void)is_beat, (void)framebuffer, (void)fbout, (void)w, (void)h;
        return 0;  // returns 1 if fbout has dest
    }
    virtual void render_with_context(RenderContext&) {}
    virtual void load(json&) {}
    virtual json save() { return nullptr; }
    virtual char* get_desc() = 0;
    virtual int32_t get_legacy_id() { return -1; }
    virtual const char* get_legacy_ape_id() { return nullptr; }
    virtual void load_legacy(unsigned char* data, int len) { (void)data, (void)len; }
    virtual int save_legacy(unsigned char* data) {
        (void)data;
        return 0;
    }
    static uint32_t string_load_legacy(const char* src,
                                       std::string& dest,
                                       uint32_t max_length);
    static uint32_t string_save_legacy(std::string& src,
                                       char* dest,
                                       uint32_t max_length = 0x7fff,
                                       bool with_nt = false);
    static uint32_t string_nt_load_legacy(const char* src,
                                          std::string& dest,
                                          uint32_t max_length);
    static uint32_t string_nt_save_legacy(std::string& src,
                                          char* dest,
                                          uint32_t max_length);

    // multithread render api
    virtual bool can_multithread() { return false; }
    virtual int smp_getflags() { return 0; }
    virtual int smp_begin(int max_threads,
                          char visdata[2][2][576],
                          int is_beat,
                          int* framebuffer,
                          int* fbout,
                          int w,
                          int h) {
        (void)max_threads, (void)visdata, (void)is_beat, (void)framebuffer, (void)fbout,
            (void)w, (void)h;
        return 0;
    }
    virtual void smp_render(int this_thread,
                            int max_threads,
                            char visdata[2][2][576],
                            int is_beat,
                            int* framebuffer,
                            int* fbout,
                            int w,
                            int h) {
        (void)this_thread, (void)max_threads, (void)visdata, (void)is_beat,
            (void)framebuffer, (void)fbout, (void)w, (void)h;
    }
    virtual int smp_finish(char visdata[2][2][576],
                           int is_beat,
                           int* framebuffer,
                           int* fbout,
                           int w,
                           int h) {
        (void)visdata, (void)is_beat, (void)framebuffer, (void)fbout, (void)w, (void)h;
        return 0;
    }

    void print_tree(std::string indent = "");
    virtual void print_config(const std::string& indent) = 0;

    void swap(Effect&);
};

bool operator==(const Effect& a, const Effect_Info& b);
bool operator==(const Effect* a, const Effect_Info& b);
bool operator!=(const Effect& a, const Effect_Info& b);
bool operator!=(const Effect* a, const Effect_Info& b);

template <class Info_T, class Config_T, class Global_Config_T = Effect_Config>
class Configurable_Effect : public Effect {
    bool trace_parameter_changes = false;

   public:
    // TODO [clean]: make info & config protected.
    static Info_T info;
    Config_T config;

    Configurable_Effect(AVS_Instance* avs) : Effect(avs) {
        this->prune_empty_globals();
        this->init_global_config(this->avs);
    }
    ~Configurable_Effect() { this->remove_from_global_instances(); }
    Configurable_Effect(const Configurable_Effect& other)
        : Effect(other), config(other.config) {}
    Configurable_Effect& operator=(const Configurable_Effect& other) {
        Effect::operator=(other);
        this->config = other.config;
        return *this;
    }
    Configurable_Effect(Configurable_Effect&& other) noexcept
        : Effect(std::move(other)) {
        std::swap(this->config, other.config);
    }
    Configurable_Effect& operator=(Configurable_Effect&& other) noexcept {
        Effect::operator=(std::move(other));
        std::swap(this->config, other.config);
        return *this;
    }
    virtual bool can_have_child_components() {
        return Configurable_Effect::info.can_have_child_components();
    }
    Effect_Info* get_info() const { return &this->info; }
    static void set_desc(char* desc) {
        Configurable_Effect::_set_desc();
        if (desc) {
            strncpy(desc, Configurable_Effect::desc.c_str(), 1024);
        }
    }
    virtual char* get_desc() {
        Configurable_Effect::_set_desc();
        return (char*)Configurable_Effect::desc.c_str();
    }

    template <typename T>
    T get(AVS_Parameter_Handle parameter,
          const std::vector<int64_t>& parameter_path = {}) {
        if (parameter == 0) {
            return parameter_dispatch<T>::zero();
        }
        auto param = this->info.get_parameter_from_handle(parameter);
        if (param == NULL) {
            return parameter_dispatch<T>::zero();
        }
        auto addr = this->get_config_address(param, parameter_path);
        return parameter_dispatch<T>::get(addr);
    }

    template <typename T>
    bool set(AVS_Parameter_Handle parameter,
             T value,
             const std::vector<int64_t>& parameter_path = {}) {
        if (parameter == 0) {
            return false;
        }
        auto param = this->info.get_parameter_from_handle(parameter);
        if (param == NULL) {
            return false;
        }
        auto addr = this->get_config_address(param, parameter_path);
        parameter_dispatch<T>::set(param, addr, value);
        if (param->on_value_change != NULL) {
            param->on_value_change(this, param, parameter_path);
        }
        if (this->trace_parameter_changes) {
            auto prefix = trace_prefix(this->info.name, param->name, parameter_path);
            log_info("%s %s",
                     prefix.c_str(),
                     parameter_dispatch<T>::trace(param, value, addr).c_str());
        }
        return true;
    }

    template <typename T>
    std::vector<T>& get_array(AVS_Parameter_Handle parameter,
                              const std::vector<int64_t>& parameter_path = {}) {
        static std::vector<T> empty;
        if (parameter == 0) {
            return empty;
        }
        auto param = this->info.get_parameter_from_handle(parameter);
        if (param == NULL) {
            return empty;
        }
        auto addr = this->get_config_address(param, parameter_path);
        return parameter_dispatch<T>::get_array(addr);
    }

    size_t parameter_list_length(AVS_Parameter_Handle parameter,
                                 const std::vector<int64_t>& parameter_path = {}) {
        if (parameter == 0) {
            return 0;
        }
        auto param = this->info.get_parameter_from_handle(parameter);
        if (param == NULL) {
            return 0;
        }
        auto addr = this->get_config_address(param, parameter_path);
        return param->list_length(addr);
    }
    bool parameter_list_entry_add(
        AVS_Parameter_Handle parameter,
        int64_t before,
        std::vector<AVS_Parameter_Value> parameter_values = {},
        const std::vector<int64_t>& parameter_path = {}) {
        if (parameter == 0) {
            return false;
        }
        auto param = this->info.get_parameter_from_handle(parameter);
        if (param == NULL) {
            return false;
        }
        auto addr = this->get_config_address(param, parameter_path);
        bool success = param->list_add(addr, param->num_child_parameters_max, &before);
        if (success) {
            std::vector<int64_t> new_parameter_path = parameter_path;
            new_parameter_path.push_back(before);
            for (auto const& pv : parameter_values) {
                auto pv_param = this->info.get_parameter_from_handle(pv.parameter);
                auto pv_addr = this->get_config_address(pv_param, new_parameter_path);
                if (pv_param == NULL) {
                    continue;
                }
                switch (pv_param->type) {
                    case AVS_PARAM_BOOL:
                        parameter_dispatch<bool>::set(pv_param, pv_addr, pv.value.b);
                        break;
                    case AVS_PARAM_SELECT:
                    case AVS_PARAM_INT:
                        parameter_dispatch<int64_t>::set(pv_param, pv_addr, pv.value.i);
                        break;
                    case AVS_PARAM_FLOAT:
                        parameter_dispatch<double>::set(pv_param, pv_addr, pv.value.f);
                        break;
                    case AVS_PARAM_COLOR:
                        parameter_dispatch<uint64_t>::set(
                            pv_param, pv_addr, pv.value.c);
                        break;
                    case AVS_PARAM_RESOURCE:
                    case AVS_PARAM_STRING:
                        parameter_dispatch<const char*>::set(
                            pv_param, pv_addr, pv.value.s);
                        break;
                    case AVS_PARAM_LIST:
                    case AVS_PARAM_ACTION:
                    case AVS_PARAM_INT_ARRAY:
                    case AVS_PARAM_FLOAT_ARRAY:
                    case AVS_PARAM_COLOR_ARRAY:
                    case AVS_PARAM_INVALID:
                    default: break;
                }
            }
            if (param->on_list_add != NULL) {
                param->on_list_add(this, param, parameter_path, before, 0);
            }
            if (this->trace_parameter_changes) {
                auto prefix =
                    trace_prefix(this->info.name, param->name, parameter_path);
                log_info("%s added new entry #%lld\n", prefix.c_str(), before);
            }
        }
        return success;
    }
    bool parameter_list_entry_move(AVS_Parameter_Handle parameter,
                                   int64_t from,
                                   int64_t to,
                                   const std::vector<int64_t>& parameter_path = {}) {
        if (parameter == 0) {
            return false;
        }
        auto param = this->info.get_parameter_from_handle(parameter);
        if (param == NULL) {
            return false;
        }
        auto addr = this->get_config_address(param, parameter_path);
        bool success = param->list_move(addr, &from, &to);
        if (success && param->on_list_move != NULL) {
            param->on_list_move(this, param, parameter_path, from, to);
            if (this->trace_parameter_changes) {
                auto prefix =
                    trace_prefix(this->info.name, param->name, parameter_path);
                log_info("%s moved entry #%lld to #%lld\n", prefix.c_str(), from, to);
            }
        }
        return success;
    }
    bool parameter_list_entry_remove(AVS_Parameter_Handle parameter,
                                     int64_t to_remove,
                                     const std::vector<int64_t>& parameter_path = {}) {
        if (parameter == 0) {
            return false;
        }
        auto param = this->info.get_parameter_from_handle(parameter);
        if (param == NULL) {
            return false;
        }
        auto addr = this->get_config_address(param, parameter_path);
        bool success =
            param->list_remove(addr, param->num_child_parameters_min, &to_remove);
        if (success && param->on_list_remove != NULL) {
            param->on_list_remove(this, param, parameter_path, to_remove, 0);
            if (this->trace_parameter_changes) {
                auto prefix =
                    trace_prefix(this->info.name, param->name, parameter_path);
                log_info("%s removed entry #%lld\n", prefix.c_str(), to_remove);
            }
        }
        return success;
    }

    bool run_action(AVS_Parameter_Handle parameter,
                    const std::vector<int64_t>& parameter_path = {}) {
        if (parameter == 0) {
            return false;
        }
        auto param = this->info.get_parameter_from_handle(parameter);
        if (param == NULL || param->on_value_change == NULL) {
            return false;
        }
        param->on_value_change(this, param, parameter_path);
        if (this->trace_parameter_changes) {
            auto prefix = trace_prefix(this->info.name, param->name, parameter_path);
            log_info("%s triggered", prefix.c_str());
        }
        return true;
    }

    static std::string trace_prefix(const char* effect_name,
                                    const char* param_name,
                                    const std::vector<int64_t>& path) {
        std::stringstream prefix;
        prefix << effect_name << "/" << param_name;
        if (!path.empty()) {
            prefix << "[";
            for (size_t i = 0; i < path.size(); i++) {
                prefix << path[i];
                if (i < path.size() - 1) {
                    prefix << ",";
                }
            }
            prefix << "]";
        }
        return prefix.str();
    }

    static size_t instance_count() { return Configurable_Effect::globals.size(); }

#define GET_SET_PARAMETER(AVS_TYPE, TYPE)                                          \
    virtual TYPE get_##AVS_TYPE(AVS_Parameter_Handle parameter,                    \
                                const std::vector<int64_t>& parameter_path = {}) { \
        return get<TYPE>(parameter, parameter_path);                               \
    }                                                                              \
    virtual bool set_##AVS_TYPE(AVS_Parameter_Handle parameter,                    \
                                TYPE value,                                        \
                                const std::vector<int64_t>& parameter_path = {}) { \
        return set<TYPE>(parameter, value, parameter_path);                        \
    }
    GET_SET_PARAMETER(bool, bool)
    GET_SET_PARAMETER(int, int64_t)
    GET_SET_PARAMETER(float, double)
    GET_SET_PARAMETER(color, uint64_t)
    GET_SET_PARAMETER(string, const char*)

#define GET_ARRAY_PARAMETER(AVS_TYPE, TYPE)                \
    virtual std::vector<TYPE> get_##AVS_TYPE##_array(      \
        AVS_Parameter_Handle parameter,                    \
        const std::vector<int64_t>& parameter_path = {}) { \
        return get_array<TYPE>(parameter, parameter_path); \
    }
    GET_ARRAY_PARAMETER(int, int64_t)
    GET_ARRAY_PARAMETER(float, double)
    GET_ARRAY_PARAMETER(color, uint64_t)

    virtual void load(json& data) {
        if (data.is_null()) {
            return;
        }
        this->enabled = data.value("enabled", true);
        this->comment = Effect_Info::load_string(data.value("comment", json::array()));
        this->info.load_config(
            &this->config, &this->global->config, data.value("config", json::object()));
        if (this->can_have_child_components()) {
            auto children_data = data.value("components", json::array());
            if (children_data.is_array()) {
                for (auto& child_data : children_data) {
                    Effect* child_effect = nullptr;
                    if (!child_data.contains("effect")) {
                        log_warn("effect without 'effect' key, preset file corrupt.");
                    }
                    child_effect = component_factory_by_name(
                        child_data.value("effect", ""), this->avs);
                    child_effect->load(child_data);
                    this->insert(child_effect, this, INSERT_CHILD);
                }
            }
        }
        this->on_load();
    }

    virtual void on_load() {}

    virtual json save() {
        json save_data;
        save_data["effect"] = this->info.get_name();
        save_data["enabled"] = this->enabled;
        save_data["comment"] = Effect_Info::save_string(this->comment);
        auto save_config = this->info.save_config(&this->config, &this->global->config);
        if (!save_config.is_null()) {
            save_data["config"] = save_config;
        }
        if (this->can_have_child_components()) {
            json child_data;
            for (auto& child : this->children) {
                child_data += child->save();
            }
            save_data["components"] = child_data;
        }
        return save_data;
    }

    virtual int32_t get_legacy_id() { return this->info.legacy_id; }
    virtual const char* get_legacy_ape_id() { return this->info.legacy_ape_id; }

   protected:
    static std::string desc;
    static void _set_desc() {
        if (Configurable_Effect::desc.empty()) {
            Configurable_Effect::desc += Configurable_Effect::info.group;
            if (!Configurable_Effect::desc.empty()) {
                Configurable_Effect::desc += " / ";
            }
            Configurable_Effect::desc += Configurable_Effect::info.name;
        }
    }

    struct Global {
        Global_Config_T config;
        std::set<Configurable_Effect*> instances;
    };
    std::shared_ptr<Global> global = nullptr;

    static Global* get_global_for_instance(AVS_Instance* avs) {
        for (auto& g : Configurable_Effect::globals) {
            if (g.second.expired()) {
                continue;
            }
            auto tmp = g.second.lock();
            if (g.first == avs) {
                return tmp.get();
            }
        }
        return nullptr;
    }

   private:
    static std::map<AVS_Instance*, std::weak_ptr<Global>> globals;
    static void prune_empty_globals() {
        for (auto it = Configurable_Effect::globals.begin();
             it != Configurable_Effect::globals.end();) {
            if (it->second.expired()) {
                it = Configurable_Effect::globals.erase(it);
            } else {
                it++;
            }
        }
    }
    void init_global_config(AVS_Instance* avs) {
        if (std::is_same<Global_Config_T, Effect_Config>::value) {
            return;
        }
        {  // This scope is needed for the shared_ptr to get deallocated at the end.
            std::shared_ptr<Global> tmp;
            for (auto& g : Configurable_Effect::globals) {
                if (g.second.expired()) {
                    continue;
                }
                tmp = g.second.lock();
                if (g.first == avs) {
                    this->global = g.second.lock();
                    this->global->instances.insert(this);
                    return;
                }
            }
            tmp = std::make_shared<Global>();
            this->globals.emplace(avs, tmp);
            this->global = tmp;
            this->global->instances.insert(this);
        }
    }
    void remove_from_global_instances() {
        if (this->global.get()) {
            this->global->instances.erase(this);
        }
    }

    uint8_t* get_config_address(const Parameter* parameter,
                                const std::vector<int64_t>& parameter_path) {
        Effect_Config* _config = parameter->is_global
                                     ? (Effect_Config*)&this->global->config
                                     : (Effect_Config*)&this->config;
        return this->info.get_config_address(_config,
                                             parameter,
                                             this->info.num_parameters,
                                             this->info.parameters,
                                             parameter_path,
                                             0);
    }

    virtual void print_config(const std::string& indent) {
        printf("%s    enabled: %s\n", indent.c_str(), this->enabled ? "true" : "false");
        if (!this->comment.empty()) {
            printf("%s    comment: %s\n", indent.c_str(), this->comment.c_str());
        }
        std::vector<int64_t> parameter_path = {};
        this->print_config(
            indent, this->info.parameters, this->info.num_parameters, parameter_path);
    }
    virtual void print_config(const std::string& indent,
                              const Parameter* parameters,
                              size_t num_parameters,
                              std::vector<int64_t>& parameter_path) {
        for (size_t i = 0; i < num_parameters; i++) {
            auto param = parameters[i];
            if (param.type == AVS_PARAM_ACTION) {
                continue;
            }
            const char* global_or_not = param.is_global ? "G" : " ";
            printf("%s  %s %s: ", indent.c_str(), global_or_not, param.name);
            switch (param.type) {
                case AVS_PARAM_BOOL: {
                    auto value = this->get_bool(param.handle, parameter_path);
                    printf("%s\n", value ? "true" : "false");
                    break;
                }
                case AVS_PARAM_INT:
                    printf("%lld\n", this->get_int(param.handle, parameter_path));
                    break;
                case AVS_PARAM_FLOAT:
                    printf("%f\n", this->get_float(param.handle, parameter_path));
                    break;
                case AVS_PARAM_RESOURCE: [[fallthrough]];
                case AVS_PARAM_STRING: {
                    std::string str = this->get_string(param.handle, parameter_path);
                    // if string contains newlines replace them with escaped newlines
                    if (str.find('\n') != std::string::npos) {
                        std::string::size_type pos = 0;
                        while ((pos = str.find('\n', pos)) != std::string::npos) {
                            str.replace(pos, 1, "\\n");
                            pos += 2;
                        }
                    }
                    if (str.find('\r') != std::string::npos) {
                        std::string::size_type pos = 0;
                        while ((pos = str.find('\r', pos)) != std::string::npos) {
                            str.replace(pos, 1, "\\r");
                            pos += 2;
                        }
                    }
                    if (str.length() > 13) {
                        printf("%s...\n", str.substr(0, 10).c_str());
                    } else {
                        printf("%s\n", str.c_str());
                    }
                    break;
                }
                case AVS_PARAM_COLOR:
                    printf("%08llx\n", this->get_color(param.handle, parameter_path));
                    break;
                case AVS_PARAM_SELECT: {
                    int64_t num_options = 0;
                    auto options = param.get_options(&num_options);
                    auto selection = this->get_int(param.handle, parameter_path);
                    if (options == nullptr) {
                        printf("<no options> (selected %lld)\n", selection);
                        break;
                    }
                    if (selection < 0 || selection >= num_options) {
                        printf("<invalid selection> (selected %lld)\n", selection);
                        break;
                    }
                    printf("%s\n", options[selection]);
                    break;
                }
                case AVS_PARAM_LIST: {
                    auto list_length = param.list_length(
                        this->get_config_address(&param, parameter_path));
                    printf("list (%u entries)\n", list_length);
                    for (size_t k = 0; k < list_length; k++) {
                        std::vector<int64_t> new_parameter_path = parameter_path;
                        new_parameter_path.push_back(k);
                        this->print_config(indent + "  ",
                                           param.child_parameters,
                                           param.num_child_parameters,
                                           new_parameter_path);
                    }
                    break;
                }
                case AVS_PARAM_ACTION: printf("action\n"); break;
                case AVS_PARAM_INT_ARRAY: printf("int array\n"); break;
                case AVS_PARAM_FLOAT_ARRAY: printf("float array\n"); break;
                case AVS_PARAM_COLOR_ARRAY: printf("color array\n"); break;
                default: printf("<unknown type>\n"); break;
            }
        }
    }
};

template <class Info_T, class Config_T, class Global_Config_T>
Info_T Configurable_Effect<Info_T, Config_T, Global_Config_T>::info;
template <class Info_T, class Config_T, class Global_Config_T>
std::string Configurable_Effect<Info_T, Config_T, Global_Config_T>::desc;
template <class Info_T, class Config_T, class Global_Config_T>
std::map<AVS_Instance*,
         std::weak_ptr<
             typename Configurable_Effect<Info_T, Config_T, Global_Config_T>::Global>>
    Configurable_Effect<Info_T, Config_T, Global_Config_T>::globals;
