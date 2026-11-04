import Foundation

extension AIMPSkinScript {
    // MARK: - Values

    enum Value {
        case number(Double)
        case string(String)
        case resource(String)
        /// What `FindObject` found, and a handler's `Sender` (`AIMPSkinScript+HostBridge.swift`).
        case object(HostObject)
        /// A binding set a script holds, and one link in it (`AIMPSkinScript+Bindings.swift`).
        case bindings(BindingSetKey)
        case link(BindingSetKey, pin: String)
        /// A Pascal array, by index.
        case array([Int: Value])
        /// The objects an event hands its handler: a mouse handler's `Arguments` (`X`, `Y`,
        /// `Button`), a visualization handler's `Data` (`Spectrum`), a form event's `EventData`;
        /// and the `TASEBindings` class, which `Create` makes a binding set of.
        case arguments, visualData, eventData, bindingsClass
        case none

        var number: Double {
            switch self {
            case .number(let n): return n
            case .string(let s): return Double(s) ?? 0
            default: return 0
            }
        }

        var string: String {
            switch self {
            case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
            case .string(let s): return s
            case .resource(let name): return name
            case .object(let object): return object.name
            default: return ""
            }
        }

        /// What it is, for a run that stops on it.
        var described: String {
            switch self {
            case .number, .string: return "'\(string)'"
            case .resource(let name): return "resource \(name)"
            case .object(let object): return "object \(object.name)"
            case .bindings, .bindingsClass: return "bindings"
            case .link(_, let pin): return "link \(pin)"
            case .array: return "array"
            case .arguments: return "Arguments"
            case .visualData: return "Data"
            case .eventData: return "EventData"
            case .none: return "nil"
            }
        }

        /// An object, whose bracketed member is an indexed property (`Data.Spectrum[Channel, I]`).
        var isObject: Bool {
            switch self {
            case .object, .arguments, .visualData, .eventData, .bindingsClass: return true
            default: return false
            }
        }
    }

    /// `exit` unwinds to the routine it left.
    struct ExitSignal: Error {}

    /// An error Delphi raises and a skin's own `except` catches: a zero divisor (`EDivByZero`,
    /// `EZeroDivide`) or a shift out of range. Uncaught, it ends the run (`execute`).
    struct Raised: Error, CustomStringConvertible {
        let what: String
        var description: String { what }
    }

    // MARK: - Running

    /// One program running on an engine: its scopes, `with` objects and binding sets. What it sets
    /// and asks for is the engine's, and so is its actor.
    @MainActor
    final class Run {
        let engine: Engine
        let program: Program
        /// A mouse handler's `Arguments` (`X`, `Y`).
        let arguments: [String: Double]
        /// Innermost last; the first is the program's globals. Scopes are dynamic, as FastScript's:
        /// a routine sees its caller's names.
        private var scopes: [[String: Value]] = [[:]]
        private var withObjects: [Value] = []
        /// Binding sets the script holds (`AIMPSkinScript+Bindings.swift`).
        var bindingSets: [BindingSetKey: BindingSet] = [:]
        var bindingSetsMade = 0

        var skin: AIMPSkin { engine.skin }
        var flow: AIMPSkinDataflow { engine.flow }

        init(engine: Engine, program: Program, sender: String, arguments: [String: Double]) {
            self.engine = engine
            self.program = program
            self.arguments = arguments
            scopes[0]["sender"] = .object(HostObject(sender, in: engine.skin))
        }

        func lookup(_ name: String) -> Value? {
            for scope in scopes.reversed() { if let value = scope[name] { return value } }
            return skinVariable(name)
        }

        func assign(_ name: String, _ value: Value) {
            for i in scopes.indices.reversed() where scopes[i][name] != nil {
                scopes[i][name] = value
                return
            }
            if skin.index.variables[name] != nil {
                engine.state.script.variables[name] = value.string
                return
            }
            scopes[scopes.count - 1][name] = value
        }

