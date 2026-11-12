// Smear Particle Script
// Author:	mykel@earthling.net
//
// A rotating toroid that pulses with the music, with perspective.

(declare init
 (set $xrchange (rnd .1))
 (set $yrchange (rnd .1))
 (set $zrchange (rnd .1))
 (set $useAspect 1)
 (set $ringDots 8)
 (set $ringCount 32)
 (set $numParticles (* $ringDots $ringCount))
 (set $useBlendType 1)
 (set $pers 1)
 (set $runAngle (rnd $pi))

 // Setup shape
 (loop $Particle 0 (- $numParticles 1)
   (block
     (set $v1 (/ (* (trunc (/ $Particle $ringDots)) 2 $pi) $ringCount))
     (set $v2 (/ (* (% $Particle $ringDots) 2 $pi) $ringDots))
     (+= $v2 (* (/ (/ $Particle $ringDots) $ringCount) 2 $pi))

     (set [$XPoint $Particle] (+ (* (cos $v1) (cos $v2) .25) (cos $v2)))
     (set [$YPoint $Particle] (+ (* (cos $v1) (sin $v2) .25) (sin $v2)))
     (set [$ZPoint $Particle] (* (sin $v1) .25))
   )
 )
)

(declare newframe
 (set $xr (+ $xr $xrchange))
 (set $yr (+ $yr $yrchange))
 (set $zr (+ $zr $zrchange))

 (3dSetup $xr $yr $zr)

 (set $midpeak (+ $midpeak .1))
 (if (< (abs (- $linesize $midpeak)) .025)
   (set $linesize $midPeak)
   (set $lineSize (if (< $midPeak $linesize) (- $linesize .025) (+ $linesize .025)))
 )
 (+= $linesize .01)

 (set $Xcenter (/ (* (sin (* $runAngle 1.228)) (cos (* $runAngle .49))) 2))
 (set $Ycenter (/ (* (sin (* $runAngle 1.9)) (cos (* $runAngle .39))) 4))
 (+= $runAngle .01)
)

(declare particle
 (3dRotate $Xo $Yo $Zo
   (* [$Xpoint $Particle] $lineSize)
   (* [$Ypoint $Particle] $lineSize)
   (* [$Zpoint $Particle] $lineSize)
 )

 (+= $Xo $Xcenter)
 (+= $Yo $Ycenter)
 
 (set $x (/ (* $Xo $pers) (+ $pers $Zo)))
 (set $y (/ (* $Yo $pers) (+ $pers $Zo)))
 (set $size (/ (* .015 (* 1.5 $lineSize)) (+ (* 1.5 $lineSize) $Zo)))
)
