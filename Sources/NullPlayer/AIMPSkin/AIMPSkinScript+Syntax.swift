import Foundation

/// A script compiled once, as the skin loads, from FastScript's syntax tree (`.fsxml`): what the
/// interpreter (`AIMPSkinScript+Run.swift`) executes. FastScript writes a tree whose shape this
/// reads by tag (`reference/format.md` § *Scripts*); a tree it does not take is a load-time
/// finding (`Malformed`), and the script is left out.
extension AIMPSkinScript {
    struct Program: Sendable {
        /// The program's own `var` and `const` declarations, then its `begin … end.` block.
        let declarations: [Declaration]
        let block: Statement?
        /// Every procedure and function, nested ones included (`GetMaxValue` inside `Execute`):
        /// the first of a name is the one called.
        let routines: [Routine]
        /// `Execute`, the event's entry point; a unit without one (Arc's empty `SOFMaster`) is only
        /// its block.
        let main: Int?
        /// The global a counter's state is in: `Execute`'s first parameter when it is a `var` one,
        /// whatever it is called (Red Bias's `Execute(var ALayout: Integer)`), else `state`.
        let stateName: String
    }

    struct Routine: Sendable {
        let name: String
        /// In order, each with its default (`maxTries: Integer = 5`, Soot's `acSetState`).
        let parameters: [(name: String, initial: Expression?)]
        let declarations: [Declaration]
        let body: Statement?
    }

    enum Declaration: Sendable {
        /// `var A, B: T = v`: each name starts at the initializer, else 0, else an empty array.
        case variables([String], initial: Expression?, isArray: Bool)
        case constant(String, Expression)
    }

    indirect enum Statement: Sendable {
        /// `begin … end`, and an `if`'s `then` and `else`.
        case block([Statement])
        case assign(String, Expression)
        /// `A[i] := v`.
        case assignElement(String, index: Expression, Expression)
        /// `Object.Property := v`: the host object's `Set(Property, v)`
        /// (`FindObject('liMlTable').Parent := FindObject('liAioTableHost')`).
        case assignProperty(Designator, property: String, Expression)
        case call(Designator)
        /// `try … except … end` and `try … finally … end` (Red Bias's theme switchers).
        case attempt(body: [Statement], except: [Statement]?, finally: [Statement]?)
        case select(Expression, [CaseBranch], otherwise: Statement?)
        case conditional(Expression, then: Statement?, otherwise: Statement?)
        case loop(variable: String, from: Expression, to: Expression, down: Bool, body: [Statement])
        case whileLoop(Expression, body: [Statement])
        case repeatLoop(body: [Statement], until: Expression)
        case with(Designator, body: [Statement])
        case exit
        case declare(Declaration)
    }

    struct CaseBranch: Sendable {
        let labels: [SetMember]
        let body: [Statement]
    }

    /// One member of a set constructor (`[a, b..c]`) or a `case` label: a value, or a range of them.
    enum SetMember: Sendable {
        case value(Expression)
        case range(Expression, Expression)
    }

    indirect enum Expression: Sendable {
        case number(Double)
        case string(String)
        /// A set constructor `[a, b..c]`, for `in`.
        case set([SetMember])
        case designator(Designator)
        case unary(UnaryOperator, Expression)
        case binary(BinaryOperator, Expression, Expression)
    }

    enum UnaryOperator: Sendable {
        case not, negate, plus

        init?(_ text: String) {
            switch text {
            case "not": self = .not
            case "-", "unminus": self = .negate
            case "+", "unplus": self = .plus
            default: return nil
            }
        }
    }

    enum BinaryOperator: Sendable {
        case add, subtract, multiply, divide, intDivide, modulo
        case and, or, xor, shiftLeft, shiftRight
        case member, equal, notEqual, less, greater, lessOrEqual, greaterOrEqual

        init?(_ text: String) {
            switch text {
            case "+": self = .add
            case "-": self = .subtract
            case "*": self = .multiply
            case "/": self = .divide
            case "div": self = .intDivide
            case "mod": self = .modulo
            case "and": self = .and
            case "or": self = .or
            case "xor": self = .xor
            case "shl": self = .shiftLeft
            case "shr": self = .shiftRight
            case "in": self = .member
            case "=": self = .equal
            case "<>": self = .notEqual
            case "<": self = .less
            case ">": self = .greater
            case "<=": self = .lessOrEqual
            case ">=": self = .greaterOrEqual
            default: return nil
            }
        }

