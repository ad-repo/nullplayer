#pragma once

#include "effect.h"
#include "effect_info.h"
#include "effect_programmable.h"

#include "../platform.h"

#include <string>

struct SuperScope_Color_Config : public Effect_Config {
    uint64_t color = 0x000000;
    SuperScope_Color_Config() = default;
    SuperScope_Color_Config(uint64_t color) : color(color) {}
};

struct SuperScope_Config : public Effect_Config {
    std::string init = "n=800";
    std::string frame = "t=t-0.05";
    std::string beat = "";
    std::string point = "d=i+v*0.2; r=t+i*$PI*4; x=cos(r)*d; y=sin(r)*d";
    std::vector<SuperScope_Color_Config> colors;
    int64_t audio_source = 0;
    int64_t audio_channel = 0;
    int64_t draw_mode = 0;
    int64_t example = 0;
    SuperScope_Config() { this->colors.emplace_back(0xffffff); }
};

struct SuperScope_Example {
    const char* name;
    const char* init;
    const char* frame;
    const char* beat;
    const char* point;
};

struct SuperScope_Info : public Effect_Info {
    static constexpr char const* group = "Render";
    static constexpr char const* name = "SuperScope";
    static constexpr char const* help =
        "Superscope tutorial goes here\r\n"
        "But for now, here is the old text:\r\n"
        "You can specify expressions that run on Init, Frame, and on Beat.\r\n"
        "  'n' specifies the number of points to render (set this in Init, Beat, or "
        "Frame).\r\n"
        "For the 'Per Point' expression (which happens 'n' times per frame), use:\r\n"
        "  'x' and 'y' are the coordinates to draw to (-1..1)\r\n"
        "  'i' is the position of the scope (0..1)\r\n"
        "  'v' is the value at that point (-1..1).\r\n"
        "  'b' is 1 if beat, 0 if not.\r\n"
        "  'red', 'green' and 'blue' are all (0..1) and can be modified\r\n"
        "  'linesize' can be set from 1.0 to 255.0\r\n"
        "  'skip' can be set to >0 to skip drawing the current item\r\n"
        "  'drawmode' can be set to > 0 for lines, <= 0 for points\r\n"
        "  'w' and 'h' are the width and height of the screen, in pixels.\r\n"
        " Anybody want to send me better text to put here? Please :)\r\n";
    static constexpr int32_t legacy_id = 36;
    static constexpr char* legacy_ape_id = NULL;

