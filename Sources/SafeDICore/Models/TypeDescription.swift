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
public enum TypeDescription: Codable, Hashable, Comparable, Sendable {
    /// A root type with possible generics. e.g. Int, or Array<Int>
    indirect case simple(name: String, generics: [TypeDescription])
    /// A nested type with possible generics. e.g. Array.Element or Swift.Array<Element>
    indirect case nested(name: String, parentType: TypeDescription, generics: [TypeDescription])
    /// A composed type. e.g. Identifiable & Equatable
    indirect case composition(UnorderedComparingCollection<TypeDescription>)
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
    /// A tuple. e.g. (Int, string: String)
    indirect case tuple([TupleElement])
    /// A closure. e.g. (Int, Double) throws -> String
    indirect case closure(arguments: [TypeDescription], isAsync: Bool, doesThrow: Bool, returnType: TypeDescription)
    /// A type that can't be represented by the above cases.
    case unknown(text: String)

    /// A shortcut for creating a `simple` case without any generic types.
    public static func simple(name: String) -> TypeDescription {
        .simple(name: name, generics: [])
    }

    /// A shortcut for creating a `nested` case without any generic types.
    public static func nested(name: String, parentType: TypeDescription) -> TypeDescription {
        .nested(name: name, parentType: parentType, generics: [])
    }

    /// A canonical representation of this type that can be used in source code.
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
                // This case represents an error.
                return type.asSource
            }
        case let .array(element):
            return "Array<\(element.asSource)>"
        case let .dictionary(key, value):
            return "Dictionary<\(key.asSource), \(value.asSource)>"
        case let .tuple(types):
            return """
                (\(types.map {
                    if let label = $0.label {
                        "\(label): \($0.typeDescription.asSource)"
                    } else {
                        $0.typeDescription.asSource
                    }
                }.joined(separator: ", ")))
                """
        case let .closure(arguments, isAsync, doesThrow, returnType):
            return "(\(arguments.map { $0.asSource }.joined(separator: ", ")))\([isAsync ? " async" : "", doesThrow ? " throws" : ""].filter { !$0.isEmpty }.joined()) -> \(returnType.asSource)"
        case let .unknown(text):
            return text
        }
    }

    public static func < (lhs: TypeDescription, rhs: TypeDescription) -> Bool {
        lhs.asSource < rhs.asSource
    }

    public struct TupleElement: Codable, Hashable, Sendable {
        public let label: String?
        public let typeDescription: TypeDescription
    }

    var isOptional: Bool {
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
                .simple,
                .some,
                .tuple,
                .unknown:
            return false
        case .optional:
            return true
        }
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
            } else if name == Dependency.forwardingInstantiatorType, let builtType = generics.dropFirst().first {
                // This is a type that is lazily instantiated with forwarded arguments.
                // The second generic is the built type.
                return builtType
            } else {
                return self
            }
        case let .any(typeDescription),
            let .implicitlyUnwrappedOptional(typeDescription),
            let .optional(typeDescription),
            let .some(typeDescription):
            return typeDescription.asInstantiatedType
        case .array, .attributed,  .closure, .composition, .dictionary, .metatype, .nested, .tuple, .unknown:
            return self
        }
    }
}

// MARK: - TypeSyntax

extension TypeSyntax {

    /// - Returns: the type description for the receiver.
    public var typeDescription: TypeDescription {
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
            return .composition(UnorderedComparingCollection(typeIdentifiers.elements.map { $0.type.typeDescription }))

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
                AttributeSyntax($0)?.attributeName.as(IdentifierTypeSyntax.self)?.name.text
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

        } else if let typeIdentifier = TupleTypeSyntax(self) {
            return .tuple(typeIdentifier.elements.map {
                TypeDescription.TupleElement(
                    label: $0.secondName?.text ?? $0.firstName?.text,
                    typeDescription: $0.type.typeDescription
                )
            })

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
            // The description is a source-accurate description of this node, so it is a reasonable fallback.
            return .unknown(text: trimmedDescription)
        }
    }
}

// MARK: - ExprSyntax

extension ExprSyntax {
    public var typeDescription: TypeDescription {
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
                    return .unknown(text: memberAccessExpr.trimmedDescription)
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
                    return .unknown(text: memberAccessExpr.trimmedDescription)
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
            case .any, .array, .attributed, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .optional, .some, .tuple, .unknown:
                return .unknown(text: trimmedDescription)
            }
        } else if let tupleExpr = TupleExprSyntax(self) {
            let tupleElements = tupleExpr.elements
            if tupleElements.count == 1 {
                // Single-element tuple types must be unwrapped.
                // Certain types can not be in a Any.Type list without being wrapped
                // in a tuple. We care only about the underlying types in this case.
                // A @Instantiable that fulfills an addition type `(some Collection).self`
                // should be unwrapped as `some Collection` to enable the @Instantiable
                // to fulfill `some Collection`.
                return tupleElements.lazy.map(\.expression)[0].typeDescription
            } else {
                return .tuple(tupleElements.map {
                    TypeDescription.TupleElement(
                        label: $0.label?.text,
                        typeDescription: $0.expression.typeDescription
                    )
                })
            }
        } else if let sequenceExpr = SequenceExprSyntax(self) {
            if sequenceExpr.elements.contains(where: { BinaryOperatorExprSyntax($0) != nil }) {
                return .composition(UnorderedComparingCollection(
                    sequenceExpr
                        .elements
                        .filter { BinaryOperatorExprSyntax($0) == nil }
                        .map(\.typeDescription)
                ))
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
                return .unknown(text: trimmedDescription)
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
            return .unknown(text: trimmedDescription)
        }
    }
}

// MARK: - UnorderedComparingCollection

public struct UnorderedComparingCollection<Element: Codable & Hashable & Sendable>: Codable, Hashable, Sendable, Collection, ExpressibleByArrayLiteral {

    // MARK: Initialization

    public init(_ array: [Element]) {
        self.array = array
        set = Set(array)
    }

    // MARK: Equatable

    public static func == (lhs: UnorderedComparingCollection, rhs: UnorderedComparingCollection) -> Bool {
        lhs.set == rhs.set
    }

    // MARK: Collection

    public func makeIterator() -> IndexingIterator<Array<Element>> { array.makeIterator() }
    public var startIndex: Int { array.startIndex }
    public var endIndex: Int { array.endIndex }
    public func index(after i: Int) -> Int {
        array.index(after: i)
    }
    public subscript(position: Int) -> Element {
        array[position]
    }

    // MARK: ExpressibleByArrayLiteral

    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }

    public typealias ArrayLiteralElement = Element

    // MARK: Private

    private let array: [Element]
    private let set: Set<Element>
}

// MARK: - GenericArgumentVisitor

private final class GenericArgumentVisitor: SyntaxVisitor {

    private(set) var genericArguments = [TypeDescription]()

    override func visit(_ node: GenericArgumentSyntax) -> SyntaxVisitorContinueKind {
        genericArguments.append(node.argument.typeDescription)
        return .skipChildren
    }
}
