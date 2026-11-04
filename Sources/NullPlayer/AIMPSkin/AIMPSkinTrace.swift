import Foundation

/// Trace switches the harness turns on through the environment, read once at process start. Debug
/// builds only: a release build never reads them. Documented with the rest of the harness in
/// `skills/aimp-skin-guide/reference/harness.md`.
enum AIMPSkinTrace {
    #if DEBUG
    private static let environment = ProcessInfo.processInfo.environment
    /// `AIMP_RENDER_ITEMS=1`: the renderer prints each layout item and control as it draws it.
    static let items = environment["AIMP_RENDER_ITEMS"] == "1"
    /// `AIMP_RENDER_VISUALIZE`: a visualization handler that fails says why.
    static let visualize = environment["AIMP_RENDER_VISUALIZE"] != nil
    /// `AIMP_ACTION_TRACE=1`: the running app logs every action a skin asks of the player.
    static let actions = environment["AIMP_ACTION_TRACE"] == "1"
    #else
    static let items = false
    static let visualize = false
    static let actions = false
    #endif
}
