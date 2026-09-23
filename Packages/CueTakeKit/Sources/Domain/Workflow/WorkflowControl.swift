import Foundation

/// A small, deterministic value language for workflow inputs. Keeping it narrower than arbitrary
/// JSON makes conditions portable between the on-device runner, an AI-authored document and a
/// future server runner.
public indirect enum WorkflowValue: Hashable, Sendable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([WorkflowValue])
    case object([String: WorkflowValue])
    case null

    public var isTruthy: Bool {
        switch self {
        case .bool(let value): value
        case .number(let value): value != 0
        case .string(let value): !value.isEmpty
        case .array(let value): !value.isEmpty
        case .object(let value): !value.isEmpty
        case .null: false
        }
    }

    public var arrayValue: [WorkflowValue]? {
        guard case .array(let values) = self else { return nil }
        return values
    }

    public var numberValue: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Double(value)
        default: nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([WorkflowValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: WorkflowValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct WorkflowCondition: Hashable, Sendable, Codable {
    public enum Operation: String, Hashable, Sendable, Codable {
        case exists, truthy, equals, notEquals, greaterThan, lessThan, contains
    }

    public var variable: String
    public var operation: Operation
    public var value: WorkflowValue?

    public init(variable: String, operation: Operation = .truthy, value: WorkflowValue? = nil) {
        self.variable = variable
        self.operation = operation
        self.value = value
    }

    public func evaluate(in variables: [String: WorkflowValue]) -> Bool {
        let actual = variables[variable]
        switch operation {
        case .exists: return actual != nil && actual != .null
        case .truthy: return actual?.isTruthy == true
        case .equals: return actual == value
        case .notEquals: return actual != value
        case .greaterThan:
            guard let lhs = actual?.numberValue, let rhs = value?.numberValue else { return false }
            return lhs > rhs
        case .lessThan:
            guard let lhs = actual?.numberValue, let rhs = value?.numberValue else { return false }
            return lhs < rhs
        case .contains:
            guard let value else { return false }
            if case .array(let values) = actual { return values.contains(value) }
            if case .string(let text) = actual, case .string(let needle) = value { return text.contains(needle) }
            return false
        }
    }
}

public struct WorkflowForEach: Hashable, Sendable, Codable {
    /// Name of an array variable.
    public var source: String
    /// Variable exposed to the step for the current element.
    public var itemVariable: String

    public init(source: String, itemVariable: String = "item") {
        self.source = source
        self.itemVariable = itemVariable
    }
}
