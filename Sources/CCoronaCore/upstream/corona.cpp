/* Libvisual-plugins - Standard plugins for libvisual
 * 
 * Copyright (C) 2000, 2001 Richard Ashburn <richard.asbury@btinternet.com>
 *
 * Authors: Richard Ashburn <richard.asbury@btinternet.com>
 * 	    Jean-Christophe Hoelt <jeko@ios-software.com>
 *	    Dennis Smit <ds@nerds-incorporated.org>
 *
 * $Id: corona.cpp,v 1.10 2006/02/05 18:47:26 synap Exp $
 *
 * Modified for NullPlayer (2026-11-12): libvisual dependency removed (the MMX blur
 * branch, which only ran on x86); the destructor frees the particles and the reflection array.
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
// Corona.cpp : Implementation of CCorona
//
/////////////////////////////////////////////////////////////////////////////

#include "corona.h"
#include <stdio.h>
#include <cstdlib>
#include <cmath>
#include <cstdint>
using namespace std;


/////////////////////////////////////////////////////////////////////////////
// Corona::Corona
// Constructor

Corona::Corona()
{
	m_clrForeground = 0x0000FF;
	m_swirltime     = 0;
	m_testing       = false;
	m_silent        = false;
	m_avg           = 1;
	m_oldval        = 0;
	m_pos           = 0;

	m_nPreset	  = PRESET_CORONA;

	m_image         = 0;
	m_real_image    = 0;
	m_deltafield    = 0;
	m_width         = -1;
	m_height        = -1;
	m_real_height   = -1;
	nbParticules    = 1000;
	m_reflArray     = 0;
	m_waveloop      = 0.0;

	m_particles = (Particle*)calloc (nbParticules, sizeof(Particle));
	// Create particles in random positions
	for (int i = nbParticules - 1; i >= 0; --i)
	{
		Particle *it = m_particles + i;
		it->x = random(0, 1);
		it->y = random(0, 1);
		it->xvel = it->yvel = 0;
	}
	// Set up the background swirling effect
	chooseRandomSwirl();
}

/////////////////////////////////////////////////////////////////////////////
// Corona::~Corona
// Destructor

Corona::~Corona()
{
	if (m_real_image) free(m_real_image);
	if (m_deltafield) free(m_deltafield);
	if (m_reflArray)  free(m_reflArray);
	free(m_particles);
}

double Corona::random(double min, double max) const {
	return rand() * (max - min) / RAND_MAX + min;
}

bool Corona::setUpSurface(int width, int height) {
	// Delete any image that might have previously been allocated
	if (m_real_image) free(m_real_image);
	if (m_deltafield) free(m_deltafield);
	if (m_reflArray)  free(m_reflArray);

	// Fill in the size details in the BitmapInfo structure
	m_width  = width;
	m_height = (height*4) / 5;
	m_real_height = height;

	// Allocate the image data
	m_real_image = (unsigned char *)calloc(1,width*height);
	if (m_real_image == 0) return false;
	m_image      = m_real_image + m_width * (m_real_height - m_height);
	m_reflArray  = (int*)malloc((m_real_height - m_height) * sizeof(*m_reflArray));

	// Allocate the delta-field memory, and initialise it
	m_deltafield = (unsigned char**)malloc(m_width * m_height * sizeof(unsigned char*));

	for (int x = 0; x < m_width; ++x) {
		for (int y = 0; y < m_height; ++y) {
			setPointDelta(x, y);
		}
	}

	// Change the number of particles
	int newsize = (int) (::sqrt(m_width * m_height) * 3.0);
	if (newsize < 2000) newsize = 2000;
	int oldsize = (int) nbParticules;
	nbParticules = newsize;
	m_particles = (Particle*)realloc (m_particles, sizeof(Particle) * newsize);
	for (int i = oldsize; i < newsize; ++i) {
		m_particles[i].x = random(0, 1);
		m_particles[i].y = random(0, 1);
		m_particles[i].xvel = m_particles[i].yvel = 0;
	}

	return true;
}

void Corona::drawLine(int x0, int y0, int x1, int y1, unsigned char col)
{
	int incx = (x1 > x0) ? 1 : -1;
	int incy = (y1 > y0) ? m_width : -m_width;
	int dincx = 2 * abs(y1 - y0);
	int dincy = 2 * abs(x1 - x0);
	unsigned char* p = &(m_image[x0 + y0 * m_width]);
	unsigned char* const end = &(m_image[m_width + (m_height - 1) * m_width]);
	unsigned char* const start = m_image;
	int n, d;	// n is the "pixel counter"

	// Always draw at least one pixel
	if (start <= p && p < end) *p = col;

	if (abs(x1 - x0) > abs(y1 - y0)) {
		d = x0 - x1;
		for (n = abs(x1 - x0); n > 0; --n, p += incx) {
			if (start <= p && p < end) *p = col;
			d += dincx;
			if (d > 0) {
				p += incy;
				d -= dincy;
			}
		}
	}
	else {
		d = y0 - y1;
		for (n = abs(y1 - y0); n > 0; --n, p += incy) {
			if (start <= p && p < end) *p = col;
			d += dincy;
			if (d > 0) {
				p += incx;
				d -= dincx;
			}
		}
	}
}


void Corona::chooseRandomSwirl()
{
	m_swirl.x = random(0.2, 0.8);
	m_swirl.y = random(0.2, 0.8);
	m_swirl.tightness = random(-0.01, 0.01);
	m_swirl.pull = random(1.0, 1.04);
}

// FIXME: inline, optimize, simd
void Corona::setPointDelta(int x, int y)
{
	/* FIXME calculate using fixed point ? */
	double tx  = ((double) x / m_width)  - m_swirl.x;
	double ty  = ((double) y / m_height) - m_swirl.y;
	double d   = tx * tx + ty * ty;
	double ds  = ::sqrt(d);
	double ang = atan2(ty, tx) + m_swirl.tightness / (d + 0.01);
	int dx = (int) ((ds * m_swirl.pull * cos(ang) - tx) * m_width) + rand()  % 5 - 2;
	int dy = (int) ((ds * m_swirl.pull * sin(ang) - ty) * m_height) + rand() % 5 - 2;
	if (x + dx < 0) dx = -dx - x;
	if (x + dx >= m_width) dx = 2 * m_width - 2 * x - dx - 1;
	if (y + dy < 0) dy = -dy - y;
	if (y + dy >= m_height) dy = 2 * m_height - 2 * y - dy - 1;
	m_deltafield[x + y * m_width] = &(m_image[x + dx + (y + dy) * m_width]);
}