    static constexpr int32_t num_examples = 14;
    static constexpr SuperScope_Example examples[num_examples] = {
        {
            "Spiral",
            "n=800",
            "t=t-0.05",
            "",
            "d=i+v*0.2; r=t+i*$PI*4; x=cos(r)*d; y=sin(r)*d",
        },
        {
            "3D Scope Dish",
            "n=200",
            "",
            "",
            "iz=1.3+sin(r+i*$PI*2)*(v+0.5)*0.88; ix=cos(r+i*$PI*2)*(v+0.5)*.88;"
            " iy=-0.3+abs(cos(v*$PI)); x=ix/iz;y=iy/iz;",
        },
        {
            "Rotating Bow Thing",
            "n=80;t=0.0;",
            "t=t+0.01",
            "",
            "r=i*$PI*2; d=sin(r*3)+v*0.5; x=cos(t+r)*d; y=sin(t-r)*d",
        },
        {
            "Vertical Bouncing Scope",
            "n=100; t=0; tv=0.1;dt=1;",
            "t=t*0.9+tv*0.1",
            "tv=((rand(50.0)/50.0))*dt; dt=-dt;",
            "x=t+v*pow(sin(i*$PI),2); y=i*2-1.0;",
        },
        {
            "Spiral Graph Fun",
            "n=100;t=0;",
            "t=t+0.01;",
            "n=80+rand(120.0)",
            "r=i*$PI*128+t; x=cos(r/64)*0.7+sin(r)*0.3; y=sin(r/64)*0.7+cos(r)*0.3",
        },
        {
            "Alternating Diagonal Scope",
            "n=64; t=1;",
            "",
            "t=-t;",
            "sc=0.4*sin(i*$PI); x=2*(i-0.5-v*sc)*t; y=2*(i-0.5+v*sc);",
        },
        {
            "Vibrating Worm",
            "n=w; dt=0.01; t=0; sc=1;",
            "t=t+dt;dt=0.9*dt+0.001; t=if(above(t,$PI*2),t-$PI*2,t);",
            "dt=sc;sc=-sc;",
            "x=cos(2*i+t)*0.9*(v*0.5+0.5); y=sin(i*2+t)*0.9*(v*0.5+0.5);",
        },
        {
            "Wandering Simple",
            "n=800;xa=-0.5;ya=0.0;xb=-0.0;yb=0.75;c=200;f=0;\r\n"
            "nxa=(rand(100)-50)*.02;nya=(rand(100)-50)*.02;\r\n"
            "nxb=(rand(100)-50)*.02;nyb=(rand(100)-50)*.02;",
            "f=f+1;\r\n"
            "t=1-((cos((f*3.1415)/c)+1)*.5);\r\n"
            "xa=((nxa-lxa)*t)+lxa;\r\n"
            "ya=((nya-lya)*t)+lya;\r\n"
            "xb=((nxb-lxb)*t)+lxb;\r\n"
            "yb=((nyb-lyb)*t)+lyb;\r\n"
            "ex=(xb-xa);\r\n"
            "ey=(yb-ya);\r\n"
            "d=sqrt(sqr(ex)+sqr(ey));\r\n"
            "r=atan(ey/ex)+(3.1415/2);\r\n"
            "dv=d*2",
            "c=f;\r\n"
            "f=0;\r\n"
            "lxa=nxa;\r\n"
            "lya=nya;\r\n"
            "lxb=nxb;\r\n"
            "lyb=nyb;\r\n"
            "nxa=(rand(100)-50)*.02;\r\n"
            "nya=(rand(100)-50)*.02;\r\n"
            "nxb=(rand(100)-50)*.02;\r\n"
            "nyb=(rand(100)-50)*.02",
            "//primary render\r\n"
            "x=(ex*i)+xa;\r\n"
            "y=(ey*i)+ya;\r\n"
            "\r\n"
            "//volume offset\r\n"
            "x=x+ ( cos(r) * v * dv);\r\n"
            "y=y+ ( sin(r) * v * dv);\r\n"
            "\r\n"
            "//color values\r\n"
            "red=i;\r\n"
            "green=(1-i);\r\n"
            "blue=abs(v*6);",
        },
        {
            "Flitterbug",
            "n=180;t=0.0;lx=0;ly=0;vx=rand(200)-100;vy=rand(200)-100;cf=.97;c=200;f=0",
            "x=nx;y=ny;\r\n"
            "r=i*3.14159*2; f=f+1;t=(f*2*3.1415)/c;\r\n"
            "vx=(vx-(lx*.1))*cf;\r\n"
            "vy=(vy-(ly*.1))*cf;\r\n"
            "lx=lx+vx;ly=ly+vy;\r\n"
            "nx=lx*.001;ny=ly*.001;\r\n"
            "s=abs(nx*ny)",
            "c=f;f=0;\r\n"
            "vx=vx+rand(600)-300;vy=vy+rand(600)-300",
            "d=(sin(r*5*(1-s))+i*0.5)*(.3-s);\r\n"
            "tx=(t*(1-(s*(i-.5))));\r\n"
            "x=x+cos(tx+r)*d; y=y+sin(t-y)*d;\r\n"
            "red=abs(x-nx)*5;\r\n"
            "green=abs(y-ny)*5;\r\n"
            "blue=1-s-red-green;",
        },
        {
            "Spirostar",
            "n=20;t=0;f=0;c=200;mn=10;dv=2;dn=0",
            "f=f+1;t=(f*3.1415*2)/c;\r\n"
            "sz=abs(sin(t-3.1415));\r\n"
            "dv=if(below(n,12),(n/2)-1,\r\n"
            "    if(equal(12,n),3,\r\n"
            "    if(equal(14,n),6,\r\n"
            "    if(below(n,20),2,4))))",
            "bb = bb + 1;\r\n"
            "beatdiv = 8;\r\n"
            "c=if(equal(bb%beatdiv,0),f,c);\r\n"
            "f=if(equal(bb%beatdiv,0),0,f);\r\n"
            "g=if(equal(bb%beatdiv,0),g+1,g);\r\n"
            "n=if(equal(bb%beatdiv,0),(abs((g%17)-8) *2)+4,n);",
            "r=if(b,0,((i*dv)*3.14159*128)+(t/2));\r\n"
            "x=cos(r)*sz;\r\n"
            "y=sin(r)*sz;",
        },
        {
            "Exploding Daisy",
            "n = 380 + rand(200) ; k = 0.0; l = 0.0; m = ( rand( 10 ) + 2 ) * .5;"
            " c = 0; f = 0",
            "a = a + 0.002 ; k = k + 0.04 ; l = l + 0.03",
            "bb = bb + 1;\r\n"
            "beatdiv = 16;\r\n"
            "n=if(equal(bb%beatdiv,0),380 + rand(200),n);\r\n"
            "t=if(equal(bb%beatdiv,0),0.0,t);\r\n"
            "a=if(equal(bb%beatdiv,0),0.0,a);\r\n"
            "k=if(equal(bb%beatdiv,0),0.0,k);\r\n"
            "l=if(equal(bb%beatdiv,0),0.0,l);\r\n"
            "m=if(equal(bb%beatdiv,0),(( rand( 100  ) + 2 ) * .1) + 2,m);",
            "r=(i*3.14159*2)+(a * 3.1415);\r\n"
            "d=sin(r*m)*.3;\r\n"
            "x=cos(k+r)*d*2;y=(  (sin(k-r)*d) + ( sin(l*(i-.5) ) ) ) * .7;\r\n"
            "red=abs(x);\r\n"
            "green=abs(y);\r\n"
            "blue=d",
        },
        {
            "Swirlie Dots",
            "n=45;t=rand(100);u=rand(100)",
            "t = t + .15; u = u + .05",
            "bb = bb + 1;\r\n"
            "beatdiv = 16;\r\n"
            "n = if(equal(bb%beatdiv,0),30 + rand( 30 ),n);",
            "di = ( i - .5) * 2;\r\n"
            "x = di;sin(u*di) * .4;\r\n"
            "y = cos(u*di) * .6;\r\n"
            "x = x + ( cos(t) * .05 );\r\n"
            "y = y + ( sin(t) * .05 );",
        },
        {
            "Sweep",
            "n=180;lsv=100;sv=200;ssv=200;c=200;f=0",
            "f=f+1;t=(f*2*3.1415)/c;\r\n"
            "lsv=slsv;sv=ssv;fv=0",
            "bb = bb + 1;\r\n"
            "beatdiv = 8;\r\n"
            "c=if(equal(bb%beatdiv,0),f,c);\r\n"
            "f=if(equal(bb%beatdiv,0),0,f);\r\n"
            "dv=if(equal(bb%beatdiv,0),((rand(100)*.01) * .1) + .02,dv);\r\n"
            "n=if(equal(bb%beatdiv,0),80+rand(100),n);\r\n"
            "ssv=if(equal(bb%beatdiv,0),rand(200)+100,ssv);\r\n"
            "slsv=if(equal(bb%beatdiv,0),rand(200)+100,slsv);",
            "sv=(sv*abs(cos(lsv)))+(lsv*abs(cos(sv)));\r\n"
            "fv=fv+(sin(sv)*dv);\r\n"
            "d=i; r=t+(fv * sin(t) * .3)*3.14159*4;\r\n"
            "x=cos(r)*d;\r\n"
            "y=sin(r)*d;\r\n"
            "red=i;\r\n"
            "green=abs(sin(r))-(red*.15);\r\n"
            "blue=fv",
        },
        {
            "Whiplash Spiral",
            "n=80;c=200;f=0",
            "t=t-0.05;f=f+1;dt=(f*2*3.1415)/c",
            "bb = bb + 1;\r\n"
            "beatdiv = 8;\r\n"
            "c=if(equal(bb%beatdiv,0),f,c);\r\n"
            "f=if(equal(bb%beatdiv,0),0,f);",
            "d=i;\r\n"
            "r=t+i*3.14159*4;\r\n"
            "sdt=sin(dt+(i*3.1415*2));\r\n"
            "cdt=cos(dt+(i*3.1415*2));\r\n"
            "x=(cos(r)*d) + (sdt * .6 * sin(t) );\r\n"
            "y=(sin(r)*d) + ( cdt *.6 * sin(t) );\r\n"
            "blue=abs(x);\r\n"
            "green=abs(y);\r\n"
            "red=cos(dt*4)",
        },
    };

