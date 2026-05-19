# Tripex

<p align="center">
  <img src="tripex.jpg" />
</p>

## Requirements

- Visual Studio 2022 (v143 toolset)
- DirectX 8
- Windows

## Background

**[Tripex](https://web.archive.org/web/20040130121720/http://www.tripex.co.uk/)**
is a visualization plugin I wrote for Winamp around 20 years ago. It seemed
[kinda popular](https://winampheritage.com/visualization/tripex3/92178) at the
time, though definitely shows its age now. I lost the original source code in a
hard drive crash around 2003, and hadn't kept a backup.

I mentioned it to a friend over the winter break, and remembered that I'd given
a copy to the guys that develop [Kodi](https://en.wikipedia.org/wiki/Kodi_(software))
(formerly Xbox Media Center). They'd [run a competition](https://kodi.tv/article/xbmc-visualization-competition/)
to add visualizations to XBMC and someone asked me to contribute, but I didn't have an
Xbox - so I made it into a standalone Win32 app and
[gave them the source](https://forum.kodi.tv/showthread.php?tid=10317).

The [wayback machine](https://www.archive.org) captured
[copy of that zip file](https://web.archive.org/web/20250000000000*/http://www.xboxmediacenter.com/temp/tripex_19-04-2004src.zip),
so I spent a few days getting it running and tidying it up.

It felt like a pretty wild exercise to go back to C++ code I'd written 20 years
earlier. I have plenty of eyebrow-raising judgements of my younger self:

* I commented very little.
* I was just starting to go down the rabbit hole of using C++ templates way more
than is necessary.
* I didn't use any VCS, so I left large chunks of code duplicated but commented
out in the same source files as a sort of "backup" in case I changed my mind.
* My intuition for optimization was pretty skewed, as was my tendency towards
premature optimization. I thought I was being clever writing things in certain
ways, while having a huge blind spot for others.
* I had certain quirks of style that I was very attached to, and really went out
of my way to follow them. I still do that to a degree, I'm embarrased to say,
but at least I'm much more wary of how counter-productive that sort of dogma can
be.

(Also interesting: CL.EXE used to leak variables from `for` loop initializers
into [the parent scope](https://learn.microsoft.com/en-us/cpp/build/reference/zc-forscope-force-conformance-in-for-loop-scope?view=msvc-170)
by default, which seems like an wildly divergent bit of standards compliance
compared to the sort of differences between GCC/Clang/MSVC today...) 

Anyway, some of the code quality isn't great, but it does the job. It should be
pretty self-contained and embeddable; I tried to get rid of all the global
variables and abstracted most of the platform-specific parts. The renderer
has fairly basic requirements (a fixed-function pipeline, one texture stage,
just a couple of alpha blend modes), and all the clipping is done in software.

## Notes

- I'd stripped out a lot of the Winamp-specific UI before passing it on to the
Kodi guys, like the 'Now playing' controls, window chrome, and Winamp settings
dialog. That's a shame - I spent a lot of time implementing little details
there, like a GDI software renderer to show an animation on the main page in
that dialog, as well as a nice little animated water simulation that ran in the
title bar. 

- The metaballs effect is also missing. I don't remember what happened to that, 
but it was a fairly standard implementation of the marching cubes algorithm.

## Links

* [www.tripex.co.uk (via archive.org)](https://web.archive.org/web/20040130121720/http://www.tripex.co.uk/)
