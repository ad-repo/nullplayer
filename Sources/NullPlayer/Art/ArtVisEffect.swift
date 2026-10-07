import AppKit
import CoreImage
import Metal

/// The Art window's audio-reactive effects: 30 Core Image filter chains over the playing track's
/// cover. One copy for every skin family (the Library Browser used to carry two that had drifted).
enum ArtVisEffect: String, CaseIterable {
    case psychedelic = "Psychedelic", kaleidoscope = "Kaleidoscope", vortex = "Vortex", spin = "Endless Spin"
    case fractal = "Fractal Zoom", tunnel = "Time Tunnel", melt = "Acid Melt", wave = "Ocean Wave"
    case glitch = "Glitch", rgbSplit = "RGB Split", twist = "Twist", fisheye = "Fisheye"
    case shatter = "Shatter", stretch = "Rubber Band", zoom = "Zoom Pulse", shake = "Earthquake"
    case bounce = "Bounce", feedback = "Feedback Loop", strobe = "Strobe", jitter = "Jitter"
    case mirror = "Infinite Mirror", tile = "Tile Grid", prism = "Prism Split", doubleVision = "Double Vision"
    case flipbook = "Flipbook", mosaic = "Mosaic", pixelate = "Pixelate", scanlines = "Scanlines"
    case datamosh = "Datamosh", blocky = "Blocky"

    static let groups: [(title: String, effects: [ArtVisEffect])] = [
        ("Rotation & Scaling", [.psychedelic, .kaleidoscope, .vortex, .spin, .fractal, .tunnel]),
        ("Distortion",         [.melt, .wave, .glitch, .rgbSplit, .twist, .fisheye, .shatter, .stretch]),
        ("Motion",             [.zoom, .shake, .bounce, .feedback, .strobe, .jitter]),
        ("Copies & Mirrors",   [.mirror, .tile, .prism, .doubleVision, .flipbook, .mosaic]),
        ("Pixel Effects",      [.pixelate, .scanlines, .datamosh, .blocky]),
    ]

    /// The effect `offset` places away in `allCases`, wrapping at both ends.
    func advanced(by offset: Int) -> ArtVisEffect {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + offset % all.count + all.count) % all.count]
    }
}

/// Renders one frame of an `ArtVisEffect` on the GPU.
final class ArtVisRenderer {
    private lazy var ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()

