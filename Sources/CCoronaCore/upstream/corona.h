/* Libvisual-plugins - Standard plugins for libvisual
 * 
 * Copyright (C) 2000, 2001 Richard Ashburn <richard.asbury@btinternet.com>
 *
 * Authors: Richard Ashburn <richard.asbury@btinternet.com>
 * 	    Jean-Christophe Hoelt <jeko@ios-software.com>
 *	    Dennis Smit <ds@nerds-incorporated.org>
 *
 * $Id: corona.h,v 1.3 2005/12/20 18:49:13 synap Exp $
 *
 * Modified for NullPlayer (2026-11-12): setPreset/getPreset, so a host can pick
 * Corona or Blaze (libvisual left the preset fixed at Corona).
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

/////////////////////////////////////////////////////////////////////////////
//
// corona.h : Declaration of the Corona class
//
/////////////////////////////////////////////////////////////////////////////

#ifndef __CORONA_H_
#define __CORONA_H_

#include "corona_types.h"

// presets
enum {
  PRESET_CORONA = 0,
  PRESET_BLAZE,
  PRESET_COUNT
};

// The particles
struct Particle
{
  double x, y, xvel, yvel;
};

// The background swirl
struct Swirl
{
  double x;
  double y;
  double tightness;
  double pull;
};


/////////////////////////////////////////////////////////////////////////////
//
// Core Class of the Corona Visual FX
//
/////////////////////////////////////////////////////////////////////////////

class Corona
{
  private:
    int m_clrForeground;    // foreground color
    int m_nPreset;

    Particle *m_particles;
    int       nbParticules;

    // The off-screen buffer
    unsigned char* m_image;
    unsigned char* m_real_image;

    int m_width;
    int m_height;
    int m_real_height;

    Swirl m_swirl;
    unsigned char** m_deltafield;

    // Particle movement info
    int   m_swirltime;
    Swirl m_movement;

    bool m_testing;
    bool m_silent;

    // Beat detection
    double m_avg;
    double m_oldval;
    int    m_pos;

    // Waves
    double m_waveloop;
    int   *m_reflArray;
    
    // Implementation functions
    double random(double min, double max) const;
    //    void setUpPalette();
    void drawLine(int x0, int y0, int x1, int y1, unsigned char col);
    void drawParticules();
    void drawParticulesWithShift();
    void blurImage();
    void drawReflected();
    
    void chooseRandomSwirl();
    void setPointDelta(int x, int y);
    void applyDeltaField(bool heavy);
    int  getBeatVal(TimedLevel *tl);
    void getAvgParticlePos(double& x, double& y) const;
    void genReflectedWaves(double loop);


  public:
    Corona();
    ~Corona();

    bool           setUpSurface(int width, int height);
    void           update(TimedLevel *pLevels);
    unsigned char *getSurface() const { return m_real_image; }

    void setPreset(int preset) { m_nPreset = preset; }
    int  getPreset() const     { return m_nPreset; }

    int  getWidth()  const { return m_width;  }
    int  getHeight() const { return m_real_height; }
};

#endif //__CORONA_H_