        /// One of the skin's variables, as last written by any of its scripts, else as declared.
        private func skinVariable(_ name: String) -> Value? {
            guard let variable = skin.index.variables[name] else { return nil }
            let text = engine.state.script.variables[name] ?? variable.value
            if variable.isText { return .string(text) }
            switch text.lowercased() {
            case "true": return .number(1)
            case "false": return .number(0)
            default: return .number(Double(text) ?? 0)
            }
        }

        /// The program's own block, then `Execute`, its parameters being the globals of the same
        /// name, so a `var State` writes back; returns `State` after the run.
        func execute(statePosition: Double) throws -> Double {
            if lookup(program.stateName) == nil { scopes[0][program.stateName] = .number(statePosition) }
            scopes[0].merge(["true": .number(1), "false": .number(0), "nil": .none]) { _, constant in constant }
            // The objects the event's other parameters are, by name.
            for (name, object) in [("arguments", Value.arguments), ("eventdata", .eventData), ("data", .visualData)]
            where lookup(name) == nil {
                scopes[0][name] = object
            }
            // An error the skin raises and does not catch ends the run where it was raised, as
            // FastScript's does: what ran before it stands (Marantz 5030's position script divides by
            // `PositionMax`, 0 with nothing loaded, after it has set its counters).
            do {
                try declare(program.declarations)
                if let block = program.block {
                    do { try execute(block) } catch is ExitSignal {}
                }
                if let main = program.main { try run(main, arguments: nil) }
            } catch is Raised {}
            return lookup(program.stateName)?.number ?? statePosition
        }

        private func declare(_ declarations: [Declaration]) throws {
            for declaration in declarations { try declare(declaration) }
        }

        /// A `var` or `const` in the current scope; a `var` already there keeps its value.
        private func declare(_ declaration: Declaration) throws {
            switch declaration {
            case .variables(let names, let initial, let isArray):
                let value = try initial.map(evaluate) ?? (isArray ? .array([:]) : .number(0))
                for name in names where scopes[scopes.count - 1][name] == nil { scopes[scopes.count - 1][name] = value }
            case .constant(let name, let value):
                scopes[scopes.count - 1][name] = try evaluate(value)
            }
        }

        /// Runs routine `index`. With `arguments` nil its parameters read the globals of their
        /// names; otherwise they are bound in order in a new scope, a missing one at its default.
        /// Returns the routine's `Result` (or the value assigned to its name).
        @discardableResult
        private func run(_ index: Int, arguments: [Value]?) throws -> Value {
            try engine.budget.nested {
                let routine = program.routines[index]
                var scope: [String: Value] = [:]
                if let arguments {
                    for (i, parameter) in routine.parameters.enumerated() {
                        scope[parameter.name] = try i < arguments.count ? arguments[i] : parameter.initial.map(evaluate) ?? .none
                    }
                    scope["result"] = .number(0)
                }
                scopes.append(scope)
                defer { scopes.removeLast() }
                try declare(routine.declarations)
                if let body = routine.body {
                    do { try execute(body) } catch is ExitSignal {}
                }
                return scopes[scopes.count - 1][routine.name] ?? scopes[scopes.count - 1]["result"] ?? .none
            }
        }

        // MARK: Statements

        private func execute(_ statements: [Statement]) throws {
            for statement in statements { try execute(statement) }
        }

