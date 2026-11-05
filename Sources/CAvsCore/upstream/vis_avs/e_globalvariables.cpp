#include "e_globalvariables.h"

#include "avs_eelif.h"

#include <algorithm>

#define IS_BEAT_MASK 0x01  // something else might be encoded in the higher bytes

constexpr Parameter GlobalVariables_Info::parameters[];

const int E_GlobalVariables::max_regs_index = 99;
const int E_GlobalVariables::max_gmb_index = 1024 * 1024 - 1;

void GlobalVariables_Info::check_ranges(Effect* component,
                                        const Parameter* parameter,
                                        const std::vector<int64_t>&) {
    auto globalvars = (E_GlobalVariables*)component;
    bool success = false;
    if (std::string("Save Reg Range") == parameter->name) {
        success = E_GlobalVariables::check_set_range(globalvars->config.save_reg_ranges,
                                                     globalvars->reg_ranges,
                                                     E_GlobalVariables::max_regs_index);
    } else if (std::string("Save Buf Range") == parameter->name) {
        success = E_GlobalVariables::check_set_range(globalvars->config.save_buf_ranges,
                                                     globalvars->buf_ranges,
                                                     E_GlobalVariables::max_gmb_index);
    }
    globalvars->config.error_msg = success ? "" : "Err";
}

void GlobalVariables_Info::save_ranges(Effect* component,
                                       const Parameter*,
                                       const std::vector<int64_t>&) {
    ((E_GlobalVariables*)component)->save_ranges_to_file();
}

void GlobalVariables_Info::recompile(Effect* component,
                                     const Parameter* parameter,
                                     const std::vector<int64_t>&) {
    auto globalvars = (E_GlobalVariables*)component;
    if (std::string("Init") == parameter->name) {
        globalvars->code_init.need_recompile = true;
    } else if (std::string("Frame") == parameter->name) {
        globalvars->code_frame.need_recompile = true;
    } else if (std::string("Beat") == parameter->name) {
        globalvars->code_beat.need_recompile = true;
    }
    globalvars->recompile_if_needed();
}

E_GlobalVariables::E_GlobalVariables(AVS_Instance* avs)
    : Programmable_Effect(avs), is_first_frame(true), load_code_next_frame(false) {
    this->need_full_recompile();
    for (int i = 0; i < 10; i++) {
        this->config.file += (char)('a' + rand() % ('z' - 'a' + 1));
    }
    this->config.file += ".gvm";
}

E_GlobalVariables::~E_GlobalVariables() {
    for (auto range : this->reg_ranges) {
        delete[] range;
    }
    for (auto range : this->buf_ranges) {
        delete[] range;
    }
}

int E_GlobalVariables::render(char visdata[2][2][576],
                              int is_beat,
                              int*,
                              int*,
                              int w,
                              int h) {
    if (this->load_code_next_frame) {
        this->exec_code_from_file(visdata);
        this->load_code_next_frame = false;
    }
    this->recompile_if_needed();
    if (this->need_init) {
        this->code_init.exec(visdata);
        this->init_variables(w, h, is_beat & IS_BEAT_MASK, 5);
        this->need_init = false;
    }
    this->code_frame.exec(visdata);
    if (is_beat & IS_BEAT_MASK) {
        this->code_beat.exec(visdata);
    }
    if (this->config.load_time == GLOBALVARS_LOAD_FRAME
        || (this->config.load_time == GLOBALVARS_LOAD_CODE && *this->vars.load != 0.0)
        || this->is_first_frame) {
        this->load_code_next_frame = true;
    }
    if (*this->vars.save != 0.0) {
        this->save_ranges_to_file();
    }
    this->is_first_frame = false;
    return 0;
}

void GlobalVariables_Vars::register_(void* vm_context) {
    this->w = NSEEL_VM_regvar(vm_context, "w");
    this->h = NSEEL_VM_regvar(vm_context, "h");
    this->b = NSEEL_VM_regvar(vm_context, "b");
    this->load = NSEEL_VM_regvar(vm_context, "load");
    this->save = NSEEL_VM_regvar(vm_context, "save");
}

void GlobalVariables_Vars::init(int w, int h, int is_beat, va_list) {
    *this->w = w;
    *this->h = h;
    *this->b = is_beat ? 1.0f : 0.0f;
    *this->load = 0.0f;
    *this->save = 0.0f;
}