void Corona::applyDeltaField(bool heavy)
{
	/* FIXME MMXify */
	if (heavy) {
		for (int y = 0; y < m_height; ++y) {
			unsigned char *s = &(m_image[y * m_width]);
			unsigned char **p = &(m_deltafield[y * m_width]);
			for (int x = 0; x < m_width; ++x, ++s, ++p) {
				*s = (*s + *(*p)) >> 1;
				if (*s >= 2) *s -= 2;
			}
		}
	}
	else {
		for (int y = 0; y < m_height; ++y) {
			unsigned char *s = &(m_image[y * m_width]);
			unsigned char **p = &(m_deltafield[y * m_width]);
			for (int x = 0; x < m_width; ++x, ++s, ++p) {
				*s = (*s + **p) >> 1;
				if (*s >= 1) *s -= 1;
			}
		}
	}
}

int Corona::getBeatVal(TimedLevel *tl)
{
	int total = 0;
	for (int i = 50; i < 250; ++i) {
		int n = tl->frequency[0][i];
		total += n;
	}
	total /= 3;

	m_avg = 0.9 * m_avg + 0.1 * total;
	if (m_avg < 1000) m_avg = 1000;

	if (total > m_avg * 1.2 && tl->timeStamp - tl->lastbeat > 750) {
		m_avg = total;
		tl->lastbeat = tl->timeStamp;
		if (total > 2500) return 2500;
		else return total;
	}
	else return 0;
}