        /// Pascal's: multiplying operators bind tighter than adding ones, and those than comparisons.
        var precedence: Int {
            switch self {
            case .multiply, .divide, .intDivide, .modulo, .and, .shiftLeft, .shiftRight: return 2
            case .add, .subtract, .or, .xor: return 1
            default: return 0
            }
        }

        /// The operator on numbers, the core a binding's expression uses too; nil for `in`.
        var numeric: AIMPSkinExpression.Operator? {
            switch self {
            case .add: return .add
            case .subtract: return .subtract
            case .multiply: return .multiply
            case .divide: return .divide
            case .intDivide: return .div
            case .modulo: return .mod
            case .and: return .and
            case .or: return .or
            case .xor: return .xor
            case .shiftLeft: return .shl
            case .shiftRight: return .shr
            case .member: return nil
            case .equal: return .equal
            case .notEqual: return .notEqual
            case .less: return .less
            case .greater: return .greater
            case .lessOrEqual: return .lessOrEqual
            case .greaterOrEqual: return .greaterOrEqual
            }
        }

        var isComparison: Bool { [.equal, .notEqual, .less, .greater, .lessOrEqual, .greaterOrEqual].contains(self) }
    }

    /// `name(args…)[index].member(args…)…`: a variable, routine or built-in, then members and
    /// indexes of what each step gives.
    struct Designator: Sendable {
        let head: Call
        let selectors: [Selector]
    }

    /// The name a designator starts with, resolved as the script compiles where it can: a routine
    /// of the program, a built-in, or neither (a method of the `with` object, else unsupported).
    /// A variable of the name, when there are no arguments, still comes first: scopes are dynamic.
    struct Call: Sendable {
        /// As written, and lowercased (Pascal names are not case-sensitive).
        let name: String
        let key: String
        let arguments: [Argument]
        let target: Target

        enum Target: Sendable {
            case routine(Int)
            case builtin(Builtin)
            case host(HostCall)
            case unresolved
        }
    }

    /// An argument, and the variable it names, for the `var` parameters some built-ins write
    /// (`Inc(X)`, `DecodeTime(T, H, M, S, MS)`).
    struct Argument: Sendable {
        let value: Expression
        let variable: String?
    }

    enum Selector: Sendable {
        /// `.Member(args…)`. `subscripts` are what followed it in brackets: an object's indexed
        /// property takes them as more arguments (`Data.Spectrum[Channel, I]`); anything else is
        /// indexed by the first.
        case member(Member, arguments: [Expression], subscripts: [Expression]?)
        case index(Expression)
    }

    /// A method a script calls on a value, by its lowercased name.
    enum Member: Sendable, Equatable {
        case set, get, execute, dock, undock, parent, free, create
        case linkAdd, linkFind, linkDelete, clear, getDataAsText, getDataAsNumber, executeAction
        case beginUpdate, endUpdate, copyToClipboard, spectrum, getResourceName
        case other(String)

        init(_ name: String) {
            switch name.lowercased() {
            case "set": self = .set
            case "get": self = .get
            case "execute": self = .execute
            case "dock": self = .dock
            case "undock": self = .undock
            case "parent": self = .parent
            case "free": self = .free
            case "create": self = .create
            case "linkadd": self = .linkAdd
            case "linkfind": self = .linkFind
            case "linkdelete", "linkremove": self = .linkDelete
            case "clear": self = .clear
            case "getdataastext": self = .getDataAsText
            case "getdataasinteger", "getdataasfloat", "getdataasboolean", "getdata": self = .getDataAsNumber
            case "executeaction": self = .executeAction
            case "beginupdate": self = .beginUpdate
            case "endupdate": self = .endUpdate
            case "copytoclipboard": self = .copyToClipboard
            case "spectrum": self = .spectrum
            case "getresourcename": self = .getResourceName
            case let other: self = .other(other)
            }
        }
    }

