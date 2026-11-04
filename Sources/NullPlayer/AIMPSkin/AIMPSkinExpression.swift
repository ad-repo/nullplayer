import Foundation

/// A binding's or provider's `Expression`, the Pascal-flavoured one-liners AIMP skins compute with:
/// `not value`, `value=1`, `value<>50`, `value div 3600`, `(value+1) mod 3`,
/// `if(value3,value1,value2)`, `round(x)`, `log10(x)`. Numbers only; `value` is a link's source,
/// `value1…valueN` a provider's inputs. True is 1, false 0. Unknown syntax evaluates to nil, and
/// the caller keeps the unshaped value.
struct AIMPSkinExpression: Sendable, Equatable {
    /// The expression, parsed: compiled once (a skin's are compiled as it loads, `AIMPSkinIndex`)
    /// and evaluated many times a frame.
    indirect enum Node: Sendable, Equatable {
        case number(Double)
        /// A variable (`value`, `value1`…), or a name that is neither (it evaluates to nil).
        case variable(String)
        case not(Node), negate(Node)
        case binary(Operator, Node, Node)
        case call(Function, [Node])
    }

    /// `or`, `xor`, `and`, a comparison, `+ - * / div mod shl shr`, as written.
    enum Operator: String, Sendable {
        case or, xor, and
        case equal = "=", notEqual = "<>", less = "<", greater = ">", lessOrEqual = "<=", greaterOrEqual = ">="
        case add = "+", subtract = "-", multiply = "*", divide = "/", div, mod, shl, shr

        /// The operator on two numbers, as Delphi's: the one core a binding's expression and a
        /// script's (`AIMPSkinScript+Run.swift`, which adds text `+`, `in` and comparing text) both
        /// use, so the same skin arithmetic answers alike in either. True is 1, false 0.
        /// - `and`, `or`, `xor` are bitwise on whole numbers, as Pascal's are on integers; on 0 and
        ///   1 that is the logical answer, as Pascal's is on booleans (Kenwood's speaker switches:
        ///   `Value XOR 1` toggles one of two). Delphi takes no fraction there; one is read by
        ///   whether it is zero.
        /// - A zero divisor is nil: Delphi raises (`EZeroDivide`, `EDivByZero`), so a binding keeps
        ///   its unshaped value and a script raises an error its `except` catches.
        /// - `div` and `mod` give whole numbers, truncating, as Pascal's.
        func apply(_ left: Double, _ right: Double) -> Double? {
            func truth(_ condition: Bool) -> Double { condition ? 1 : 0 }
            func bits(_ op: (Int, Int) -> Int, else logical: (Bool, Bool) -> Bool) -> Double {
                guard let a = Int(exactly: left), let b = Int(exactly: right) else { return truth(logical(left != 0, right != 0)) }
                return Double(op(a, b))
            }
            switch self {
            case .xor: return bits(^, else: !=)
            case .or: return bits(|, else: { $0 || $1 })
            case .and: return bits(&, else: { $0 && $1 })
            case .equal: return truth(left == right)
            case .notEqual: return truth(left != right)
            case .less: return truth(left < right)
            case .greater: return truth(left > right)
            case .lessOrEqual: return truth(left <= right)
            case .greaterOrEqual: return truth(left >= right)
            case .add: return left + right
            case .subtract: return left - right
            case .multiply: return left * right
            case .divide: return right == 0 ? nil : left / right
            case .div: return right == 0 ? nil : (left / right).rounded(.towardZero)
            case .mod: return right == 0 ? nil : left.truncatingRemainder(dividingBy: right).rounded(.towardZero)
            case .shl, .shr:
                guard let a = Int(exactly: left.rounded(.towardZero)), let b = Int(exactly: right.rounded(.towardZero)) else { return nil }
                return Double(self == .shl ? a << b : a >> b)
            }
        }
    }

    enum Function: String, Sendable {
        case `if`, round, trunc, log10, abs, min, max
    }

    let root: Node

    /// Nil for syntax the parser does not take.
    init?(_ text: String) {
        var parser = Parser(tokens: Self.tokenize(text))
        guard let root = parser.or(), parser.at == parser.tokens.count else { return nil }
        self.root = root
    }

    func evaluate(value: Double) -> Double? { evaluate(variables: ["value": value]) }

    /// Whether it reads the variable `name` (lowercased: `scrolldelta`).
    func reads(_ name: String) -> Bool { Self.reads(root, name) }

    /// The number it is when it reads nothing (`3`, `-1`): a fixed position.
    var constant: Double? {
        switch root {
        case .number(let number): return number
        case .negate(.number(let number)): return -number
        default: return nil
        }
    }

    /// Whether it steps to the next position: `value + 1`, or `(value + 1) mod n` however the skin
    /// spells it (`Value + 1`, `(value+1)mod 3`, `(Value + 1) MOD 6`).
    var stepsToNext: Bool {
        let next = Node.binary(.add, .variable("value"), .number(1))
        if root == next { return true }
        if case .binary(.mod, next, _) = root { return true }
        return false
    }

