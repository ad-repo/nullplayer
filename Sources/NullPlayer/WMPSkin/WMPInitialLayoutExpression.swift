import CoreGraphics
import Foundation

/// The static renderer's deliberately small, side-effect-free subset of WMP geometry expressions.
/// It accepts only finite numbers, + - * /, parentheses, and geometry property reads. Full JScript
/// remains confined to the Phase 5 helper process.
struct WMPInitialLayoutResolver {
    enum Property: String, CaseIterable {
        case left, top, width, height
    }

    enum Resolution: Equatable {
        case value(CGFloat)
        case unresolved(String)
    }

    private struct Key: Hashable {
        let stableID: Int
        let property: Property
    }

    private let graph: WMPObjectGraph
    private let view: WMPNode
    private let canvas: WMPSize
    private var cache: [Key: Resolution] = [:]
    private var active: Set<Key> = []

    init(graph: WMPObjectGraph, view: WMPNode, canvas: WMPSize) {
        self.graph = graph
        self.view = view
        self.canvas = canvas
    }

    mutating func resolve(_ node: WMPNode, property: Property) -> Resolution {
        resolve(node, property: property, depth: 0)
    }

    private mutating func resolve(_ node: WMPNode, property: Property, depth: Int) -> Resolution {
        let key = Key(stableID: node.stableID, property: property)
        if let cached = cache[key] { return cached }
        guard depth <= WMPPhase0Limits.expressionDependencyDepth else {
            return .unresolved("expression dependency depth exceeds \(WMPPhase0Limits.expressionDependencyDepth)")
        }
        guard active.insert(key).inserted else {
            return .unresolved("cyclic geometry dependency")
        }
        defer { active.remove(key) }

        let result: Resolution
        if node === view {
            switch property {
            case .left, .top: result = .value(0)
            case .width: result = .value(canvas.width)
            case .height: result = .value(canvas.height)
            }
        } else if let attribute = node.attribute(named: property.rawValue) {
            result = resolve(attribute, for: node, property: property, depth: depth + 1)
        } else if property == .left || property == .top {
            result = .value(0)
        } else {
            result = .unresolved("missing \(property.rawValue)")
        }
        cache[key] = result
        return result
    }

    private mutating func resolve(
        _ attribute: WMPAttribute,
        for node: WMPNode,
        property: Property,
        depth: Int
    ) -> Resolution {
        let source: String
        switch attribute.value {
        case let .literal(raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let number = Double(trimmed), number.isFinite {
                return validated(CGFloat(number), property: property)
            }
            source = trimmed
        case let .jScript(expression):
            source = expression
        case let .binding(kind, path) where kind == .property:
            source = path
        default:
            return .unresolved("unsupported geometry value")
        }

        do {
            var parser = WMPInitialLayoutParser(source: source)
            let expression = try parser.parse()
            let value = try expression.evaluate { reference in
                try lookup(reference, relativeTo: node, depth: depth + 1)
            }
            return validated(value, property: property)
        } catch let error as WMPInitialLayoutExpressionError {
            return .unresolved(error.description)
        } catch {
            return .unresolved("invalid geometry expression")
        }
    }

    private mutating func lookup(
        _ reference: WMPInitialLayoutReference,
        relativeTo node: WMPNode,
        depth: Int
    ) throws -> CGFloat {
        let target: WMPNode
        if reference.object == nil {
            target = node
        } else if reference.object?.caseInsensitiveCompare("view") == .orderedSame {
            target = view
        } else {
            // WMP IDs are scoped to a VIEW. Real multi-view skins commonly reuse IDs such as
            // `svTop`, `seek`, and `volume`; treating those as theme-global makes otherwise valid
            // geometry ambiguous and drops whole pieces of the active view.
            let matches = graph.nodes(id: reference.object ?? "").filter(isInActiveView)
            guard matches.count == 1, let match = matches.first else {
                throw WMPInitialLayoutExpressionError(
                    matches.isEmpty ? "unknown geometry object '\(reference.object ?? "")'"
                                    : "ambiguous geometry object '\(reference.object ?? "")'")
            }
            target = match
        }
        guard let property = Property(rawValue: reference.property.lowercased()) else {
            throw WMPInitialLayoutExpressionError("unsupported geometry property '\(reference.property)'")
        }
        switch resolve(target, property: property, depth: depth) {
        case let .value(value): return value
        case let .unresolved(reason): throw WMPInitialLayoutExpressionError(reason)
        }
    }

    private func isInActiveView(_ node: WMPNode) -> Bool {
        var current: WMPNode? = node
        while let candidate = current {
            if candidate === view { return true }
            if candidate.kind == .view { return false }
            current = candidate.parent
        }
        return false
    }

    private func validated(_ value: CGFloat, property: Property) -> Resolution {
        guard value.isFinite else { return .unresolved("non-finite geometry result") }
        if property == .width || property == .height, value < 0 {
            return .unresolved("negative \(property.rawValue)")
        }
        return .value(value)
    }
}

private struct WMPInitialLayoutReference: Equatable {
    let object: String?
    let property: String
}

private indirect enum WMPInitialLayoutExpression {
    case number(CGFloat)
    case reference(WMPInitialLayoutReference)
    case unaryMinus(WMPInitialLayoutExpression)
    case binary(Character, WMPInitialLayoutExpression, WMPInitialLayoutExpression)

    func evaluate(resolve: (WMPInitialLayoutReference) throws -> CGFloat) throws -> CGFloat {
        let value: CGFloat
        switch self {
        case let .number(number): value = number
        case let .reference(reference): value = try resolve(reference)
        case let .unaryMinus(expression): value = try -expression.evaluate(resolve: resolve)
        case let .binary(operation, lhs, rhs):
            let left = try lhs.evaluate(resolve: resolve)
            let right = try rhs.evaluate(resolve: resolve)
            switch operation {
            case "+": value = left + right
            case "-": value = left - right
            case "*": value = left * right
            case "/":
                guard right != 0 else { throw WMPInitialLayoutExpressionError("division by zero") }
                value = left / right
            default: throw WMPInitialLayoutExpressionError("unsupported operator")
            }
        }
        guard value.isFinite else { throw WMPInitialLayoutExpressionError("non-finite geometry result") }
        return value
    }
}

private struct WMPInitialLayoutExpressionError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct WMPInitialLayoutParser {
    private enum Token: Equatable {
        case number(CGFloat), identifier(String), symbol(Character), end
    }

