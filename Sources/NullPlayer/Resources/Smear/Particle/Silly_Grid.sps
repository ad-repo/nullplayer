// Smear Particle Script
// Author:	mykel@earthling.net
//
// A silly grid

(declare init
 (set $yrchange (+ (rnd .1) .05))
 (set $useAspect 1)
 (set $lineSize .3)
 (set $negSize (neg $lineSize))
 (set $edgeCount 8)
 (set $numParticles (* $edgeCount 2))
 (set $useBlendType 1)
 (set $pers .7)
 (set $runAngle (rnd $pi))
 (set $style 2)
 (set $fade .4)

 (set $P 0)
 (loop $Loop 0 (- $edgeCount 1)
   (block
    (= [$Xpoint $P] (- (* (/ $Loop (- $edgeCount 1)) 2) 1))
    (= [$Zpoint $P] 1)

    (= [$Xpoint (+ $P $numParticles)] (- (* (/ $Loop (- $edgeCount 1)) 2) 1))
    (= [$Zpoint (+ $P $numParticles)] -1)
    (+= $P 1)

    (= [$Xpoint $P] 1)
    (= [$Zpoint $P] (- (* (/ $Loop (- $edgeCount 1)) 2) 1))

    (= [$Xpoint (+ $P $numParticles)] -1)
    (= [$Zpoint (+ $P $numParticles)] (- (* (/ $Loop (- $edgeCount 1)) 2) 1))
    (+= $P 1)
   )
 )
)

(declare newframe
 (+= $xr (* (sin (* $yr .938)) .1))
 (+= $zr (* (cos (* $yr .389)) .1))
 (+= $yr $yrchange)

 (3dSetup $xr $yr $zr)

 (set $yValue (* (sin $runAngle) .4))
 (+= $runAngle .006)
)

(declare particle
 (3dRotate $Xo $Yo $Zo
  (* [$XPoint $Particle] $lineSize)
  $yValue
  (* [$ZPoint $Particle] $lineSize)
 )

 (3dRotate $Xo2 $Yo2 $Zo2
  (* [$XPoint (+ $Particle $numParticles)] $lineSize)
  $yValue
  (* [$ZPoint (+ $Particle $numParticles)] $lineSize)
 )

 (set $x (/ (* $Xo $pers) (+ $pers $Zo)))
 (set $y (/ (* $Yo $pers) (+ $pers $Zo)))

 (set $Xend (/ (* $Xo2 $pers) (+ $pers $Zo2)))
 (set $Yend (/ (* $Yo2 $pers) (+ $pers $Zo2)))
// (set $size (/ (* .015 (* 1.5 $lineSize)) (+ (* 1.5 $lineSize) $Zo)))
)
