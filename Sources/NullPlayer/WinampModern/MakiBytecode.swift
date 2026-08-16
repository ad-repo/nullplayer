import Foundation

struct MakiExecutionLimits: Equatable {
    var maximumInstructionsPerEvent = 5_000_000
    var maximumCallDepth = 256
    var maximumAllocatedBytesPerEvent = 64 * 1_024 * 1_024
    var maximumStackValues = 1_000_000
    var maximumObjectMembers = 65_536

    static let production = MakiExecutionLimits()
}

enum MakiValueKind: UInt8 {
    case null = 0
    case integer = 2
    case float = 3
    case double = 4
    case boolean = 5
    case string = 6
    case object = 7
}

final class MakiObjectReference: Hashable {
    enum Kind: Hashable {
        case system
        case gui(WasabiObjectID)
        case popupMenu(UInt64)
        case dynamic(UInt64)
    }

    let kind: Kind

    init(_ kind: Kind) { self.kind = kind }

    static func == (lhs: MakiObjectReference, rhs: MakiObjectReference) -> Bool {
        lhs.kind == rhs.kind
    }

    func hash(into hasher: inout Hasher) { hasher.combine(kind) }
}

enum MakiValue {
    case null
    case integer(Int32)
    case float(Double)
    case double(Double)
    case boolean(Bool)
    case string(String)
    case object(MakiObjectReference)

    var truthy: Bool {
        switch self {
        case .null: return false
        case .integer(let value): return value != 0
        case .float(let value), .double(let value): return value != 0
        case .boolean(let value): return value
        case .string(let value): return !value.isEmpty
        case .object: return true
        }
    }

    var integerValue: Int32 {
        switch self {
        case .integer(let value): return value
        case .boolean(let value): return value ? 1 : 0
        case .float(let value), .double(let value): return Int32(clamping: Int64(value))
        case .string(let value): return Int32(value) ?? 0
        case .null, .object: return 0
        }
    }

    var doubleValue: Double {
        switch self {
        case .integer(let value): return Double(value)
        case .float(let value), .double(let value): return value
        case .boolean(let value): return value ? 1 : 0
        case .string(let value): return Double(value) ?? 0
        case .null, .object: return 0
        }
    }

    var stringValue: String {
        switch self {
        case .null: return ""
        case .integer(let value): return String(value)
        case .float(let value), .double(let value): return String(value)
        case .boolean(let value): return value ? "1" : "0"
        case .string(let value): return value
        case .object: return ""
        }
    }
}

final class MakiVariable {
    let declaredKind: MakiValueKind
    let classGUID: String?
    let isGlobal: Bool
    let isSystem: Bool
    var value: MakiValue
    var classMembers: [Int] = []
    var isClass = false

    init(declaredKind: MakiValueKind, classGUID: String? = nil, isGlobal: Bool = false,
         isSystem: Bool = false, value: MakiValue) {
        self.declaredKind = declaredKind
        self.classGUID = classGUID
        self.isGlobal = isGlobal
        self.isSystem = isSystem
        self.value = value
    }

    static func temporary(_ value: MakiValue) -> MakiVariable {
        let kind: MakiValueKind
        switch value {
        case .null: kind = .null
        case .integer: kind = .integer
        case .float: kind = .float
        case .double: kind = .double
        case .boolean: kind = .boolean
        case .string: kind = .string
        case .object: kind = .object
        }
        return MakiVariable(declaredKind: kind, value: value)
    }
}

struct MakiMethod {
    let classIndex: Int
    let name: String
}

struct MakiBinding {
    let variableIndex: Int
    let methodIndex: Int
    let instructionIndex: Int
}

enum MakiInstructionArgument {
    case none
    case variable(Int)
    case method(Int)
    case type(Int)
    case instruction(Int)
    /// The declared value type of a dynamic `Member` access (opcode 104).
    case valueKind(MakiValueKind)
}

struct MakiInstruction {
    let opcode: UInt8
    let argument: MakiInstructionArgument
    let byteOffset: Int
}

final class MakiProgram {
    let version: UInt16
    let classes: [String]
    let methods: [MakiMethod]
    let variables: [MakiVariable]
    let bindings: [MakiBinding]
    let instructions: [MakiInstruction]
    let source: WalSourceLocation
    let ownerID: WasabiObjectID?
    let parameter: String?

