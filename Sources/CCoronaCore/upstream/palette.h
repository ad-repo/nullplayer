/* Libvisual-plugins - Standard plugins for libvisual
 * 
 * Copyright (C) 2000, 2001 Richard Ashburn <richard.asbury@btinternet.com>
 *
 * Authors: Richard Ashburn <richard.asbury@btinternet.com>
 * 	    Jean-Christophe Hoelt <jeko@ios-software.com>
 *	    Dennis Smit <ds@nerds-incorporated.org>
 *
 * $Id: palette.h,v 1.4 2005/12/20 18:49:13 synap Exp $
 *
 * Modified for NullPlayer (2026-11-12): libvisual dependency removed
 * (updateVisPalette); the host reads getPalette(). A host can hold a palette
 * (holdPalette), which stops the random palette changes.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 */

#ifndef _PALETTE_H
#define _PALETTE_H

// The longest palette row: autopal.h's 10 checkpoints take 21 ints.
#define NB_PALETTES 23

#include "corona_types.h"

// PALETTE
// 
typedef ColorRGB Palette[256];
class   CompressedPalette;

// COLLECTION OF PALETTES
//
// Definition of some palettes stored in compressed format.
//
class PaletteCollection
{
  public:
    PaletteCollection(const int palettes[][NB_PALETTES], int nbPalettes);
    ~PaletteCollection();

    int size() const  { return m_nbPalettes; }
    void expandPalette(int i, Palette dest) const;

  private:
    CompressedPalette *m_cpal;
    int                m_nbPalettes;
};

// PALETTE CYCLER
//
// A class to create cycling palettes.
// 
class PaletteCycler
{
  private:
    Palette m_srcpal;
    Palette m_destpal;
    Palette m_curpal;

    PaletteCollection m_palettes;
    int    m_srcnum, m_destnum;
    bool   m_transferring;
    double m_progress;

    bool   m_held;

    void startPaletteTransition(int dest);
    void affectPaletteTransition(double p);

  public:
    PaletteCycler(const int palettes[][NB_PALETTES], int nbPalettes);
    void update(TimedLevel *pLevels);
    // Fades (or, with fade false, switches) to palette i and keeps it.
    void holdPalette(int i, bool fade);
    const Palette &getPalette() const { return m_curpal; }
};

// PALETTE CONVERSIOn
//
// Display/Architecture specific routines to convert Palette to int[] (hardware color)
// 
void paletteToRGBA(int dest[256], const Palette src);

// BLIT A PALETTIZED SURFACE using converted palette.
void blitSurface8To32(unsigned char *byteSurf, int *colorSurf, int palette[256], int size);

#endif
