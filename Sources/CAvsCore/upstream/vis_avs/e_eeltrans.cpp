#include "e_eeltrans.h"
#include "e_eeltrans_translate.h"

#include "instance.h"

#include "../3rdparty/WDL-EEL2/eel2/ns-eel.h"

#include <stdio.h>  // for logging
#include <vector>

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

constexpr Parameter EelTrans_Info::parameters[];

std::vector<void*> comp_ctxs;
std::map<AVS_Instance*, std::string> translated_strings;

void E_EelTrans::on_enable(bool enabled) {
    this->global->config.translate_enabled = enabled;
    for (auto it : this->global->instances) {
        it->enabled = enabled;
    }
}

E_EelTrans::E_EelTrans(AVS_Instance* avs) : Configurable_Effect(avs) {
    if (this->global->config.need_new_first_instance) {
        this->is_first_instance = true;
        this->global->config.need_new_first_instance = false;
        this->global->config.avs_base_path = this->avs->base_path;
        this->enabled = this->global->config.translate_enabled;

        std::string filename = this->avs->base_path + "\\eeltrans.ini";
        FILE* ini = fopen(filename.c_str(), "r");
        if (ini) {
            char* tmp = new char[2048];
            fscanf(ini, "%s", tmp);
            this->global->config.log_path = tmp;
            fclose(ini);
        }

        this->avs->eel_state.pre_compile_hook = this->pre_compile_hook;
        this->avs->eel_state.post_compile_hook = this->post_compile_hook;
    } else {
        this->is_first_instance = false;
    }
}

E_EelTrans::~E_EelTrans() {
    if (this->is_first_instance) {
        this->global->config.need_new_first_instance = true;
        std::string filename = this->avs->base_path + "\\eeltrans.ini";
        FILE* ini = fopen(filename.c_str(), "w");
        if (ini) {
            fprintf(ini, "%s", this->global->config.log_path.c_str());
            fclose(ini);
        }
    }
    if (this->global->instances.size() == 1) {
        this->avs->eel_state.pre_compile_hook = nullptr;
        this->avs->eel_state.post_compile_hook = nullptr;
    }
}

unsigned int compnum(void* ctx) {
    unsigned int i = 0;
    for (; i < comp_ctxs.size(); i++) {
        if (comp_ctxs[i] == ctx) {
            return i;
        }
    }
    // TODO [bug]: When does this list get cleared?
    comp_ctxs.push_back(ctx);
    return i;
}

const char* E_EelTrans::pre_compile_hook(void* ctx,
                                         char* expression,
                                         void* avs_instance) {
    static void* lastctx = 0;
    static int num = 0;
    auto avs = (AVS_Instance*)avs_instance;
    if (expression == NULL) {
        return NULL;
    }
    E_EelTrans::Global* global_ptr;
    if (!(global_ptr = E_EelTrans::get_global_for_instance(avs))) {
        return expression;
    }
    EelTrans_Global_Config g_config = global_ptr->config;
    auto g_instances = global_ptr->instances;
    if (g_config.log_enabled) {
        if (ctx == lastctx) {
            num = (num % 4) + 1;
        } else {
            num = 1;
            lastctx = ctx;
        }
        char filename[200];
        sprintf(filename,
                "%s\\comp%02dpart%d.log",
                g_config.log_path.c_str(),
                compnum(ctx),
                num);
        FILE* logfile = fopen(filename, "w");
        if (logfile) {
            fprintf(logfile, "%s", expression);
            fclose(logfile);
        } else {
            if (!create_directory((char*)g_config.log_path.c_str())) {
                printf("Could not create log directory, deactivating Code Logger.\n");
                g_config.log_enabled = 0;
            }
        }
    }
    if (g_config.translate_enabled && (strncmp(expression, "//$notrans", 10) != 0)) {
        std::string all_code;
        for (auto it : g_instances) {
            all_code += it->config.code;
            all_code += "\r\n";
        }
        translated_strings[avs] = translate(all_code,
                                            expression,
                                            g_config.translate_firstlevel,
                                            g_config.avs_base_path);
        return translated_strings[avs].c_str();
    }
    return expression;
}

void E_EelTrans::post_compile_hook(void* avs_instance) {
    translated_strings.erase((AVS_Instance*)avs_instance);
}

int E_EelTrans::render(char[2][2][576], int, int*, int*, int, int) {
    if (this->global->config.need_new_first_instance && !this->is_first_instance) {
        this->global->config.need_new_first_instance = false;
        this->is_first_instance = true;
    }
    return 0;
}

void E_EelTrans::on_load() { this->global->config.translate_enabled |= this->enabled; }

void E_EelTrans::load_legacy(unsigned char* data, int len) {
    int pos = 0;

    if (len - pos >= 4) {
        this->global->config.translate_enabled = (GET_INT() != 0);
        this->enabled = this->global->config.translate_enabled;
        pos += 4;
    }
    if (len - pos >= 4) {
        this->global->config.log_enabled = (GET_INT() != 0);
        pos += 4;
    }
    if (len - pos >= 4) {
        this->global->config.translate_firstlevel = (GET_INT() != 0);
        pos += 4;
    }
    if (len - pos >= 4) {
        this->global->config.read_comment_codes = (GET_INT() != 0);
        pos += 4;
    }
    if (len > pos) {
        char* str_data = (char*)data;
        this->string_nt_load_legacy(&str_data[pos], this->config.code, len - pos);
    } else {
        this->config.code = "";
    }
}

int E_EelTrans::save_legacy(unsigned char* data) {
    int pos = 0;

    PUT_INT(this->enabled);
    pos += 4;

    PUT_INT(this->global->config.log_enabled);
    pos += 4;

    PUT_INT(((int)this->global->config.translate_firstlevel));
    pos += 4;

    PUT_INT(this->global->config.read_comment_codes);
    pos += 4;

    char* str_data = (char*)data;
    pos += string_nt_save_legacy(
        this->config.code, &str_data[pos], MAX_CODE_LEN - 1 - pos);

    return pos;
}

Effect_Info* create_EelTrans_Info() { return new EelTrans_Info(); }
Effect* create_EelTrans(AVS_Instance* avs) { return new E_EelTrans(avs); }
void set_EelTrans_desc(char* desc) { E_EelTrans::set_desc(desc); }