    init(version: UInt16, classes: [String], methods: [MakiMethod], variables: [MakiVariable],
         bindings: [MakiBinding], instructions: [MakiInstruction], source: WalSourceLocation,
         ownerID: WasabiObjectID?, parameter: String?) {
        self.version = version
        self.classes = classes
        self.methods = methods
        self.variables = variables
        self.bindings = bindings
        self.instructions = instructions
        self.source = source
        self.ownerID = ownerID
        self.parameter = parameter
    }
}

struct MakiBytecodeParser {
    private enum Immediate {
        case none, variable, method, type, instruction, valueKind
    }

    private struct Reader {
        let data: Data
        var offset = 0

        mutating func readUInt8() throws -> UInt8 {
            try require(1)
            defer { offset += 1 }
            return data[data.startIndex + offset]
        }

        mutating func readUInt16() throws -> UInt16 {
            try require(2)
            let a = UInt16(data[data.startIndex + offset])
            let b = UInt16(data[data.startIndex + offset + 1]) << 8
            offset += 2
            return a | b
        }

        mutating func readUInt32() throws -> UInt32 {
            try require(4)
            var result: UInt32 = 0
            for index in 0..<4 {
                result |= UInt32(data[data.startIndex + offset + index]) << UInt32(index * 8)
            }
            offset += 4
            return result
        }

        mutating func readInt32() throws -> Int32 {
            Int32(bitPattern: try readUInt32())
        }

