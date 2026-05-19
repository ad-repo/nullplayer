#ifndef TRIPEX_PORT_D3D9_STUB_H
#define TRIPEX_PORT_D3D9_STUB_H

// Empty stub. Upstream Tripex includes <d3d9.h> from a handful of effect
// files (e.g. EffectBlank.cpp) but never actually uses any D3D9 type
// symbols outside of RendererDirect3d.{cpp,h}, which the port excludes
// entirely. We provide an empty header here so the `#include <d3d9.h>`
// preprocessor line resolves without forcing edits to upstream files.

#endif
