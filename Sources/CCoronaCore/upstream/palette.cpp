/* Libvisual-plugins - Standard plugins for libvisual
 * 
 * Copyright (C) 2000, 2001 Richard Ashburn <richard.asbury@btinternet.com>
 *
 * Authors: Richard Ashburn <richard.asbury@btinternet.com>
 * 	    Jean-Christophe Hoelt <jeko@ios-software.com>
 *	    Dennis Smit <ds@nerds-incorporated.org>
 *
 * $Id: palette.cpp,v 1.6 2005/12/20 18:49:13 synap Exp $
 *
 * Modified for NullPlayer (2026-11-12): libvisual dependency removed
 * (visual_mem_* become memset/memcpy; updateVisPalette is gone); holdPalette.
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

#include "palette.h"

#include <cstdlib>
#include <cstring>
using namespace std;

///////////////////////////////////////////////////////////////////////////////


// Palette stored in compressed format (just checkpoints)
class CompressedPalette
{
  public:
  ColorRGB m_col[16];
  int      m_ind[16];
  int      m_nb;

  CompressedPalette() : m_nb(0) {}
  void push_color(int i, ColorRGB col) { m_col[m_nb] = col; m_ind[m_nb++] = i; }

  void expand(Palette pal) const;
};

///////////////////////////////////////////////////////////////////////////////
    
PaletteCycler::PaletteCycler(const int palettes[][NB_PALETTES], int nbPalettes)
  : m_palettes(palettes, nbPalettes), m_held(false)
{
  memset (m_srcpal, 0, sizeof (Palette));
  memset (m_destpal, 0, sizeof (Palette));
  memset (m_curpal, 0, sizeof (Palette));

  startPaletteTransition(rand() % (int) m_palettes.size());
  affectPaletteTransition(1);
  m_transferring  = false;
  m_srcnum        = m_destnum;
}

void PaletteCycler::startPaletteTransition(int dest)
{
  if (m_palettes.size() > 0)
  {
    // Copy the current palette to the "source palette"
    memcpy(m_srcpal, m_curpal, sizeof(m_srcpal));

    // Create a new palette as the "destination palette"
    m_srcnum  = m_destnum;
    m_destnum = dest;
    m_palettes.expandPalette(m_destnum, m_destpal);

    // Begin the transition
    m_transferring = true;
    m_progress     = 0;
  }
}

void PaletteCycler::update(TimedLevel *pLevels)
{
  // Randomly change the destination palette, unless the host holds one
  if (m_held) {}
  else if (pLevels->timeStamp - pLevels->lastbeat > 10000000) {
    if (rand() % 100 == 0) startPaletteTransition(rand() % (int) m_palettes.size());
  }
  else {
    if (rand() % 400 == 0) startPaletteTransition(rand() % (int) m_palettes.size());
  }

  // Continue any current palette transtion
  if (m_transferring) {
    if (pLevels->timeStamp - pLevels->lastbeat > 10000000) m_progress += 0.01;
    else m_progress += 0.005;
    if (m_progress >= 1) {
      m_transferring = false;
      m_progress = 1;
      m_srcnum = m_destnum;
    }
    // Use an inverse sigmoid transition to emphasise the midway palette
    double x;
    if (m_progress < 0.5) x = 2 * m_progress * (1 - m_progress);
    else x = 2 * m_progress * (m_progress - 1) + 1;
    affectPaletteTransition(x);
  }
}

void PaletteCycler::holdPalette(int i, bool fade)
{
  m_held = true;
  startPaletteTransition(i);
  if (!fade) {
    affectPaletteTransition(1);
    m_transferring = false;
    m_srcnum = m_destnum;
  }
}

void PaletteCycler::affectPaletteTransition(double p)
{
  for (int i = 0; i < 256; ++i)
  {
    ColorRGB c1 = m_srcpal[i];
    ColorRGB c2 = m_destpal[i];
    m_curpal[i].rgbRed   = (unsigned char) ((1 - p) * c1.rgbRed   + p * c2.rgbRed);
    m_curpal[i].rgbGreen = (unsigned char) ((1 - p) * c1.rgbGreen + p * c2.rgbGreen);
    m_curpal[i].rgbBlue  = (unsigned char) ((1 - p) * c1.rgbBlue  + p * c2.rgbBlue);
  }
}



///////////////////////////////////////////////////////////////////////////////

void CompressedPalette::expand(Palette dest) const
{
  ColorRGB col;
  int entry = 0;
  col.rgbBlue = col.rgbGreen = col.rgbRed = 0;

  int i = 0;
  for (; i < m_nb; ++i)
  {
    int j = entry;
    for (; j < m_ind[i]; ++j)
    {
      double t = (double) (j - entry) / (m_ind[i] - entry);
      dest[j].rgbRed   = (unsigned char) ((1 - t) * col.rgbRed   + t * m_col[i].rgbRed);
      dest[j].rgbGreen = (unsigned char) ((1 - t) * col.rgbGreen + t * m_col[i].rgbGreen);
      dest[j].rgbBlue  = (unsigned char) ((1 - t) * col.rgbBlue  + t * m_col[i].rgbBlue);
    }
    entry = j;
    col = m_col[i];
  }
  for (; entry < 256; ++entry) dest[entry] = col;
}

///////////////////////////////////////////////////////////////////////////////

PaletteCollection::PaletteCollection(const int palettes[][NB_PALETTES], int nbPalettes)
{
  m_cpal = new CompressedPalette[nbPalettes];
  m_nbPalettes = nbPalettes;

	// Set up the palettes from the array
	for (int i = 0; i < nbPalettes; ++i)
  {
    CompressedPalette newpal;
		const int* pal = palettes[i];
		for (int j = 1; j < pal[0] * 2; j += 2)
    {
			ColorRGB rgb;
			rgb.rgbRed   = (pal[j + 1] & 0xff0000) >> 16;
			rgb.rgbGreen = (pal[j + 1] & 0xff00) >> 8;
			rgb.rgbBlue  = pal[j + 1] & 0xff;
			newpal.push_color(pal[j], rgb);
		}
    m_cpal[i] = newpal;
	}
}

PaletteCollection::~PaletteCollection()
{
  delete[] m_cpal;
}
    
void PaletteCollection::expandPalette(int i, Palette dest) const
{
  m_cpal[i].expand(dest);
}

///////////////////////////////////////////////////////////////////////////////

void blitSurface8To32(unsigned char *byteSurf, int *colorSurf, int palette[256], int size)
{
  int i = 0;
  while(size--) {
    colorSurf[i++] = palette[byteSurf[size]];
  }
}

void paletteToRGBA(int dest[256], const Palette src)
{
  for (int i=0; i<256; ++i)
    dest[i] = ((int)src[i].rgbRed << 16) | ((int)src[i].rgbGreen << 8) | (int)src[i].rgbBlue;
}