    /// A syntax tree this compiler does not take: the script is left out of the skin, with this as
    /// its load-time finding.
    struct Malformed: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: - Compiling

    /// `root`, FastScript's tree of one script, compiled.
    static func compile(_ root: AIMPNode) throws -> Program {
        try Compiler(root).program()
    }

    private struct Compiler {
        let root: AIMPNode
        /// Every routine node, nested ones included, in the order they are found; the first of a
        /// name wins.
        let routineNodes: [AIMPNode]
        let routineIndex: [String: Int]

        init(_ root: AIMPNode) {
            self.root = root
            var nodes: [AIMPNode] = []
            var index: [String: Int] = [:]
            func register(_ node: AIMPNode) {
                for routine in node.children where routine.tag == "procedure" || routine.tag == "function" {
                    if let name = routine.child("name")?["text"]?.lowercased(), index[name] == nil {
                        index[name] = nodes.count
                        nodes.append(routine)
                    }
                    register(routine)
                }
            }
            register(root)
            routineNodes = nodes
            routineIndex = index
        }

        func program() throws -> Program {
            let main = routineIndex["execute"]
            return Program(declarations: try declarations(in: root),
                           block: try root.child("compoundstmt").map(statement),
                           routines: try routineNodes.map(routine),
                           main: main,
                           stateName: main.flatMap { stateParameter(routineNodes[$0]) } ?? "state")
        }

        /// The name of `routine`'s first parameter when it is a `var` one: `procedure Execute(var
        /// State: Integer)` arrives as `parameters` holding `varparams`, then `var` with the name.
        private func stateParameter(_ routine: AIMPNode) -> String? {
            guard let parameters = routine.child("parameters"), parameters.children.first?.tag == "varparams" else { return nil }
            return parameters.child("var")?.child("ident")?["text"]?.lowercased()
        }

        private func routine(_ node: AIMPNode) throws -> Routine {
            let parameters = try (node.child("parameters")?.children("var") ?? []).flatMap { group in
                let initial = try group.child("init")?.child("expr").map(expression)
                return group.children("ident").compactMap { $0["text"]?.lowercased() }.map { (name: $0, initial: initial) }
            }
            return Routine(name: node.child("name")?["text"]?.lowercased() ?? "", parameters: parameters,
                           declarations: try declarations(in: node), body: try node.child("compoundstmt").map(statement))
        }

        private func declarations(in node: AIMPNode) throws -> [Declaration] {
            try node.children.compactMap(declaration)
        }

        /// A `var` or `const`; nil for any other node.
        private func declaration(_ node: AIMPNode) throws -> Declaration? {
            switch node.tag {
            case "var":
                // `var Normalize: Boolean = True` starts at its initializer (Soot's timers).
                return .variables(node.children("ident").compactMap { $0["text"]?.lowercased() },
                                  initial: try node.child("init")?.child("expr").map(expression),
                                  isArray: node.descendants().contains { $0.tag == "array" })
            case "const":
                guard let name = node.child("ident")?["text"]?.lowercased(), let value = node.child("expr") else { return nil }
                return .constant(name, try expression(value))
            default:
                return nil
            }
        }

        private func statements(_ nodes: [AIMPNode]) throws -> [Statement] { try nodes.map(statement) }

