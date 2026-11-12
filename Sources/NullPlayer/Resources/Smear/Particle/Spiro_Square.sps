// Smear Particle Script
// Author:	mykel@earthling.net
//
// An attempt at a square with a trail that changes size and speed with music

(declare init
 (set $yrchange (+ (rnd .05) .075))
 (set $useAspect 1)
 (set $lineSize .3)
 (set $trail 20)
 (set $numParticles (* $trail 4))
 (set $useBlendType 1)
 (set $pers .7)
 (set $style 2)
 (set $fade .7)
 (set $theInit 0)
 (set $runAngle (rnd 300))
)

(declare newframe
 (if (!= $theInit 0)
  (loop $l 1 (* (- $trail 1) 4)
   (block
     (= $tl (- (* $trail 4) $l))
     (= [$Xpoint $tl] [$Xpoint (- $tl 4)])
     (= [$Ypoint $tl] [$Ypoint (- $tl 4)])
   )
  )
 )

 (+= $xr (* (sin (* $yr .938)) .05))
 (+= $zr (* (cos (* $yr .389)) .05))
 (+= $yr $yrchange)
 (if (> (= $yrchange (* $midPeak 2)) .1) (= $yrchange .1))


 (set $Xcenter (/ (* (sin (* $runAngle .839)) (cos (* $runAngle 1.39))) 2))
 (set $Ycenter (/ (* (sin (* $runAngle 1.2)) (cos (* $runAngle .89))) 4))
 (+= $runAngle .01)

 (if (> (*= $midPeak 10) .4) (= $midPeak .4))

 (if (< (abs (- $linesize $midpeak)) .025)
   (set $linesize $midPeak)
   (set $lineSize (if (< $midPeak $linesize) (- $linesize .025) (+ $linesize .025)))
 )
 (+= $linesize .01)

 (3dSetup $xr $yr $zr)

 (3dRotate $Xo $Yo $Zo $lineSize $lineSize 0)
 (set [$Xpoint 0] (/ (* (+ $Xo $Xcenter) $pers) (+ $pers $Zo)))
 (set [$Ypoint 0] (/ (* (+ $Yo $Ycenter) $pers) (+ $pers $Zo)))

 (3dRotate $Xo $Yo $Zo $lineSize (neg $lineSize) 0)
 (set [$Xpoint 1] (/ (* (+ $Xo $Xcenter) $pers) (+ $pers $Zo)))
 (set [$Ypoint 1] (/ (* (+ $Yo $Ycenter) $pers) (+ $pers $Zo)))

 (3dRotate $Xo $Yo $Zo (neg $lineSize) (neg $lineSize) 0)
 (set [$Xpoint 2] (/ (* (+ $Xo $Xcenter) $pers) (+ $pers $Zo)))
 (set [$Ypoint 2] (/ (* (+ $Yo $Ycenter) $pers) (+ $pers $Zo)))

 (3dRotate $Xo $Yo $Zo (neg $lineSize) $lineSize 0)
 (set [$Xpoint 3] (/ (* (+ $Xo $Xcenter) $pers) (+ $pers $Zo)))
 (set [$Ypoint 3] (/ (* (+ $Yo $Ycenter) $pers) (+ $pers $Zo)))

 (if (== $theInit 0)
  (block
   (= $theInit 1)
   (loop $l 4 (- (* $trail 4) 1)
    (block
      (= [$Xpoint $l] [$Xpoint (- $l 4)])
      (= [$Ypoint $l] [$Ypoint (- $l 4)])
    )
   )
  )
 )
)

(declare particle
 (set $x [$Xpoint $Particle])
 (set $y [$Ypoint $Particle])

 (set $P (if (% $Particle 4) (- $Particle 1) (+ $Particle 3)))
 (set $Xend [$Xpoint $P])
 (set $Yend [$Ypoint $P])
)