    /// `spectrum` is the engine's 75 bands: 0-9 bass, 10-39 mid, 40-74 treble.
    func render(_ cgImage: CGImage, effect: ArtVisEffect, spectrum: [Float],
                time: TimeInterval, intensity: CGFloat) -> CGImage? {
        let bass = CGFloat(spectrum.prefix(10).reduce(0, +) / 10.0)
        let mid = CGFloat(spectrum.dropFirst(10).prefix(30).reduce(0, +) / 30.0)
        let treble = CGFloat(spectrum.dropFirst(40).prefix(35).reduce(0, +) / 35.0)
        let level = (bass + mid + treble) / 3.0
        let t = CGFloat(time)

        var ciImage = CIImage(cgImage: cgImage)
        let imageSize = ciImage.extent.size
        let center = CIVector(x: imageSize.width / 2, y: imageSize.height / 2)

        switch effect {
        case .psychedelic:
            // Twirl + hue rotation + bloom
            let twirl = CIFilter(name: "CITwirlDistortion")!
            twirl.setValue(ciImage, forKey: kCIInputImageKey)
            twirl.setValue(center, forKey: kCIInputCenterKey)
            twirl.setValue(min(imageSize.width, imageSize.height) * 0.4, forKey: kCIInputRadiusKey)
            twirl.setValue(bass * 3 * intensity * sin(t * 2), forKey: kCIInputAngleKey)
            ciImage = twirl.outputImage ?? ciImage
            
            let hue = CIFilter(name: "CIHueAdjust")!
            hue.setValue(ciImage, forKey: kCIInputImageKey)
            hue.setValue(t * 0.5 + bass, forKey: kCIInputAngleKey)
            ciImage = hue.outputImage ?? ciImage
            
            let bloom = CIFilter(name: "CIBloom")!
            bloom.setValue(ciImage, forKey: kCIInputImageKey)
            bloom.setValue(10 * level * intensity, forKey: kCIInputRadiusKey)
            bloom.setValue(1.0 + bass * intensity, forKey: kCIInputIntensityKey)
            ciImage = bloom.outputImage ?? ciImage
            
        case .kaleidoscope:
            let kaleido = CIFilter(name: "CIKaleidoscope")!
            kaleido.setValue(ciImage, forKey: kCIInputImageKey)
            kaleido.setValue(center, forKey: kCIInputCenterKey)
            kaleido.setValue(Int(6 + bass * 6 * intensity), forKey: "inputCount")
            kaleido.setValue(t * 0.3 * intensity, forKey: kCIInputAngleKey)
            ciImage = kaleido.outputImage ?? ciImage
            
        case .vortex:
            let vortex = CIFilter(name: "CIVortexDistortion")!
            vortex.setValue(ciImage, forKey: kCIInputImageKey)
            vortex.setValue(center, forKey: kCIInputCenterKey)
            vortex.setValue(min(imageSize.width, imageSize.height) * 0.5, forKey: kCIInputRadiusKey)
            vortex.setValue(bass * 10 * intensity * sin(t), forKey: kCIInputAngleKey)
            ciImage = vortex.outputImage ?? ciImage
            
        case .spin:
            // Zoom blur + rotation
            let zoomBlur = CIFilter(name: "CIZoomBlur")!
            zoomBlur.setValue(ciImage, forKey: kCIInputImageKey)
            zoomBlur.setValue(center, forKey: kCIInputCenterKey)
            zoomBlur.setValue(bass * 20 * intensity, forKey: kCIInputAmountKey)
            ciImage = zoomBlur.outputImage ?? ciImage
            
            let transform = CIFilter(name: "CIAffineTransform")!
            var affine = CGAffineTransform(translationX: imageSize.width/2, y: imageSize.height/2)
            affine = affine.rotated(by: t * 2 * intensity)
            affine = affine.translatedBy(x: -imageSize.width/2, y: -imageSize.height/2)
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(affine, forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
            
        case .fractal:
            // Multiple zoom levels
            let scale = 1.0 + sin(t * intensity) * 0.3 * bass
            let transform = CIFilter(name: "CIAffineTransform")!
            var affine = CGAffineTransform(translationX: imageSize.width/2, y: imageSize.height/2)
            affine = affine.scaledBy(x: scale, y: scale)
            affine = affine.rotated(by: t * 0.2 * intensity)
            affine = affine.translatedBy(x: -imageSize.width/2, y: -imageSize.height/2)
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(affine, forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
            
            let bloom = CIFilter(name: "CIBloom")!
            bloom.setValue(ciImage, forKey: kCIInputImageKey)
            bloom.setValue(20 * bass * intensity, forKey: kCIInputRadiusKey)
            bloom.setValue(0.5 + level, forKey: kCIInputIntensityKey)
            ciImage = bloom.outputImage ?? ciImage
            
        case .tunnel:
            let hole = CIFilter(name: "CIHoleDistortion")!
            hole.setValue(ciImage, forKey: kCIInputImageKey)
            hole.setValue(center, forKey: kCIInputCenterKey)
            hole.setValue(50 + bass * 100 * intensity * abs(sin(t)), forKey: kCIInputRadiusKey)
            ciImage = hole.outputImage ?? ciImage
            
        case .melt:
            // Glass distortion for melting effect
            let glass = CIFilter(name: "CIGlassDistortion")!
            glass.setValue(ciImage, forKey: kCIInputImageKey)
            // Create a simple texture
            let noiseFilter = CIFilter(name: "CIRandomGenerator")!
            if let noise = noiseFilter.outputImage?.cropped(to: ciImage.extent) {
                glass.setValue(noise, forKey: "inputTexture")
                glass.setValue(center, forKey: kCIInputCenterKey)
                glass.setValue(50 * bass * intensity, forKey: kCIInputScaleKey)
                ciImage = glass.outputImage ?? ciImage
            }
            
        case .wave:
            // Bump distortion moving across
            let bump = CIFilter(name: "CIBumpDistortion")!
            let waveX = imageSize.width * (0.5 + 0.4 * sin(t * 2))
            let waveY = imageSize.height * (0.5 + 0.3 * cos(t * 1.5))
            bump.setValue(ciImage, forKey: kCIInputImageKey)
            bump.setValue(CIVector(x: waveX, y: waveY), forKey: kCIInputCenterKey)
            bump.setValue(min(imageSize.width, imageSize.height) * 0.4, forKey: kCIInputRadiusKey)
            bump.setValue(bass * 2 * intensity * sin(t * 3), forKey: kCIInputScaleKey)
            ciImage = bump.outputImage ?? ciImage
            
        case .glitch:
            // RGB offset + posterize
            if bass > 0.3 {
                let offset = bass * 30 * intensity
                
                // Separate and offset RGB channels
                let rOffset = CIFilter(name: "CIAffineTransform")!
                rOffset.setValue(ciImage, forKey: kCIInputImageKey)
                rOffset.setValue(CGAffineTransform(translationX: offset, y: 0), forKey: kCIInputTransformKey)
                
                let colorMatrix = CIFilter(name: "CIColorMatrix")!
                colorMatrix.setValue(ciImage, forKey: kCIInputImageKey)
                colorMatrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
                colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
                ciImage = colorMatrix.outputImage ?? ciImage
            }
            
            let posterize = CIFilter(name: "CIColorPosterize")!
            posterize.setValue(ciImage, forKey: kCIInputImageKey)
            posterize.setValue(4 + (1 - bass) * 10, forKey: "inputLevels")
            ciImage = posterize.outputImage ?? ciImage
            
        case .rgbSplit:
            let offset = (10 + bass * 40) * intensity
            
            // Create offset versions
            let rFilter = CIFilter(name: "CIColorMatrix")!
            rFilter.setValue(ciImage, forKey: kCIInputImageKey)
            rFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
            rFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
            rFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
            let rImage = rFilter.outputImage ?? ciImage
            
            let gFilter = CIFilter(name: "CIColorMatrix")!
            gFilter.setValue(ciImage, forKey: kCIInputImageKey)
            gFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
            gFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
            gFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
            let gImage = gFilter.outputImage ?? ciImage
            
            let bFilter = CIFilter(name: "CIColorMatrix")!
            bFilter.setValue(ciImage, forKey: kCIInputImageKey)
            bFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
            bFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
            bFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
            let bImage = bFilter.outputImage ?? ciImage
            
            // Offset red
            let rTransform = CIFilter(name: "CIAffineTransform")!
            rTransform.setValue(rImage, forKey: kCIInputImageKey)
            rTransform.setValue(CGAffineTransform(translationX: -offset, y: 0), forKey: kCIInputTransformKey)
            let rOffset = rTransform.outputImage ?? rImage
            
            // Offset blue
            let bTransform = CIFilter(name: "CIAffineTransform")!
            bTransform.setValue(bImage, forKey: kCIInputImageKey)
            bTransform.setValue(CGAffineTransform(translationX: offset, y: 0), forKey: kCIInputTransformKey)
            let bOffset = bTransform.outputImage ?? bImage
            
            // Combine
            let addR = CIFilter(name: "CIAdditionCompositing")!
            addR.setValue(rOffset, forKey: kCIInputImageKey)
            addR.setValue(gImage, forKey: kCIInputBackgroundImageKey)
            let rg = addR.outputImage ?? ciImage
            
            let addB = CIFilter(name: "CIAdditionCompositing")!
            addB.setValue(bOffset, forKey: kCIInputImageKey)
            addB.setValue(rg, forKey: kCIInputBackgroundImageKey)
            ciImage = addB.outputImage ?? ciImage
            
        case .twist:
            let twirl = CIFilter(name: "CITwirlDistortion")!
            twirl.setValue(ciImage, forKey: kCIInputImageKey)
            twirl.setValue(center, forKey: kCIInputCenterKey)
            twirl.setValue(min(imageSize.width, imageSize.height) * 0.6, forKey: kCIInputRadiusKey)
            twirl.setValue(t * 2 * intensity + bass * 5, forKey: kCIInputAngleKey)
            ciImage = twirl.outputImage ?? ciImage
            
        case .fisheye:
            let bump = CIFilter(name: "CIBumpDistortion")!
            bump.setValue(ciImage, forKey: kCIInputImageKey)
            bump.setValue(center, forKey: kCIInputCenterKey)
            bump.setValue(min(imageSize.width, imageSize.height) * 0.8, forKey: kCIInputRadiusKey)
            bump.setValue(-1.5 * intensity * (1 + bass * 0.5), forKey: kCIInputScaleKey)
            ciImage = bump.outputImage ?? ciImage
            
        case .shatter:
            // Triangular tile + displacement
            let triangle = CIFilter(name: "CITriangleTile")!
            triangle.setValue(ciImage, forKey: kCIInputImageKey)
            triangle.setValue(center, forKey: kCIInputCenterKey)
            triangle.setValue(t * 0.5 * intensity, forKey: kCIInputAngleKey)
            triangle.setValue(50 + bass * 100 * intensity, forKey: kCIInputWidthKey)
            ciImage = triangle.outputImage?.cropped(to: CIImage(cgImage: cgImage).extent) ?? ciImage
            
        case .stretch:
            let pinch = CIFilter(name: "CIPinchDistortion")!
            pinch.setValue(ciImage, forKey: kCIInputImageKey)
            pinch.setValue(center, forKey: kCIInputCenterKey)
            pinch.setValue(min(imageSize.width, imageSize.height) * 0.7, forKey: kCIInputRadiusKey)
            pinch.setValue(bass * intensity * sin(t * 2), forKey: kCIInputScaleKey)
            ciImage = pinch.outputImage ?? ciImage
            
        case .zoom:
            let zoomBlur = CIFilter(name: "CIZoomBlur")!
            zoomBlur.setValue(ciImage, forKey: kCIInputImageKey)
            zoomBlur.setValue(center, forKey: kCIInputCenterKey)
            zoomBlur.setValue(bass * 50 * intensity, forKey: kCIInputAmountKey)
            ciImage = zoomBlur.outputImage ?? ciImage
            
        case .shake:
            let offset = bass * 30 * intensity
            let shakeX = sin(t * 30) * offset
            let shakeY = cos(t * 25) * offset * 0.7
            
            let transform = CIFilter(name: "CIAffineTransform")!
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(CGAffineTransform(translationX: shakeX, y: shakeY), forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
            
            let motionBlur = CIFilter(name: "CIMotionBlur")!
            motionBlur.setValue(ciImage, forKey: kCIInputImageKey)
            motionBlur.setValue(bass * 20 * intensity, forKey: kCIInputRadiusKey)
            motionBlur.setValue(t * 10, forKey: kCIInputAngleKey)
            ciImage = motionBlur.outputImage ?? ciImage
            
        case .bounce:
            let bounceY = abs(sin(t * 3 * intensity)) * 50 * bass
            let scaleY = 1.0 - (1 - abs(sin(t * 3 * intensity))) * bass * 0.2 * intensity
            
            let transform = CIFilter(name: "CIAffineTransform")!
            var affine = CGAffineTransform(translationX: 0, y: bounceY)
            affine = affine.concatenating(CGAffineTransform(scaleX: 1.0 / scaleY, y: scaleY))
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(affine, forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
            
        case .feedback:
            // Multiple scaled copies
            for i in 1..<5 {
                let scale = 1.0 - CGFloat(i) * 0.1
                let alpha = 0.5 / CGFloat(i)
                
                let scaleTransform = CIFilter(name: "CIAffineTransform")!
                var affine = CGAffineTransform(translationX: imageSize.width/2, y: imageSize.height/2)
                affine = affine.scaledBy(x: scale, y: scale)
                affine = affine.rotated(by: CGFloat(i) * 0.05 * bass * intensity)
                affine = affine.translatedBy(x: -imageSize.width/2, y: -imageSize.height/2)
                scaleTransform.setValue(CIImage(cgImage: cgImage), forKey: kCIInputImageKey)
                scaleTransform.setValue(affine, forKey: kCIInputTransformKey)
                
                if let layerImage = scaleTransform.outputImage {
                    let blend = CIFilter(name: "CISourceOverCompositing")!
                    blend.setValue(layerImage.applyingFilter("CIColorMatrix", parameters: [
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
                    ]), forKey: kCIInputImageKey)
                    blend.setValue(ciImage, forKey: kCIInputBackgroundImageKey)
                    ciImage = blend.outputImage ?? ciImage
                }
            }
            
            let bloom = CIFilter(name: "CIBloom")!
            bloom.setValue(ciImage, forKey: kCIInputImageKey)
            bloom.setValue(15 * level * intensity, forKey: kCIInputRadiusKey)
            bloom.setValue(0.5 + bass, forKey: kCIInputIntensityKey)
            ciImage = bloom.outputImage ?? ciImage
            
        case .strobe:
            let strobeOn = Int(t * 10 * intensity) % 2 == 0 || bass > 0.6
            if strobeOn {
                let exposure = CIFilter(name: "CIExposureAdjust")!
                exposure.setValue(ciImage, forKey: kCIInputImageKey)
                exposure.setValue(bass * 2 * intensity, forKey: kCIInputEVKey)
                ciImage = exposure.outputImage ?? ciImage
            } else {
                let exposure = CIFilter(name: "CIExposureAdjust")!
                exposure.setValue(ciImage, forKey: kCIInputImageKey)
                exposure.setValue(-1.0, forKey: kCIInputEVKey)
                ciImage = exposure.outputImage ?? ciImage
            }
            
        case .jitter:
            let jitterX = CGFloat.random(in: -1...1) * bass * 20 * intensity
            let jitterY = CGFloat.random(in: -1...1) * bass * 20 * intensity
            let jitterScale = 1.0 + CGFloat.random(in: -0.05...0.05) * bass * intensity
            
            let transform = CIFilter(name: "CIAffineTransform")!
            var affine = CGAffineTransform(translationX: jitterX, y: jitterY)
            affine = affine.scaledBy(x: jitterScale, y: jitterScale)
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(affine, forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
            
        case .mirror:
            // 4-way mirror
            let fourFold = CIFilter(name: "CIFourfoldReflectedTile")!
            fourFold.setValue(ciImage, forKey: kCIInputImageKey)
            fourFold.setValue(center, forKey: kCIInputCenterKey)
            fourFold.setValue(t * 0.2 * intensity, forKey: kCIInputAngleKey)
            fourFold.setValue(imageSize.width * (0.3 + bass * 0.2 * intensity), forKey: kCIInputWidthKey)
            ciImage = fourFold.outputImage?.cropped(to: CIImage(cgImage: cgImage).extent) ?? ciImage
            
        case .tile:
            let op = CIFilter(name: "CIOpTile")!
            op.setValue(ciImage, forKey: kCIInputImageKey)
            op.setValue(center, forKey: kCIInputCenterKey)
            op.setValue(t * intensity, forKey: kCIInputAngleKey)
            op.setValue(1.5 + bass * intensity, forKey: kCIInputScaleKey)
            op.setValue(imageSize.width * 0.3, forKey: kCIInputWidthKey)
            ciImage = op.outputImage?.cropped(to: CIImage(cgImage: cgImage).extent) ?? ciImage
            
        case .prism:
            // Triangular kaleidoscope
            let triangle = CIFilter(name: "CITriangleKaleidoscope")!
            triangle.setValue(ciImage, forKey: kCIInputImageKey)
            triangle.setValue(CIVector(x: imageSize.width * 0.5, y: imageSize.height * 0.5), forKey: "inputPoint")
            triangle.setValue(imageSize.width * (0.3 + bass * 0.2), forKey: "inputSize")
            triangle.setValue(t * 0.5 * intensity, forKey: "inputRotation")
            triangle.setValue(0.1, forKey: "inputDecay")
            ciImage = triangle.outputImage?.cropped(to: CIImage(cgImage: cgImage).extent) ?? ciImage
            
        case .doubleVision:
            let offset = 20 + bass * 50 * intensity
            
            let transform1 = CIFilter(name: "CIAffineTransform")!
            transform1.setValue(ciImage, forKey: kCIInputImageKey)
            transform1.setValue(CGAffineTransform(translationX: -offset, y: 0), forKey: kCIInputTransformKey)
            let img1 = transform1.outputImage ?? ciImage
            
            let transform2 = CIFilter(name: "CIAffineTransform")!
            transform2.setValue(ciImage, forKey: kCIInputImageKey)
            transform2.setValue(CGAffineTransform(translationX: offset, y: 0), forKey: kCIInputTransformKey)
            let img2 = transform2.outputImage ?? ciImage
            
            let blend = CIFilter(name: "CIAdditionCompositing")!
            blend.setValue(img1.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.5)]), forKey: kCIInputImageKey)
            blend.setValue(img2.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.5)]), forKey: kCIInputBackgroundImageKey)
            ciImage = blend.outputImage ?? ciImage
            
        case .flipbook:
            // Rapid flip between normal and transformed
            let flipPhase = Int(t * 8 * intensity) % 4
            
            let transform = CIFilter(name: "CIAffineTransform")!
            var affine = CGAffineTransform.identity
            switch flipPhase {
            case 0: affine = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -imageSize.width, y: 0)
            case 1: affine = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -imageSize.height)
            case 2:
                affine = CGAffineTransform(translationX: imageSize.width/2, y: imageSize.height/2)
                affine = affine.rotated(by: .pi)
                affine = affine.translatedBy(x: -imageSize.width/2, y: -imageSize.height/2)
            default: break
            }
            transform.setValue(ciImage, forKey: kCIInputImageKey)
            transform.setValue(affine, forKey: kCIInputTransformKey)
            ciImage = transform.outputImage ?? ciImage
            
        case .mosaic:
            let hexagonal = CIFilter(name: "CIHexagonalPixellate")!
            hexagonal.setValue(ciImage, forKey: kCIInputImageKey)
            hexagonal.setValue(center, forKey: kCIInputCenterKey)
            hexagonal.setValue(10 + (1 - level) * 30 * intensity, forKey: kCIInputScaleKey)
            ciImage = hexagonal.outputImage ?? ciImage
            
        case .pixelate:
            let pixellate = CIFilter(name: "CIPixellate")!
            pixellate.setValue(ciImage, forKey: kCIInputImageKey)
            pixellate.setValue(center, forKey: kCIInputCenterKey)
            pixellate.setValue(5 + (1 - level) * 40 * intensity, forKey: kCIInputScaleKey)
            ciImage = pixellate.outputImage ?? ciImage
            
        case .scanlines:
            // CRT scanline effect
            let lines = CIFilter(name: "CILineScreen")!
            lines.setValue(ciImage, forKey: kCIInputImageKey)
            lines.setValue(center, forKey: kCIInputCenterKey)
            lines.setValue(t * 0.5, forKey: kCIInputAngleKey)
            lines.setValue(3 + bass * 5 * intensity, forKey: kCIInputWidthKey)
            lines.setValue(0.7 + bass * 0.3, forKey: kCIInputSharpnessKey)
            ciImage = lines.outputImage ?? ciImage
            
            let bloom = CIFilter(name: "CIBloom")!
            bloom.setValue(ciImage, forKey: kCIInputImageKey)
            bloom.setValue(5 * level, forKey: kCIInputRadiusKey)
            bloom.setValue(0.3, forKey: kCIInputIntensityKey)
            ciImage = bloom.outputImage ?? ciImage
            
        case .datamosh:
            // Simulate datamosh with edge work + color shift
            let edges = CIFilter(name: "CIEdgeWork")!
            edges.setValue(ciImage, forKey: kCIInputImageKey)
            edges.setValue(3 + bass * 10 * intensity, forKey: kCIInputRadiusKey)
            let edgeImage = edges.outputImage ?? ciImage
            
            let blend = CIFilter(name: "CIMultiplyBlendMode")!
            blend.setValue(edgeImage, forKey: kCIInputImageKey)
            blend.setValue(ciImage, forKey: kCIInputBackgroundImageKey)
            ciImage = blend.outputImage ?? ciImage
            
            let hue = CIFilter(name: "CIHueAdjust")!
            hue.setValue(ciImage, forKey: kCIInputImageKey)
            hue.setValue(bass * 3 * intensity, forKey: kCIInputAngleKey)
            ciImage = hue.outputImage ?? ciImage
            
        case .blocky:
            // Large pixelation with color boost
            let pixellate = CIFilter(name: "CIPixellate")!
            pixellate.setValue(ciImage, forKey: kCIInputImageKey)
            pixellate.setValue(center, forKey: kCIInputCenterKey)
            pixellate.setValue(20 + bass * 60 * intensity, forKey: kCIInputScaleKey)
            ciImage = pixellate.outputImage ?? ciImage
            
            let vibrance = CIFilter(name: "CIVibrance")!
            vibrance.setValue(ciImage, forKey: kCIInputImageKey)
            vibrance.setValue(0.5 + bass * intensity, forKey: "inputAmount")
            ciImage = vibrance.outputImage ?? ciImage
        }

        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
}
