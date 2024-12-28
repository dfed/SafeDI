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

/// A representation of a property.
/// e.g. `let myProperty: MyProperty`
public struct Property: Codable, Hashable, Comparable, Sendable {
    // MARK: Initialization

    init(
        label: String,
        typeDescription: TypeDescription
    ) {
        self.label = label
        self.typeDescription = typeDescription
    }

    // MARK: Public

    /// The label by which the property is referenced.
    public let label: String
    /// The type to which the property conforms.
    public let typeDescription: TypeDescription

    public func withUpdatedTypeDescription(_ typeDescription: TypeDescription) -> Self {
        .init(
            label: label,
            typeDescription: typeDescription
        )
    }

    /// The property represented as source code.
    public var asSource: String {
        "\(label): \(typeDescription.asSource)"
    }

    // MARK: Hashable

    public static func < (lhs: Property, rhs: Property) -> Bool {
        lhs.label < rhs.label
    }

    // MARK: Internal

    var asFunctionParamter: FunctionParameterSyntax {
        switch typeDescription {
        case .closure:
            FunctionParameterSyntax(
                firstName: .identifier(label),
                colon: .colonToken(trailingTrivia: .space),
                type: AttributedTypeSyntax(
                    specifiers: [],
                    attributes: AttributeListSyntax {
                        AttributeSyntax(attributeName: IdentifierTypeSyntax(
                            name: "escaping",
                            trailingTrivia: .space
                        ))
                    },
                    baseType: IdentifierTypeSyntax(name: .identifier(typeDescription.asSource))
                )
            )
        case let .attributed(typeDescription, _, attributes):
            FunctionParameterSyntax(
                firstName: .identifier(label),
                colon: .colonToken(trailingTrivia: .space),
                type: AttributedTypeSyntax(
                    // It is not possible for a property declaration to have specifiers today.
                    specifiers: [],
                    attributes: AttributeListSyntax {
                        AttributeSyntax(attributeName: IdentifierTypeSyntax(
                            name: "escaping",
                            trailingTrivia: .space
                        ))
                        if let attributes {
                            for attribute in attributes {
                                AttributeSyntax(
                                    attributeName: IdentifierTypeSyntax(name: .identifier(attribute)),
                                    trailingTrivia: .space
                                )
                            }
                        }
                    },
                    baseType: IdentifierTypeSyntax(name: .identifier(typeDescription.asSource))
                )
            )
        case .simple,
             .nested,
             .composition,
             .optional,
             .implicitlyUnwrappedOptional,
             .some,
             .any,
             .metatype,
             .array,
             .dictionary,
             .tuple,
             .unknown,
             .void:
            FunctionParameterSyntax(
                firstName: .identifier(label),
                colon: .colonToken(trailingTrivia: .space),
                type: IdentifierTypeSyntax(name: .identifier(typeDescription.asSource))
            )
        }
    }

    var asTupleElement: TupleTypeElementSyntax {
        TupleTypeElementSyntax(
            firstName: .identifier(label),
            colon: .colonToken(),
            type: IdentifierTypeSyntax(name: .identifier(typeDescription.asSource))
        )
    }

    var propertyType: PropertyType {
        typeDescription.propertyType
    }

    var generics: [TypeDescription]? {
        typeDescription.simpleNameAndGenerics?.generics
    }

    // MARK: PropertyType

    public enum PropertyType {
        /// A `let` property.
        case constant
        /// An `Instantiator` property.
        /// The instantiated product is not forwarded down the dependency tree. This is done intentionally to avoid unexpected retains.
        case instantiator
        /// An `ErasedInstantiator` property.
        /// The instantiated product is not forwarded down the dependency tree. This is done intentionally to avoid unexpected retains.
        case erasedInstantiator
        /// A `SendableInstantiator` property.
        /// The instantiated product is not forwarded down the dependency tree. This is done intentionally to avoid unexpected retains.
        case sendableInstantiator
        /// A `SendableErasedInstantiator` property.
        /// The instantiated product is not forwarded down the dependency tree. This is done intentionally to avoid unexpected retains.
        case sendableErasedInstantiator

        public var isConstant: Bool {
            switch self {
            case .constant:
                true
            case .instantiator, .erasedInstantiator, .sendableInstantiator, .sendableErasedInstantiator:
                false
            }
        }

        public var isInstantiator: Bool {
            switch self {
            case .instantiator, .sendableInstantiator:
                true
            case .constant, .erasedInstantiator, .sendableErasedInstantiator:
                false
            }
        }

        public var isErasedInstantiator: Bool {
            switch self {
            case .erasedInstantiator, .sendableErasedInstantiator:
                true
            case .constant, .instantiator, .sendableInstantiator:
                false
            }
        }

        public var isSendable: Bool {
            switch self {
            case .instantiator, .erasedInstantiator, .constant:
                false
            case .sendableInstantiator, .sendableErasedInstantiator:
                true
            }
        }
    }
}
