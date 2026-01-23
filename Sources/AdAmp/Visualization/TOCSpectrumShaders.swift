import Foundation

/// GLSL shaders for TOC Spectrum visualization
///
/// These shaders render vertical spectrum bars with height-based color gradients.
/// Compatible with OpenGL 3.2 Core Profile (GLSL 150).
enum TOCSpectrumShaders {

    // MARK: - Vertex Shader

    /// Vertex shader for 3D spectrum bars with lighting
    ///
    /// Transforms bar vertices with perspective projection and calculates lighting.
    static let vertexShader = """
    #version 150 core

    in vec3 position;       // Vertex position (x, y, z for 3D cube)
    in vec3 normal;         // Vertex normal for lighting
    in float barIndex;      // Which bar this vertex belongs to
    in float heightMult;    // Height multiplier for this bar

    out vec3 vPosition;     // World position for fragment shader
    out vec3 vNormal;       // Normal for lighting
    out float vHeight;      // Height for coloring
    out float vBarIndex;    // Bar index for fragment shader

    uniform mat4 projection;
    uniform mat4 view;
    uniform mat4 model;
    uniform float maxHeight;

    void main() {
        // Scale bar height
        vec3 pos = position;
        pos.y *= heightMult;

        // Transform to world space
        vec4 worldPos = model * vec4(pos, 1.0);
        vPosition = worldPos.xyz;

        // Transform normal (for lighting)
        vNormal = mat3(model) * normal;

        // Project to screen space
        gl_Position = projection * view * worldPos;

        // Pass data to fragment shader
        vHeight = pos.y;
        vBarIndex = barIndex;
    }
    """

    // MARK: - Fragment Shader

    /// Fragment shader for 3D spectrum bars with lighting
    ///
    /// Applies height-based colors with Phong lighting for 3D effect.
    static let fragmentShader = """
    #version 150 core

    in vec3 vPosition;
    in vec3 vNormal;
    in float vHeight;
    in float vBarIndex;

    out vec4 fragColor;

    uniform int colorScheme;    // 0=classic, 1=modern, 2=ozone
    uniform float maxHeight;
    uniform int barCount;
    uniform vec3 lightDir;      // Directional light direction
    uniform vec3 cameraPos;     // Camera position for specular

    // HSV to RGB conversion for rainbow effects
    vec3 hsv2rgb(vec3 c) {
        vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
        vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
    }

    // Classic green gradient with rainbow bass-to-treble spectrum
    vec3 getClassicColor(float normalizedHeight, float barPosition) {
        // Rainbow hue based on bar position (bass = red, treble = violet)
        float hue = barPosition * 0.8;  // 0.0 (red) to 0.8 (purple)

        // Saturation and value based on height
        float saturation = 0.7 + normalizedHeight * 0.3;  // More saturated at peaks
        float value = 0.3 + normalizedHeight * 0.7;       // Brighter at peaks

        vec3 rainbowColor = hsv2rgb(vec3(hue, saturation, value));

        // Mix with traditional green gradient for classic feel
        vec3 greenGradient;
        if (normalizedHeight < 0.33) {
            greenGradient = mix(vec3(0.0, 0.4, 0.0), vec3(0.0, 0.8, 0.2), normalizedHeight / 0.33);
        } else if (normalizedHeight < 0.66) {
            greenGradient = mix(vec3(0.0, 0.8, 0.2), vec3(0.9, 1.0, 0.0), (normalizedHeight - 0.33) / 0.33);
        } else {
            greenGradient = mix(vec3(0.9, 1.0, 0.0), vec3(1.0, 1.0, 0.5), (normalizedHeight - 0.66) / 0.34);
        }

        // Blend rainbow and green based on height (more rainbow at peaks)
        return mix(greenGradient, rainbowColor, normalizedHeight * 0.4);
    }

    // Modern gradient with vibrant rainbow spectrum
    vec3 getModernColor(float normalizedHeight, float barPosition) {
        // Full rainbow spectrum from bass to treble
        float hue = barPosition;  // Full spectrum

        // High saturation and brightness
        float saturation = 0.85 + normalizedHeight * 0.15;
        float value = 0.4 + normalizedHeight * 0.6;

        return hsv2rgb(vec3(hue, saturation, value));
    }

    // Ozone gradient with electric blue-cyan-purple spectrum
    vec3 getOzoneColor(float normalizedHeight, float barPosition) {
        // Blue to cyan to purple spectrum
        float hue = 0.5 + barPosition * 0.3;  // 0.5 (cyan) to 0.8 (purple)

        // Vibrant saturation
        float saturation = 0.8 + normalizedHeight * 0.2;
        float value = 0.3 + normalizedHeight * 0.7;

        vec3 electricColor = hsv2rgb(vec3(hue, saturation, value));

        // Add extra cyan/white highlights at peaks
        if (normalizedHeight > 0.7) {
            vec3 highlight = vec3(0.5, 1.0, 1.0);
            float highlightMix = (normalizedHeight - 0.7) / 0.3;
            electricColor = mix(electricColor, highlight, highlightMix * 0.5);
        }

        return electricColor;
    }

    void main() {
        float normalizedHeight = clamp(vHeight / maxHeight, 0.0, 1.0);

        // Calculate bar position (0.0 = bass, 1.0 = treble)
        float barPosition = vBarIndex / float(barCount - 1);

        // Get base color based on height and position
        vec3 baseColor;
        if (colorScheme == 0) {
            baseColor = getClassicColor(normalizedHeight, barPosition);
        } else if (colorScheme == 1) {
            baseColor = getModernColor(normalizedHeight, barPosition);
        } else {
            baseColor = getOzoneColor(normalizedHeight, barPosition);
        }

        // Lighting calculations (Phong shading)
        vec3 norm = normalize(vNormal);
        vec3 lightDirection = normalize(lightDir);

        // Ambient light
        float ambientStrength = 0.3;
        vec3 ambient = ambientStrength * baseColor;

        // Diffuse light
        float diff = max(dot(norm, lightDirection), 0.0);
        vec3 diffuse = diff * baseColor;

        // Specular light (shininess based on height)
        vec3 viewDir = normalize(cameraPos - vPosition);
        vec3 reflectDir = reflect(-lightDirection, norm);
        float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32.0);
        float specularStrength = 0.5 * normalizedHeight;  // More specular at peaks
        vec3 specular = specularStrength * spec * vec3(1.0, 1.0, 1.0);

        // Add extra glow at peaks
        float glow = 0.0;
        if (normalizedHeight > 0.85) {
            glow = (normalizedHeight - 0.85) / 0.15;
        }

        // Combine lighting
        vec3 finalColor = ambient + diffuse + specular + (glow * baseColor * 0.5);

        fragColor = vec4(finalColor, 1.0);
    }
    """

