#ifndef VIS_CLASSIC_CORE_H
#define VIS_CLASSIC_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct VisClassicCore VisClassicCore;

VisClassicCore *vc_create(int width, int height);
void vc_destroy(VisClassicCore *core);

void vc_set_waveform_u8(VisClassicCore *core,
                        const uint8_t *left,
                        const uint8_t *right,
                        size_t count,
                        double sample_rate);

void vc_render_rgba(VisClassicCore *core,
                    uint8_t *out_rgba,
                    int width,
                    int height,
                    size_t stride);

int vc_set_option(VisClassicCore *core, const char *key, int value);
int vc_get_option(VisClassicCore *core, const char *key, int *value_out);

int vc_load_profile_ini(VisClassicCore *core, const char *path_utf8);
int vc_save_profile_ini(VisClassicCore *core, const char *path_utf8);

const char *vc_get_last_error(VisClassicCore *core);

#ifdef __cplusplus
}
#endif

#endif