        private func statement(_ node: AIMPNode) throws -> Statement {
            switch node.tag {
            case "compoundstmt", "thenstmt", "elsestmt":
                return .block(try statements(node.children))
            case "assignstmt":
                guard let target = node.child("dsgn"), let value = node.child("expr") else { throw malformed(node) }
                let parts = target.children
                guard let first = parts.first, first.tag == "node", let name = first["text"]?.lowercased() else { throw malformed(node) }
                if parts.count == 1 { return .assign(name, try expression(value)) }
                if parts.count == 3, parts[1]["text"] == "[", parts[2].tag == "expr" {
                    return .assignElement(name, index: try expression(parts[2]), try expression(value))
                }
                guard let property = parts.last, property.tag == "node", let propertyName = property["text"] else { throw malformed(node) }
                let object = AIMPNode(tag: "dsgn", attributes: target.attributes, children: Array(parts.dropLast()), text: nil)
                return .assignProperty(try designator(object), property: propertyName, try expression(value))
            case "callstmt":
                guard let call = node.child("dsgn") else { throw malformed(node) }
                return .call(try designator(call))
            case "trystmt":
                return .attempt(body: try statements(node.children.filter { $0.tag != "exceptstmt" && $0.tag != "finallystmt" }),
                                except: try node.child("exceptstmt").map { try statements($0.children) },
                                finally: try node.child("finallystmt").map { try statements($0.children) })
            case "casestmt":
                guard let selector = node.child("expr") else { throw malformed(node) }
                let branches = try node.children("caseselector").map { branch in
                    CaseBranch(labels: try labels(branch.child("set")), body: try statements(branch.children.filter { $0.tag != "set" }))
                }
                return .select(try expression(selector), branches, otherwise: try node.child("elsestmt").map(statement))
            case "ifstmt":
                guard let condition = node.child("expr") else { throw malformed(node) }
                return .conditional(try expression(condition), then: try node.child("thenstmt").map(statement),
                                    otherwise: try node.child("elsestmt").map(statement))
            case "forstmt":
                let bounds = node.children("expr")
                guard let name = node.child("ident")?["text"]?.lowercased(), bounds.count == 2 else { throw malformed(node) }
                return .loop(variable: name, from: try expression(bounds[0]), to: try expression(bounds[1]),
                             down: node.child("downto") != nil,
                             body: try statements(node.children.filter { !["ident", "expr", "downto"].contains($0.tag) }))
            case "whilestmt":
                guard let condition = node.child("expr") else { throw malformed(node) }
                return .whileLoop(try expression(condition), body: try statements(node.children.filter { $0.tag != "expr" }))
            case "repeatstmt":
                guard let condition = node.children.last(where: { $0.tag == "expr" }) else { throw malformed(node) }
                return .repeatLoop(body: try statements(node.children.filter { $0.tag != "expr" }), until: try expression(condition))
            case "with":
                guard let target = node.child("dsgn") else { throw malformed(node) }
                return .with(try designator(target), body: try statements(node.children.filter { $0.tag != "dsgn" }))
            case "exit":
                return .exit
            case "var", "const":
                guard let declaration = try declaration(node) else { throw malformed(node) }
                return .declare(declaration)
            default:
                throw Malformed(description: "statement \(node.tag)")
            }
        }

        /// A set's or a `case` branch's members. FastScript writes `0..1` flat, as it writes
        /// expressions: the two ends with an empty `range` between them (Pioneer RT-909's level
        /// scale, `0..1: U := 0`; Denon Classic Style's EQ bands, `if Band in [1..20]`).
        private func labels(_ set: AIMPNode?) throws -> [SetMember] {
            var labels: [SetMember] = []
            var opensRange = false
            for option in set?.children ?? [] {
                switch option.tag {
                case "expr":
                    let value = try expression(option)
                    if opensRange, case .value(let low) = labels.last {
                        labels[labels.count - 1] = .range(low, value)
                    } else {
                        labels.append(.value(value))
                    }
                    opensRange = false
                case "range":
                    guard case .value = labels.last, !opensRange else { throw malformed(option) }
                    opensRange = true
                default:
                    throw malformed(option)
                }
            }
            guard !opensRange else { throw malformed(set ?? AIMPNode(tag: "set", attributes: [:], children: [], text: nil)) }
            return labels
        }

        /// FastScript writes an expression flat: operands and `op`s in source order, a parenthesised
        /// one as a nested `expr` between `(` and `)` ops. Built into a tree by Pascal precedence,
        /// left to right; a unary operator binds to the operand after it.
        private func expression(_ node: AIMPNode) throws -> Expression {
            var operands: [Expression] = []
            var operators: [BinaryOperator] = []
            var unary: [UnaryOperator] = []
            func reduce() throws {
                guard let op = operators.popLast(), let right = operands.popLast(), let left = operands.popLast() else { throw malformed(node) }
                operands.append(.binary(op, left, right))
            }
            var expectOperand = true
            for child in node.children {
                if child.tag == "op", let text = child["text"]?.lowercased() {
                    if text == "(" || text == ")" { continue }
                    if expectOperand {
                        guard let op = UnaryOperator(text) else { throw Malformed(description: "unary \(text)") }
                        unary.append(op)
                        continue
                    }
                    guard let op = BinaryOperator(text) else { throw Malformed(description: "operator \(text)") }
                    while let top = operators.last, top.precedence >= op.precedence { try reduce() }
                    operators.append(op)
                    expectOperand = true
                    continue
                }
                var value = try operand(child)
                while let op = unary.popLast() { value = .unary(op, value) }
                operands.append(value)
                expectOperand = false
            }
            while !operators.isEmpty { try reduce() }
            guard operands.count == 1, unary.isEmpty else { throw malformed(node) }
            return operands[0]
        }

