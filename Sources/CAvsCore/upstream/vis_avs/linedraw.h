#include <stdint.h>

extern int g_line_blend_mode;

void line(uint32_t* fb,
          int x1,
          int y1,
          int x2,
          int y2,
          int width,
          int height,
          uint32_t color,
          int lw);
