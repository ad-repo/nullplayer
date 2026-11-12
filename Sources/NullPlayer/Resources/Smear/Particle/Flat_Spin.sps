// Smear Particle Script
// Author:	mykel@earthling.net
// Inspired by:	G-Force
//
// Just a rotating flat layer of points that moves up and down

(declare init
 (set $yrchange (+ (rnd .1) .05))
 (set $useAspect 1)
 (set $lineSize .3)
 (set $negSize (neg $lineSize))
 (set $edgeCount 8)
 (set $numParticles (* $edgeCount $edgeCount))
 (set $useBlendType 1)
 (set $pers .7)
 (set $runAngle (rnd $pi))

 (set $P 0)
 (loop $xLoop 0 (- $edgeCount 1)
  (loop $zLoop 0 (- $edgeCount 1)
   (block
    (= [$Xpoint $P] (- (* (/ $xLoop (- $edgeCount 1)) 2) 1))
    (= [$Zpoint $P] (- (* (/ $zLoop (- $edgeCount 1)) 2) 1))
    (+= $P 1)
   )
  )
 )
)

(declare newframe
 (set $yr (+ $yr $yrchange))

 (3dSetup 0 $yr 0)

 (set $yValue (* (sin $runAngle) .4))
 (+= $runAngle .01)
)

(declare particle
 (3dRotate $Xo $Yo $Zo
  (* [$XPoint $Particle] $lineSize)
  $yValue
  (* [$ZPoint $Particle] $lineSize)
 )

 (set $x (/ (* $Xo $pers) (+ $pers $Zo)))
 (set $y (/ (* $Yo $pers) (+ $pers $Zo)))
 (set $size (/ (* .015 (* 1.5 $lineSize)) (+ (* 1.5 $lineSize) $Zo)))
)
