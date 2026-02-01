import AppKit

/// Controller for adding/editing radio stations
class AddRadioStationSheet: NSWindowController, NSWindowDelegate {
    
    private var nameField: NSTextField!
    private var urlField: NSTextField!
    private var genreField: NSTextField!
    private var statusLabel: NSTextField!
    private var saveButton: NSButton!
    private var testButton: NSButton!
    
    private var editingStation: RadioStation?
    var completionHandler: ((RadioStation?) -> Void)?
    
    convenience init(station: RadioStation? = nil) {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = station == nil ? "Add Radio Station" : "Edit Radio Station"
        
        self.init(window: w)
        self.editingStation = station
        w.delegate = self
        
        setupUI()
        
        if let s = station {
            nameField.stringValue = s.name
            urlField.stringValue = s.url.absoluteString
            genreField.stringValue = s.genre ?? ""
        }
    }
    
    private func setupUI() {
        guard let cv = window?.contentView else { return }
        
        var y: CGFloat = 150
        let lx: CGFloat = 20, lw: CGFloat = 60, fx: CGFloat = 88, fw: CGFloat = 312, rh: CGFloat = 24, gap: CGFloat = 8
        
        let nl = NSTextField(labelWithString: "Name:")
        nl.frame = NSRect(x: lx, y: y, width: lw, height: rh)
        nl.alignment = .right
        cv.addSubview(nl)
        nameField = NSTextField(frame: NSRect(x: fx, y: y, width: fw, height: rh))
        nameField.placeholderString = "Station Name"
        cv.addSubview(nameField)
        
        y -= rh + gap
        let ul = NSTextField(labelWithString: "URL:")
        ul.frame = NSRect(x: lx, y: y, width: lw, height: rh)
        ul.alignment = .right
        cv.addSubview(ul)
        urlField = NSTextField(frame: NSRect(x: fx, y: y, width: fw, height: rh))
        urlField.placeholderString = "https://stream.example.com/radio.mp3"
        cv.addSubview(urlField)
        
        y -= rh + gap
        let gl = NSTextField(labelWithString: "Genre:")
        gl.frame = NSRect(x: lx, y: y, width: lw, height: rh)
        gl.alignment = .right
        cv.addSubview(gl)
        genreField = NSTextField(frame: NSRect(x: fx, y: y, width: fw, height: rh))
        genreField.placeholderString = "Electronic, Ambient, etc. (optional)"
        cv.addSubview(genreField)
        
        y -= rh + gap + 4
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: lx, y: y, width: 380, height: rh)
        statusLabel.alignment = .center
        statusLabel.isBezeled = false
        statusLabel.drawsBackground = false
        statusLabel.isEditable = false
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        cv.addSubview(statusLabel)
        
        let cb = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cb.bezelStyle = .rounded
        cb.frame = NSRect(x: 20, y: 16, width: 80, height: 32)
        cb.keyEquivalent = "\u{1b}"
        cv.addSubview(cb)
        
        testButton = NSButton(title: "Test", target: self, action: #selector(test))
        testButton.bezelStyle = .rounded
        testButton.frame = NSRect(x: 108, y: 16, width: 80, height: 32)
        cv.addSubview(testButton)
        
        saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: 320, y: 16, width: 80, height: 32)
        saveButton.keyEquivalent = "\r"
        cv.addSubview(saveButton)
    }
    
    func showDialog(completion: @escaping (RadioStation?) -> Void) {
        completionHandler = completion
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        completionHandler?(nil)
        completionHandler = nil
    }
    
    private func status(_ msg: String, err: Bool = false) {
        statusLabel.stringValue = msg
        statusLabel.textColor = err ? .systemRed : .secondaryLabelColor
    }
    
    private func buttons(_ on: Bool) {
        saveButton.isEnabled = on
        testButton.isEnabled = on
    }
    
    private func validate() -> Bool {
        if nameField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            status("Enter station name", err: true)
            return false
        }
        
        let urlString = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        if urlString.isEmpty {
            status("Enter stream URL", err: true)
            return false
        }
        
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            status("URL needs http:// or https://", err: true)
            return false
        }
        
        guard URL(string: urlString) != nil else {
            status("Invalid URL format", err: true)
            return false
        }
        
        return true
    }
    
    @objc private func cancel() {
        // Save handler before clearing to ensure callback is invoked
        let handler = completionHandler
        completionHandler = nil
        window?.close()
        handler?(nil)
    }
    
    @objc private func test() {
        guard validate() else { return }
        
        let urlString = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: urlString) else { return }
        
        status("Testing connection...")
        buttons(false)
        
        // Test by making a HEAD request to check if URL is accessible
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                self?.buttons(true)
                
                if let error = error {
                    self?.status("Connection failed: \(error.localizedDescription)", err: true)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 || httpResponse.statusCode == 206 {
                        self?.status("Connection successful!", err: false)
                    } else if httpResponse.statusCode == 405 {
                        // Some streaming servers don't support HEAD, but this is OK
                        self?.status("Stream appears accessible", err: false)
                    } else {
                        self?.status("Server returned status \(httpResponse.statusCode)", err: true)
                    }
                } else {
                    self?.status("Could not verify stream", err: true)
                }
            }
        }.resume()
    }
    
    @objc private func save() {
        guard validate() else { return }
        
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let urlString = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        let genre = genreField.stringValue.trimmingCharacters(in: .whitespaces)
        
        guard let url = URL(string: urlString) else {
            status("Invalid URL", err: true)
            return
        }
        
        let station: RadioStation
        if let existing = editingStation {
            // Update existing station
            station = RadioStation(
                id: existing.id,
                name: name,
                url: url,
                genre: genre.isEmpty ? nil : genre,
                iconURL: existing.iconURL
            )
        } else {
            // Create new station
            station = RadioStation(
                name: name,
                url: url,
                genre: genre.isEmpty ? nil : genre
            )
        }
        
        // Clear completion handler before closing to prevent double-call
        let handler = completionHandler
        completionHandler = nil
        window?.close()
        handler?(station)
    }
}
