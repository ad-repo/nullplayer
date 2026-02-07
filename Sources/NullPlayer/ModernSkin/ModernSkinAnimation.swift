import AppKit
import QuartzCore

/// Animation system for the modern skin engine.
/// Supports two types of animation:
/// 1. Sprite frame animations: Cycle through numbered PNG frames
/// 2. Parametric animations: Code-driven effects (pulse, glow, rotate, colorCycle)
class ModernSkinAnimation {
    
    // MARK: - Active Animation
    
    /// Represents a running animation instance
    class ActiveAnimation {
        let elementId: String
        let config: AnimationConfig
        var currentFrame: Int = 0
        var time: CGFloat = 0
        var value: CGFloat = 0  // Current parametric value (0-1 for pulse, angle for rotate, etc.)
        var isReversing: Bool = false
        
        init(elementId: String, config: AnimationConfig) {
            self.elementId = elementId
            self.config = config
        }
    }
    
    // MARK: - Properties
    
    /// All active animations, keyed by element ID
    private var activeAnimations: [String: ActiveAnimation] = [:]
    
    /// Display link for driving animations
    private var displayLink: CVDisplayLink?
    
    /// Last frame timestamp
    private var lastTimestamp: TimeInterval = 0
    
    /// Whether the animation engine is running
    private(set) var isRunning = false
    
    /// Callback when an animation value changes (elementId, value)
    var onAnimationUpdate: ((String, CGFloat) -> Void)?
    
    /// Callback when a sprite frame changes (elementId, frameIndex)
    var onFrameChange: ((String, Int) -> Void)?
    
    // MARK: - Lifecycle
    
    /// Start an animation for an element
    func startAnimation(elementId: String, config: AnimationConfig) {
        let animation = ActiveAnimation(elementId: elementId, config: config)
        activeAnimations[elementId] = animation
        
        if !isRunning {
            startDisplayLink()
        }
    }
    
    /// Stop an animation for an element
    func stopAnimation(elementId: String) {
        activeAnimations.removeValue(forKey: elementId)
        
        if activeAnimations.isEmpty {
            stopDisplayLink()
        }
    }
    
    /// Stop all animations
    func stopAll() {
        activeAnimations.removeAll()
        stopDisplayLink()
    }
    
    /// Get current animation value for an element
    func currentValue(for elementId: String) -> CGFloat? {
        return activeAnimations[elementId]?.value
    }
    
    /// Get current frame index for a sprite animation
    func currentFrame(for elementId: String) -> Int? {
        return activeAnimations[elementId]?.currentFrame
    }
    
    // MARK: - Display Link
    
    private func startDisplayLink() {
        guard !isRunning else { return }
        isRunning = true
        lastTimestamp = CACurrentMediaTime()
        
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let displayLink = link else { return }
        
        self.displayLink = displayLink
        
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, context -> CVReturn in
            guard let context = context else { return kCVReturnError }
            let engine = Unmanaged<ModernSkinAnimation>.fromOpaque(context).takeUnretainedValue()
            
            let now = CACurrentMediaTime()
            let dt = CGFloat(now - engine.lastTimestamp)
            engine.lastTimestamp = now
            
            DispatchQueue.main.async {
                engine.update(dt: dt)
            }
            
            return kCVReturnSuccess
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, selfPtr)
        CVDisplayLinkStart(displayLink)
    }
    
    private func stopDisplayLink() {
        guard isRunning else { return }
        isRunning = false
        
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }
    
    // MARK: - Update
    
    private func update(dt: CGFloat) {
        for (_, animation) in activeAnimations {
            let duration = animation.config.duration ?? 1.0
            animation.time += dt
            
            switch animation.config.type {
            case .spriteFrames:
                updateSpriteAnimation(animation, duration: duration)
                
            case .pulse:
                updatePulseAnimation(animation, duration: duration)
                
            case .glow:
                updateGlowAnimation(animation, duration: duration)
                
            case .rotate:
                updateRotateAnimation(animation, dt: dt, duration: duration)
                
            case .colorCycle:
                updateColorCycleAnimation(animation, duration: duration)
            }
        }
    }
    
    // MARK: - Animation Types
    
    private func updateSpriteAnimation(_ anim: ActiveAnimation, duration: CGFloat) {
        guard let frameCount = anim.config.frames?.count, frameCount > 0 else { return }
        
        let fps = CGFloat(frameCount) / duration
        let frameTime = 1.0 / fps
        
        if anim.time >= frameTime {
            anim.time -= frameTime
            
            let repeatMode = anim.config.repeatMode ?? .loop
            
            switch repeatMode {
            case .loop:
                anim.currentFrame = (anim.currentFrame + 1) % frameCount
            case .reverse:
                if anim.isReversing {
                    anim.currentFrame -= 1
                    if anim.currentFrame <= 0 {
                        anim.isReversing = false
                    }
                } else {
                    anim.currentFrame += 1
                    if anim.currentFrame >= frameCount - 1 {
                        anim.isReversing = true
                    }
                }
            case .once:
                if anim.currentFrame < frameCount - 1 {
                    anim.currentFrame += 1
                }
            }
            
            onFrameChange?(anim.elementId, anim.currentFrame)
        }
    }
    
    private func updatePulseAnimation(_ anim: ActiveAnimation, duration: CGFloat) {
        let minVal = anim.config.minValue ?? 0.3
        let maxVal = anim.config.maxValue ?? 1.0
        let range = maxVal - minVal
        
        // Sinusoidal oscillation
        let t = sin(anim.time * .pi * 2 / duration) * 0.5 + 0.5
        anim.value = minVal + t * range
        
        onAnimationUpdate?(anim.elementId, anim.value)
    }
    
    private func updateGlowAnimation(_ anim: ActiveAnimation, duration: CGFloat) {
        let minVal = anim.config.minValue ?? 0.2
        let maxVal = anim.config.maxValue ?? 1.0
        let range = maxVal - minVal
        
        // Smooth sine wave for glow intensity
        let t = sin(anim.time * .pi * 2 / duration) * 0.5 + 0.5
        anim.value = minVal + t * range
        
        onAnimationUpdate?(anim.elementId, anim.value)
    }
    
    private func updateRotateAnimation(_ anim: ActiveAnimation, dt: CGFloat, duration: CGFloat) {
        // Continuous rotation (duration = time for full 360°)
        let rotationSpeed = 360.0 / duration
        anim.value += rotationSpeed * dt
        if anim.value >= 360 { anim.value -= 360 }
        
        onAnimationUpdate?(anim.elementId, anim.value)
    }
    
    private func updateColorCycleAnimation(_ anim: ActiveAnimation, duration: CGFloat) {
        // Value cycles 0 to 1 over duration
        anim.value = anim.time.truncatingRemainder(dividingBy: duration) / duration
        
        onAnimationUpdate?(anim.elementId, anim.value)
    }
}