        mutating func readData(count: Int) throws -> Data {
            try require(count)
            defer { offset += count }
            return data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + count))
        }

        mutating func readString() throws -> String {
            let length = Int(try readUInt16())
            let bytes = try readData(count: length)
            guard let value = String(data: bytes, encoding: .utf8) else {
                throw ParseError("MAKI string is not valid UTF-8.")
            }
            return value
        }

        func peekUInt32() throws -> UInt32 {
            var copy = self
            return try copy.readUInt32()
        }

        func require(_ count: Int) throws {
            guard count >= 0, offset <= data.count - count else {
                throw ParseError("MAKI file ends unexpectedly at byte \(offset).")
            }
        }
    }

    private struct ParseError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    let maximumTableEntries: Int

    init(maximumTableEntries: Int = 100_000) {
        self.maximumTableEntries = maximumTableEntries
    }

    func parse(_ data: Data, source: WalSourceLocation, ownerID: WasabiObjectID? = nil,
               parameter: String? = nil) throws -> MakiProgram {
        do {
            var reader = Reader(data: data)
            guard try reader.readData(count: 2) == Data([0x46, 0x47]) else {
                throw ParseError("MAKI magic must be 'FG'.")
            }
            let version = try reader.readUInt16()
            _ = try reader.readUInt32()

            let classCount = try boundedCount(try reader.readUInt32(), section: "class")
            var classes: [String] = []
            classes.reserveCapacity(classCount)
            for _ in 0..<classCount {
                let bytes = try reader.readData(count: 16)
                classes.append(bytes.map { String(format: "%02x", $0) }.joined())
            }

            let methodCount = try boundedCount(try reader.readUInt32(), section: "method")
            var methods: [MakiMethod] = []
            methods.reserveCapacity(methodCount)
            for _ in 0..<methodCount {
                let classCode = try reader.readUInt16()
                _ = try reader.readUInt16()
                let classIndex = Int(classCode & 0xff)
                guard classIndex < classes.count else { throw ParseError("MAKI method references an unknown class.") }
                methods.append(MakiMethod(classIndex: classIndex, name: try reader.readString().lowercased()))
            }

            let variableCount = try boundedCount(try reader.readUInt32(), section: "variable")
            var variables: [MakiVariable] = []
            variables.reserveCapacity(variableCount)
            for _ in 0..<variableCount {
                let typeOffset = Int(try reader.readUInt8())
                let object = try reader.readUInt8() != 0
                let subclass = try reader.readUInt16() != 0
                let initial1 = try reader.readUInt16()
                let initial2 = try reader.readUInt16()
                _ = try reader.readUInt16()
                _ = try reader.readUInt16()
                let global = try reader.readUInt8() != 0
                let system = try reader.readUInt8() != 0

                if subclass {
                    guard typeOffset < variables.count else { throw ParseError("MAKI subclass references an unknown variable.") }
                    let base = variables[typeOffset]
                    base.isClass = true
                    let variable = MakiVariable(declaredKind: .object, classGUID: base.classGUID,
                                                isGlobal: global, isSystem: system, value: .null)
                    variables.append(variable)
                    base.classMembers.append(variables.count - 1)
                } else if object {
                    guard typeOffset < classes.count else { throw ParseError("MAKI object references an unknown class.") }
                    let initial: MakiValue = system ? .object(MakiObjectReference(.system)) : .null
                    variables.append(MakiVariable(declaredKind: .object, classGUID: classes[typeOffset],
                                                  isGlobal: global, isSystem: system, value: initial))
                } else {
                    let kind = MakiValueKind(rawValue: UInt8(typeOffset))
                    let value: MakiValue
                    switch kind {
                    case .integer:
                        value = .integer(Int32(initial1))
                    case .boolean:
                        value = .boolean(initial1 != 0)
                    case .float, .double:
                        let exponent = Int((initial2 & 0xff80) >> 7)
                        let mantissa = Int((0x80 | (initial2 & 0x7f)) << 16) | Int(initial1)
                        let decoded = Double(mantissa) * pow(2, Double(exponent - 0x96))
                        value = kind == .float ? .float(decoded) : .double(decoded)
                    case .string:
                        value = .string("")
                    default:
                        throw ParseError("Unsupported MAKI primitive type \(typeOffset).")
                    }
                    variables.append(MakiVariable(declaredKind: kind!, isGlobal: global,
                                                  isSystem: system, value: value))
                }
            }

            let constantCount = try boundedCount(try reader.readUInt32(), section: "constant")
            for _ in 0..<constantCount {
                let variableIndex = Int(try reader.readUInt32())
                guard variableIndex < variables.count else { throw ParseError("MAKI constant references an unknown variable.") }
                variables[variableIndex].value = .string(try reader.readString())
            }

            let bindingCount = try boundedCount(try reader.readUInt32(), section: "binding")
            var unresolvedBindings: [(Int, Int, Int)] = []
            unresolvedBindings.reserveCapacity(bindingCount)
            for _ in 0..<bindingCount {
                let variable = Int(try reader.readUInt32())
                let method = Int(try reader.readUInt32())
                let byteOffset = Int(try reader.readUInt32())
                guard variable < variables.count, method < methods.count else {
                    throw ParseError("MAKI binding references an unknown variable or method.")
                }
                unresolvedBindings.append((variable, method, byteOffset))
            }

            let codeLength = Int(try reader.readUInt32())
            try reader.require(codeLength)
            let codeStart = reader.offset
            let codeEnd = codeStart + codeLength
            var unresolvedInstructions: [(UInt8, Immediate, Int, Int)] = []
            var offsetToInstruction: [Int: Int] = [:]
            while reader.offset < codeEnd {
                let byteOffset = reader.offset - codeStart
                offsetToInstruction[byteOffset] = unresolvedInstructions.count
                let opcode = try reader.readUInt8()
                let immediate = try immediate(for: opcode)
                var rawArgument = 0
                if immediate != .none {
                    if immediate == .instruction {
                        rawArgument = byteOffset + 5 + Int(try reader.readInt32())
                    } else {
                        rawArgument = Int(try reader.readUInt32())
                    }
                    if reader.offset + 4 <= codeEnd {
                        let protection = try reader.peekUInt32()
                        if (0xffff0000...0xffff000f).contains(protection) { _ = try reader.readUInt32() }
                    }
                    if opcode == 112 { _ = try reader.readUInt8() }
                }
                unresolvedInstructions.append((opcode, immediate, rawArgument, byteOffset))
            }
            guard reader.offset == codeEnd else { throw ParseError("MAKI instruction crosses the code-section boundary.") }

            let instructions = try unresolvedInstructions.map { opcode, immediate, raw, byteOffset in
                let argument: MakiInstructionArgument
                switch immediate {
                case .none: argument = .none
                case .variable:
                    guard raw >= 0, raw < variables.count else { throw ParseError("MAKI opcode references unknown variable \(raw).") }
                    argument = .variable(raw)
                case .method:
                    guard raw >= 0, raw < methods.count else { throw ParseError("MAKI opcode references unknown method \(raw).") }
                    argument = .method(raw)
                case .type:
                    guard raw >= 0, raw < classes.count else { throw ParseError("MAKI opcode references unknown class \(raw).") }
                    argument = .type(raw)
                case .instruction:
                    guard let target = offsetToInstruction[raw] else { throw ParseError("MAKI jump target \(raw) is not an instruction boundary.") }
                    argument = .instruction(target)
                case .valueKind:
                    guard raw >= 0, raw <= Int(UInt8.max), let kind = MakiValueKind(rawValue: UInt8(raw)) else {
                        throw ParseError("MAKI member access declares unknown value type \(raw).")
                    }
                    argument = .valueKind(kind)
                }
                return MakiInstruction(opcode: opcode, argument: argument, byteOffset: byteOffset)
            }

            let bindings = try unresolvedBindings.map { variable, method, byteOffset in
                guard let instruction = offsetToInstruction[byteOffset] else {
                    throw ParseError("MAKI binding target \(byteOffset) is not an instruction boundary.")
                }
                return MakiBinding(variableIndex: variable, methodIndex: method, instructionIndex: instruction)
            }

            return MakiProgram(version: version, classes: classes, methods: methods, variables: variables,
                               bindings: bindings, instructions: instructions, source: source,
                               ownerID: ownerID, parameter: parameter)
        } catch let error as ParseError {
            throw WalFailure(WalDiagnostic(.invalidScript, error.message, location: source))
        }
    }

    private func boundedCount(_ raw: UInt32, section: String) throws -> Int {
        guard raw <= UInt32(maximumTableEntries) else {
            throw ParseError("MAKI \(section) table exceeds \(maximumTableEntries) entries.")
        }
        return Int(raw)
    }

    private func immediate(for opcode: UInt8) throws -> Immediate {
        switch opcode {
        case 1, 3: return .variable
        case 16, 17, 18, 25: return .instruction
        case 24, 112: return .method
        case 96: return .type
        case 104: return .valueKind
        case 2, 8, 9, 10, 11, 12, 13, 33, 40, 48, 56, 57, 58, 59,
             64, 65, 66, 67, 68, 72, 73, 74, 76, 80, 81, 88, 89, 90, 91, 97:
            return .none
        default:
            throw ParseError("Unsupported MAKI opcode \(opcode).")
        }
    }
}

