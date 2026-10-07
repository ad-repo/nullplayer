import Foundation
import Metal

enum BundledShaderError: Error, CustomStringConvertible {
    case notFound(String)

    var description: String {
        switch self {
        case .notFound(let name): return "\(name).metal not found in the resource bundle"
        }
    }
}

extension MTLDevice {
    /// Compiles a `.metal` source file shipped in the resource bundle.
    ///
    /// Every shader loads through here. makeDefaultLibrary() returns nil in SPM executables, so
    /// shaders ship as source and compile at runtime, and BundleHelper resolves the resource
    /// bundle in whatever layout the build system produced.
    func makeBundledLibrary(_ name: String) throws -> MTLLibrary {
        guard let url = BundleHelper.url(forResource: name, withExtension: "metal") else {
            throw BundledShaderError.notFound(name)
        }
        return try makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: nil)
    }
}