    private static func reads(_ node: Node, _ name: String) -> Bool {
        switch node {
        case .number: return false
        case .variable(let variable): return variable == name
        case .not(let inner), .negate(let inner): return reads(inner, name)
        case .binary(_, let left, let right): return reads(left, name) || reads(right, name)
        case .call(_, let arguments): return arguments.contains { reads($0, name) }
        }
    }

    /// `variables` keyed lowercased (`value`, `value1`…). Nil when a name is unknown, a divisor is
    /// zero or a call has the wrong arguments: the caller keeps the unshaped value.
    func evaluate(variables: [String: Double]) -> Double? { Self.evaluate(root, variables) }

    private static func evaluate(_ node: Node, _ variables: [String: Double]) -> Double? {
        switch node {
        case .number(let number): return number
        case .variable(let name): return variables[name]
        case .not(let inner): return evaluate(inner, variables).map { $0 == 0 ? 1 : 0 }
        case .negate(let inner): return evaluate(inner, variables).map { -$0 }
        case .binary(let op, let lhs, let rhs):
            guard let left = evaluate(lhs, variables), let right = evaluate(rhs, variables) else { return nil }
            return op.apply(left, right)
        case .call(let name, let argumentNodes):
            var args: [Double] = []
            for argument in argumentNodes {
                guard let value = evaluate(argument, variables) else { return nil }
                args.append(value)
            }
            switch (name, args.count) {
            case (.if, 3): return args[0] != 0 ? args[1] : args[2]
            case (.round, 1): return args[0].rounded()
            case (.trunc, 1): return args[0].rounded(.towardZero)
            case (.log10, 1): return args[0] > 0 ? log10(args[0]) : 0
            case (.abs, 1): return abs(args[0])
            case (.min, 2): return min(args[0], args[1])
            case (.max, 2): return max(args[0], args[1])
            default: return nil
            }
        }
    }

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { tokens.append(current.lowercased()) }
            current = ""
        }
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                flush()
            } else if "()+-*/=,".contains(c) {
                flush()
                tokens.append(String(c))
            } else if c == "<" || c == ">" {
                flush()
                if i + 1 < chars.count, chars[i + 1] == "=" || (c == "<" && chars[i + 1] == ">") {
                    tokens.append(String([c, chars[i + 1]]))
                    i += 1
                } else {
                    tokens.append(String(c))
                }
            } else {
                current.append(c)
            }
            i += 1
        }
        flush()
        return tokens
    }

    private struct Parser {
        let tokens: [String]
        var at = 0

        mutating func next(_ options: Set<String>) -> String? {
            guard at < tokens.count, options.contains(tokens[at]) else { return nil }
            at += 1
            return tokens[at - 1]
        }

        /// The next token when it is one of `operators`.
        mutating func next(_ operators: [Operator]) -> Operator? {
            guard at < tokens.count, let op = Operator(rawValue: tokens[at]), operators.contains(op) else { return nil }
            at += 1
            return op
        }

        /// Operands joined, left to right, by any of `operators`.
        mutating func chain(_ operators: [Operator], _ operand: (inout Parser) -> Node?) -> Node? {
            guard var left = operand(&self) else { return nil }
            while let op = next(operators) {
                guard let right = operand(&self) else { return nil }
                left = .binary(op, left, right)
            }
            return left
        }

        mutating func or() -> Node? { chain([.or, .xor]) { $0.and() } }

        mutating func and() -> Node? { chain([.and]) { $0.comparison() } }

        mutating func comparison() -> Node? {
            guard let left = sum() else { return nil }
            guard let op = next([.equal, .notEqual, .less, .greater, .lessOrEqual, .greaterOrEqual]) else { return left }
            guard let right = sum() else { return nil }
            return .binary(op, left, right)
        }

        mutating func sum() -> Node? { chain([.add, .subtract]) { $0.product() } }

        mutating func product() -> Node? { chain([.multiply, .divide, .div, .mod, .shl, .shr]) { $0.unary() } }

        mutating func unary() -> Node? {
            if next(["not"]) != nil { return unary().map { .not($0) } }
            if next(["-"]) != nil { return unary().map { .negate($0) } }
            if next(["("]) != nil {
                let inner = or()
                return next([")"]) != nil ? inner : nil
            }
            guard at < tokens.count else { return nil }
            let token = tokens[at]
            at += 1
            if let function = Function(rawValue: token) { return call(function) }
            switch token {
            case "true": return .number(1)
            case "false": return .number(0)
            default: return Double(token).map { .number($0) } ?? .variable(token)
            }
        }

        /// `name(args…)`.
        mutating func call(_ name: Function) -> Node? {
            guard next(["("]) != nil else { return nil }
            var args: [Node] = []
            repeat {
                guard let arg = or() else { return nil }
                args.append(arg)
            } while next([","]) != nil
            guard next([")"]) != nil else { return nil }
            return .call(name, args)
        }
    }
}
