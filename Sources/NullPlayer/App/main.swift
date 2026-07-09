import AppKit

let args = CommandLine.arguments
if args.contains("--cli") && args.contains("--ui-testing") {
    fputs("Error: --cli and --ui-testing are mutually exclusive\n", stderr)
    exit(1)
}

if args.contains("--cli") {
    // Silence the app's pervasive NSLog output before anything can log, keeping the
    // CLI's own messages (via cliStderr) visible. --verbose keeps logs for debugging.
    suppressFrameworkLoggingForCLI(verbose: args.contains("--verbose"))

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
    let cliDelegate = CLIMode()
    app.delegate = cliDelegate
    app.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.activate(ignoringOtherApps: true)
    app.run()
}
