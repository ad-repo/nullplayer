/* Libvisual-plugins - Standard plugins for libvisual
 * 
 * Copyright (C) 2000, 2001 Richard Ashburn <richard.asbury@btinternet.com>
 *
 * Authors: Richard Ashburn <richard.asbury@btinternet.com>
 * 	    Jean-Christophe Hoelt <jeko@ios-software.com>
 *	    Dennis Smit <ds@nerds-incorporated.org>
 *
 * $Id: corona_types.h,v 1.4 2005/12/20 18:49:13 synap Exp $
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

#ifndef _CORONA_TYPES_H
#define _CORONA_TYPES_H

#define pause_state 10
#define normal_state 9

// TIMED LEVEL
//
struct TimedLevel
{
  unsigned char frequency[2][512];
  int state;
  unsigned int timeStamp;

  int lastbeat; // filled by corona
};

// COLOR
//
struct ColorRGB 
{
  unsigned char rgbRed;
  unsigned char rgbGreen;
  unsigned char rgbBlue;
};


#endif
