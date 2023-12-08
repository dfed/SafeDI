// Distributed under the MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import SwiftSyntax

/// An enum that describes a parsed type in a canonical form.
public enum TypeDescription: Codable, Hashable, Comparable {
    /// A root type with possible generics. e.g. Int, or Array<Int>
    indirect case simple(name: String, generics: [TypeDescription])
    /// A nested type with possible generics. e.g. Array.Element or Swift.Array<Element>
    indirect case nested(name: String, parentType: TypeDescription, generics: [TypeDescription])
    /// A composed type. e.g. Identifiable & Equatable
    indirect case composition([TypeDescription])
    /// An optional type. e.g. Int?
    indirect case optional(TypeDescription)
    /// An implicitly unwrapped optional type. e.g. Int!
    indirect case implicitlyUnwrappedOptional(TypeDescription)
    /// An opaque type that conforms to a protocol. e.g. some Equatable
    indirect case some(TypeDescription)
    /// An opaque type that conforms to a protocol. e.g. any Equatable
    indirect case any(TypeDescription)
    /// A meta type. e.g. `Int.Type` or `Equatable.Protocol`
    indirect case metatype(TypeDescription, isType: Bool)
    /// A type identifier with a specifier or attributes. e.g. `inout Int` or `@autoclosure () -> Void`
    indirect case attributed(TypeDescription, specifier: String?, attributes: [String]?)
    /// An array. e.g. [Int]
    indirect case array(element: TypeDescription)
    /// A dictionary. e.g. [Int: String]
    indirect case dictionary(key: TypeDescription, value: TypeDescription)
    /// A tuple. e.g. (Int, String)
    indirect case tuple([TypeDescription])
    /// A closure. e.g. (Int, Double) throws -> String
    indirect case closure(arguments: [TypeDescription], isAsync: Bool, doesThrow: Bool, returnType: TypeDescription)
    /// A type that can't be represented by the above cases.
    case unknown(text: String)

    /// Creates a type description of case `.nested` with the given name as the name and the receiver as the parent type.
    /// If no parent is provided, creates a type description of case `.simple`.
    ///
    /// - Parameters:
    ///   - name: The simple name of the returned type.
    ///   - parent: The parent type for the returned type.
    /// - Note: This method only makes sense when the `parent` is of case  `simple`, `nested`, `optional`, and `implicitlyUnwrappedOptional`.
    init(name: String, parent: TypeDescription?) {
        if let parent = parent {
            self = .nested(name: name, parentType: parent)
        } else {
            self = .simple(name: name)
        }
    }

    /// A shortcut for creating a `simple` case without any generic types.
    public static func simple(name: String) -> TypeDescription {
        .simple(name: name, generics: [])
    }

    /// A shortcut for creating a `nested` case without any generic types.
    public static func nested(name: String, parentType: TypeDescription) -> TypeDescription {
        .nested(name: name, parentType: parentType, generics: [])
    }

