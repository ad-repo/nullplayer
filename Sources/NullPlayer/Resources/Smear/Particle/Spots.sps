// Smear Particle Script
// Concept from:	G-Force
// Scripted by:		mykel@earthling.net

(declare init
 (set $useAspect 1)
 (set $numParticles 8)
 (set $useBlendType 1)
 (set $offY -1)
)

(declare newframe
 (set $offY (+ $offY 0.02))
)

(declare particle
 (set $x (rnd -1 1))
 (set $y (wrap (+ $offY (rnd .2)) -1 1))
 (set $size (rnd 0.015 0.5))
)
