// Smear Particle Script
// Concept from:	G-Force
// Scripted by:		mykel@earthling.net

(declare init
 (set $offX (rnd -1 1))
 (set $offY (rnd -1 1))
 (set $offA (rnd))
 (set $useAspect 1)
 (set $numParticles 256)
 (set $useBlendType 1)
 (set $fade .3)
)

(declare newframe
 (set $offA (+ $offA 0.03))
 (set $offX (* (sin $offA) 0.28))
 (set $offY (* (cos $offA) 0.38))
)

(declare particle
 (set $x (wrap (- (/ (trunc (/ $Particle 16)) 8) $offX) -1 1))
 (set $y (wrap (- (/ (trunc (mod $Particle 16)) 8) $offY) -1 1))
 (set $size 0.015)
)
