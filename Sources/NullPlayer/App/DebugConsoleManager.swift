import Foundation

/// Captures stderr (NSLog output) and maintains a buffer of messages for the debug console
class DebugConsoleManager {
    
    // MARK: - Singleton
    
    static let shared = DebugConsoleManager()
    
    // MARK: - Notifications
    
    static let messageReceivedNotification = Notification.Name("DebugConsoleMessageReceived")
    
    // MARK: - Properties
    
    private var messages: [String] = []
    private let messagesLock = NSLock()
    private let maxMessages = 1000
    
    private var pipe: Pipe?
    private var originalStderr: Int32 = -1
    private(set) var isCapturing = false
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start capturing stderr output
    func startCapturing() {
        guard !isCapturing else { return }
        isCapturing = true
        
        // Save original stderr
        originalStderr = dup(STDERR_FILENO)
        
        // Create pipe
        pipe = Pipe()
        guard let pipe = pipe else { return }
        
        // Redirect stderr to our pipe
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        
        // Also write to original stderr so logs still appear in Xcode/Terminal
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            
            // Write to original stderr
            if let self = self, self.originalStderr >= 0 {
                write(self.originalStderr, (data as NSData).bytes, data.count)
            }
            
            // Parse and store messages
            if let string = String(data: data, encoding: .utf8) {
                self?.addMessage(string)
            }
        }
    }
    
    /// Stop capturing stderr output
    func stopCapturing() {
        guard isCapturing else { return }
        isCapturing = false
        
        // Restore original stderr
        if originalStderr >= 0 {
            dup2(originalStderr, STDERR_FILENO)
            close(originalStderr)
            originalStderr = -1
        }
        
        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe = nil
    }
    
    /// Get all captured messages
    func getMessages() -> [String] {
        messagesLock.lock()
        defer { messagesLock.unlock() }
        return messages
    }
    
    /// Clear all messages
    func clearMessages() {
        messagesLock.lock()
        messages.removeAll()
        messagesLock.unlock()
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.messageReceivedNotification, object: nil)
        }
    }
    
    // MARK: - Private Methods
    
    private func addMessage(_ message: String) {
        messagesLock.lock()
        
        // Split by newlines and add each line
        let lines = message.components(separatedBy: .newlines).filter { !$0.isEmpty }
        messages.append(contentsOf: lines)
        
        // Trim if over limit
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
        
        messagesLock.unlock()
        
        // Notify on main thread
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.messageReceivedNotification, object: nil)
        }
    }
}