void Corona::drawParticules()
{
	int p;
	for (p = 0; p < nbParticules; ++p) {
		Particle *it = m_particles + p;
		int x = (int) (it->x * m_width);
		int y = (int) (it->y * m_height);
		int xv = (int) (it->xvel * m_width);
		int yv = (int) (it->yvel * m_height);
		drawLine(x, y, x - xv, y - yv, 255);
	}
}

void Corona::drawParticulesWithShift()
{
	int p;
	for (p = 0; p < nbParticules; ++p) {
		Particle *it = m_particles + p;
		int x = (int) (it->x * m_width);
		int y = (int) (it->y * m_height);
		int xv = (int) (it->xvel * m_width);
		int yv = (int) (it->yvel * m_height);
		double l = (xv * xv + yv * yv);
		if (l > 10.0 * 10.0) {
			l = ::sqrt(l);
			double dl = 10 / (l + 0.01);
			xv = (int) (xv * dl);
			yv = (int) (yv * dl);
		}
		drawLine(x, y, x - xv, y - yv, 255);
	}
}

void Corona::getAvgParticlePos(double& x, double& y) const
{
	x = y = 0;
	for (int i = 0; i < 10; ++i) {
		int r = rand() % nbParticules;
		x += m_particles[r].x;
		y += m_particles[r].y;
	}
	x /= 10;
	y /= 10;
}

#define REFL_MIN_WIDTH 3.0
#define REFL_INC_WIDTH 0.08

void Corona::genReflectedWaves(double loop)
{
	double fdec   = 0.0;
	double floop  = 0.0;
	double fwidth = (m_real_height - m_height) * REFL_INC_WIDTH + REFL_MIN_WIDTH;
	double REFL_MAX_WIDTH = fwidth;

	//  int *reflArray;
	//  reflArray = new int[(m_real_height - m_height) + m_width];

	for (int i = 0; i < m_real_height - m_height; ++i)
	{
		double fincr = (3.1415 / 2.0) * (1.0 - (fwidth - REFL_MIN_WIDTH) / REFL_MAX_WIDTH);
		floop  += fincr;

		fwidth -= REFL_INC_WIDTH;
		fdec    = fwidth * sin(floop + loop);
		m_reflArray[i] = (int)fdec;
	}
}

void Corona::drawReflected()
{
	genReflectedWaves(m_waveloop);
	int offsetDest  = (m_real_height - m_height - 1) * m_width;
	int offsetSrc   = (m_real_height - m_height)     * m_width;

	for (int i = m_real_height - m_height; i--;)
	{
		int idec = m_reflArray[i];

		for (int x = m_width; x--;)
		{
			int out = m_real_image[(offsetSrc++) + idec];
			m_real_image[offsetDest++] = out;
		}

		offsetDest -= m_width * 2;
		offsetSrc  += m_width;
	}
}

void Corona::blurImage()
{
	uint8_t *ptr = m_real_image + m_width;
	int n = (m_real_height - 2) * m_width;

	while (n--) {
		int val = *(ptr + 1);
		val += *(ptr - 1);
		val += *(ptr - m_width);
		val += *(ptr + m_width);
		val >>= 2;

		*(ptr++) = val;
	}
}

