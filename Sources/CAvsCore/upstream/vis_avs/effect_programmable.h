#pragma once

#include "avs_eelif.h"
#include "effect.h"
#include "effect_info.h"

#include "../platform.h"

#include <stdarg.h>
#include <string.h>
#include <string>

// Legacy maximum code section length (for legacy preset files)
#define MAX_CODE_LEN (1 << 16)

/**
 * Inherit from `Variables` to define available EEL variables:
 *
 *     #include "avs_eelif.h"  // for NSEEL_VM_regvar()
 *
 *     struct My_Vars : public Variables {
 *        public:
 *         double* w;
 *         double* h;
 *         double* n;
 *         double* stuff;
 *         double* things;
 *
 *         virtual void register_(void* vm_context) {
 *             this->w = NSEEL_VM_regvar(vm_context, "w");
 *             this->h = NSEEL_VM_regvar(vm_context, "h");
 *             this->n = NSEEL_VM_regvar(vm_context, "n");
 *             this->stuff = NSEEL_VM_regvar(vm_context, "stuff");
 *             this->things = NSEEL_VM_regvar(vm_context, "t"); // Can have other name.
 *         };
 *
 *         virtual void init(int w, int h, int is_beat, va_list extra_args) {
 *             *this->w = w;
 *             *this->h = h;
 *             *this->n = 0.0f;
 *             *this->stuff = va_arg(extra_args, int);
 *             *this->things = va_arg(extra_args, double);
 *         };
 *     }
 *
 * Now, in your Effect class inheriting from `Programmable_Effect`,
 *
 *    class My_Effect : public Programmable_Effect<My_Info, My_Config, My_Vars> {
 *        // ...
 *    }
 *
 * you can call (probably from within `render()`):
 *
 *    this->init_variables(w, h, is_beat, stuff, things);
 *
 * If using `extra_args` pay attention to the order of the arguments and their retrieval
 * in your Variables' `init()` method.
 */
struct Variables {
    virtual void register_(void* vm_context) = 0;
    // Overriding this method is not strictly necessary, but probably helpful.
    // Pass in additional parameters to your effect's `init_variables()` as needed, and
    // retrieve them with va_arg() like above.
    virtual void init(int w, int h, int is_beat, va_list) {
        (void)w, (void)h, (void)is_beat;
    }
};

class Code_Section {
   private:
    AVS_Instance* avs;
    void*& vm_context;
    void* code = nullptr;
    std::string& code_str;
    lock_t* code_lock = nullptr;

   public:
    bool need_recompile = false;

    Code_Section(AVS_Instance* avs,
                 void*& vm_context,
                 std::string& code_str,
                 lock_t* code_lock)
        : avs(avs), vm_context(vm_context), code_str(code_str), code_lock(code_lock) {}
    ~Code_Section() { NSEEL_code_free(this->code); }
    Code_Section(const Code_Section& other)
        : avs(other.avs),
          vm_context(other.vm_context),
          code_str(other.code_str),
          code_lock(other.code_lock),
          need_recompile(other.need_recompile) {}
    Code_Section& operator=(const Code_Section& other) {
        Code_Section tmp(other);
        this->swap(tmp);
        return *this;
    }
    Code_Section(Code_Section&& other) noexcept
        : avs(other.avs), vm_context(other.vm_context), code_str(other.code_str) {
        this->swap(other);
    }

    Code_Section& operator=(Code_Section&& other) noexcept {
        this->swap(other);
        return *this;
    }
    void swap(Code_Section& other) noexcept {
        std::swap(this->avs, other.avs);
        std::swap(this->vm_context, other.vm_context);
        std::swap(this->code, other.code);
        std::swap(this->code_str, other.code_str);
        std::swap(this->code_lock, other.code_lock);
        std::swap(this->need_recompile, other.need_recompile);
    }

    bool recompile_if_needed() {
        if (!this->need_recompile) {
            return false;
        }
        // log_info("Compiling code: %s", this->code_str.c_str());
        NSEEL_code_free(this->code);
        this->code = AVS_EEL_IF_Compile(
            this->avs, this->vm_context, (char*)this->code_str.c_str());
        this->need_recompile = false;
        return true;
    }
    void exec(char visdata[2][2][576]) {
        if (this->code == NULL) {
            return;
        }
        lock_lock(this->code_lock);
        AVS_EEL_IF_Execute(this->avs, this->code, visdata);
        lock_unlock(this->code_lock);
    }
    bool is_valid() { return this->code != NULL; }
};

