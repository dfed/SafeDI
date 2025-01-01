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
    /// The Void or () type.
    case void(VoidSpelling)
    /// A root type with possible generics. e.g. Int, or Array<Int>
    indirect case simple(name: String, generics: [TypeDescription])
    /// A nested type with possible generics. e.g. Array.Element or Swift.Array<Element>
    indirect case nested(name: String, parentType: TypeDescription, generics: [TypeDescription])
    /// A composed type. e.g. Identifiable & Equatable
    indirect case composition(UnorderedEquatingCollection<TypeDescription>)
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
    indirect case attributed(TypeDescription, specifiers: [String]?, attributes: [String]?)
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

    /// A shortcut for creating possible `nested` cases given both a property's type description and the type description of the property's parent type.
    public static func nestedOptions(referencedType: TypeDescription, within parentType: TypeDescription) -> [TypeDescription] {
        func zip(outer: TypeDescription, inner: TypeDescription) -> TypeDescription {
            if let simpleNameAndGenerics = inner.simpleNameAndGenerics {
                if let innerParent = inner.popNested {
                    .nested(
                        name: simpleNameAndGenerics.name,
                        parentType: zip(outer: outer, inner: innerParent),
                        generics: simpleNameAndGenerics.generics
                    )
                } else {
                    .nested(
                        name: simpleNameAndGenerics.name,
                        parentType: outer,
                        generics: simpleNameAndGenerics.generics
                    )
                }
            } else {
                // There is no way to shoehorn `inner` into a nested type.
                inner
            }
        }

        // Options must be in the order that the compiler will search for them. Start with the most qualified, working towards the least qualified.
        var nestedOptions = [zip(outer: parentType, inner: referencedType)]
        var parentType = parentType
        while let poppedParent = parentType.popNested {
            nestedOptions.append(zip(outer: poppedParent, inner: referencedType))
            parentType = poppedParent
        }
        nestedOptions.append(referencedType)

        return nestedOptions
    }

    /// A canonical representation of this type that can be used in source code.
    public var asSource: String {
        switch self {
        case let .void(representation):
            return representation.description
        case let .simple(name, generics):
            return if generics.isEmpty {
                name
            } else {
                "\(name)<\(generics.map(\.asSource).joined(separator: ", "))>"
            }
        case let .composition(types):
            return types.map(\.asSource).joined(separator: " & ")
        case let .optional(type):
            return "\(type.wrappedIfAmbiguous.asSource)?"
        case let .implicitlyUnwrappedOptional(type):
            return "\(type.wrappedIfAmbiguous.asSource)!"
        case let .nested(name, parentType, generics):
            return if generics.isEmpty {
                "\(parentType.asSource).\(name)"
            } else {
                "\(parentType.asSource).\(name)<\(generics.map(\.asSource).joined(separator: ", "))>"
            }
        case let .metatype(type, isType):
            return "\(type.wrappedIfAmbiguous.asSource).\(isType ? "Type" : "Protocol")"
        case let .some(type):
            return "some \(type.wrappedIfAmbiguous.asSource)"
        case let .any(type):
            return "any \(type.wrappedIfAmbiguous.asSource)"
        case let .attributed(type, specifiers, attributes):
            func attributesFromList(_ attributes: [String]) -> String {
                attributes
                    .map { "@\($0)" }
                    .joined(separator: " ")
            }
            return switch (specifiers, attributes) {
            case let (.some(specifiers), .none):
                "\(specifiers.joined(separator: " ")) \(type.asSource)"
            case let (.none, .some(attributes)):
                "\(attributesFromList(attributes)) \(type.asSource)"
            case let (.some(specifiers), .some(attributes)):
                // This case likely represents an error.
                // We are unaware of type reference that compiles with both a specifier and attributes.
                // The Swift reference manual specifies that attributes come before the specifier,
                // however code that puts an attribute first does not parse as AttributedTypeSyntax.
                // Only code where the specifier comes before the attribute parses as an AttributedTypeSyntax.
                // As a result, we construct this source with the specifier first.
                // Reference manual: https://docs.swift.org/swift-book/ReferenceManual/Types.html#grammar_type
                "\(specifiers.joined(separator: " ")) \(attributesFromList(attributes)) \(type.asSource)"
            case (.none, .none):
                type.asSource // This case represents an error.
            }
        case let .array(element):
            return "[\(element.asSource)]"
        case let .dictionary(key, value):
            return "[\(key.asSource): \(value.asSource)]"
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
            return "(\(arguments.map(\.asSource).joined(separator: ", ")))\([isAsync ? " async" : "", doesThrow ? " throws" : ""].removingEmpty().joined()) -> \(returnType.asSource)"
        case let .unknown(text):
            return text
        }
    }

    public static func < (lhs: TypeDescription, rhs: TypeDescription) -> Bool {
        lhs.asSource < rhs.asSource
    }

    public enum VoidSpelling: String, Codable, Hashable, Sendable, CustomStringConvertible {
        /// The `()` spelling.
        case tuple
        /// The `Void` spelling.
        case identifier

        public static func == (_: VoidSpelling, _: VoidSpelling) -> Bool {
            // Void is functionally equivalent no matter how it is spelled.
            true
        }

        public func hash(into hasher: inout Hasher) {
            // Void representations have an equivalent hash because they are equivalent types.
            hasher.combine(0)
        }

        public var description: String {
            switch self {
            case .identifier:
                "Void"
            case .tuple:
                "()"
            }
        }
    }

    public struct TupleElement: Codable, Hashable, Sendable {
        init(label: String? = nil, _ typeDescription: TypeDescription) {
            self.label = label
            self.typeDescription = typeDescription
        }

        public let label: String?
        public let typeDescription: TypeDescription
    }

    public var propertyType: Property.PropertyType {
        switch self {
        case let .simple(name, _):
            if name == Dependency.instantiatorType {
                .instantiator
            } else if name == Dependency.erasedInstantiatorType {
                .erasedInstantiator
            } else if name == Dependency.sendableInstantiatorType {
                .sendableInstantiator
            } else if name == Dependency.sendableErasedInstantiatorType {
                .sendableErasedInstantiator
            } else {
                .constant
            }
        case
            let .optional(type),
            let .implicitlyUnwrappedOptional(type):
            type.propertyType
        case .any, .array, .attributed, .closure, .composition, .dictionary, .metatype, .nested, .some, .tuple, .unknown, .void:
            .constant
        }
    }

    public var isOptional: Bool {
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
             .unknown,
             .void:
            false
        case .optional:
            true
        }
    }

    public var popNested: TypeDescription? {
        switch self {
        case let .nested(_, parentType, _):
            parentType
        case .any, .array, .attributed, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .optional, .simple, .some, .tuple, .unknown, .void:
            nil
        }
    }

    var strippingGenerics: TypeDescription {
        switch self {
        case let .simple(name, _):
            .simple(name: name, generics: [])
        case let .nested(name, parentType, _):
            .nested(name: name, parentType: parentType, generics: [])
        case .array, .attributed, .any, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .optional, .some, .tuple, .unknown, .void:
            self
        }
    }

    /// The receiver as an `@Instantiable` type.
    var asInstantiatedType: TypeDescription {
        switch self {
        case let .simple(name, generics):
            if name == Dependency.instantiatorType || name == Dependency.sendableInstantiatorType,
               let builtType = generics.first
            {
                // This is a type that is lazily instantiated.
                // The first generic is the built type.
                builtType
            } else if name == Dependency.erasedInstantiatorType || name == Dependency.sendableErasedInstantiatorType,
                      let builtType = generics.dropFirst().first
            {
                // This is a type that is lazily instantiated with explicitly declared forwarded arguments due to type erasure.
                // The second generic is the built type.
                builtType
            } else {
                self
            }
        case let .any(typeDescription),
             let .implicitlyUnwrappedOptional(typeDescription),
             let .optional(typeDescription),
             let .some(typeDescription):
            typeDescription.asInstantiatedType
        case .array, .attributed, .closure, .composition, .dictionary, .metatype, .nested, .tuple, .unknown, .void:
            self
        }
    }

    /// The name of a simple type sans nesting, with associated generics.
    var simpleNameAndGenerics: (name: String, generics: [TypeDescription])? {
        switch self {
        case let .simple(name, generics),
             let .nested(name, _, generics):
            (name, generics)
        case .any, .array, .attributed, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .optional, .some, .tuple, .unknown, .void:
            nil
        }
    }

    /// A representation of this type that may be wrapped in a single element tuple to ensure cohesiveness of the type description.
    private var wrappedIfAmbiguous: Self {
        switch self {
        case .void, .simple, .optional, .implicitlyUnwrappedOptional, .metatype, .nested, .array, .dictionary, .tuple, .unknown:
            // These types contain no spaces, and are therefore unambiguous without being wrapped.
            self
        case .composition, .some, .any, .attributed, .closure:
            // These types contain spaces and may be ambigous without being wrapped.
            .tuple([.init(self)])
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
            if genericTypeVisitor.genericArguments.isEmpty, typeIdentifier.name.text == "Void" {
                return .void(.identifier)
            } else {
                return .simple(
                    name: typeIdentifier.name.text,
                    generics: genericTypeVisitor.genericArguments
                )
            }

        } else if let typeIdentifier = MemberTypeSyntax(self) {
            let genericTypeVisitor = GenericArgumentVisitor(viewMode: .sourceAccurate)
            if let genericArgumentClause = typeIdentifier.genericArgumentClause {
                genericTypeVisitor.walk(genericArgumentClause)
            }
            return .nested(
                name: typeIdentifier.name.text,
                parentType: typeIdentifier.baseType.typeDescription,
                generics: genericTypeVisitor.genericArguments
            )

        } else if let typeIdentifiers = CompositionTypeSyntax(self) {
            return .composition(UnorderedEquatingCollection(typeIdentifiers.elements.map(\.type.typeDescription)))

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
                isType: typeIdentifier.metatypeSpecifier.text == "Type"
            )

        } else if let typeIdentifier = AttributedTypeSyntax(self) {
            let attributes: [String] = typeIdentifier.attributes.compactMap {
                AttributeSyntax($0)?.attributeName.as(IdentifierTypeSyntax.self)?.name.text
            }
            return .attributed(
                typeIdentifier.baseType.typeDescription,
                specifiers: typeIdentifier.specifiers.textRepresentation,
                attributes: attributes.isEmpty ? nil : attributes
            )

        } else if let typeIdentifier = ArrayTypeSyntax(self) {
            return .array(element: typeIdentifier.element.typeDescription)

        } else if let typeIdentifier = DictionaryTypeSyntax(self) {
            return .dictionary(
                key: typeIdentifier.key.typeDescription,
                value: typeIdentifier.value.typeDescription
            )

        } else if let typeIdentifier = TupleTypeSyntax(self) {
            let elements = typeIdentifier.elements.map {
                TypeDescription.TupleElement(
                    label: $0.secondName?.text ?? $0.firstName?.text,
                    $0.type.typeDescription
                )
            }
            if elements.isEmpty {
                return .void(.tuple)
            } else if elements.count == 1 {
                // A type wrapped in a tuple is equivalent to the underlying type.
                // To avoid handling complex comparisons later, just strip the type.
                return elements[0].typeDescription
            } else {
                return .tuple(elements)
            }

        } else if ClassRestrictionTypeSyntax(self) != nil {
            // A class restriction is the same as requiring inheriting from AnyObject:
            // https://forums.swift.org/t/class-only-protocols-class-vs-anyobject/11507/4
            return .simple(name: "AnyObject")

        } else if let typeIdentifier = FunctionTypeSyntax(self) {
            return .closure(
                arguments: typeIdentifier.parameters.map(\.type.typeDescription),
                isAsync: typeIdentifier.effectSpecifiers?.asyncSpecifier != nil,
                doesThrow: typeIdentifier.effectSpecifiers?.throwsClause?.throwsSpecifier != nil,
                returnType: typeIdentifier.returnClause.type.typeDescription
            )

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
        } else if let memberAccessExpr = MemberAccessExprSyntax(self), let base = memberAccessExpr.base {
            let declName = memberAccessExpr.declName.baseName.text
            return if declName == "self" {
                base.typeDescription
            } else if declName == "Type" {
                .metatype(base.typeDescription, isType: true)
            } else if declName == "Protocol" {
                .metatype(base.typeDescription, isType: false)
            } else {
                .nested(
                    name: declName,
                    parentType: base.typeDescription,
                    generics: []
                )
            }
        } else if let genericExpr = GenericSpecializationExprSyntax(self) {
            let genericTypeVisitor = GenericArgumentVisitor(viewMode: .sourceAccurate)
            genericTypeVisitor.walk(genericExpr.genericArgumentClause)
            return switch genericExpr.expression.typeDescription {
            case let .simple(name, _):
                .simple(
                    name: name,
                    generics: genericTypeVisitor.genericArguments
                )
            case let .nested(name, parentType, _):
                .nested(
                    name: name,
                    parentType: parentType, generics: genericTypeVisitor.genericArguments
                )
            case .any, .array, .attributed, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .optional, .some, .tuple, .unknown, .void:
                .unknown(text: trimmedDescription)
            }
        } else if let tupleExpr = TupleExprSyntax(self) {
            let tupleElements = tupleExpr.elements
            return if tupleElements.count == 1 {
                // Single-element tuple types must be unwrapped.
                // Certain types can not be in a Any.Type list without being wrapped
                // in a tuple. We care only about the underlying types in this case.
                // A @Instantiable that fulfills an addition type `(some Collection).self`
                // should be unwrapped as `some Collection` to enable the @Instantiable
                // to fulfill `some Collection`.
                tupleElements.lazy.map(\.expression)[0].typeDescription
            } else {
                .tuple(tupleElements.map {
                    TypeDescription.TupleElement(
                        label: $0.label?.text,
                        $0.expression.typeDescription
                    )
                })
            }
        } else if let sequenceExpr = SequenceExprSyntax(self) {
            if sequenceExpr.elements.contains(where: { BinaryOperatorExprSyntax($0) != nil }) {
                return .composition(UnorderedEquatingCollection(
                    sequenceExpr
                        .elements
                        .filter { BinaryOperatorExprSyntax($0) == nil }
                        .map(\.typeDescription)
                ))
            } else if sequenceExpr.elements.count == 3,
                      let arguments = TupleExprSyntax(sequenceExpr.elements.first),
                      let arrow = ArrowExprSyntax(sequenceExpr.elements[
                          sequenceExpr.elements.index(after: sequenceExpr.elements.startIndex)
                      ]),
                      let returnType = sequenceExpr.elements.last
            {
                return .closure(
                    arguments: arguments.elements.map(\.expression.typeDescription),
                    isAsync: arrow.effectSpecifiers?.asyncSpecifier != nil,
                    doesThrow: arrow.effectSpecifiers?.throwsClause?.throwsSpecifier != nil,
                    returnType: returnType.typeDescription
                )
            }
        } else if let optionalChainingExpr = OptionalChainingExprSyntax(self) {
            return .optional(optionalChainingExpr.expression.typeDescription)
        } else if let arrayExpr = ArrayExprSyntax(self),
                  arrayExpr.elements.count == 1,
                  let onlyElement = arrayExpr.elements.first
        {
            return .array(element: onlyElement.expression.typeDescription)
        } else if let dictionaryExpr = DictionaryExprSyntax(self),
                  let content = DictionaryElementListSyntax(dictionaryExpr.content),
                  content.count == 1,
                  let onlyElement = DictionaryElementSyntax(content.first)
        {
            return .dictionary(
                key: onlyElement.key.typeDescription,
                value: onlyElement.value.typeDescription
            )
        }
        return .unknown(text: trimmedDescription)
    }
}

// MARK: - GenericArgumentVisitor

private final class GenericArgumentVisitor: SyntaxVisitor {
    private(set) var genericArguments = [TypeDescription]()

    override func visit(_ node: GenericArgumentSyntax) -> SyntaxVisitorContinueKind {
        genericArguments.append(node.argument.typeDescription)
        return .skipChildren
    }
}

extension TypeSpecifierListSyntax {
    fileprivate var textRepresentation: [String]? {
        if isEmpty {
            nil
        } else {
            compactMap(\.trimmedDescription)
        }
    }
}
