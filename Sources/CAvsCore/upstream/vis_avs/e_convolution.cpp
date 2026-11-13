// convolution filter
// copyright tom holden, 2002
// mail: cfp@myrealbox.com

#include "e_convolution.h"

#include "constants.h"

#include <cstdint>
#include <cstdlib>

#define MAX_DRAW_SIZE 16384

#define GET_INT() \
    (data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24))

#define PUT_INT(y) /* NullPlayer: (y) parenthesised in every byte */ \
    data[pos] = (y) & 255;           \
    data[pos + 1] = ((y) >> 8) & 255;  \
    data[pos + 2] = ((y) >> 16) & 255; \
    data[pos + 3] = ((y) >> 24) & 255

constexpr Parameter Convolution_Info::kernel_params[];
constexpr Parameter Convolution_Info::parameters[];

void Convolution_Info::update_kernel(Effect* component,
                                     const Parameter*,
                                     const std::vector<int64_t>&) {
    ((E_Convolution*)component)->need_draw_update = true;
}

void Convolution_Info::on_wrap_or_absolute_change(Effect* component,
                                                  const Parameter* parameter,
                                                  const std::vector<int64_t>&) {
    ((E_Convolution*)component)
        ->check_mutually_exclusive_abs_wrap(std::string("Wrap") == parameter->name);
    Convolution_Info::update_kernel(component, nullptr, {});
}

void Convolution_Info::on_scale_change(Effect* component,
                                       const Parameter*,
                                       const std::vector<int64_t>&) {
    ((E_Convolution*)component)->check_scale_not_zero();
    Convolution_Info::update_kernel(component, nullptr, {});
}

void Convolution_Info::autoscale(Effect* component,
                                 const Parameter*,
                                 const std::vector<int64_t>&) {
    ((E_Convolution*)component)->autoscale();
}

void Convolution_Info::kernel_clear(Effect* component,
                                    const Parameter*,
                                    const std::vector<int64_t>&) {
    ((E_Convolution*)component)->kernel_clear();
}

void Convolution_Info::kernel_save(Effect* component,
                                   const Parameter*,
                                   const std::vector<int64_t>&) {
    ((E_Convolution*)component)->kernel_save();
}

void Convolution_Info::kernel_load(Effect* component,
                                   const Parameter*,
                                   const std::vector<int64_t>&) {
    ((E_Convolution*)component)->kernel_load();
}

E_Convolution::E_Convolution(AVS_Instance* avs)
    : Configurable_Effect(avs),
      draw(nullptr),
      m64_farray(),
      m64_bias(),
      width(0),
      height(0),
      draw_created(false),
      need_draw_update(true),
      code_length(0) {
    this->config.scale = 1;
}

E_Convolution::~E_Convolution() { delete_draw_func(); }

inline void E_Convolution::delete_draw_func(void) {
    if (this->draw_created) {
        delete[] (unsigned char*)draw;
        this->draw_created = false;
    }
}

void E_Convolution::check_scale_not_zero() {
    if (this->config.scale == 0) {
        this->config.scale = 1;
    }
}

void E_Convolution::check_mutually_exclusive_abs_wrap(bool wrap_changed_last) {
    if (this->config.wrap && this->config.absolute) {
        if (wrap_changed_last) {
            this->config.absolute = false;
        } else {
            this->config.wrap = false;
        }
    }
}

void E_Convolution::autoscale() {
    int64_t sum = 0;
    for (int i = 0; i < CONVO_KERNEL_SIZE; i++) {
        sum += this->config.kernel[i].value;
    }
    sum += this->config.bias;
    if (this->config.two_pass) {
        sum *= 2;
    }
    if (sum == 0) {
        sum = 1;
    }
    this->config.scale = sum;
}

void E_Convolution::kernel_clear() {
    for (int i = 0; i < CONVO_KERNEL_SIZE; ++i) {
        this->config.kernel[i].value = (i == (CONVO_KERNEL_SIZE / 2)) ? 1 : 0;
    }
    this->config.wrap = false;
    this->config.absolute = false;
    this->config.two_pass = false;
    this->config.bias = 0;
    this->config.scale = 1;
    this->need_draw_update = true;
}

// #define data(xx, yy) framebuffer[c[yy] + min(max(i + xx, 0), lastcol)]
// #define scale(out) min(max((long)((out+farray[25])/this->config.scale),0),255)
// #define bound(xx) min(max(xx, 0), 255)

int E_Convolution::render(char[2][2][576],
                          int,
                          int* framebuffer,
                          int* fbout,
                          int w,
                          int h) {
    if ((w != this->width) || (h != this->height)) {
        this->width = w;
        this->height = h;
        this->need_draw_update = true;
    }
#if !defined(__i386__) && !defined(_M_IX86)
    // NullPlayer: create_draw_func() JITs 32-bit x86 machine code, which cannot run on
    // arm64/x86_64; upstream_port/convolution_portable.cpp computes what that code computes.
    if (this->need_draw_update) {
        this->portable.plan(this->config);
        this->need_draw_update = false;
    }
    return this->portable.apply(framebuffer, fbout, w, h);
#endif
    if (this->need_draw_update) {
        this->create_draw_func();
    }
    return this->draw(framebuffer, fbout, this->m64_farray);
}

#define appenddraw(a) ((unsigned char*)draw)[this->code_length++] = a