struct MakiMethodSignature {
    let argumentCount: Int
    let returnKind: MakiValueKind
}

protocol MakiMethodDispatching: AnyObject {
    func signature(for method: String, classGUID: String?) -> MakiMethodSignature?
    func invoke(method: String, on object: MakiObjectReference, arguments: [MakiValue],
                program: MakiProgram) throws -> MakiValue
    func makeObject(classGUID: String, program: MakiProgram) throws -> MakiObjectReference
}

final class MakiInterpreter {
    let limits: MakiExecutionLimits
    weak var dispatcher: MakiMethodDispatching?

    private(set) var lastInstructionCount = 0
    private(set) var isTornDown = false

    /// Backing store for MAKI `Member` declarations (`Member int CProWidget.custombg;`), which attach
    /// named, typed storage to an object at runtime rather than to a compiled variable slot. Opcode
    /// 104 resolves one of these to an lvalue, so the entry must persist across events — assignment
    /// (opcode 48) writes straight through the returned `MakiVariable`.
    private var objectMembers: [MakiObjectReference: [String: MakiVariable]] = [:]
    private var objectMemberCount = 0

    init(dispatcher: MakiMethodDispatching, limits: MakiExecutionLimits = .production) {
        self.dispatcher = dispatcher
        self.limits = limits
    }