        private func execute(_ statement: Statement) throws {
            try engine.budget.step()
            switch statement {
            case .block(let statements):
                try execute(statements)
            case .assign(let name, let value):
                assign(name, try evaluate(value))
            case .assignElement(let name, let index, let value):
                let value = try evaluate(value)
                let index = Int(try evaluate(index).number)
                // An array declared through a type alias starts as a plain variable.
                var elements: [Int: Value] = [:]
                if case .array(let existing) = lookup(name) ?? .none { elements = existing }
                elements[index] = value
                assign(name, .array(elements))
            case .assignProperty(let target, let property, let value):
                let value = try evaluate(value)
                _ = try method(try evaluate(target), .set, [.string(property), value])
            case .call(let designator):
                _ = try evaluate(designator)
            case .attempt(let body, let handler, let cleanup):
                try attempt(body, except: handler, finally: cleanup)
            case .select(let selector, let branches, let otherwise):
                let value = try evaluate(selector)
                for branch in branches where try contains(branch.labels, value) {
                    return try execute(branch.body)
                }
                if let otherwise { try execute(otherwise) }
            case .conditional(let condition, let then, let otherwise):
                if try evaluate(condition).number != 0 {
                    if let then { try execute(then) }
                } else if let otherwise {
                    try execute(otherwise)
                }
            case .loop(let name, let from, let to, let down, let body):
                let from = Int(try evaluate(from).number), to = Int(try evaluate(to).number)
                guard down ? from >= to : from <= to else { return }
                for i in stride(from: from, through: to, by: down ? -1 : 1) {
                    assign(name, .number(Double(i)))
                    try execute(body)
                    try engine.budget.step()
                }
            case .whileLoop(let condition, let body):
                while try evaluate(condition).number != 0 {
                    try execute(body)
                    try engine.budget.step()
                }
            case .repeatLoop(let body, let condition):
                repeat {
                    try execute(body)
                    try engine.budget.step()
                } while try evaluate(condition).number == 0
            case .with(let target, let body):
                withObjects.append(try evaluate(target))
                defer { withObjects.removeLast() }
                try execute(body)
            case .exit:
                throw ExitSignal()
            case .declare(let declaration):
                try declare(declaration)
            }
        }

        /// `try … except … end` runs its handler on an error the skin can catch; `try … finally …
        /// end` its cleanup whatever happens (Red Bias's theme switchers). `exit`, a spent budget and
        /// an interpreter gap (`Unsupported`) pass through the handler: a skin's `except` must not
        /// hide what NullPlayer cannot do.
        private func attempt(_ body: [Statement], except handler: [Statement]?, finally cleanup: [Statement]?) throws {
            var failure: Error?
            do { try execute(body) } catch { failure = error }
            if let cleanup { try execute(cleanup) }
            guard let failure else { return }
            guard let handler, !(failure is ExitSignal || failure is Budget.Spent || failure is Unsupported) else { throw failure }
            try execute(handler)
        }

        /// Whether `value` is one of `members`; a range holds everything from its low end to its high
        /// end, as Pascal's does (Pioneer RT-909's level scale picks a frame by `0..9`, `10..19`…):
        /// numbers by value, a character range (`'a'..'z'`) by its text.
        private func contains(_ members: [SetMember], _ value: Value) throws -> Bool {
            try members.contains { member in
                switch member {
                case .value(let option): return try evaluate(option).string == value.string
                case .range(let low, let high):
                    let (low, high) = (try evaluate(low), try evaluate(high))
                    if case .string(let text) = value, Double(text) == nil {
                        return low.string <= text && text <= high.string
                    }
                    return low.number <= value.number && value.number <= high.number
                }
            }
        }

        // MARK: Expressions

