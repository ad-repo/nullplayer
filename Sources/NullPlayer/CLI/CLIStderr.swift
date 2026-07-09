import Foundation

/// Handle the CLI uses for its own diagnostics (errors, status). Starts as the real
/// `stderr` and stays pointed at the terminal even after `suppressFrameworkLoggingForCLI`
/// redirects fd 2 to /dev/null to silence the app's pervasive `NSLog` output.
var cliStderr: UnsafeMutablePointer<FILE> = stderr

/// Silence framework logging noise in CLI mode.
///
/// The app calls `NSLog` in ~80 files; that output goes to fd 2 (stderr) and floods
/// a headless session endlessly. Redirect fd 2 to /dev/null so those writes vanish,
/// but first dup the real stderr and expose it via `cliStderr` so the CLI's own
/// messages still reach the terminal. No-op when `verbose` is set, so logs remain
/// available for debugging.
func suppressFrameworkLoggingForCLI(verbose: Bool) {
    guard !verbose else { return }

    // Preserve the real stderr for CLI diagnostics before repointing fd 2.
    let saved = dup(STDERR_FILENO)
    guard saved >= 0 else { return }

    if let devnull = fopen("/dev/null", "w") {
        dup2(fileno(devnull), STDERR_FILENO)
        fclose(devnull)
    }

    if let handle = fdopen(saved, "w") {
        cliStderr = handle
    } else {
        close(saved)
    }
}
