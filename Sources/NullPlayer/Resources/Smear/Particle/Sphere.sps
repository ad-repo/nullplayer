// Smear Particle Script
// Author:	mykel@earthling.net
// Inspired By:	AcidSpunk
//
// A rotating sphere that pulses with the music, with perspective.

(declare init
 (set $xrchange (rnd .1))
 (set $yrchange (rnd .1))
 (set $zrchange (rnd .1))
 (set $useAspect 1)
 (set $lineSize .3)
 (set $negSize (neg $lineSize))
 (set $ringDots 16)
 (set $ringCount 16)
 (set $numParticles (* $ringDots $ringCount))
 (set $useBlendType 1)
 (set $pers 1)
 (set $runAngle (rnd $pi))

 // Setup point array here
 (loop $Particle 0 (- $numParticles 1)
  (block
   (set $v1 (/ (* (trunc (/ $Particle $ringDots)) 2 $pi) $ringCount))
   (set $v2 (/ (* (% $Particle $ringDots) $pi) $ringDots))

   (set [$Xpoint $Particle] (* (cos $v1) (cos $v2)))
   (set [$Ypoint $Particle] (* (cos $v1) (sin $v2)))
   (set [$Zpoint $Particle] (sin $v1))
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
 (set $negSize (neg $lineSize))

 (set $Xcenter (/ (* (sin (* $runAngle .938)) (cos (* $runAngle 1.49))) 2))
 (set $Ycenter (/ (* (sin (* $runAngle 1.1)) (cos (* $runAngle .79))) 4))
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
 (set $size (/ (* .015 (* 1.2 $lineSize)) (+ (* 1.2 $lineSize) $Zo)))
)