void E_Convolution::create_draw_func() {
    this->delete_draw_func();
    unsigned int possum = 0, negsum = 0;  // absolute sums of pos and neg values
    int zerostringl = 0;                  // length of the initial run of zeroes
    int numpos = 0;                       // number of pos entries
    int numneg = 0;                       // number of neg entries
    bool zerostring = true;               // are we still in an initial zero run
    unsigned int fposdata[2][CONVO_KERNEL_SIZE][3];
    // for each pass, will contain the x and y co-ords and the value of the
    // pos data elements. e.g.
    // this->config.kernel[ 7*fposdata[pass][i][1] + fposdata[pass][i][0] ] =
    // fposdata[pass][i][2]>0
    unsigned int fnegdata[2][CONVO_KERNEL_SIZE][3];
    // for each pass, will contain the x and y co-ords and the absolute value
    // of the neg data elements. e.g.
    // abs(this->config.kernel[ 7*fnegdata[pass][i][1] + fnegdata[i][0] ]) =
    // fnegdata[pass][i][2]>0
    uint8_t use_fbout;  // 1 if need to use fbout
    int divisionfactor = (int32_t)this->config.scale;
    this->need_draw_update = false;
    for (int i = 0; i < CONVO_KERNEL_SIZE; i++) {
        if (this->config.kernel[i].value < 0) {
            negsum -= this->config.kernel[i].value;
            zerostring = false;
            this->m64_farray[i] =
                _mm_set1_pi16(((int16_t)(-this->config.kernel[i].value)));
        } else if (this->config.kernel[i].value > 0) {
            possum += this->config.kernel[i].value;
            zerostring = false;
            this->m64_farray[i] =
                _mm_set1_pi16(((int16_t)(this->config.kernel[i].value)));
        } else {
            if (zerostring) {
                zerostringl++;
            }
            this->m64_farray[i] = _mm_setzero_si64();
        }
    }
    if (this->config.bias < 0) {
        negsum -= this->config.bias;
        this->m64_bias = _mm_set1_pi16(((int16_t)(-256 * this->config.bias)));
    } else {
        possum += this->config.bias;
        this->m64_bias = _mm_set1_pi16(((int16_t)(256 * this->config.bias)));
    }
    _mm_empty();
    if (divisionfactor > 0) {
        // no sign swapping necessary
        for (int i = 0; i < CONVO_KERNEL_SIZE; i++) {
            if (this->config.kernel[i].value < 0) {
                fnegdata[0][numneg][0] = i % CONVO_KERNEL_DIM;
                fnegdata[0][numneg][1] = i / CONVO_KERNEL_DIM;
                fnegdata[0][numneg][2] = -this->config.kernel[i].value;
                fnegdata[1][numneg][0] = 6 - i / CONVO_KERNEL_DIM;
                fnegdata[1][numneg][1] = i % CONVO_KERNEL_DIM;
                fnegdata[1][numneg][2] = -this->config.kernel[i].value;
                numneg++;
            } else if (this->config.kernel[i].value > 0) {
                fposdata[0][numpos][0] = i % CONVO_KERNEL_DIM;
                fposdata[0][numpos][1] = i / CONVO_KERNEL_DIM;
                fposdata[0][numpos][2] = this->config.kernel[i].value;
                fposdata[1][numpos][0] = 6 - i / CONVO_KERNEL_DIM;
                fposdata[1][numpos][1] = i % CONVO_KERNEL_DIM;
                fposdata[1][numpos][2] = this->config.kernel[i].value;
                numpos++;
            }
        }
        if (this->config.bias < 0) {
            fnegdata[0][numneg][0] = 0;
            fnegdata[0][numneg][1] = CONVO_KERNEL_DIM;
            fnegdata[0][numneg][2] = -this->config.bias;
            fnegdata[1][numneg][0] = 0;
            fnegdata[1][numneg][1] = CONVO_KERNEL_DIM;
            fnegdata[1][numneg][2] = -this->config.bias;
            numneg++;
        } else if (this->config.bias > 0) {
            fposdata[0][numpos][0] = 0;
            fposdata[0][numpos][1] = CONVO_KERNEL_DIM;
            fposdata[0][numpos][2] = this->config.bias;
            fposdata[1][numpos][0] = 0;
            fposdata[1][numpos][1] = CONVO_KERNEL_DIM;
            fposdata[1][numpos][2] = this->config.bias;
            numpos++;
        }
    } else {
        // do sign swapping
        for (int i = 0; i < CONVO_KERNEL_SIZE; i++) {
            if (this->config.kernel[i].value < 0) {
                fposdata[0][numpos][0] = i % CONVO_KERNEL_DIM;
                fposdata[0][numpos][1] = i / CONVO_KERNEL_DIM;
                fposdata[0][numpos][2] = -this->config.kernel[i].value;
                fposdata[1][numpos][0] = 6 - i / CONVO_KERNEL_DIM;
                fposdata[1][numpos][1] = i % CONVO_KERNEL_DIM;
                fposdata[1][numpos][2] = -this->config.kernel[i].value;
                numpos++;
            } else if (this->config.kernel[i].value > 0) {
                fnegdata[0][numneg][0] = i % CONVO_KERNEL_DIM;
                fnegdata[0][numneg][1] = i / CONVO_KERNEL_DIM;
                fnegdata[0][numneg][2] = this->config.kernel[i].value;
                fnegdata[1][numneg][0] = 6 - i / CONVO_KERNEL_DIM;
                fnegdata[1][numneg][1] = i % CONVO_KERNEL_DIM;
                fnegdata[1][numneg][2] = this->config.kernel[i].value;
                numneg++;
            }
        }
        if (this->config.bias < 0) {
            fposdata[0][numpos][0] = 0;
            fposdata[0][numpos][1] = CONVO_KERNEL_DIM;
            fposdata[0][numpos][2] = -this->config.bias;
            fposdata[1][numpos][0] = 0;
            fposdata[1][numpos][1] = CONVO_KERNEL_DIM;
            fposdata[1][numpos][2] = -this->config.bias;
            numpos++;
        } else if (this->config.bias > 0) {
            fnegdata[0][numneg][0] = 0;
            fnegdata[0][numneg][1] = CONVO_KERNEL_DIM;
            fnegdata[0][numneg][2] = this->config.bias;
            fnegdata[1][numneg][0] = 0;
            fnegdata[1][numneg][1] = CONVO_KERNEL_DIM;
            fnegdata[1][numneg][2] = this->config.bias;
            numneg++;
        }
        divisionfactor = -divisionfactor;
    }
    if (zerostringl < (CONVO_KERNEL_SIZE / 2)) {
        use_fbout = 1;
    } else {
        use_fbout = 0;
    }
    draw = (draw_func) new uint8_t[MAX_DRAW_SIZE];

    // addresses to loop back to
    int iloopstart;
    int jloopstart;
    this->code_length = 0;

    // function header (nonstandard stack - see stack.txt)
    appenddraw(0x53);  // push ebx
    appenddraw(0x56);  // push esi
    appenddraw(0x57);  // push edi
    appenddraw(0x55);  // push ebp
    appenddraw(0x8B);  // mov ebp, esp
    // throughout this code the coments will reference i, j, k and c[.].
    // see prog.txt to see the original non-optimised code to which they
    // (approximiately) refer. also see registers.txt for correspondances
    // between the registers here and the vars in prog.txt. double for loop
    // header j external loop, i internal loop, k internal non reset int j = 0;
    appenddraw(0xEC);
    appenddraw(0x33);  // xor ebx, ebx
    appenddraw(0xDB);
    appenddraw(0x8B);  // mov esi, ebx (esi will be permanently used for j)
    appenddraw(0xF3);
    // int *k = (use_fbout)?fbout:framebuffer - this var will serve as a pointer
    // to the address to output to
    appenddraw(0x8B);  // mov ebx, [ebp+(use_fbout)?24:20]
    appenddraw(0x5D);
    appenddraw((use_fbout) ? 0x18 : 0x14);
    appenddraw(0x8B);  // mov edx, ebx (edx
                       // will be permanently
                       // used for k)
    appenddraw(0xD3);
    // set up ecx as pointer to farray
    appenddraw(0x8B);  // mov ecx, [ebp+28] (e.g. mov ecx, this->m64_farray)
    appenddraw(0x4D);
    appenddraw(0x1C);
    // c[0] = framebuffer;
    appenddraw(0x8B);  // mov ebx, [ebp+20]
    appenddraw(0x5D);
    appenddraw(0x14);
    appenddraw(0x53);  // push ebx
    // c[1] = framebuffer;
    appenddraw(0x53);  // push ebx
    // c[2] = framebuffer;
    appenddraw(0x53);  // push ebx
    // c[3] = framebuffer;
    appenddraw(0x53);  // push ebx
    // c[4] = framebuffer+4*width;
    appenddraw(0x81);  // add ebx, 4*width
    appenddraw(0xC3);
    // 4*width needs to begin with the lowest byte
    appenddraw((4 * this->width) & 0x000000FF);
    appenddraw(((4 * this->width) & 0x0000FF00) >> 8);
    appenddraw(((4 * this->width) & 0x00FF0000) >> 16);
    appenddraw(((4 * this->width) & 0xFF000000) >> 24);
    appenddraw(0x53);  // push ebx
    // c[5] = framebuffer+8*width;
    appenddraw(0x81);  // add ebx, 4*width
    appenddraw(0xC3);
    // 4*width needs to begin with the lowest byte
    appenddraw((4 * this->width) & 0x000000FF);
    appenddraw(((4 * this->width) & 0x0000FF00) >> 8);
    appenddraw(((4 * this->width) & 0x00FF0000) >> 16);
    appenddraw(((4 * this->width) & 0xFF000000) >> 24);
    appenddraw(0x53);  // push ebx
    // c[6] = framebuffer+12*width;
    appenddraw(0x81);  // add ebx, 4*width
    appenddraw(0xC3);
    // 4*width needs to begin with the lowest byte
    appenddraw((4 * this->width) & 0x000000FF);
    appenddraw(((4 * this->width) & 0x0000FF00) >> 8);
    appenddraw(((4 * this->width) & 0x00FF0000) >> 16);
    appenddraw(((4 * this->width) & 0xFF000000) >> 24);
    appenddraw(0x53);  // push ebx
    // note: c[6] is at esp, c[5] is at esp+4, c[4] is at esp+8,c[3] is at
    // esp+12,c[2] is at esp+16,c[1] is at esp+20,c[0] is at esp+24
    appenddraw(0x0F);  // pxor	mm7, mm7 - mm7 will be permanently set to 0
    appenddraw(0xEF);
    appenddraw(0xFF);
    // start of j loop
    jloopstart = this->code_length;
    // int i = 0;
    // xor edi, edi - this register will be permanently assigned to i
    appenddraw(0x33);
    appenddraw(0xFF);
    // start of i loop
    for (int im = 0; im < CONVO_KERNEL_DIM; im++) {
        // when im=0 this will deal with the i=0
        // case, im=1, i=1, im=2, i=2, im=3,
        // 2<i<width-3, im=4, i=width-3, im=5,
        // i=width-2, im=6, i=width-1.
        iloopstart = this->code_length;
        for (int pass = 0; pass < (this->config.two_pass ? 2 : 1); pass++) {
            // the last f***data[i][1] looked at (initialize with impossible value)
            unsigned int lasty = 0xffffffff;
            appenddraw(0x0F);  // movq mm0, mm7
            appenddraw(0x7F);
            appenddraw(0xF8);
            if (numneg > 0) {
                appenddraw(0x0F);  // movq mm1, mm7
                appenddraw(0x7F);
                appenddraw(0xF9);
            }
            // go through the pos values
            for (int i = 0; i < numpos; i++) {
                if (fposdata[pass][i][1] == CONVO_KERNEL_DIM) {
                    // see if this the bias entry
                    appenddraw(0x0F);
                    // paddusw mm0, [ecx+49*8] (e.g. paddw mm0,
                    // this->m64_farray[49])
                    appenddraw(0xDD);
                    appenddraw(0x81);
                    appenddraw(0x88);
                    appenddraw(0x01);
                    appenddraw(0x00);
                    appenddraw(0x00);
                } else {
                    if (lasty != fposdata[pass][i][1]) {
                        // see if we actually need to adjust the value of eax
                        // (the start of row address)
                        appenddraw(0x8B);
                        // mov eax, [esp+4*(6-fposdata[pass][i][1])]
                        // (e.g. mov eax, c[fposdata[pass][i][1]])
                        appenddraw(0x44);
                        appenddraw(0x24);
                        appenddraw((4 * (6 - fposdata[pass][i][1])) & 0xFF);
                        lasty = fposdata[pass][i][1];
                    }
                    switch (im) {
                        case 0:
                            // movq mm2, [eax+max(4*(fposdata[pass][i][0]-3),0)]
                            appenddraw(0x0F);
                            appenddraw(0x6F);
                            appenddraw(0x50);
                            appenddraw(
                                (max((signed)(4 * (fposdata[pass][i][0] - 3)), 0))
                                & 0xFF);
                            break;
                        case 1:
                            // movq mm2, [eax+max(4*(fposdata[pass][i][0]-2),0)]
                            appenddraw(0x0F);
                            appenddraw(0x6F);
                            appenddraw(0x50);
                            appenddraw(
                                (max((signed)(4 * (fposdata[pass][i][0] - 2)), 0))
                                & 0xFF);
                            break;
                        case 2:
                            // movq mm2, [eax+max(4*(fposdata[pass][i][0]-1),0)]
                            appenddraw(0x0F);
                            appenddraw(0x6F);
                            appenddraw(0x50);
                            appenddraw(
                                (max((signed)(4 * (fposdata[pass][i][0] - 1)), 0))
                                & 0xFF);
                            break;
                        case 3:
                            // movq mm2, [eax+edi+4*(fposdata[pass][i][0]-3)]
                            appenddraw(0x0F);
                            appenddraw(0x6F);
                            appenddraw(0x54);
                            appenddraw(0x38);
                            appenddraw((4 * (fposdata[pass][i][0] - 3)) & 0xFF);
                            break;
                        case 4: {
                            int xpos;
                            // movq mm2,
                            // [eax+4*min(fposdata[pass][i][0]-6+width,width-2)]
                            appenddraw(0x0F);
                            appenddraw(0x6F);
                            appenddraw(0x90);
                            xpos = (4
                                    * min((unsigned)(fposdata[pass][i][0] - 6
                                                     + this->width),
                                          (unsigned)(this->width - 2)));
                            // xpos needs to begin with the lowest byte
                            appenddraw(xpos & 0x000000FF);
                            appenddraw((xpos & 0x0000FF00) >> 8);
                            appenddraw((xpos & 0x00FF0000) >> 16);
                            appenddraw((xpos & 0xFF000000) >> 24);
                            break;
                        }
                        case 5: {
                            int xpos;
                            appenddraw(
                                0x0F);  // movq mm2,
                                        // [eax+4*min(fposdata[pass][i][0]-5+width,width-2)]
                            appenddraw(0x6F);
                            appenddraw(0x90);
                            xpos = (4
                                    * min((unsigned)(fposdata[pass][i][0] - 5
                                                     + this->width),
                                          (unsigned)(this->width - 2)));
                            // xpos needs to begin with the lowest byte
                            appenddraw(xpos & 0x000000FF);
                            appenddraw((xpos & 0x0000FF00) >> 8);
                            appenddraw((xpos & 0x00FF0000) >> 16);
                            appenddraw((xpos & 0xFF000000) >> 24);
                            break;
                        }
                        case 6: {
                            int xpos;
                            // movq mm2,
                            // [eax+4*min(fposdata[pass][i][0]-4+width,width-2)]
                            appenddraw(0x0F);
                            appenddraw(0x6F);
                            appenddraw(0x90);
                            xpos = (4
                                    * min((unsigned)(fposdata[pass][i][0] - 4
                                                     + this->width),
                                          (unsigned)(this->width - 2)));
                            // xpos needs to begin with the lowest byte
                            appenddraw(xpos & 0x000000FF);
                            appenddraw((xpos & 0x0000FF00) >> 8);
                            appenddraw((xpos & 0x00FF0000) >> 16);
                            appenddraw((xpos & 0xFF000000) >> 24);
                            break;
                        }
                    }
                    appenddraw(0x0F);  // punpcklbw mm2, mm7
                    appenddraw(0x60);
                    appenddraw(0xD7);
                    // in which case we can just add
                    if (fposdata[pass][i][2] != 1) {  // just add
                        // see if fposdata[pass][i][2] is a power of 2
                        unsigned int j;
                        uint8_t k = 0;
                        for (j = 1; j < fposdata[pass][i][2]; j <<= 1) {
                            k++;
                        }
                        if (j == fposdata[pass][i][2]) {
                            // fposdata[pass][i][2]=2^k
                            appenddraw(0x0F);  // psllw mm2, k
                            appenddraw(0x71);
                            appenddraw(0xF2);
                            appenddraw(k);
                        } else {
                            appenddraw(0x0F);
                            // pmullw mm2,
                            // [ecx+8*(7*fposdata[pass][i][1]+fposdata[pass][i][0])]
                            // (e.g. pmullw mm2,
                            // this->m64_farray[7*fposdata[pass][i][1]+fposdata[pass][i][0]])
                            appenddraw(0xD5);
                            appenddraw(0x91);
                            // 8*(7*fposdata[pass][i][1]+fposdata[pass][i][0])
                            // needs to begin with the lowest byte
                            appenddraw((8
                                        * (CONVO_KERNEL_DIM * fposdata[pass][i][1]
                                           + fposdata[pass][i][0]))
                                       & 0x000000FF);
                            appenddraw(((8
                                         * (CONVO_KERNEL_DIM * fposdata[pass][i][1]
                                            + fposdata[pass][i][0]))
                                        & 0x0000FF00)
                                       >> 8);
                            appenddraw(((8
                                         * (CONVO_KERNEL_DIM * fposdata[pass][i][1]
                                            + fposdata[pass][i][0]))
                                        & 0x00FF0000)
                                       >> 16);
                            appenddraw(((8
                                         * (CONVO_KERNEL_DIM * fposdata[pass][i][1]
                                            + fposdata[pass][i][0]))
                                        & 0xFF000000)
                                       >> 24);
                        }
                    }
                    if (possum < 256) {
                        appenddraw(0x0F);  // paddw mm0, mm2
                        appenddraw(0xFD);
                        appenddraw(0xC2);
                    } else {
                        appenddraw(0x0F);  // paddw mm0, mm2
                        appenddraw(0xDD);
                        appenddraw(0xC2);
                    }
                }
            }
            // go through the neg values
            lasty = 0xffffffff;
            for (int i = 0; i < numneg; i++) {
                // see if this the bias entry
                if (fnegdata[pass][i][1] == CONVO_KERNEL_DIM) {
                    // paddw mm1, [ecx+49*8] (e.g. paddw mm0, this->m64_farray[49])
                    appenddraw(0x0F);
                    appenddraw(0xDD);
                    appenddraw(0x89);
                    appenddraw(0x88);
                    appenddraw(0x01);
                    appenddraw(0x00);
                    appenddraw(0x00);
                } else {
                    // see if we actually need to adjust the value of eax (the start
                    // of row address)
                    if (lasty != fnegdata[pass][i][1]) {
                        // mov eax, [esp+4*(6-fnegdata[pass][i][1])]
                        // (e.g. mov eax, c[fnegdata[pass][i][1]])
                        appenddraw(0x8B);
                        appenddraw(0x44);
                        appenddraw(0x24);
                        appenddraw((4 * (6 - fnegdata[pass][i][1])) & 0xFF);
                        lasty = fnegdata[pass][i][1];
                    }
                    switch (im) {
                        case 0:
                            // movq mm2, [eax+max(4*(fnegdata[pass][i][0]-3),0)]
                            appenddraw(0x0F);
                            appenddraw(0x6F);
                            appenddraw(0x50);
                            appenddraw(
                                (max((signed)(4 * (fnegdata[pass][i][0] - 3)), 0))
                                & 0xFF);
                            break;
                        case 1:
                            // movq mm2, [eax+max(4*(fnegdata[pass][i][0]-2),0)]
                            appenddraw(0x0F);
                            appenddraw(0x6F);
                            appenddraw(0x50);
                            appenddraw(
                                (max((signed)(4 * (fnegdata[pass][i][0] - 2)), 0))
                                & 0xFF);
                            break;
                        case 2:
                            // movq mm2, [eax+max(4*(fnegdata[pass][i][0]-1),0)]
                            appenddraw(0x0F);
                            appenddraw(0x6F);
                            appenddraw(0x50);
                            appenddraw(
                                (max((signed)(4 * (fnegdata[pass][i][0] - 1)), 0))
                                & 0xFF);
                            break;
                        case 3:
                            // movq mm2, [eax+edi+4*(fnegdata[pass][i][0]-3)]
                            appenddraw(0x0F);
                            appenddraw(0x6F);
                            appenddraw(0x54);
                            appenddraw(0x38);
                            appenddraw((4 * (fnegdata[pass][i][0] - 3)) & 0xFF);
                            break;
                        case 4: {
                            int xpos;
                            // movq mm2,
                            // [eax+4*min(fnegdata[pass][i][0]-6+width,width-2)]
                            appenddraw(0x0F);
                            appenddraw(0x6F);
                            appenddraw(0x90);
                            xpos = (4
                                    * min((unsigned)(fnegdata[pass][i][0] - 6
                                                     + this->width),
                                          (unsigned)(this->width - 2)));
                            // xpos needs to begin with the lowest byte
                            appenddraw(xpos & 0x000000FF);
                            appenddraw((xpos & 0x0000FF00) >> 8);
                            appenddraw((xpos & 0x00FF0000) >> 16);
                            appenddraw((xpos & 0xFF000000) >> 24);
                            break;
                        }
                        case 5: {
                            int xpos;
                            // movq mm2,
                            // [eax+4*min(fnegdata[pass][i][0]-5+width,width-2)]
                            appenddraw(0x0F);
                            appenddraw(0x6F);
                            appenddraw(0x90);
                            xpos = (4
                                    * min((unsigned)(fnegdata[pass][i][0] - 5
                                                     + this->width),
                                          (unsigned)(this->width - 2)));
                            // xpos needs to begin with the lowest byte
                            appenddraw(xpos & 0x000000FF);
                            appenddraw((xpos & 0x0000FF00) >> 8);
                            appenddraw((xpos & 0x00FF0000) >> 16);
                            appenddraw((xpos & 0xFF000000) >> 24);
                            break;
                        }
                        case 6: {
                            int xpos;
                            // movq mm2,
                            // [eax+4*min(fnegdata[pass][i][0]-4+width,width-2)]
                            appenddraw(0x0F);
                            appenddraw(0x6F);
                            appenddraw(0x90);
                            xpos = (4
                                    * min((unsigned)(fnegdata[pass][i][0] - 4
                                                     + this->width),
                                          (unsigned)(this->width - 2)));
                            // xpos needs to begin with the lowest byte
                            appenddraw(xpos & 0x000000FF);
                            appenddraw((xpos & 0x0000FF00) >> 8);
                            appenddraw((xpos & 0x00FF0000) >> 16);
                            appenddraw((xpos & 0xFF000000) >> 24);
                            break;
                        }
                    }
                    appenddraw(0x0F);  // punpcklbw mm2, mm7
                    appenddraw(0x60);
                    appenddraw(0xD7);
                    // in which case we can just add
                    if (fnegdata[pass][i][2] != 1) {  // just add
                        // see if fnegdata[pass][i][2] is a power of 2
                        unsigned int j;
                        uint8_t k = 0;
                        for (j = 1; j < fnegdata[pass][i][2]; j <<= 1) {
                            k++;
                        }
                        if (j == fnegdata[pass][i][2]) {
                            // fnegdata[pass][i][2]=2^k
                            appenddraw(0x0F);  // psllw mm2, k
                            appenddraw(0x71);
                            appenddraw(0xF2);
                            appenddraw(k);
                        } else {
                            appenddraw(0x0F);
                            // pmullw mm2,
                            // [ecx+8*(7*fnegdata[pass][i][1]+fnegdata[pass][i][0])]
                            // (e.g. pmullw mm2,
                            // this->m64_farray[7*fnegdata[pass][i][1]+fnegdata[pass][i][0]])
                            appenddraw(0xD5);
                            appenddraw(0x91);
                            // 8*(7*fnegdata[pass][i][1]+fnegdata[pass][i][0])
                            // needs to begin with the lowest byte
                            appenddraw((8
                                        * (CONVO_KERNEL_DIM * fnegdata[pass][i][1]
                                           + fnegdata[pass][i][0]))
                                       & 0x000000FF);
                            appenddraw(((8
                                         * (CONVO_KERNEL_DIM * fnegdata[pass][i][1]
                                            + fnegdata[pass][i][0]))
                                        & 0x0000FF00)
                                       >> 8);
                            appenddraw(((8
                                         * (CONVO_KERNEL_DIM * fnegdata[pass][i][1]
                                            + fnegdata[pass][i][0]))
                                        & 0x00FF0000)
                                       >> 16);
                            appenddraw(((8
                                         * (CONVO_KERNEL_DIM * fnegdata[pass][i][1]
                                            + fnegdata[pass][i][0]))
                                        & 0xFF000000)
                                       >> 24);
                        }
                    }
                    if (negsum < 256) {
                        // paddw mm1, mm2
                        appenddraw(0x0F);
                        appenddraw(0xFD);
                        appenddraw(0xCA);
                    } else {
                        // paddw mm1, mm2
                        appenddraw(0x0F);
                        appenddraw(0xDD);
                        appenddraw(0xCA);
                    }
                }
            }
            // do pos take neg
            if (numneg > 0) {
                if (this->config.absolute) {
                    // psubsw mm0, mm1
                    appenddraw(0x0F);
                    appenddraw(0xE9);
                    appenddraw(0xC1);
                    // calculate absolute values
                    // psllw mm0, 1
                    appenddraw(0x0F);
                    appenddraw(0x71);
                    appenddraw(0xF0);
                    appenddraw(0x01);
                    // psrlw mm0, 1
                    appenddraw(0x0F);
                    appenddraw(0x71);
                    appenddraw(0xD0);
                    appenddraw(0x01);
                } else {
                    if (this->config.wrap) {
                        // psubw mm0, mm1
                        appenddraw(0x0F);
                        appenddraw(0xF9);
                        appenddraw(0xC1);
                    } else {
                        // psubusw mm0, mm1
                        appenddraw(0x0F);
                        appenddraw(0xD9);
                        appenddraw(0xC1);
                    }
                }
            }
            if (this->config.two_pass && pass == 0) {
                // movq mm3, mm0
                appenddraw(0x0F);
                appenddraw(0x7F);
                appenddraw(0xC3);
            }
        }  // end of pass for
        if (this->config.two_pass) {
            // psubusw mm0, mm3
            appenddraw(0x0F);
            appenddraw(0xDD);
            appenddraw(0xC3);
        }
        // scale
        if (divisionfactor != 1) {
            int j;
            // see if divisionfactor is a power of 2
            uint8_t k = 0;
            for (j = 1; j < divisionfactor; j <<= 1) {
                k++;
            }
            if (j == divisionfactor) {
                // divisionfactor=2^k
                // psrlw mm0, k
                appenddraw(0x0F);
                appenddraw(0x71);
                appenddraw(0xD0);
                appenddraw(k);
            } else {
                // movq [esp-8], mm0
                appenddraw(0x0F);
                appenddraw(0x7F);
                appenddraw(0x44);
                appenddraw(0x24);
                appenddraw(0xF8);
                // mov [esp-10], ax
                appenddraw(0x66);
                appenddraw(0x89);
                appenddraw(0x44);
                appenddraw(0x24);
                appenddraw(0xF6);
                // mov [esp-12], dx
                appenddraw(0x66);
                appenddraw(0x89);
                appenddraw(0x54);
                appenddraw(0x24);
                appenddraw(0xF4);
                appenddraw(0xBB);
                // mov mov ebx,
                // 65536/divisionfactor
                // 65536/divisionfactor needs to begin with the lowest byte
                appenddraw((65536 / divisionfactor) & 0x000000FF);
                appenddraw(((65536 / divisionfactor) & 0x0000FF00) >> 8);
                appenddraw(((65536 / divisionfactor) & 0x00FF0000) >> 16);
                appenddraw(((65536 / divisionfactor) & 0xFF000000) >> 24);
                appenddraw(0x66);  // mov dx, bx
                appenddraw(0x8B);
                appenddraw(0xD3);
                appenddraw(0x66);  // mov ax, [esp-8]
                appenddraw(0x8B);
                appenddraw(0x44);
                appenddraw(0x24);
                appenddraw(0xF8);
                appenddraw(0x66);  // mul dx
                appenddraw(0xF7);
                appenddraw(0xE2);
                appenddraw(0x66);  // mov [esp-8], dx
                appenddraw(0x89);
                appenddraw(0x54);
                appenddraw(0x24);
                appenddraw(0xF8);
                appenddraw(0x66);  // mov dx, bx
                appenddraw(0x8B);
                appenddraw(0xD3);
                appenddraw(0x66);  // mov ax, [esp-6]
                appenddraw(0x8B);
                appenddraw(0x44);
                appenddraw(0x24);
                appenddraw(0xFA);
                appenddraw(0x66);  // mul dx
                appenddraw(0xF7);
                appenddraw(0xE2);
                appenddraw(0x66);  // mov [esp-6], dx
                appenddraw(0x89);
                appenddraw(0x54);
                appenddraw(0x24);
                appenddraw(0xFA);
                appenddraw(0x66);  // mov dx, bx
                appenddraw(0x8B);
                appenddraw(0xD3);
                appenddraw(0x66);  // mov ax, [esp-4]
                appenddraw(0x8B);
                appenddraw(0x44);
                appenddraw(0x24);
                appenddraw(0xFC);
                appenddraw(0x66);  // mul dx
                appenddraw(0xF7);
                appenddraw(0xE2);
                appenddraw(0x66);  // mov [esp-4], dx
                appenddraw(0x89);
                appenddraw(0x54);
                appenddraw(0x24);
                appenddraw(0xFC);
                appenddraw(0x66);  // mov dx, [esp-12]
                appenddraw(0x8B);
                appenddraw(0x54);
                appenddraw(0x24);
                appenddraw(0xF4);
                appenddraw(0x66);  // mov ax, [esp-10]
                appenddraw(0x8B);
                appenddraw(0x44);
                appenddraw(0x24);
                appenddraw(0xF6);
                appenddraw(0x0F);  // movq mm0, [esp-8]
                appenddraw(0x6F);
                appenddraw(0x44);
                appenddraw(0x24);
                appenddraw(0xF8);
            }
        }
        // output
        appenddraw(0x0F);  // packuswb mm0, mm7
        appenddraw(0x67);
        appenddraw(0xC7);
        appenddraw(0x0F);  // movd [edx], mm0
        appenddraw(0x7E);
        appenddraw(0x02);
        // increase k
        appenddraw(0x83);  // add edx, 4
        appenddraw(0xC2);
        appenddraw(0x04);
        // i "next" block
        if (im < 4) {
            appenddraw(0x83);  // add edi, 4
            appenddraw(0xC7);
            appenddraw(0x04);
        }
        if (im == 3) {
            appenddraw(0x81);  // cmp edi, 4*(width-3)
            appenddraw(0xFF);
            // 4*(width-3) needs to begin with the lowest byte
            appenddraw((4 * (this->width - 3)) & 0x000000FF);
            appenddraw(((4 * (this->width - 3)) & 0x0000FF00) >> 8);
            appenddraw(((4 * (this->width - 3)) & 0x00FF0000) >> 16);
            appenddraw(((4 * (width - 3)) & 0xFF000000) >> 24);
            // return to i "for". which jump to use depends on this->code_length
            // can't use short jumps
            if (iloopstart - this->code_length - 2 < -128) {
                int jumpoffset;
                appenddraw(0x0F);  // jb near back to i loop start
                appenddraw(0x82);
                jumpoffset = iloopstart - (this->code_length + 4);
                // this->code_length + 4 is the index of the next command
                // offset needs to begin with the lowest byte
                appenddraw(jumpoffset & 0x000000FF);
                appenddraw((jumpoffset & 0x0000FF00) >> 8);
                appenddraw((jumpoffset & 0x00FF0000) >> 16);
                appenddraw((jumpoffset & 0xFF000000) >> 24);
            } else {  // can use short jumps.
                // jb short back to i loop start
                appenddraw(0x72);
                // this->code_length+1 is the indes of the next command
                auto value = ((char)(iloopstart - (this->code_length + 1)));
                appenddraw(value);
            }
        }
    }
    // increment the line address array
    appenddraw(0x8B);  // mov ebx, [esp]
    appenddraw(0x1C);
    appenddraw(0x24);
    appenddraw(0x81);  // add ebx, 4*width
    appenddraw(0xC3);
    // 4*width needs to begin with the lowest byte
    appenddraw((4 * this->width) & 0x000000FF);
    appenddraw(((4 * this->width) & 0x0000FF00) >> 8);
    appenddraw(((4 * this->width) & 0x00FF0000) >> 16);
    appenddraw(((4 * this->width) & 0xFF000000) >> 24);
    appenddraw(0x8B);  // mov eax, framebuffer
    appenddraw(0x45);
    appenddraw(0x14);
    appenddraw(0x05);  // add eax, 4*width*(height-1)
    // 4*width*(height-1) needs to begin with the lowest byte
    appenddraw((4 * this->width * (this->height - 1)) & 0x000000FF);
    appenddraw(((4 * this->width * (this->height - 1)) & 0x0000FF00) >> 8);
    appenddraw(((4 * this->width * (this->height - 1)) & 0x00FF0000) >> 16);
    appenddraw(((4 * this->width * (this->height - 1)) & 0xFF000000) >> 24);
    appenddraw(0x3B);  // cmp ebx, eax
    appenddraw(0xD8);
    appenddraw(0x75);  // jne 3 (e.g. to the push epx line)
    appenddraw(0x03);
    appenddraw(0x8B);  // mov ebx, [esp]
    appenddraw(0x1C);
    appenddraw(0x24);
    appenddraw(0x53);  // push ebx
    // note: relative to esp the addresses of c[0]-c[6] are the same.
    // this has effectively done
    // c[0]=c[1]...c[5]=c[6],c[6]+=4*w,c[6]=min(c[6],address of the last row of
    // franebuffer) j next block
    appenddraw(0x46);  // inc esi
    appenddraw(0x81);  // cmp esi, height
    appenddraw(0xFE);
    // height needs to begin with the lowest byte
    appenddraw(this->height & 0x000000FF);
    appenddraw((this->height & 0x0000FF00) >> 8);
    appenddraw((this->height & 0x00FF0000) >> 16);
    appenddraw((this->height & 0xFF000000) >> 24);
    // return to j "for". which jump to use depends on this->code_length
    if (jloopstart - this->code_length - 2 < -128) {
        // can't use short jumps
        int jumpoffset;
        appenddraw(0x0F);  // jb near back to j loop start

        // this->code_length + 4 is the index of the next command
        appenddraw(0x82);
        jumpoffset = jloopstart - (this->code_length + 4);
        // offset needs to begin with the lowest byte
        appenddraw(jumpoffset & 0x000000FF);
        appenddraw((jumpoffset & 0x0000FF00) >> 8);
        appenddraw((jumpoffset & 0x00FF0000) >> 16);
        appenddraw((jumpoffset & 0xFF000000) >> 24);
    } else {
        // can use short jumps.
        appenddraw(0x72);  // jb short back to j loop start
        auto value = ((char)(jloopstart - (this->code_length + 1)));
        appenddraw(value);
        // this->code_length + 1 is the index of the next command
    }  // clear mmx state
    appenddraw(0x0F);  // emms
    appenddraw(0x77);
    // function exit code
    appenddraw(0x8B);  // mov esp, ebp
    appenddraw(0xE5);
    appenddraw(0x5D);  // pop ebp
    appenddraw(0x5F);  // pop edi
    appenddraw(0x5E);  // pop esi
    appenddraw(0x5B);  // pop ebx
    appenddraw(0xB8);  // mov eax, use_fbout
    appenddraw(use_fbout);
    appenddraw(0x00);
    appenddraw(0x00);
    appenddraw(0x00);
    appenddraw(0xC3);  // ret
    this->draw_created = true;
}