    static const char* const* sources(int64_t* length_out) {
        *length_out = 2;
        static const char* const options[2] = {"Waveform", "Spectrum"};
        return options;
    }
    static const char* const* channels(int64_t* length_out) {
        *length_out = 3;
        static const char* const options[3] = {"Center", "Left", "Right"};
        return options;
    }
    static const char* const* drawmodes(int64_t* length_out) {
        *length_out = 2;
        static const char* const options[2] = {"Dots", "Lines"};
        return options;
    }
    static const char* const* example_names(int64_t* length_out) {
        *length_out = 14;
        static const char* const options[14] = {
            examples[0].name,
            examples[1].name,
            examples[2].name,
            examples[3].name,
            examples[4].name,
            examples[5].name,
            examples[6].name,
            examples[7].name,
            examples[8].name,
            examples[9].name,
            examples[10].name,
            examples[11].name,
            examples[12].name,
            examples[13].name,
        };
        return options;
    }

    static constexpr uint32_t num_color_params = 1;
    static constexpr Parameter color_params[num_color_params] = {
        P_COLOR(offsetof(SuperScope_Color_Config, color), "Color"),
    };

    static void recompile(Effect*, const Parameter*, const std::vector<int64_t>&);
    static void load_example(Effect*, const Parameter*, const std::vector<int64_t>&);
    static constexpr uint32_t num_parameters = 10;
    static constexpr Parameter parameters[num_parameters] = {
        P_STRING(offsetof(SuperScope_Config, init), "Init", NULL, recompile),
        P_STRING(offsetof(SuperScope_Config, frame), "Frame", NULL, recompile),
        P_STRING(offsetof(SuperScope_Config, beat), "Beat", NULL, recompile),
        P_STRING(offsetof(SuperScope_Config, point), "Point", NULL, recompile),
        P_LIST<SuperScope_Color_Config>(offsetof(SuperScope_Config, colors),
                                        "Colors",
                                        color_params,
                                        num_color_params,
                                        1,
                                        16),
        P_SELECT(offsetof(SuperScope_Config, audio_source), "Audio Source", sources),
        P_SELECT(offsetof(SuperScope_Config, audio_channel), "Audio Channel", channels),
        P_SELECT(offsetof(SuperScope_Config, draw_mode), "Draw Mode", drawmodes),
        P_SELECT_X(offsetof(SuperScope_Config, example), "Example", example_names),
        P_ACTION("Load Example", load_example, "Load the selected example code"),
    };

    EFFECT_INFO_GETTERS;
};

struct SuperScope_Vars : public Variables {
    double* n;
    double* b;
    double* x;
    double* y;
    double* i;
    double* v;
    double* w;
    double* h;
    double* red;
    double* green;
    double* blue;
    double* linesize;
    double* skip;
    double* drawmode;

    virtual void register_(void*);
    virtual void init(int, int, int, va_list);
};

class E_SuperScope
    : public Programmable_Effect<SuperScope_Info, SuperScope_Config, SuperScope_Vars> {
   public:
    E_SuperScope(AVS_Instance* avs);
    virtual ~E_SuperScope();
    virtual int render(char visdata[2][2][576],
                       int is_beat,
                       int* framebuffer,
                       int* fbout,
                       int w,
                       int h);
    virtual void load_legacy(unsigned char* data, int len);
    virtual int save_legacy(unsigned char* data);
    virtual E_SuperScope* clone() { return new E_SuperScope(*this); }

    uint32_t color_pos;
};
