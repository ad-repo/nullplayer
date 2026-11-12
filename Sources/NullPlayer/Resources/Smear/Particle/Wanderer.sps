// Smear Particle Script
// Author:		mykel@earthling.net
//
// Four blobs that wander around the screen

(declare init
 (set $useAspect 1)
 (set $numParticles 16)
 (set $useBlendType 1)
 (set $fade .3)
 (set $a0 (rnd (* 2 $pi)))
 (set $a1 (rnd (* 2 $pi)))
 (set $a2 (rnd (* 2 $pi)))
 (set $a3 (rnd (* 2 $pi)))
 (set $d0 (rnd 0.1))
 (set $d1 (rnd 0.1))
 (set $d2 (rnd 0.1))
 (set $d3 (rnd 0.1))
 (set $size .4)
)

(declare newframe
 (set $a0 (wrap (+ $a0 $d0) (* 2 $pi)))
 (set $a1 (wrap (+ $a1 $d0) (* 2 $pi)))
 (set $a2 (wrap (+ $a2 $d0) (* 2 $pi)))
 (set $a3 (wrap (+ $a3 $d0) (* 2 $pi)))
)

(declare particle
 (if (== $Particle 0) (block
   (set $x (* (cos $a0) (sin $a1)))
   (set $y (* (cos $a2) (sin $a3)))
 ))
 (if (== $Particle 1) (block
   (set $x (* (cos (* .9824 $a0)) (sin (* .8384 $a3))))
   (set $y (* (cos (* .8942 $a1)) (sin (* 1.289 $a2))))
 ))
 (if (== $Particle 2) (block
   (set $x (* (cos (* .8930 $a1)) (sin (* .7979 $a1))))
   (set $y (* (cos (* 1.392 $a0)) (sin (* .9909 $a3))))
 ))
 (if (== $Particle 3) (block
   (set $x (* (cos (* 1.934 $a2)) (sin (* .8884 $a3))))
   (set $y (* (cos (* .9042 $a1)) (sin (* 2.289 $a0))))
 ))
)