template <class Info_T,
          class Config_T,
          class Vars_T,
          class Global_Config_T = Effect_Config>
class Programmable_Effect
    : public Configurable_Effect<Info_T, Config_T, Global_Config_T> {
    typedef Configurable_Effect<Info_T, Config_T, Global_Config_T> Super;

   protected:
    void* vm_context = nullptr;
    lock_t* code_lock;

   public:
    Vars_T vars;
    Code_Section code_init;
    Code_Section code_frame;
    Code_Section code_beat;
    Code_Section code_point;
    bool need_init = true;

    explicit Programmable_Effect(AVS_Instance* avs)
        : Super(avs),
          code_lock(lock_init()),
          code_init(this->avs, this->vm_context, this->config.init, this->code_lock),
          code_frame(this->avs, this->vm_context, this->config.frame, this->code_lock),
          code_beat(this->avs, this->vm_context, this->config.beat, this->code_lock),
          code_point(this->avs, this->vm_context, this->config.point, this->code_lock) {
    }
    ~Programmable_Effect() {
        NSEEL_VM_free(this->vm_context);
        lock_destroy(this->code_lock);
    }
    Programmable_Effect(const Programmable_Effect& other)
        : Super(other),
          code_lock(lock_init()),
          code_init(this->avs, this->vm_context, this->config.init, this->code_lock),
          code_frame(this->avs, this->vm_context, this->config.init, this->code_lock),
          code_beat(this->avs, this->vm_context, this->config.init, this->code_lock),
          code_point(this->avs, this->vm_context, this->config.init, this->code_lock) {}
    Programmable_Effect& operator=(const Programmable_Effect& other) {
        Programmable_Effect tmp(other);
        this->swap(tmp);
        return *this;
    }
    Programmable_Effect(Programmable_Effect&& other) noexcept
        : Super(std::move(other)) {
        this->swap(other);
    }
    Programmable_Effect& operator=(Programmable_Effect&& other) noexcept {
        Super::operator=(std::move(other));
        std::swap(this->config, other.config);
        return *this;
    }

    void need_full_recompile() {
        this->code_init.need_recompile = true;
        this->code_frame.need_recompile = true;
        this->code_beat.need_recompile = true;
        this->code_point.need_recompile = true;
    }

    bool recompile_if_needed() {
        lock_lock(this->code_lock);
        if (this->vm_context == NULL) {
            this->vm_context = NSEEL_VM_alloc();
            if (this->vm_context == NULL) {
                lock_unlock(this->code_lock);
                return false;
            }
            this->vars.register_(this->vm_context);
        }
        bool any_recompiled = false;
        if (this->code_init.recompile_if_needed()) {
            this->need_init = true;
            any_recompiled = true;
        }
        any_recompiled |= this->code_frame.recompile_if_needed();
        any_recompiled |= this->code_beat.recompile_if_needed();
        any_recompiled |= this->code_point.recompile_if_needed();
        lock_unlock(this->code_lock);
        return any_recompiled;
    }

    void reset_code_context() {
        lock_lock(this->code_lock);
        NSEEL_VM_free(this->vm_context);
        this->vm_context = NULL;
        lock_unlock(this->code_lock);
    }

    virtual void init_variables(int w, int h, int is_beat, ...) {
        va_list extra_args;
        va_start(extra_args, is_beat);
        this->vars.init(w, h, is_beat, extra_args);
        va_end(extra_args);
    }

    virtual void on_load() { this->need_full_recompile(); }

   protected:
    void swap(Programmable_Effect& other) {
        std::swap(this->vm_context, other.vm_context);
        std::swap(this->code_lock, other.code_lock);
        std::swap(this->code_init, other.code_init);
        std::swap(this->code_frame, other.code_frame);
        std::swap(this->code_beat, other.code_beat);
        std::swap(this->code_point, other.code_point);
        std::swap(this->need_init, other.need_init);
    }
};
