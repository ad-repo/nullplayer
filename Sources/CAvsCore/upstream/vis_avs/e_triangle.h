#pragma once

#include "effect.h"
#include "effect_info.h"
#include "effect_programmable.h"

#include <string>

struct Triangle_Config : public Effect_Config {
    std::string init = "";
    std::string frame = "";
    std::string beat = "";
    std::string point = "";
};

struct Triangle_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "Triangle";
    static constexpr char const* help = "";
    static constexpr int32_t legacy_id = -1;
    static constexpr char* legacy_ape_id = "Render: Triangle";

    static void recompile(Effect*, const Parameter*, const std::vector<int64_t>&);
    static constexpr uint32_t num_parameters = 4;
    static constexpr Parameter parameters[num_parameters] = {
        P_STRING(offsetof(Triangle_Config, init), "Init", NULL, recompile),
        P_STRING(offsetof(Triangle_Config, frame), "Frame", NULL, recompile),
        P_STRING(offsetof(Triangle_Config, beat), "Beat", NULL, recompile),
        P_STRING(offsetof(Triangle_Config, point), "Triangle", NULL, recompile),
    };

    EFFECT_INFO_GETTERS;
};

struct Triangle_Vars : public Variables {
    double* w;
    double* h;
    double* n;
    double* i;
    double* skip;
    double* x1;
    double* y1;
    double* red1;
    double* green1;
    double* blue1;
    double* x2;
    double* y2;
    double* red2;
    double* green2;
    double* blue2;
    double* x3;
    double* y3;
    double* red3;
    double* green3;
    double* blue3;
    double* z1;
    double* zbuf;
    double* zbclear;

    virtual void register_(void*);
    virtual void init(int, int, int, va_list);
};

class TriangleDepthBuffer {
   public:
    unsigned int w;
    unsigned int h;
    unsigned int* buffer;

    TriangleDepthBuffer(unsigned int w, unsigned int h);
    ~TriangleDepthBuffer();
    void reset_if_needed(unsigned int w, unsigned int h, bool clear);
};

typedef struct {
    int x;
    int y;
    uint64_t z;
} Vertex;

class E_Triangle
    : public Programmable_Effect<Triangle_Info, Triangle_Config, Triangle_Vars> {
   public:
    E_Triangle(AVS_Instance* avs);
    virtual ~E_Triangle();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_Triangle* clone() { return new E_Triangle(*this); }

   private:
    static unsigned int instance_count;
    static TriangleDepthBuffer* depth_buffer;
    bool need_depth_buffer = false;
    void init_depthbuffer_if_needed(int w, int h);
    inline void draw_triangle(int* framebuffer,
                              int w,
                              int h,
                              Vertex vertices[3],
                              bool use_depthbuffer,
                              unsigned int color);
    inline void draw_line(int* framebuffer,
                          int fb_index,
                          int startx,
                          int endx,
                          uint64_t z,
                          int w,
                          bool use_depthbuffer,
                          unsigned int color);
    inline void sort_vertices(Vertex vertices[3]);
};