void E_GlobalVariables::exec_code_from_file(char visdata[2][2][576]) {
    FILE* file;
    size_t file_size;
    char* file_code;
    void* file_code_handle;

    file = fopen(this->config.file.c_str(), "r");
    if (!file) {
        return;
    }
    fseek(file, 0, SEEK_END);
    file_size = ftell(file);
    rewind(file);
    if (file_size > 0) {
        file_code = (char*)calloc((file_size + 1), sizeof(char));
        fread(file_code, sizeof(char), file_size, file);
    } else {
        return;
    }
    lock_lock(this->code_lock);
    file_code_handle = AVS_EEL_IF_Compile(this->avs, this->vm_context, file_code);
    if (file_code_handle) {
        AVS_EEL_IF_Execute(this->avs, file_code_handle, visdata);
    }
    NSEEL_code_free(file_code_handle);
    lock_unlock(this->code_lock);
    free(file_code);
}

bool compare_ranges(const void* a, const void* b) {
    return ((int*)a)[0] < ((int*)b)[0];
}

void E_GlobalVariables::save_ranges_to_file() {
    int i;
    FILE* file = fopen(this->config.file.c_str(), "w");
    if (!file) {
        return;
    }
    E_GlobalVariables::check_set_range(this->config.save_reg_ranges,
                                       this->reg_ranges,
                                       E_GlobalVariables::max_regs_index);
    std::sort(this->reg_ranges.begin(), this->reg_ranges.end(), compare_ranges);
    E_GlobalVariables::check_set_range(this->config.save_buf_ranges,
                                       this->buf_ranges,
                                       E_GlobalVariables::max_gmb_index);
    std::sort(this->buf_ranges.begin(), this->buf_ranges.end(), compare_ranges);
    i = 0;
    for (auto range : this->reg_ranges) {
        if (i < range[0]) {
            i = range[0];
        }
        while (i <= range[1]) {
            fprintf(file, "reg%02d=%0.6f;\n", i, E_GlobalVariables::reg_value(i));
            i++;
        }
    }
    i = 0;
    for (auto range : this->buf_ranges) {
        if (i < range[0]) {
            i = range[0];
        }
        while (i <= range[1]) {
            fprintf(file,
                    "assign(gmegabuf(%d),%0.6f);\n",
                    i,
                    E_GlobalVariables::buf_value(i));
            i++;
        }
    }
    fclose(file);
}

double E_GlobalVariables::reg_value(int index) {
    if (index >= 0 && index < 100) {
        return NSEEL_getglobalregs()[index];
    }
    return 0.0f;
}

double E_GlobalVariables::buf_value(int index) {
    if (index >= 0 && index <= E_GlobalVariables::max_gmb_index) {
        // return AVS_EEL_IF_gmb_value(index);
    }
    return 0.0f;
}

/* Check entered ranges for reg and gmegabuf values.

   Rough state machine:

   START ──"1...9"─▶ first number ─┬─"-"─▶ hyphen ──"1...9"─▶ second number ─┐
     ▲                             │                                         │
     └───────── comma ◀───","──────┘◀────────────────────────────────────────┘

   Additionally, spaces are ignored, and any other symbol than the ones indicated result
   in an abort and discards the current range. Previous valid ranges are kept. */
enum RangeCheckStates {
    RCS_START = 0,
    RCS_FIRST_NUM,
    RCS_HYPHEN,
    RCS_SECOND_NUM,
    RCS_COMMA,
};