    /// A canonical representation of this type that can be used as source code.
    public var asSource: String {
        switch self {
        case let .simple(name, generics):
            if generics.isEmpty {
                return name
            } else {
                return "\(name)<\(generics.map { $0.asSource }.joined(separator: ", "))>"
            }
        case let .composition(types):
            return types.map { $0.asSource }.joined(separator: " & ")
        case let .optional(type):
            return "\(type.asSource)?"
        case let .implicitlyUnwrappedOptional(type):
            return "\(type.asSource)!"
        case let .nested(name, parentType, generics):
            if generics.isEmpty {
                return "\(parentType.asSource).\(name)"
            } else {
                return "\(parentType.asSource).\(name)<\(generics.map { $0.asSource }.joined(separator: ", "))>"
            }
        case let .metatype(type, isType):
            return "\(type.asSource).\(isType ? "Type" : "Protocol")"
        case let .some(type):
            return "some \(type.asSource)"
        case let .any(type):
            return "any \(type.asSource)"
        case let .attributed(type, specifier, attributes):
            func attributesFromList(_ attributes: [String]) -> String {
                attributes
                    .map { "@\($0)" }
                    .joined(separator: " ")
            }
            switch (specifier, attributes) {
            case let (.some(specifier), .none):
                return "\(specifier) \(type.asSource)"
            case let (.none, .some(attributes)):
                return "\(attributesFromList(attributes)) \(type.asSource)"
            case let (.some(specifier), .some(attributes)):
                // This case likely represents an error.
                // We are unaware of type reference that compiles with both a specifier and attributes.
                // The Swift reference manual specifies that attributes come before the specifier,
                // however code that puts an attribute first does not parse as AttributedTypeSyntax.
                // Only code where the specifier comes before the attribute parses as an AttributedTypeSyntax.
                // As a result, we construct this source with the specifier first.
                // Reference manual: https://docs.swift.org/swift-book/ReferenceManual/Types.html#grammar_type
                return "\(specifier) \(attributesFromList(attributes)) \(type.asSource)"
            case (.none, .none):
                // This case represents an error that has previously caused an assertion.
                return type.asSource
            }
        case let .array(element):
            return "Array<\(element.asSource)>"
        case let .dictionary(key, value):
            return "Dictionary<\(key.asSource), \(value.asSource)>"
        case let .tuple(types):
            return "(\(types.map { $0.asSource }.joined(separator: ", ")))"
        case let .closure(arguments, isAsync, doesThrow, returnType):
            return "(\(arguments.map { $0.asSource }.joined(separator: ", ")))\([isAsync ? " async" : "", doesThrow ? " throws" : ""].filter { !$0.isEmpty }.joined()) -> \(returnType.asSource)"
        case let .unknown(text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let caseDescription = try values.decode(String.self, forKey: .caseDescription)
        switch caseDescription {
        case Self.simpleDescription:
            let text = try values.decode(String.self, forKey: .text)
            let typeDescriptions = try values.decode([Self].self, forKey: .typeDescriptions)
            self = .simple(name: text, generics: typeDescriptions)

        case Self.unknownDescription:
            let text = try values.decode(String.self, forKey: .text)
            self = .unknown(text: text)

        case Self.nestedDescription:
            let text = try values.decode(String.self, forKey: .text)
            let parentType = try values.decode(Self.self, forKey: .typeDescription)
            let typeDescriptions = try values.decode([Self].self, forKey: .typeDescriptions)
            self = .nested(name: text, parentType: parentType, generics: typeDescriptions)

        case Self.optionalDescription:
            let typeDescription = try values.decode(Self.self, forKey: .typeDescription)
            self = .optional(typeDescription)

        case Self.implicitlyUnwrappedOptionalDescription:
            let typeDescription = try values.decode(Self.self, forKey: .typeDescription)
            self = .implicitlyUnwrappedOptional(typeDescription)

        case Self.compositionDescription:
            let typeDescriptions = try values.decode([Self].self, forKey: .typeDescriptions)
            self = .composition(typeDescriptions)

        case Self.someDescription:
            let typeDescription = try values.decode(Self.self, forKey: .typeDescription)
            self = .some(typeDescription)

        case Self.anyDescription:
            let typeDescription = try values.decode(Self.self, forKey: .typeDescription)
            self = .any(typeDescription)

        case Self.metatypeDescription:
            let typeDescription = try values.decode(Self.self, forKey: .typeDescription)
            let isType = try values.decode(Bool.self, forKey: .isType)
            self = .metatype(typeDescription, isType: isType)

        case Self.attributedDescription:
            let typeDescription = try values.decode(Self.self, forKey: .typeDescription)
            let specifier = try values.decodeIfPresent(String.self, forKey: .specifier)
            let attributes = try values.decodeIfPresent([String].self, forKey: .attributes)
            self = .attributed(typeDescription, specifier: specifier, attributes: attributes)

        case Self.arrayDescription:
            let typeDescription = try values.decode(Self.self, forKey: .typeDescription)
            self = .array(element: typeDescription)

        case Self.dictionaryDescription:
            let key = try values.decode(Self.self, forKey: .dictionaryKey)
            let value = try values.decode(Self.self, forKey: .dictionaryValue)
            self = .dictionary(key: key, value: value)

        case Self.tupleDescription:
            let typeDescriptions = try values.decode([Self].self, forKey: .typeDescriptions)
            self = .tuple(typeDescriptions)

        case Self.closureDescription:
            let typeDescriptions = try values.decode([Self].self, forKey: .closureArguments)
            let isAsync = try values.decode(Bool.self, forKey: .closureIsAsync)
            let doesThrow = try values.decode(Bool.self, forKey: .closureThrows)
            let typeDescription = try values.decode(Self.self, forKey: .closureReturn)
            self = .closure(arguments: typeDescriptions, isAsync: isAsync, doesThrow: doesThrow, returnType: typeDescription)

        default:
            throw CodingError.unknownCase
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(caseDescription, forKey: .caseDescription)
        switch self {
        case let .simple(name, generics):
            try container.encode(name, forKey: .text)
            try container.encode(generics, forKey: .typeDescriptions)
        case let .unknown(text):
            try container.encode(text, forKey: .text)
        case let .optional(type),
            let .implicitlyUnwrappedOptional(type),
            let .array(type),
            let .some(type),
            let .any(type):
            try container.encode(type, forKey: .typeDescription)
        case let .tuple(types),
            let .composition(types):
            try container.encode(types, forKey: .typeDescriptions)
        case let .metatype(type, isType):
            try container.encode(type, forKey: .typeDescription)
            try container.encode(isType, forKey: .isType)
        case let .attributed(type, specifier: specifier, attributes: attributes):
            try container.encode(type, forKey: .typeDescription)
            try container.encodeIfPresent(specifier, forKey: .specifier)
            try container.encodeIfPresent(attributes, forKey: .attributes)
        case let .nested(name, parentType, generics):
            try container.encode(name, forKey: .text)
            try container.encode(parentType, forKey: .typeDescription)
            try container.encode(generics, forKey: .typeDescriptions)
        case let .dictionary(key, value):
            try container.encode(key, forKey: .dictionaryKey)
            try container.encode(value, forKey: .dictionaryValue)
        case let .closure(arguments, isAsync, doesThrow, returnType):
            try container.encode(arguments, forKey: .closureArguments)
            try container.encode(isAsync, forKey: .closureIsAsync)
            try container.encode(doesThrow, forKey: .closureThrows)
            try container.encode(returnType, forKey: .closureReturn)
        }
    }

    enum CodingKeys: String, CodingKey {
        /// The value for this key is the case encoded as a String.
        case caseDescription
        /// The value for this key is an associated value of type String
        case text
        /// The value for this key is the associated value of type TypeDescription
        case typeDescription
        /// The value for this key is the associated value of type [TypeDescription]
        case typeDescriptions
        /// The value for this key represents whether a metatype is a Type (as opposed to a Protocol) and is of type Bool
        case isType
        /// The value for this key is the specifier on an attributed type of type String
        case specifier
        /// The value for this key is the attributes on an attributed type of type [String]
        case attributes
        /// The value for this key is a dictionary's key of type TypeDescription
        case dictionaryKey
        /// The value for this key is a dictionary's value of type TypeDescription
        case dictionaryValue
        /// The value for this key represents the list of types in a closure argument list and is of type [TypeDescription]
        case closureArguments
        /// The value for this key represents whether a closure is `async` and is of type Bool
        case closureIsAsync
        /// The value for this key represents whether a closure `throws` and is of type Bool
        case closureThrows
        /// The value for this key represents the return type of a closure argument list and is of type TypeDescription
        case closureReturn
    }

    public enum CodingError: Error {
        case unknownCase
    }

    public static func < (lhs: TypeDescription, rhs: TypeDescription) -> Bool {
        lhs.asSource < rhs.asSource
    }

    var isUnknown: Bool {
        switch self {
        case .any,
                .array,
                .attributed,
                .closure,
                .composition,
                .dictionary,
                .implicitlyUnwrappedOptional,
                .metatype,
                .nested,
                .optional,
                .simple,
                .some,
                .tuple:
            return false
        case .unknown:
            return true
        }
    }

    /// The receiver as an `@Instantiable` type.
    var asInstantiatedType: TypeDescription {
        switch self {
        case let .simple(name, generics):
            if name == Dependency.instantiatorType, let builtType = generics.first {
                // This is a type that is lazily instantiated.
                // The first generic is the built type.
                return builtType
            } else if name == Dependency.forwardingInstantiatorType, let builtType = generics.last {
                // This is a type that is lazily instantiated with forwarded arguments.
                // The last generic is the built type.
                return builtType
            } else {
                return self
            }
        case .any,
                .array,
                .attributed,
                .closure,
                .composition,
                .dictionary,
                .implicitlyUnwrappedOptional,
                .metatype,
                .nested,
                .optional,
                .some,
                .tuple,
                .unknown:
            return self
        }
    }

    private var caseDescription: String {
        switch self {
        case .composition:
            return Self.compositionDescription
        case .implicitlyUnwrappedOptional:
            return Self.implicitlyUnwrappedOptionalDescription
        case .nested:
            return Self.nestedDescription
        case .optional:
            return Self.optionalDescription
        case .simple:
            return Self.simpleDescription
        case .some:
            return Self.someDescription
        case .any:
            return Self.anyDescription
        case .metatype:
            return Self.metatypeDescription
        case .attributed:
            return Self.attributedDescription
        case .array:
            return Self.arrayDescription
        case .dictionary:
            return Self.dictionaryDescription
        case .tuple:
            return Self.tupleDescription
        case .closure:
            return Self.closureDescription
        case .unknown:
            return Self.unknownDescription
        }
    }

    private static let simpleDescription = "simple"
    private static let nestedDescription = "nested"
    private static let compositionDescription = "composition"
    private static let optionalDescription = "optional"
    private static let implicitlyUnwrappedOptionalDescription = "implicitlyUnwrappedOptional"
    private static let someDescription = "some"
    private static let anyDescription = "any"
    private static let metatypeDescription = "metatype"
    private static let attributedDescription = "attributed"
    private static let arrayDescription = "array"
    private static let dictionaryDescription = "dictionary"
    private static let tupleDescription = "tuple"
    private static let closureDescription = "closure"
    private static let unknownDescription = "unknown"
}

extension TypeSyntax {

    /// - Returns: the type description for the receiver.
    var typeDescription: TypeDescription {
        if let typeIdentifier = IdentifierTypeSyntax(self) {
            let genericTypeVisitor = GenericArgumentVisitor(viewMode: .sourceAccurate)
            if let genericArgumentClause = typeIdentifier.genericArgumentClause {
                genericTypeVisitor.walk(genericArgumentClause)
            }
            return .simple(
                name: typeIdentifier.name.text,
                generics: genericTypeVisitor.genericArguments)

        } else if let typeIdentifier = MemberTypeSyntax(self) {
            let genericTypeVisitor = GenericArgumentVisitor(viewMode: .sourceAccurate)
            if let genericArgumentClause = typeIdentifier.genericArgumentClause {
                genericTypeVisitor.walk(genericArgumentClause)
            }
            return .nested(
                name: typeIdentifier.name.text,
                parentType: typeIdentifier.baseType.typeDescription,
                generics: genericTypeVisitor.genericArguments)

        } else if let typeIdentifiers = CompositionTypeSyntax(self) {
            return .composition(typeIdentifiers.elements.map { $0.type.typeDescription })

        } else if let typeIdentifier = OptionalTypeSyntax(self) {
            return .optional(typeIdentifier.wrappedType.typeDescription)

        } else if let typeIdentifier = ImplicitlyUnwrappedOptionalTypeSyntax(self) {
            return .implicitlyUnwrappedOptional(typeIdentifier.wrappedType.typeDescription)

        } else if let typeIdentifier = SomeOrAnyTypeSyntax(self) {
            if typeIdentifier.someOrAnySpecifier.text == "some" {
                return .some(typeIdentifier.constraint.typeDescription)
            } else {
                return .any(typeIdentifier.constraint.typeDescription)
            }

        } else if let typeIdentifier = MetatypeTypeSyntax(self) {
            return .metatype(
                typeIdentifier.baseType.typeDescription,
                isType: typeIdentifier.metatypeSpecifier.text == "Type")

        } else if let typeIdentifier = AttributedTypeSyntax(self) {
            let attributes: [String] = typeIdentifier.attributes.compactMap {
                guard
                    let attributeName = AttributeSyntax($0)?.attributeName,
                    let attributeIdentifier = IdentifierTypeSyntax(attributeName)
                else {
                    return nil
                }
                return attributeIdentifier.name.text
            }
            return .attributed(
                typeIdentifier.baseType.typeDescription,
                specifier: typeIdentifier.specifier?.text,
                attributes: attributes.isEmpty ? nil : attributes)

        } else if let typeIdentifier = ArrayTypeSyntax(self) {
            return .array(element: typeIdentifier.element.typeDescription)

        } else if let typeIdentifier = DictionaryTypeSyntax(self) {
            return .dictionary(
                key: typeIdentifier.key.typeDescription,
                value: typeIdentifier.value.typeDescription)

        } else if let typeIdentifiers = TupleTypeSyntax(self) {
            return .tuple(typeIdentifiers.elements.map { $0.type.typeDescription })

        } else if ClassRestrictionTypeSyntax(self) != nil {
            // A class restriction is the same as requiring inheriting from AnyObject:
            // https://forums.swift.org/t/class-only-protocols-class-vs-anyobject/11507/4
            return .simple(name: "AnyObject")

        } else if let typeIdentifier = FunctionTypeSyntax(self) {
            return .closure(
                arguments: typeIdentifier.parameters.map { $0.type.typeDescription },
                isAsync: typeIdentifier.effectSpecifiers?.asyncSpecifier != nil,
                doesThrow: typeIdentifier.effectSpecifiers?.throwsSpecifier != nil,
                returnType: typeIdentifier.returnClause.type.typeDescription)

        } else {
            assertionFailure("TypeSyntax of unknown type. Defaulting to `description`.")
            // The description is a source-accurate description of this node, so it is a reasonable fallback.
            return .unknown(text: description)
        }
    }
}

extension ExprSyntax {
    var typeDescription: TypeDescription {
        if let typeExpr = TypeExprSyntax(self) {
            return typeExpr.type.typeDescription

        } else if let declReferenceExpr = DeclReferenceExprSyntax(self) {
            return TypeSyntax(
                IdentifierTypeSyntax(
                    name: declReferenceExpr.baseName,
                    genericArgumentClause: nil
                )
            ).typeDescription
        } else if let memberAccessExpr = MemberAccessExprSyntax(self) {
            if memberAccessExpr.declName.baseName.text == "self" {
                if let base = memberAccessExpr.base {
                    return base.typeDescription
                } else {
                    return .unknown(text: memberAccessExpr.description)
                }
            } else {
                if let base = memberAccessExpr.base {
                    let declName = memberAccessExpr.declName.baseName.text
                    if declName == "Type" {
                        return .metatype(base.typeDescription, isType: true)
                    } else if declName == "Protocol" {
                        return .metatype(base.typeDescription, isType: false)
                    } else {
                        return .nested(
                            name: declName,
                            parentType: base.typeDescription,
                            generics: []
                        )
                    }
                } else {
                    return .unknown(text: memberAccessExpr.description)
                }
            }
        } else if let genericExpr = GenericSpecializationExprSyntax(self) {
            let genericTypeVisitor = GenericArgumentVisitor(viewMode: .sourceAccurate)
            genericTypeVisitor.walk(genericExpr.genericArgumentClause)
            switch genericExpr.expression.typeDescription {
            case let .simple(name, _):
                return .simple(
                    name: name,
                    generics: genericTypeVisitor.genericArguments
                )
            case let .nested(name, parentType, _):
                return .nested(
                    name: name,
                    parentType: parentType, generics: genericTypeVisitor.genericArguments
                )
            case .any,
                    .array,
                    .attributed,
                    .closure,
                    .composition,
                    .dictionary,
                    .implicitlyUnwrappedOptional,
                    .metatype,
                    .optional,
                    .some,
                    .tuple,
                    .unknown:
                return .unknown(text: description)
            }
        } else if let tupleExpr = TupleExprSyntax(self) {
            let tupleTypes = tupleExpr.elements.map(\.expression.typeDescription)
            if tupleTypes.count == 1 {
                // Single-element tuple types must be unwrapped.
                // Certain types can not be in a Any.Type list without being wrapped
                // in a tuple. We care only about the underlying types in this case.
                // A @Instantiable that fulfills an addition type `(some Collection).self`
                // should be unwrapped as `some Collection` to enable the @Instantiable
                // to fulfill `some Collection`.
                return tupleTypes[0]
            } else {
                return .tuple(tupleTypes)
            }
        } else if let sequenceExpr = SequenceExprSyntax(self) {
            if sequenceExpr.elements.contains(where: { BinaryOperatorExprSyntax($0) != nil }) {
                return .composition(
                    sequenceExpr
                        .elements
                        .filter { BinaryOperatorExprSyntax($0) == nil }
                        .map(\.typeDescription)
                )
            } else if
                sequenceExpr.elements.count == 3,
                let arguments = TupleExprSyntax(sequenceExpr.elements.first),
                let arrow = ArrowExprSyntax(sequenceExpr.elements[
                    sequenceExpr.elements.index(after: sequenceExpr.elements.startIndex)
                ]),
                let returnType = sequenceExpr.elements.last
            {
                return .closure(
                    arguments: arguments.elements.map(\.expression.typeDescription),
                    isAsync: arrow.effectSpecifiers?.asyncSpecifier != nil,
                    doesThrow: arrow.effectSpecifiers?.throwsSpecifier != nil,
                    returnType: returnType.typeDescription
                )
            } else {
                return .unknown(text: description)
            }
        } else if let optionalChainingExpr = OptionalChainingExprSyntax(self) {
            return .optional(optionalChainingExpr.expression.typeDescription)
        } else if
            let arrayExpr = ArrayExprSyntax(self),
            arrayExpr.elements.count == 1,
            let onlyElement = arrayExpr.elements.first
        {
            return .array(element: onlyElement.expression.typeDescription)
        } else if
            let dictionaryExpr = DictionaryExprSyntax(self),
            let content = DictionaryElementListSyntax(dictionaryExpr.content),
            content.count == 1,
            let onlyElement = DictionaryElementSyntax(content.first)
        {
            return .dictionary(
                key: onlyElement.key.typeDescription,
                value: onlyElement.value.typeDescription
            )
        } else {
            return .unknown(text: description)
        }
    }
}

private final class GenericArgumentVisitor: SyntaxVisitor {

    private(set) var genericArguments = [TypeDescription]()

    override func visit(_ node: GenericArgumentSyntax) -> SyntaxVisitorContinueKind {
        genericArguments.append(node.argument.typeDescription)
        return .skipChildren
    }
}
