import Foundation

/// An `NSLog` for a chatty diagnostic cycle, silent unless its environment variable is set (to any
/// value, empty included). Read once at launch. Called like `NSLog`, so call sites inside closures
/// don't need `self`; printf-style format semantics are preserved and URL query secrets redacted.
struct EnvGatedLog {
    let isEnabled: Bool

    init(_ variable: String) {
        isEnabled = ProcessInfo.processInfo.environment[variable] != nil
    }

    func callAsFunction(_ format: String, _ args: CVarArg...) {
        guard isEnabled else { return }
        NSLog("%@", String(format: format, arguments: args).redactingSensitiveURLQueryItems)
    }
}
