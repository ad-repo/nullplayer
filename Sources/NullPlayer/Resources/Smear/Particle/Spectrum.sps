// Smear Particle Script
// Concept from:	G-Force
// Scripted:		mykel@earthling.net

(declare init
 (set $useAspect 1)
 (set $numParticles 16)
 (set $useBlendType 1)
 (set $fade .3)
 (set $offY 1)
)

(declare newframe
 (set $offY (- $offY 0.011))
)

(declare particle
 (set $t (/ $Particle $numParticles))
 (set $x (wrap (* $t 2) -1 1))
 (set $y (wrap $offY -1 1))
 (set $size (clamp (* (+ (lSpect $t) (rSpect (- 1 $t))) 5) .01 .8))
)