bool E_GlobalVariables::check_set_range(const std::string& input,
                                        std::vector<int*>& ranges,
                                        int max_index) {
    RangeCheckStates state = RCS_START;
    int prev_number = -1;
    int number;
    std::string number_str;
    for (auto range : ranges) {
        delete[] range;
    }
    ranges.clear();
    for (auto c : input) {
        if (c >= '0' && c <= '9') {
            if (state == RCS_START) {
                state = RCS_FIRST_NUM;
            } else if (state == RCS_HYPHEN) {
                state = RCS_SECOND_NUM;
            }  // else `state` stays the same
            number_str += c;
        } else if (c == '-' && state == RCS_FIRST_NUM) {
            number = atoi(number_str.c_str());
            if (number > max_index) {
                return false;
            }
            prev_number = number;
            number_str.clear();
            state = RCS_HYPHEN;
        } else if (c == ',') {
            number = atoi(number_str.c_str());
            if (number > max_index) {
                return false;
            }
            if (state == RCS_FIRST_NUM) {
                prev_number = number;
            } else if (state == RCS_SECOND_NUM) {
                if (prev_number > number) {
                    return false;
                }
            } else {
                return false;
            }
            number_str.clear();
            state = RCS_COMMA;
        } else if (c == ' ') {
            continue;
        } else {
            return false;
        }
        if (state == RCS_COMMA) {
            ranges.push_back(new int[2]{prev_number, number});
            state = RCS_START;
        }
    }
    if (!number_str.empty()) {
        number = atoi(number_str.c_str());
        if (number > max_index) {
            return false;
        }
        if (state == RCS_FIRST_NUM) {
            prev_number = number;
        } else if (state == RCS_SECOND_NUM) {
            if (prev_number > number) {
                return false;
            }
        }
        if (prev_number < 0) {  // this should never occur, but let's be safe.
            prev_number = number;
        }
        ranges.push_back(new int[2]{prev_number, number});
    }
    return true;
}

void E_GlobalVariables::load_legacy(unsigned char* data, int len) {
    char* str = (char*)data;
    uint32_t pos = 0;
    this->config.load_time = (GlobalVariables_Load_Options)(*(int32_t*)data);
    pos += 4;
    // 24 bytes of unused (or unknown?) data
    pos += 24;
    pos += E_GlobalVariables::string_nt_load_legacy(
        &str[pos], this->config.init, len - pos);
    pos += E_GlobalVariables::string_nt_load_legacy(
        &str[pos], this->config.frame, len - pos);
    pos += E_GlobalVariables::string_nt_load_legacy(
        &str[pos], this->config.beat, len - pos);
    if (pos >= (uint32_t)max(0, len)) {
        return;
    }
    pos += E_GlobalVariables::string_nt_load_legacy(
        &str[pos], this->config.file, len - pos);
    if (pos >= (uint32_t)max(0, len)) {
        return;
    }
    pos += E_GlobalVariables::string_nt_load_legacy(
        &str[pos], this->config.save_reg_ranges, len - pos);
    if (pos >= (uint32_t)max(0, len)) {
        return;
    }
    E_GlobalVariables::check_set_range(this->config.save_reg_ranges,
                                       this->reg_ranges,
                                       E_GlobalVariables::max_regs_index);
    E_GlobalVariables::string_nt_load_legacy(
        &str[pos], this->config.save_buf_ranges, len - pos);
    E_GlobalVariables::check_set_range(this->config.save_buf_ranges,
                                       this->buf_ranges,
                                       E_GlobalVariables::max_gmb_index);
}

int E_GlobalVariables::save_legacy(unsigned char* data) {
    char* str = (char*)data;
    uint32_t pos = 0;
    *(int32_t*)data = (int)this->config.load_time;
    pos += 4;
    // 24 bytes of unused (or unknown?) data
    pos += 24;
    pos += E_GlobalVariables::string_nt_save_legacy(
        this->config.init, &str[pos], MAX_CODE_LEN - 1 - pos);
    pos += E_GlobalVariables::string_nt_save_legacy(
        this->config.frame, &str[pos], MAX_CODE_LEN - 1 - pos);
    pos += E_GlobalVariables::string_nt_save_legacy(
        this->config.beat, &str[pos], MAX_CODE_LEN - 1 - pos);
    pos += E_GlobalVariables::string_nt_save_legacy(
        this->config.file, &str[pos], MAX_CODE_LEN - 1 - pos);
    pos += E_GlobalVariables::string_nt_save_legacy(
        this->config.save_reg_ranges, &str[pos], MAX_CODE_LEN - 1 - pos);
    pos += E_GlobalVariables::string_nt_save_legacy(
        this->config.save_buf_ranges, &str[pos], MAX_CODE_LEN - 1 - pos);
    return (int)pos;
}

Effect_Info* create_GlobalVariables_Info() { return new GlobalVariables_Info(); }
Effect* create_GlobalVariables(AVS_Instance* avs) { return new E_GlobalVariables(avs); }
void set_GlobalVariables_desc(char* desc) { E_GlobalVariables::set_desc(desc); }
