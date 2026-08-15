import AppKit
import Foundation

final class WinampModernScriptRuntime: MakiMethodDispatching {
    let loadedSkin: WinampModernLoadedSkin
    let host: WinampModernHost
    let timers: MakiTimerService
    let interpreter: MakiInterpreter
    private(set) var programs: [MakiProgram] = []
    private(set) var isTornDown = false

    var graphDidMutate: (() -> Void)?
    var popupPresenter: (([(String, Int32, Bool, Bool)]) -> Int32)?

    private var nextPopupID: UInt64 = 1
    private var popupCommands: [UInt64: [(String, Int32, Bool, Bool)]] = [:]
    private let preferenceNamespace: String

    init(loadedSkin: WinampModernLoadedSkin, host: WinampModernHost,
         executionLimits: MakiExecutionLimits = .production,
         timers: MakiTimerService = MakiTimerService()) throws {
        self.loadedSkin = loadedSkin
        self.host = host
        self.timers = timers
        self.preferenceNamespace = loadedSkin.archive.sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: ".", with: "_")
        self.interpreter = MakiInterpreter(dispatcher: DummyMakiDispatcher.shared,
                                           limits: executionLimits)
        self.interpreter.dispatcher = self
        self.programs = try loadedSkin.runtime.scriptBindings.map { binding in
            let data = try loadedSkin.vfs.data(at: binding.logicalPath, location: binding.source)
            return try MakiBytecodeParser().parse(data, source: binding.source,
                                                  ownerID: binding.ownerID,
                                                  parameter: binding.parameter)
        }
    }

    func start() throws {
        host.beginVisualizationConsumption()
        try dispatchSystem(event: "onscriptloaded")
    }

    @discardableResult
    func dispatchSystem(event: String, arguments: [MakiValue] = []) throws -> Int {
        try dispatch(target: MakiObjectReference(.system), event: event, arguments: arguments)
    }

    @discardableResult
    func dispatch(object: WasabiObject, event: String, arguments: [MakiValue] = []) throws -> Int {
        try dispatch(target: MakiObjectReference(.gui(object.stableID)), event: event, arguments: arguments)
    }

    func hasBinding(for object: WasabiObject, event: String? = nil) -> Bool {
        let target = MakiObjectReference(.gui(object.stableID))
        return programs.contains { program in
            program.bindings.contains { binding in
                if let event, program.methods[binding.methodIndex].name != event.lowercased() { return false }
                let variable = program.variables[binding.variableIndex]
                if self.object(variable.value, equals: target) { return true }
                return variable.classMembers.contains {
                    self.object(program.variables[$0].value, equals: target)
                }
            }
        }
    }

    private func dispatch(target: MakiObjectReference, event: String,
                          arguments: [MakiValue]) throws -> Int {
        guard !isTornDown else { return 0 }
        let eventName = event.lowercased()
        var executed = 0
        for program in programs {
            for binding in program.bindings where program.methods[binding.methodIndex].name == eventName {
                let variable = program.variables[binding.variableIndex]
                var matches = object(variable.value, equals: target)
                if variable.isClass {
                    matches = variable.classMembers.contains { index in
                        object(program.variables[index].value, equals: target)
                    }
                    if matches { variable.value = .object(target) }
                }
                guard matches else { continue }
                try interpreter.execute(program: program, at: binding.instructionIndex,
                                        arguments: arguments)
                executed += 1
            }
        }
        return executed
    }

    func signature(for method: String) -> MakiMethodSignature? {
        let signatures: [String: MakiMethodSignature] = [
            "getcontainer": .init(argumentCount: 1, returnKind: .object),
            "getlayout": .init(argumentCount: 1, returnKind: .object),
            "getobject": .init(argumentCount: 1, returnKind: .object),
            "findobject": .init(argumentCount: 1, returnKind: .object),
            "getscriptgroup": .init(argumentCount: 0, returnKind: .object),
            "getparam": .init(argumentCount: 0, returnKind: .string),
            "gettoken": .init(argumentCount: 3, returnKind: .string),
            "setxmlparam": .init(argumentCount: 2, returnKind: .null),
            "resize": .init(argumentCount: 4, returnKind: .null),
            "show": .init(argumentCount: 0, returnKind: .null),
            "hide": .init(argumentCount: 0, returnKind: .null),
            "getleft": .init(argumentCount: 0, returnKind: .integer),
            "gettop": .init(argumentCount: 0, returnKind: .integer),
            "getwidth": .init(argumentCount: 0, returnKind: .integer),
            "getheight": .init(argumentCount: 0, returnKind: .integer),
            "getleftvumeter": .init(argumentCount: 0, returnKind: .integer),
            "getrightvumeter": .init(argumentCount: 0, returnKind: .integer),
            "getvolume": .init(argumentCount: 0, returnKind: .integer),
            "setvolume": .init(argumentCount: 1, returnKind: .null),
            "seekto": .init(argumentCount: 1, returnKind: .null),
            "getplayitemlength": .init(argumentCount: 0, returnKind: .integer),
            "integertostring": .init(argumentCount: 1, returnKind: .string),
            "getprivateint": .init(argumentCount: 3, returnKind: .integer),
            "setprivateint": .init(argumentCount: 3, returnKind: .null),
            "getviewportwidth": .init(argumentCount: 0, returnKind: .integer),
            "getviewportheight": .init(argumentCount: 0, returnKind: .integer),
            "getcurappleft": .init(argumentCount: 0, returnKind: .integer),
            "getcurapptop": .init(argumentCount: 0, returnKind: .integer),
            "getruntimeversion": .init(argumentCount: 0, returnKind: .integer),
            "getskinname": .init(argumentCount: 0, returnKind: .string),
            "gettimeofday": .init(argumentCount: 0, returnKind: .integer),
            "addcommand": .init(argumentCount: 4, returnKind: .null),
            "addseparator": .init(argumentCount: 0, returnKind: .null),
            "checkcommand": .init(argumentCount: 2, returnKind: .null),
            "popatmouse": .init(argumentCount: 0, returnKind: .integer),
            "newgroup": .init(argumentCount: 1, returnKind: .object),
            "init": .init(argumentCount: 1, returnKind: .null),
            "messagebox": .init(argumentCount: 4, returnKind: .integer),
            "callme": .init(argumentCount: 1, returnKind: .null),
        ]
        return signatures[method.lowercased()]
    }

    func invoke(method: String, on reference: MakiObjectReference, arguments: [MakiValue],
                program: MakiProgram) throws -> MakiValue {
        let method = method.lowercased()
        switch reference.kind {
        case .system:
            return try invokeSystem(method: method, arguments: arguments, program: program)
        case .gui(let objectID):
            guard let object = loadedSkin.runtime.graph.object(withID: objectID) else { return .null }
            return try invokeGUI(method: method, object: object, arguments: arguments, program: program)
        case .popupMenu(let id):
            return invokePopup(method: method, id: id, arguments: arguments)
        }
    }

    func makeObject(classGUID: String, program: MakiProgram) throws -> MakiObjectReference {
        let id = nextPopupID
        nextPopupID &+= 1
        popupCommands[id] = []
        return MakiObjectReference(.popupMenu(id))
    }

    private func invokeSystem(method: String, arguments: [MakiValue], program: MakiProgram) throws -> MakiValue {
        switch method {
        case "getcontainer":
            return objectValue(findRoot(type: "container", xmlID: arguments[0].stringValue))
        case "getscriptgroup":
            return objectValue(program.ownerID.flatMap(loadedSkin.runtime.graph.object(withID:)))
        case "getparam": return .string(program.parameter ?? "")
        case "gettoken":
            let tokens = arguments[0].stringValue.components(separatedBy: arguments[1].stringValue)
            let index = Int(arguments[2].integerValue)
            return .string(tokens.indices.contains(index) ? tokens[index] : "")
        case "getleftvumeter": return .integer(vuValue(left: true))
        case "getrightvumeter": return .integer(vuValue(left: false))
        case "getvolume": return .integer(Int32((host.volume * 255).rounded()))
        case "setvolume":
            host.volume = Double(arguments[0].integerValue) / 255
            return .null
        case "seekto":
            host.seek(to: TimeInterval(arguments[0].integerValue))
            return .null
        case "getplayitemlength": return .integer(Int32(clamping: Int64(host.duration)))
        case "integertostring": return .string(String(arguments[0].integerValue))
        case "getprivateint":
            let key = privateKey(section: arguments[0].stringValue, key: arguments[1].stringValue)
            guard UserDefaults.standard.object(forKey: key) != nil else { return .integer(arguments[2].integerValue) }
            return .integer(Int32(UserDefaults.standard.integer(forKey: key)))
        case "setprivateint":
            UserDefaults.standard.set(Int(arguments[2].integerValue),
                                      forKey: privateKey(section: arguments[0].stringValue,
                                                         key: arguments[1].stringValue))
            return .null
        case "getviewportwidth": return .integer(Int32(NSScreen.main?.frame.width ?? 0))
        case "getviewportheight": return .integer(Int32(NSScreen.main?.frame.height ?? 0))
        case "getcurappleft": return .integer(Int32(NSApp.mainWindow?.frame.minX ?? 0))
        case "getcurapptop": return .integer(Int32(NSApp.mainWindow?.frame.minY ?? 0))
        case "getruntimeversion": return .integer(5)
        case "getskinname": return .string(preferenceNamespace)
        case "gettimeofday": return .integer(Int32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000)))
        case "newgroup": return .null
        case "messagebox": return .integer(0) // Sandboxed: skins cannot create modal host UI.
        default:
            throw unsupported(method, program: program)
        }
    }

    private func invokeGUI(method: String, object: WasabiObject, arguments: [MakiValue],
                           program: MakiProgram) throws -> MakiValue {
        switch method {
        case "getlayout", "getobject", "findobject":
            return objectValue(descendant(of: object, xmlID: arguments[0].stringValue))
        case "setxmlparam":
            _ = object.setAttribute(arguments[0].stringValue, value: arguments[1].stringValue)
            graphDidMutate?()
            return .null
        case "resize":
            for (key, value) in zip(["x", "y", "w", "h"], arguments) {
                _ = object.setAttribute(key, value: String(value.integerValue))
            }
            graphDidMutate?()
            return .null
        case "show":
            _ = object.setAttribute("visible", value: "1")
            graphDidMutate?()
            return .null
        case "hide":
            _ = object.setAttribute("visible", value: "0")
            graphDidMutate?()
            return .null
        case "getleft": return .integer(Int32(object.geometry.x))
        case "gettop": return .integer(Int32(object.geometry.y))
        case "getwidth": return .integer(Int32(object.geometry.width ?? 0))
        case "getheight": return .integer(Int32(object.geometry.height ?? 0))
        case "init", "callme": return .null
        default:
            throw unsupported(method, program: program)
        }
    }

    private func invokePopup(method: String, id: UInt64, arguments: [MakiValue]) -> MakiValue {
        switch method {
        case "addcommand":
            popupCommands[id, default: []].append((arguments[0].stringValue, arguments[1].integerValue,
                                                   arguments[2].truthy, arguments[3].truthy))
            return .null
        case "addseparator":
            popupCommands[id, default: []].append(("", 0, false, true))
            return .null
        case "checkcommand":
            let commandID = arguments[0].integerValue
            if let index = popupCommands[id]?.firstIndex(where: { $0.1 == commandID }) {
                let old = popupCommands[id]![index]
                popupCommands[id]![index] = (old.0, old.1, arguments[1].truthy, old.3)
            }
            return .null
        case "popatmouse": return .integer(popupPresenter?(popupCommands[id] ?? []) ?? 0)
        default: return .null
        }
    }

    private func findRoot(type: String, xmlID: String) -> WasabiObject? {
        loadedSkin.runtime.graph.roots.first {
            $0.typeName.caseInsensitiveCompare(type) == .orderedSame &&
            $0.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame
        }
    }

    private func descendant(of root: WasabiObject, xmlID: String) -> WasabiObject? {
        if root.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame { return root }
        for child in root.children {
            if let match = descendant(of: child, xmlID: xmlID) { return match }
        }
        return nil
    }

    private func objectValue(_ object: WasabiObject?) -> MakiValue {
        object.map { .object(MakiObjectReference(.gui($0.stableID))) } ?? .null
    }

    private func object(_ value: MakiValue, equals reference: MakiObjectReference) -> Bool {
        guard case .object(let candidate) = value else { return false }
        return candidate == reference
    }

    private func vuValue(left: Bool) -> Int32 {
        let levels = host.spectrumLevels
        guard !levels.isEmpty else { return 0 }
        let range = left ? levels.prefix((levels.count + 1) / 2) : levels.suffix(levels.count / 2)
        return Int32(max(0, min(255, (range.max() ?? 0) * 255)))
    }

    private func privateKey(section: String, key: String) -> String {
        "winampModern.private.\(preferenceNamespace).\(section).\(key)"
    }

    private func unsupported(_ method: String, program: MakiProgram) -> WalFailure {
        WalFailure(WalDiagnostic(.unsupportedScriptCapability,
                                 "CornerAmp MAKI target does not support method '\(method)'.",
                                 location: program.source))
    }

    func teardown() {
        guard !isTornDown else { return }
        graphDidMutate = nil
        popupPresenter = nil
        timers.teardown()
        interpreter.teardown()
        host.endVisualizationConsumption()
        programs.removeAll()
        popupCommands.removeAll()
        isTornDown = true
    }

    deinit { teardown() }
}

private final class DummyMakiDispatcher: MakiMethodDispatching {
    static let shared = DummyMakiDispatcher()
    func signature(for method: String) -> MakiMethodSignature? { nil }
    func invoke(method: String, on object: MakiObjectReference, arguments: [MakiValue],
                program: MakiProgram) throws -> MakiValue { .null }
    func makeObject(classGUID: String, program: MakiProgram) throws -> MakiObjectReference {
        MakiObjectReference(.system)
    }
}
