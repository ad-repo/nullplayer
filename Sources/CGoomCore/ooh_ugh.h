/* NullPlayer port: the Ooh/Ugh effect (OOH_UGH_MODE) — original work, not upstream Goom.
   A heavy-metal hellscape that morphs between five scenes (flow fields in filters.c, each with
   its own abyss and mix of emitters): smoke wraiths, fire, ash and, rarely,
   a sigil (inverted pentacle, goat head, sword, inverted cross) flung out of the abyss, all
   drawn into Goom's feedback buffer for its zoom to carry. Kicks flare the fire and strobe
   the sky; then a red/black/white palette map on the finished frame. State: update.oohUgh. */
#ifndef OOH_UGH_H
#define OOH_UGH_H

#include "goom_config.h"
#include "goom_plugin_info.h"
#include "goom_filters.h"

/* Advances the scene clock; 1 when the scene just changed (deliver the zoom config). */
int ooh_ugh_scene (PluginInfo *goomInfo);
/* Puts the zoom's middle on the current scene's abyss and tags the config with the scene. */
void ooh_ugh_settle (PluginInfo *goomInfo, ZoomFilterData *zf);
/* Draws this cycle's emitters into p (the buffer the scope lines draw on). */
void ooh_ugh_draw (PluginInfo *goomInfo, gint16 data[2][512], Pixel *p);
/* Maps the finished frame onto the black -> red -> white ramp and lights the sky around the abyss. */
void ooh_ugh_finish (PluginInfo *goomInfo, Pixel *frame);
void ooh_ugh_free (PluginInfo *goomInfo);

#endif
