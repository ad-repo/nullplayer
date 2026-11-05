#pragma once

#include "effect.h"
#include "effect_info.h"

struct Normalise_Config : public Effect_Config {};

struct Normalise_Info : public Effect_Info {
    static constexpr char const* group = "Trans";
    static constexpr char const* name = "Normalise";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = -1;
    static constexpr char* legacy_ape_id = "Trans: Normalise";

    EFFECT_INFO_GETTERS_NO_PARAMETERS;
};

class E_Normalise : public Configurable_Effect<Normalise_Info, Normalise_Config> {
   public:
    E_Normalise(AVS_Instance* avs);
    virtual ~E_Normalise();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Normalise* clone() { return new E_Normalise(*this); }

   protected:
    int scan_min_max(int* framebuffer,
                     int fb_length,
                     unsigned char* max_out,
                     unsigned char* min_out);
    int scan_min_max_sse2(int* framebuffer,
                          int fb_length,
                          unsigned char* max_out,
                          unsigned char* min_out);
    void make_scale_table(unsigned char max,
                          unsigned char min,
                          unsigned int scale_table_out[]);
    void apply(int* framebuffer, int fb_length, unsigned int scale_table[]);
};