        private func operand(_ node: AIMPNode) throws -> Expression {
            switch node.tag {
            case "number":
                // Pascal hex (`$FFF1F1F1`: Unsquareable's light colours, which all read 0, black).
                let text = node["text"] ?? ""
                if text.hasPrefix("$") { return .number(Double(UInt64(text.dropFirst(), radix: 16) ?? 0)) }
                return .number(Double(text) ?? 0)
            case "string":
                let raw = node["text"] ?? ""
                return .string(raw.count >= 2 && raw.hasPrefix("'") && raw.hasSuffix("'") ? String(raw.dropFirst().dropLast()) : raw)
            case "expr": return try expression(node)
            case "dsgn": return .designator(try designator(node))
            case "set": return .set(try labels(node))
            default: throw Malformed(description: "operand \(node.tag)")
            }
        }

        /// A designator's children are names (`node`), `[` (a `node` too), and argument or index
        /// `expr`s, in source order.
        private func designator(_ node: AIMPNode) throws -> Designator {
            var head: Call?
            var selectors: [Selector] = []
            var pending: (name: String, arguments: [AIMPNode], subscripts: [AIMPNode]?)?
            var stray: [AIMPNode] = []
            var expectIndex = false
            func finish() throws {
                guard let call = pending else { return }
                pending = nil
                if head == nil {
                    head = try self.call(call.name, call.arguments)
                } else {
                    selectors.append(.member(Member(call.name), arguments: try call.arguments.map(expression),
                                             subscripts: try call.subscripts?.map(expression)))
                }
            }
            for child in node.children {
                guard child.tag == "node" || child.tag == "expr" else { throw malformed(node) }
                if child.tag == "node", child["text"] == "[" {
                    // After a member, brackets may be an indexed property's (decided as it runs).
                    if pending != nil, head != nil {
                        if pending?.subscripts == nil { pending?.subscripts = [] }
                        continue
                    }
                    try finish()
                    expectIndex = true
                } else if child.tag == "node" {
                    try finish()
                    pending = (child["text"] ?? "", stray, nil)
                    stray = []
                } else if expectIndex {
                    selectors.append(.index(try expression(child)))
                    expectIndex = false
                } else if pending?.subscripts != nil {
                    pending?.subscripts?.append(child)
                } else if pending != nil {
                    pending?.arguments.append(child)
                } else {
                    stray.append(child)
                }
            }
            try finish()
            guard let head else { throw malformed(node) }
            return Designator(head: head, selectors: selectors)
        }

        /// What a designator's first name calls, resolved now where it can be. `Inc`, `Dec` and
        /// `Delete` on a variable come before the program's routines; every other built-in after.
        private func call(_ name: String, _ argumentNodes: [AIMPNode]) throws -> Call {
            let key = name.lowercased()
            let arguments = try argumentNodes.map {
                Argument(value: try expression($0), variable: $0.child("dsgn")?.child("node")?["text"]?.lowercased())
            }
            let target: Call.Target
            if let builtin = Builtin.writingVariable(key, arguments) {
                target = .builtin(builtin)
            } else if let routine = routineIndex[key] {
                target = .routine(routine)
            } else if let builtin = Builtin(key) {
                target = .builtin(builtin)
            } else if let host = HostCall(key) {
                target = .host(host)
            } else {
                target = .unresolved
            }
            return Call(name: name, key: key, arguments: arguments, target: target)
        }

        private func malformed(_ node: AIMPNode) -> Malformed { Malformed(description: "malformed \(node.tag)") }
    }
}
