import Foundation
import OpenGL.GL3

/// Compiles and links a GLSL program for the GL engines that draw with their own shaders
/// (Geiss, NullPlayer-Fractal). Failures are logged under `label` and return nil.
enum GLProgram {
    static func make(vertex: String, fragment: String, label: String) -> GLuint? {
        guard let vs = compile(GLenum(GL_VERTEX_SHADER), vertex, label: label) else { return nil }
        guard let fs = compile(GLenum(GL_FRAGMENT_SHADER), fragment, label: label) else {
            glDeleteShader(vs)
            return nil
        }
        let prog = glCreateProgram()
        glAttachShader(prog, vs)
        glAttachShader(prog, fs)
        glLinkProgram(prog)
        glDeleteShader(vs)
        glDeleteShader(fs)
        var status: GLint = 0
        glGetProgramiv(prog, GLenum(GL_LINK_STATUS), &status)
        guard status == GL_FALSE else { return prog }
        var logLen: GLint = 0
        glGetProgramiv(prog, GLenum(GL_INFO_LOG_LENGTH), &logLen)
        var log = [GLchar](repeating: 0, count: Int(max(logLen, 1)))
        glGetProgramInfoLog(prog, GLsizei(log.count), nil, &log)
        NSLog("%@: program link failed: %@", label, String(cString: log))
        glDeleteProgram(prog)
        return nil
    }

    private static func compile(_ type: GLenum, _ source: String, label: String) -> GLuint? {
        let shader = glCreateShader(type)
        guard shader != 0 else { return nil }
        source.withCString { cString in
            var pointer: UnsafePointer<GLchar>? = cString
            var length = GLint(strlen(cString))
            glShaderSource(shader, 1, &pointer, &length)
        }
        glCompileShader(shader)
        var status: GLint = 0
        glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &status)
        guard status == GL_FALSE else { return shader }
        var logLen: GLint = 0
        glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &logLen)
        var log = [GLchar](repeating: 0, count: Int(max(logLen, 1)))
        glGetShaderInfoLog(shader, GLsizei(log.count), nil, &log)
        NSLog("%@: shader compile failed: %@", label, String(cString: log))
        glDeleteShader(shader)
        return nil
    }
}