void Corona::update(TimedLevel *pLevels)
{
	// Check for a beat
	int beatval = getBeatVal(pLevels);
	if (beatval > 1000)
	{
		int total = 0;
		for (int i = 0; i < 512; ++i)
			total += 2 * pLevels->frequency[0][i];
		double currval = 1.0 - exp(-total / 40000.0);
		m_oldval = (m_oldval + currval) / 2.0;

		double tx, ty;
		getAvgParticlePos(tx, ty);
		// If most of the particles are low down, use a launch
		if (ty < 0.2 && rand() % 4 != 0) {
			int p;
			double bv = m_oldval * 5.0;
			for (p = 0; p < nbParticules; ++p)
			{
				Particle *it = m_particles + p;
				if (it->y < 0.1) {
					double x = (it->x - tx) / bv;
					it->yvel += 0.01 * bv * exp(-1000.0 * x * x);
				}
			}
		}
		else
		{	// Otherwise use a swirl
			tx += random(-0.1, 0.1);
			ty += random(-0.1, 0.1);
			double bv = 0.009 * m_oldval;
			double bv2 = 0.0036 * m_oldval;
			if (rand() % 2 == 0) bv = -bv;
			m_movement.x = tx;
			m_movement.y = ty;
			m_movement.tightness = random(0.8 * bv, bv);
			m_movement.pull = random(1 - bv2, 1 - 0.2 * bv2);
			m_swirltime = 1;
		}

		pLevels->lastbeat = pLevels->timeStamp;
	}

	// Deal with the particles
	int p;
	for (p = 0; p < nbParticules; ++p)
	{
		Particle *it = m_particles + p;
		// Apply gravity
		it->yvel -= 0.0006;		// the gravity value

		// If there's an active swirl, swirl around it
		if (m_swirltime > 0) {
			double dx = it->x - m_movement.x;
			double dy = it->y - m_movement.y;
			double d = dx * dx + dy * dy;
			double ds = ::sqrt(d);
			double ang = atan2(dy, dx) + m_movement.tightness / (d + 0.01);
			it->xvel += (ds * m_movement.pull * cos(ang) - dx);
			it->yvel += (ds * m_movement.pull * sin(ang) - dy);
		}

		// Gitter
		it->xvel += random(-0.0002, 0.0002);
		it->yvel += random(-0.0002, 0.0002);

		// Clamp the velocity
		if (it->xvel < -0.1 ) it->xvel = -0.1;
		if (it->xvel > 0.1 ) it->xvel = 0.1;
		if (it->yvel < -0.1 ) it->yvel = -0.1;
		if (it->yvel > 0.1 ) it->yvel = 0.1;

		// Randomly move the particle once in a while
		if (rand() % (nbParticules / 5) == 0)
		{
			it->x = random(0, 1);
			it->y = random(0, 1);
			it->xvel = it->yvel = 0;
		}

		// Move and bounce the particle
		it->x += it->xvel;
		it->y += it->yvel;
		if (it->x < 0) { it->x = -it->x; it->xvel *= -0.25; it->yvel *= 0.25; }
		if (it->y < 0) { it->y = -it->y; it->xvel *= 0.25; it->yvel *= -0.25; }
		if (it->x > 1) { it->x = 2.0 - it->x; it->xvel *= -0.25; it->yvel *= 0.25; }
		if (it->y > 1) { it->y = 2.0 - it->y; it->xvel *= 0.25; it->yvel = 0; }
	}

	if (m_swirltime > 0) --m_swirltime;

	// Randomly change the delta field
	if (rand() % 200 == 0) chooseRandomSwirl();

	// Animate the waves
	m_waveloop += 0.6;

	// drawing.
	if (m_image != 0)
	{
		// Draw the particles on the bitmap
		drawParticules();

		// Apply the deltafield and update a few of its points
		applyDeltaField(m_nPreset == PRESET_BLAZE && m_width * m_height < 150000); 

		int n = (m_width * m_height) / 100;
		for (int i = 0; i < n; ++i)
			setPointDelta(rand() % m_width, rand() % m_height);

		// If on the blaze preset, draw the particles again
		if (m_nPreset == PRESET_BLAZE)
			drawParticules();

		drawReflected();

		// Blur the bitmap
		blurImage();

		// If on the blaze preset, draw the particles one last time
		if (m_nPreset == PRESET_BLAZE)
			drawParticulesWithShift();
	}
}

