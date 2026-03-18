import Foundation

class CLIKeyboard {
    private let player: CLIPlayer
    private let queue = DispatchQueue(label: "cli.keyboard", qos: .userInteractive)
    private static var originalTermios = termios()
    private static var isRawMode = false

    init(player: CLIPlayer) {
        self.player = player
    }

    func start() {
        enableRawMode()
        queue.async { [weak self] in
            self?.inputLoop()
        }
    }

    private func enableRawMode() {
        tcgetattr(STDIN_FILENO, &CLIKeyboard.originalTermios)
        var raw = CLIKeyboard.originalTermios
        raw.c_lflag &= ~UInt(ICANON | ECHO)
        // c_cc is a C tuple in Swift — must use withUnsafeMutablePointer to index it
        withUnsafeMutablePointer(to: &raw.c_cc) {
            let ptr = UnsafeMutableRawPointer($0).assumingMemoryBound(to: cc_t.self)
            ptr[Int(VMIN)] = 1
            ptr[Int(VTIME)] = 0
        }
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        CLIKeyboard.isRawMode = true
        // Note: terminal restore is handled by signal handlers and quit(), not atexit
        // (atexit requires @convention(c) function pointer, not a closure)
    }

    static func restoreTerminal() {
        if isRawMode {
            tcsetattr(STDIN_FILENO, TCSANOW, &originalTermios)
            isRawMode = false
            // Move to new line so shell prompt isn't on progress bar line
            print("")
        }
    }

    private func inputLoop() {
        var buf = [UInt8](repeating: 0, count: 3)
        while true {
            let bytesRead = read(STDIN_FILENO, &buf, 1)
            guard bytesRead == 1 else { continue }

            let byte = buf[0]

            if byte == 0x1B {
                // Escape sequence — read 2 more bytes
                let r1 = read(STDIN_FILENO, &buf, 1)
                let r2: Int
                if r1 == 1 && buf[0] == 0x5B { // '['
                    var buf2 = [UInt8](repeating: 0, count: 1)
                    r2 = read(STDIN_FILENO, &buf2, 1)
                    if r2 == 1 {
                        let arrow = buf2[0]
                        DispatchQueue.main.async { [weak self] in
                            guard let self else { return }
                            switch arrow {
                            case 0x41: self.player.volumeUp()       // Up
                            case 0x42: self.player.volumeDown()     // Down
                            case 0x43: self.player.seekForward()    // Right
                            case 0x44: self.player.seekBackward()   // Left
                            default: break
                            }
                        }
                    }
                }
                continue
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch byte {
                case 0x20:                              // Space
                    self.player.togglePlayPause()
                case UInt8(ascii: "q"), UInt8(ascii: "Q"):
                    self.player.quit()
                case UInt8(ascii: ">"):
                    self.player.nextTrack()
                case UInt8(ascii: "<"):
                    self.player.previousTrack()
                case UInt8(ascii: "s"), UInt8(ascii: "S"):
                    self.player.toggleShuffle()
                case UInt8(ascii: "r"), UInt8(ascii: "R"):
                    self.player.cycleRepeat()
                case UInt8(ascii: "m"), UInt8(ascii: "M"):
                    self.player.toggleMute()
                case UInt8(ascii: "i"), UInt8(ascii: "I"):
                    if let track = self.player.audioEngine.currentTrack {
                        self.player.display.printTrackInfo(track)
                    }
                default:
                    break
                }
            }
        }
    }
}
