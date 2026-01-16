import AppKit

// Create the application instance
let app = NSApplication.shared

// Create and set the delegate
let delegate = AppDelegate()
app.delegate = delegate

// Activate the application
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)

// Run the main event loop
app.run()