    // MARK: - Reflection Shaders (Phase 3)

    /// Vertex shader for reflection rendering
    ///
    /// Flips and fades the spectrum bars below the main visualization.
    static let reflectionVertexShader = """
    #version 150 core

    in vec3 position;
    in float barIndex;

    out float vHeight;
    out float vBarIndex;
    out float vReflectionFade;

    uniform mat4 projection;
    uniform float maxHeight;

    void main() {
        // Flip vertically and scale by height
        vec3 pos = position;
        pos.y *= position.z;  // Apply height
        pos.y = -pos.y;       // Flip for reflection

        gl_Position = projection * vec4(pos.x, pos.y, 0.0, 1.0);
        vHeight = abs(pos.y);
        vBarIndex = barIndex;

        // Fade based on distance from reflection origin
        vReflectionFade = 1.0 - clamp(abs(pos.y) / maxHeight, 0.0, 1.0);
    }
    """

    /// Fragment shader for reflection rendering
    ///
    /// Same color logic as main shader but with fade applied.
    static let reflectionFragmentShader = """
    #version 150 core

    in float vHeight;
    in float vBarIndex;
    in float vReflectionFade;

    out vec4 fragColor;

    uniform int colorScheme;
    uniform float maxHeight;
    uniform int barCount;

    // HSV to RGB conversion for rainbow effects
    vec3 hsv2rgb(vec3 c) {
        vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
        vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
    }

    // Classic green gradient with rainbow bass-to-treble spectrum
    vec3 getClassicColor(float normalizedHeight, float barPosition) {
        float hue = barPosition * 0.8;
        float saturation = 0.7 + normalizedHeight * 0.3;
        float value = 0.3 + normalizedHeight * 0.7;
        vec3 rainbowColor = hsv2rgb(vec3(hue, saturation, value));

        vec3 greenGradient;
        if (normalizedHeight < 0.33) {
            greenGradient = mix(vec3(0.0, 0.4, 0.0), vec3(0.0, 0.8, 0.2), normalizedHeight / 0.33);
        } else if (normalizedHeight < 0.66) {
            greenGradient = mix(vec3(0.0, 0.8, 0.2), vec3(0.9, 1.0, 0.0), (normalizedHeight - 0.33) / 0.33);
        } else {
            greenGradient = mix(vec3(0.9, 1.0, 0.0), vec3(1.0, 1.0, 0.5), (normalizedHeight - 0.66) / 0.34);
        }

        return mix(greenGradient, rainbowColor, normalizedHeight * 0.4);
    }

    // Modern gradient with vibrant rainbow spectrum
    vec3 getModernColor(float normalizedHeight, float barPosition) {
        float hue = barPosition;
        float saturation = 0.85 + normalizedHeight * 0.15;
        float value = 0.4 + normalizedHeight * 0.6;
        return hsv2rgb(vec3(hue, saturation, value));
    }

    // Ozone gradient with electric blue-cyan-purple spectrum
    vec3 getOzoneColor(float normalizedHeight, float barPosition) {
        float hue = 0.5 + barPosition * 0.3;
        float saturation = 0.8 + normalizedHeight * 0.2;
        float value = 0.3 + normalizedHeight * 0.7;
        vec3 electricColor = hsv2rgb(vec3(hue, saturation, value));

        if (normalizedHeight > 0.7) {
            vec3 highlight = vec3(0.5, 1.0, 1.0);
            float highlightMix = (normalizedHeight - 0.7) / 0.3;
            electricColor = mix(electricColor, highlight, highlightMix * 0.5);
        }

        return electricColor;
    }

    void main() {
        float normalizedHeight = clamp(vHeight / maxHeight, 0.0, 1.0);
        float barPosition = vBarIndex / float(barCount - 1);

        vec3 baseColor;
        if (colorScheme == 0) {
            baseColor = getClassicColor(normalizedHeight, barPosition);
        } else if (colorScheme == 1) {
            baseColor = getModernColor(normalizedHeight, barPosition);
        } else {
            baseColor = getOzoneColor(normalizedHeight, barPosition);
        }

        // Enhanced brightness with glow effect at peaks
        float brightness = 1.0 + normalizedHeight * 0.5;
        if (normalizedHeight > 0.85) {
            float glow = (normalizedHeight - 0.85) / 0.15;
            brightness += glow * 0.8;
        }

        vec3 finalColor = baseColor * brightness;

        // Apply reflection fade (40% opacity at base, fading to 0)
        float alpha = vReflectionFade * 0.4;
        fragColor = vec4(finalColor, alpha);
    }
    """
}
