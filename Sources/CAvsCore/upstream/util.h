#pragma once

// "Signed" or "small" sizeof operators. When sizeof x is known to fit into a specific
// signed integer, i.e. ssizeofN(x) => sizeof(x) <= 2^(N-1). This suppresses signed /
// unsigned comparison warnings, without turning everything on the other side into
// unsigned types, which is not always desired or possible.
// If the size assumption is violated the value will overflow and you will get negative
// sizes.
#define ssizeof8(x)  ((int8_t)sizeof(x))
#define ssizeof32(x) ((int32_t)sizeof(x))
#define ssizeof64(x) ((int64_t)sizeof(x))

// DLLRENDERBASE is the magic effect-ID cutoff that signifies an APE effect. If the
// legacy effect ID is less than this, it's a builtin effect. If it's greater than or
// equal to this, it's an APE. The actual type of the APE effect is encoded in the 32
// bytes following this value.
// The legacy saving code used to use the _pointer_ to the effect object as the ID,
// which, because of how memory is laid out, was in practice always greater than this
// value. The current legacy saving code just always uses this specific value.
#define DLLRENDERBASE 0x4000  // 16384