void E_Convolution::kernel_save() {
    FILE* file = fopen(this->config.save_file.c_str(), "wb");
    if (file == nullptr) {
        // TODO [feature]: Log an error here.
        return;
    }
    auto data = new uint8_t[CONVO_FILE_STATIC_SIZE + this->config.save_file.size()];
    auto length = (uint32_t)max(0, this->save_legacy(data));
    if (length != (CONVO_FILE_STATIC_SIZE + this->config.save_file.size())) {
        // TODO [feature]: Log an error here.
        return;
    }
    fwrite(data, length, 1, file);
    fclose(file);
}

void E_Convolution::kernel_load() {
    size_t filesize;
    FILE* file = fopen(this->config.save_file.c_str(), "rb");
    if (file == nullptr) {
        return;
    }
    fseek(file, 0, SEEK_END);
    filesize = min(ftell(file), CONVO_FILE_STATIC_SIZE + LEGACY_SAVE_PATH_LEN);
    auto content = new uint8_t[filesize];
    fseek(file, 0, SEEK_SET);
    auto bytes_read = fread(content, 1, filesize, file);
    if (!bytes_read) {
        delete[] content;
        return;
    }
    fclose(file);
    this->load_legacy(content, (int)filesize);
    this->need_draw_update = true;
}

void E_Convolution::load_legacy(unsigned char* data, int len) {
    int pos = 0;
    if (len - pos >= 4) {
        this->enabled = GET_INT() == 1;
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.wrap = GET_INT() == 1;
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.absolute = GET_INT() == 1;
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.two_pass = GET_INT() == 1;
        pos += 4;
    }
    for (int i = 0; i < CONVO_KERNEL_SIZE; i++) {
        if (len - pos >= 4) {
            this->config.kernel[i].value = GET_INT();
            pos += 4;
        }
    }
    if (len - pos >= 4) {
        this->config.bias = GET_INT();
        pos += 4;
    }
    if (len - pos >= 4) {
        this->config.scale = GET_INT();
        pos += 4;
    }
    this->check_scale_not_zero();
    this->need_draw_update = true;

    if (this->config.save_file.empty()) {
        auto str_data = (char*)data;
        // See `save_legacy()` for the reason why we're doing this by hand.
        this->config.save_file = std::string(str_data, len - pos);
    }
}

int E_Convolution::save_legacy(unsigned char* data) {
    int pos = 0;
    PUT_INT((int)this->enabled);
    pos += 4;
    PUT_INT((int)this->config.wrap);
    pos += 4;
    PUT_INT((int)this->config.absolute);
    pos += 4;
    PUT_INT((int)this->config.two_pass);
    pos += 4;
    for (int i = 0; i < CONVO_KERNEL_SIZE; i++) {
        PUT_INT(this->config.kernel[i].value);
        pos += 4;
    }
    PUT_INT(this->config.bias);
    pos += 4;
    PUT_INT(this->config.scale);
    pos += 4;

    // Can't use either `string_nt_save_legacy()` or `string_save_legacy()` because the
    // string gets saved without length header _and_ without null-terminator.
    // It can only do this because it's at the end of the save section and the effect
    // section has a known length.
    for (int i = 0; this->config.save_file[i] != '\0'; pos++, i++) {
        data[pos] = this->config.save_file[i];
    }
    return pos;
}

Effect_Info* create_Convolution_Info() { return new Convolution_Info(); }
Effect* create_Convolution(AVS_Instance* avs) { return new E_Convolution(avs); }
void set_Convolution_desc(char* desc) { E_Convolution::set_desc(desc); }
