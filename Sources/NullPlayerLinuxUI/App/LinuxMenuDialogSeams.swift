#if os(Linux)
import Foundation

struct LinuxMenuAction: Sendable, Equatable {
    let id: String
    let title: String
}

struct LinuxPoint: Sendable, Equatable {
    let x: Double
    let y: Double
}

protocol LinuxMenuBuilding: AnyObject {
    func updateMainMenu(actions: [LinuxMenuAction])
    func showContextMenu(actions: [LinuxMenuAction], at location: LinuxPoint)
}

protocol LinuxDialogPresenting: AnyObject {
    func showInfo(title: String, message: String)
    func showError(title: String, message: String)
    func confirm(title: String, message: String) -> Bool
    func requestURLInput(title: String, placeholder: String) -> String?
    func pickFiles(allowMultiple: Bool) -> [URL]
    func pickDirectory() -> URL?
    func requestSaveURL(suggestedName: String) -> URL?
}

final class LinuxMenuDialogService: LinuxMenuBuilding, LinuxDialogPresenting {
    private var currentMainActions: [LinuxMenuAction] = []

    func updateMainMenu(actions: [LinuxMenuAction]) {
        currentMainActions = actions
    }

    func showContextMenu(actions: [LinuxMenuAction], at location: LinuxPoint) {
        _ = (actions, location)
    }

    func showInfo(title: String, message: String) {
        fputs("[INFO] \(title): \(message)\n", stderr)
    }

    func showError(title: String, message: String) {
        fputs("[ERROR] \(title): \(message)\n", stderr)
    }

    func confirm(title: String, message: String) -> Bool {
        fputs("[CONFIRM] \(title): \(message) (default=no)\n", stderr)
        return false
    }

    func requestURLInput(title: String, placeholder: String) -> String? {
        fputs("[INPUT] \(title): \(placeholder)\n", stderr)
        return nil
    }

    func pickFiles(allowMultiple: Bool) -> [URL] {
        _ = allowMultiple
        return []
    }

    func pickDirectory() -> URL? {
        nil
    }

    func requestSaveURL(suggestedName: String) -> URL? {
        _ = suggestedName
        return nil
    }
}
#endif
