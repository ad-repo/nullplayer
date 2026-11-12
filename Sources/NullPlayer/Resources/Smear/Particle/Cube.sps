// Smear Particle Script
// Author:	mykel@earthling.net
//
// A rotating cube that pulses with the music, with perspective.

(declare init
 (set $xrchange (rnd .1))
 (set $yrchange (rnd .1))
 (set $zrchange (rnd .1))
 (set $useAspect 1)
 (set $lineSize .3)
 (set $negSize (neg $lineSize))
 (set $lineDots 6)
 (set $numParticles (- (* 12 $lineDots) 4))
 (set $useBlendType 1)
 (set $pers 1)

 // Setup the points
 (set $P 0)
 (loop $v 0 (- $lineDots 1) (block
     (= $pn (- (* (/ $v $lineDots) 2) 1))
     (= $np (- 0 $pn))

     (= [$Xpoint $P]   1) (= [$Ypoint $P]  1) (= [$Zpoint $P] $pn) (+= $P 1)
     (= [$Xpoint $P]  -1) (= [$Ypoint $P]  1) (= [$Zpoint $P] $np) (+= $P 1)
     (= [$Xpoint $P] $np) (= [$Ypoint $P]  1) (= [$Zpoint $P]   1) (+= $P 1) 
     (= [$Xpoint $P] $pn) (= [$Ypoint $P]  1) (= [$Zpoint $P]  -1) (+= $P 1) 
     (= [$Xpoint $P]   1) (= [$Ypoint $P] -1) (= [$Zpoint $P] $pn) (+= $P 1) 
     (= [$Xpoint $P]  -1) (= [$Ypoint $P] -1) (= [$Zpoint $P] $np) (+= $P 1) 
     (= [$Xpoint $P] $np) (= [$Ypoint $P] -1) (= [$Zpoint $P]   1) (+= $P 1) 
     (= [$Xpoint $P] $pn) (= [$Ypoint $P] -1) (= [$Zpoint $P]  -1) (+= $P 1) 

     (if (> $v 0) (block
         (= [$Xpoint $P]  1) (= [$Ypoint $P] $pn) (= [$Zpoint $P]  1) (+= $P 1)
         (= [$Xpoint $P]  1) (= [$Ypoint $P] $pn) (= [$Zpoint $P] -1) (+= $P 1)
         (= [$Xpoint $P] -1) (= [$Ypoint $P] $pn) (= [$Zpoint $P]  1) (+= $P 1)
         (= [$Xpoint $P] -1) (= [$Ypoint $P] $pn) (= [$Zpoint $P] -1) (+= $P 1)
 ))))
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
 (set $negSize (neg $lineSize))
)

(declare particle
 (3dRotate $Xo $Yo $Zo
   (* [$Xpoint $Particle] $lineSize)
   (* [$Ypoint $Particle] $lineSize)
   (* [$Zpoint $Particle] $lineSize)
 )
 
 (set $x (/ (* $Xo $pers) (+ $pers $Zo)))
 (set $y (/ (* $Yo $pers) (+ $pers $Zo)))
 (set $size (/ (* .03 (* 2 $lineSize)) (+ (* 2 $lineSize) $Zo)))
)
