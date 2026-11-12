// Smear Particle Script
// Concept from:	G-Force
// Scripted by:		mykel@earthling.net

(declare init
 (set $spinAngle 0)
 (set $magAngle 0)
 (set $useAspect 1)
 (set $numParticles 16)
 (set $useBlendType 1)
)

(declare newframe
 (set $magAngle (+ $magAngle 0.016))
 (set $spinAngle (+ $magAngle 0.05))
 (set $mag (/ (+ (sin $magAngle) 1.1) 2.5))
)

(declare particle
 (cart $x $y $mag (+ $spinAngle (* (/ $Particle $numParticles) (* 2 $pi))))
 (set $size (/ (* $mag 2) 8))
)
