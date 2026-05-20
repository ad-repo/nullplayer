// Out-of-class definitions for upstream `static const` members that are
// ODR-used in non-MSVC builds.
//
// Background: Tripex's MSVC build treats class-scope `static const`
// integer initializers as valid definitions. Under clang/C++17, taking
// the address (or using by const-reference, as `std::vector::push_back`
// does) ODR-uses the member and requires an out-of-class definition.

#include "Actor.h"

const uint16 Actor::WORD_INVALID_INDEX;