    private let characters: [Character]
    private var index = 0
    private var token: Token = .end
    private var depth = 0

    init(source: String) {
        characters = Array(source.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    mutating func parse() throws -> WMPInitialLayoutExpression {
        token = try nextToken()
        let result = try parseAdditive()
        if token == .symbol(";") { token = try nextToken() }
        guard token == .end else { throw WMPInitialLayoutExpressionError("unexpected trailing input") }
        return result
    }

    private mutating func parseAdditive() throws -> WMPInitialLayoutExpression {
        var lhs = try parseMultiplicative()
        while token == .symbol("+") || token == .symbol("-") {
            guard case let .symbol(operation) = token else { break }
            token = try nextToken()
            lhs = .binary(operation, lhs, try parseMultiplicative())
        }
        return lhs
    }

    private mutating func parseMultiplicative() throws -> WMPInitialLayoutExpression {
        var lhs = try parsePrimary()
        while token == .symbol("*") || token == .symbol("/") {
            guard case let .symbol(operation) = token else { break }
            token = try nextToken()
            lhs = .binary(operation, lhs, try parsePrimary())
        }
        return lhs
    }

    private mutating func parsePrimary() throws -> WMPInitialLayoutExpression {
        switch token {
        case let .number(value):
            token = try nextToken()
            return .number(value)
        case let .identifier(first):
            token = try nextToken()
            if token == .symbol(".") {
                token = try nextToken()
                guard case let .identifier(property) = token else {
                    throw WMPInitialLayoutExpressionError("expected property after '.'")
                }
                token = try nextToken()
                return .reference(WMPInitialLayoutReference(object: first, property: property))
            }
            return .reference(WMPInitialLayoutReference(object: nil, property: first))
        case .symbol("-"):
            token = try nextToken()
            return .unaryMinus(try parsePrimary())
        case .symbol("+"):
            token = try nextToken()
            return try parsePrimary()
        case .symbol("("):
            depth += 1
            guard depth <= WMPPhase0Limits.expressionDependencyDepth else {
                throw WMPInitialLayoutExpressionError("expression nesting is too deep")
            }
            token = try nextToken()
            let expression = try parseAdditive()
            guard token == .symbol(")") else { throw WMPInitialLayoutExpressionError("missing ')'") }
            depth -= 1
            token = try nextToken()
            return expression
        default:
            throw WMPInitialLayoutExpressionError("expected number or geometry reference")
        }
    }

    private mutating func nextToken() throws -> Token {
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index < characters.count else { return .end }
        let character = characters[index]
        if "+-*/().;".contains(character) {
            index += 1
            return .symbol(character)
        }
        if character.isNumber || character == "." {
            let start = index
            var sawDot = false
            while index < characters.count {
                let current = characters[index]
                if current == "." {
                    if sawDot { break }
                    sawDot = true
                    index += 1
                } else if current.isNumber {
                    index += 1
                } else {
                    break
                }
            }
            let raw = String(characters[start..<index])
            guard let value = Double(raw), value.isFinite else {
                throw WMPInitialLayoutExpressionError("invalid numeric literal")
            }
            return .number(CGFloat(value))
        }
        if character.isLetter || character == "_" {
            let start = index
            index += 1
            while index < characters.count,
                  characters[index].isLetter || characters[index].isNumber || characters[index] == "_" {
                index += 1
            }
            return .identifier(String(characters[start..<index]))
        }
        throw WMPInitialLayoutExpressionError("unsupported token '\(character)'")
    }
}