    func execute(program: MakiProgram, at start: Int, arguments: [MakiValue] = []) throws {
        guard !isTornDown, let dispatcher else { return }
        var stack = arguments.reversed().map(MakiVariable.temporary)
        var callStack: [Int] = []
        var instructionPointer = start
        var instructionCount = 0
        var allocatedBytes = stack.count * 32

        func failure(_ code: WalDiagnosticCode, _ message: String) -> WalFailure {
            WalFailure(WalDiagnostic(code, message, location: program.source))
        }
        func argument(_ instruction: MakiInstruction, variable: Bool = false) throws -> Int {
            switch instruction.argument {
            case .variable(let value) where variable: return value
            case .method(let value) where !variable: return value
            case .type(let value) where !variable: return value
            case .instruction(let value) where !variable: return value
            default: throw failure(.invalidScript, "MAKI opcode \(instruction.opcode) has an invalid argument.")
            }
        }
        func pop() throws -> MakiVariable {
            guard let value = stack.popLast() else { throw failure(.invalidScript, "MAKI value stack underflow.") }
            return value
        }
        func push(_ value: MakiVariable) throws {
            guard stack.count < limits.maximumStackValues else {
                throw failure(.scriptBudgetExceeded, "MAKI value stack exceeds \(limits.maximumStackValues) entries.")
            }
            stack.append(value)
        }
        func numericResult(_ lhs: MakiValue, _ rhs: MakiValue, operation: (Double, Double) -> Double) -> MakiValue {
            if case .integer = lhs, case .integer = rhs {
                return .integer(Int32(clamping: Int64(operation(lhs.doubleValue, rhs.doubleValue))))
            }
            return .double(operation(lhs.doubleValue, rhs.doubleValue))
        }

        while instructionPointer >= 0, instructionPointer < program.instructions.count {
            instructionCount += 1
            guard instructionCount <= limits.maximumInstructionsPerEvent else {
                throw failure(.scriptBudgetExceeded, "MAKI event exceeded \(limits.maximumInstructionsPerEvent) instructions.")
            }
            guard allocatedBytes <= limits.maximumAllocatedBytesPerEvent else {
                throw failure(.scriptBudgetExceeded, "MAKI event exceeded its \(limits.maximumAllocatedBytesPerEvent)-byte allocation budget.")
            }

            let instruction = program.instructions[instructionPointer]
            var next = instructionPointer + 1
            switch instruction.opcode {
            case 1:
                try push(program.variables[try argument(instruction, variable: true)])
            case 2:
                _ = try pop()
            case 3:
                program.variables[try argument(instruction, variable: true)].value = try pop().value
            case 8, 9:
                let rhs = try pop().value
                let lhs = try pop().value
                let equal: Bool
                switch (lhs, rhs) {
                case (.string(let a), .string(let b)): equal = a.caseInsensitiveCompare(b) == .orderedSame
                case (.object(let a), .object(let b)): equal = a == b
                case (.null, .null): equal = true
                case (.null, .integer(let b)), (.integer(let b), .null): equal = b == 0
                default: equal = lhs.stringValue == rhs.stringValue
                }
                try push(.temporary(.boolean(instruction.opcode == 8 ? equal : !equal)))
            case 10, 11, 12, 13:
                let rhs = try pop().value.doubleValue
                let lhs = try pop().value.doubleValue
                let result: Bool
                switch instruction.opcode {
                case 10: result = lhs > rhs
                case 11: result = lhs >= rhs
                case 12: result = lhs < rhs
                default: result = lhs <= rhs
                }
                try push(.temporary(.boolean(result)))
            case 16:
                if !(try pop().value.truthy) { next = try argument(instruction) }
            case 17:
                if try pop().value.truthy { next = try argument(instruction) }
            case 18:
                next = try argument(instruction)
            case 104:
                // Dynamic `Member` access: pops the member name and its owning object, and pushes the
                // member's storage as an lvalue (the compiler emits the declared type as the immediate).
                guard case .valueKind(let kind) = instruction.argument else {
                    throw failure(.invalidScript, "MAKI member access is missing its value type.")
                }
                let name = try pop().value.stringValue
                let owner = try pop().value
                guard case .object(let reference) = owner else {
                    throw failure(.invalidScript, "MAKI member '\(name)' was accessed on a non-object value.")
                }
                try push(try member(name, on: reference, kind: kind))
            case 24, 112:
                let methodIndex = try argument(instruction)
                let method = program.methods[methodIndex]
                let classGUID = program.classes.indices.contains(method.classIndex)
                    ? program.classes[method.classIndex] : nil
                guard let signature = dispatcher.signature(for: method.name, classGUID: classGUID) else {
                    throw failure(.unsupportedScriptCapability, "Winamp Modern runtime does not support method '\(method.name)'.")
                }
                var arguments: [MakiValue] = []
                arguments.reserveCapacity(signature.argumentCount)
                for _ in 0..<signature.argumentCount { arguments.append(try pop().value) }
                let receiver = try pop()
                guard case .object(let object) = receiver.value else {
                    let variableIndex = program.variables.firstIndex { $0 === receiver }
                    let suffix = variableIndex.map { " from variable \($0)." } ?? "."
                    throw failure(.invalidScript,
                                  "MAKI attempted '\(method.name)' (class \(classGUID ?? "unknown")) on a null/non-object value" +
                                  suffix)
                }
                let result = try dispatcher.invoke(method: method.name, on: object,
                                                   arguments: arguments, program: program)
                if case .string(let string) = result { allocatedBytes += string.utf8.count }
                try push(.temporary(result))
            case 25:
                guard callStack.count < limits.maximumCallDepth else {
                    throw failure(.scriptBudgetExceeded, "MAKI call depth exceeds \(limits.maximumCallDepth).")
                }
                callStack.append(next)
                next = try argument(instruction)
            case 33:
                guard let returnAddress = callStack.popLast() else {
                    lastInstructionCount = instructionCount
                    return
                }
                next = returnAddress
            case 40:
                break
            case 48:
                let source = try pop()
                let destination = try pop()
                destination.value = source.value
                try push(source)
            case 56, 57, 58, 59:
                let value = try pop()
                let old = value.value.integerValue
                let delta: Int32 = (instruction.opcode == 56 || instruction.opcode == 58) ? 1 : -1
                value.value = .integer(old &+ delta)
                let result = (instruction.opcode == 56 || instruction.opcode == 57) ? old : old &+ delta
                try push(.temporary(.integer(result)))
            case 64, 65, 66, 67, 68:
                let rhs = try pop().value
                let lhs = try pop().value
                let result: MakiValue
                if instruction.opcode == 64,
                   case .string(let left) = lhs, case .string(let right) = rhs {
                    result = .string(left + right)
                    allocatedBytes += left.utf8.count + right.utf8.count
                } else {
                    switch instruction.opcode {
                    case 64: result = numericResult(lhs, rhs, operation: +)
                    case 65: result = numericResult(lhs, rhs, operation: -)
                    case 66: result = numericResult(lhs, rhs, operation: *)
                    case 67:
                        guard rhs.doubleValue != 0 else { throw failure(.invalidScript, "MAKI division by zero.") }
                        result = numericResult(lhs, rhs, operation: /)
                    default:
                        guard rhs.integerValue != 0 else { throw failure(.invalidScript, "MAKI modulo by zero.") }
                        result = .integer(lhs.integerValue % rhs.integerValue)
                    }
                }
                try push(.temporary(result))
            case 72, 73, 88, 89, 90, 91:
                let rhs = try pop().value.integerValue
                let lhs = try pop().value.integerValue
                let result: Int32
                switch instruction.opcode {
                case 72: result = lhs & rhs
                case 73: result = lhs | rhs
                case 88, 90: result = lhs << (rhs & 31)
                default: result = lhs >> (rhs & 31)
                }
                try push(.temporary(.integer(result)))
            case 74:
                try push(.temporary(.boolean(!(try pop().value.truthy))))
            case 76:
                try push(.temporary(.integer(-(try pop().value.integerValue))))
            case 80, 81:
                let rhs = try pop().value
                let lhs = try pop().value
                let result = instruction.opcode == 80 ? (lhs.truthy && rhs.truthy) : (lhs.truthy || rhs.truthy)
                try push(.temporary(.boolean(result)))
            case 96:
                let classIndex = try argument(instruction)
                try push(.temporary(.object(try dispatcher.makeObject(classGUID: program.classes[classIndex], program: program))))
                allocatedBytes += 128
            case 97:
                _ = try pop()
            default:
                throw failure(.unsupportedScriptCapability, "Unsupported MAKI opcode \(instruction.opcode).")
            }
            instructionPointer = next
        }
        lastInstructionCount = instructionCount
    }

    func teardown() {
        dispatcher = nil
        objectMembers.removeAll()
        objectMemberCount = 0
        isTornDown = true
    }

    /// Resolve (creating on first touch) the storage for `name` on `object`, typed by the member's
    /// declaration. Returned as an lvalue so reads and assignments both hit the same slot.
    private func member(_ name: String, on object: MakiObjectReference,
                        kind: MakiValueKind) throws -> MakiVariable {
        let key = name.lowercased()
        if let existing = objectMembers[object]?[key] { return existing }
        guard objectMemberCount < limits.maximumObjectMembers else {
            throw WalFailure(WalDiagnostic(.scriptBudgetExceeded,
                                           "MAKI skin exceeds \(limits.maximumObjectMembers) object members."))
        }
        let initial: MakiValue
        switch kind {
        case .integer: initial = .integer(0)
        case .boolean: initial = .boolean(false)
        case .float: initial = .float(0)
        case .double: initial = .double(0)
        case .string: initial = .string("")
        case .null, .object: initial = .null
        }
        let variable = MakiVariable(declaredKind: kind, value: initial)
        objectMembers[object, default: [:]][key] = variable
        objectMemberCount += 1
        return variable
    }
}