        func evaluate(_ expression: Expression) throws -> Value {
            switch expression {
            case .number(let number): return .number(number)
            case .string(let text): return .string(text)
            // A set held as a value: its members, a range of whole numbers every one between its ends
            // (a Pascal set holds at most 256), any other range by its ends.
            case .set(let members):
                let values = try members.flatMap { member -> [Value] in
                    switch member {
                    case .value(let value): return [try evaluate(value)]
                    case .range(let low, let high):
                        let (low, high) = (try evaluate(low), try evaluate(high))
                        guard let from = Int(exactly: low.number), let to = Int(exactly: high.number),
                              from <= to, to - from < 256 else { return [low, high] }
                        return (from...to).map { .number(Double($0)) }
                    }
                }
                return .array(Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0, $1) }))
            case .designator(let designator): return try evaluate(designator)
            case .unary(let op, let operand):
                let value = try evaluate(operand)
                switch op {
                case .not: return .number(value.number == 0 ? 1 : 0)
                case .negate: return .number(-value.number)
                case .plus: return value
                }
            case .binary(.member, let left, .set(let members)):
                return .number(try contains(members, try evaluate(left)) ? 1 : 0)
            case .binary(let op, let left, let right):
                return try apply(op, try evaluate(left), try evaluate(right))
            }
        }

        /// `op` on two values: the numeric core a binding's expression uses
        /// (`AIMPSkinExpression.Operator.apply`), with what only a script has on top: `+` joins text,
        /// `in` tests a set, and a comparison compares text unless a number meets a number (`'1.0' =
        /// 1` holds, `'10' < '9'` too, as Delphi's variants compare).
        private func apply(_ op: BinaryOperator, _ left: Value, _ right: Value) throws -> Value {
            if op == .add, case .string = left { return .string(left.string + right.string) }
            if op == .add, case .string = right { return .string(left.string + right.string) }
            func truth(_ condition: Bool) -> Value { .number(condition ? 1 : 0) }
            guard let numeric = op.numeric else {
                guard case .array(let members) = right else { return .number(0) }
                return truth(members.values.contains { $0.string == left.string })
            }
            if op.isComparison, !Self.comparesAsNumbers(left, right) {
                let (a, b) = (left.string, right.string)
                switch numeric {
                case .equal: return truth(a == b)
                case .notEqual: return truth(a != b)
                case .less: return truth(a < b)
                case .greater: return truth(a > b)
                case .lessOrEqual: return truth(a <= b)
                default: return truth(a >= b)
                }
            }
            guard let result = numeric.apply(left.number, right.number) else { throw Raised(what: "\(left.string) \(numeric.rawValue) \(right.string)") }
            return .number(result)
        }

        /// Whether a comparison is numeric: a number against a number, or against text that reads as one.
        private static func comparesAsNumbers(_ left: Value, _ right: Value) -> Bool {
            func number(_ value: Value) -> Double? {
                switch value {
                case .number(let n): return n
                case .string(let s): return Double(s)
                default: return nil
                }
            }
            let oneIsNumber: Bool
            if case .number = left { oneIsNumber = true } else if case .number = right { oneIsNumber = true } else { oneIsNumber = false }
            return oneIsNumber && number(left) != nil && number(right) != nil
        }

        private func evaluate(_ designator: Designator) throws -> Value {
            var value = try call(designator.head)
            for selector in designator.selectors {
                switch selector {
                case .index(let index):
                    value = element(of: value, Int(try evaluate(index).number))
                case .member(let member, let arguments, let subscripts):
                    let arguments = try arguments.map(evaluate)
                    guard let subscripts else {
                        value = try method(value, member, arguments)
                        continue
                    }
                    if value.isObject {
                        value = try method(value, member, arguments + subscripts.map(evaluate))
                    } else {
                        value = try method(value, member, arguments)
                        if let first = subscripts.first { value = element(of: value, Int(try evaluate(first).number)) }
                    }
                }
            }
            return value
        }

        private func element(of value: Value, _ index: Int) -> Value {
            if case .array(let elements) = value { return elements[index] ?? .number(0) }
            return .number(0)
        }

        /// A designator's first name: a variable (with no arguments), a routine, a built-in, a host
        /// call, or, inside `with`, a method of the `with` object.
        private func call(_ call: Call) throws -> Value {
            if call.arguments.isEmpty, let variable = lookup(call.key) { return variable }
            if case .builtin(let builtin) = call.target, builtin.readsVariable {
                var args = [lookup(call.arguments[0].variable ?? "") ?? .none]
                args += try call.arguments.dropFirst().map { try evaluate($0.value) }
                return write(builtin.call(args), to: call.arguments)
            }
            let args = try call.arguments.map { try evaluate($0.value) }
            switch call.target {
            case .routine(let index): return try run(index, arguments: args)
            case .builtin(let builtin): return write(builtin.call(args), to: call.arguments)
            case .host(let host): return try self.host(host, args)
            case .unresolved:
                if let target = withObjects.last { return try method(target, Member(call.name), args) }
                throw Unsupported(what: "call \(call.name)")
            }
        }

        /// A built-in's result, its `var` parameters written to the variables their arguments name.
        private func write(_ result: (value: Value, outputs: [Int: Value]), to arguments: [Argument]) -> Value {
            for (i, value) in result.outputs where i < arguments.count {
                if let name = arguments[i].variable { assign(name, value) }
            }
            return result.value
        }
    }
}
