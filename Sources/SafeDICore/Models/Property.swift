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

	public init(label: String, typeDescription: TypeDescription) {
		self.label = label
		self.typeDescription = typeDescription
		var hasher = Hasher()
		hasher.combine(label)
		hasher.combine(typeDescription)
		hashOfLabelAndTypeDescription = hasher.finalize()
	}

	// MARK: Decodable

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		try self.init(
			label: container.decode(String.self, forKey: .label),
			typeDescription: container.decode(TypeDescription.self, forKey: .typeDescription),
		)
	}

	// MARK: Public

	/// The label by which the property is referenced.
	public let label: String
	/// The type to which the property conforms.
	public let typeDescription: TypeDescription

	// MARK: Equatable

	public static func == (lhs: Property, rhs: Property) -> Bool {
		lhs.label == rhs.label && lhs.typeDescription == rhs.typeDescription
	}

	// MARK: Hashable

	/// Feeds the hash of the label and type description, computed once when the property is created:
	/// sets and dictionaries of properties hash each property many times, and hashing a type
	/// description walks its whole tree.
	public func hash(into hasher: inout Hasher) {
		hasher.combine(hashOfLabelAndTypeDescription)
	}

	public func withUpdatedTypeDescription(_ typeDescription: TypeDescription) -> Self {
		.init(
			label: label,
			typeDescription: typeDescription,
		)
	}

	/// The property represented as source code.
	public var asSource: String {
		"\(label): \(typeDescription.asSource)"
	}

	// MARK: Comparable

	public static func < (lhs: Property, rhs: Property) -> Bool {
		if lhs.label != rhs.label {
			return lhs.label < rhs.label
		}
		return lhs.typeDescription.asSource < rhs.typeDescription.asSource
	}

	// MARK: Public

	public var asFunctionParamter: Property {
		.init(
			label: label,
			typeDescription: typeDescription.asFunctionParameter,
		)
	}

	public var asFunctionParamterSyntax: FunctionParameterSyntax {
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
							trailingTrivia: .space,
						))
					},
					baseType: IdentifierTypeSyntax(name: .identifier(typeDescription.asSource)),
				),
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
							trailingTrivia: .space,
						))
						for attribute in attributes {
							AttributeSyntax(
								attributeName: IdentifierTypeSyntax(name: .identifier(attribute)),
								trailingTrivia: .space,
							)
						}
					},
					baseType: IdentifierTypeSyntax(name: .identifier(typeDescription.asSource)),
				),
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
				type: IdentifierTypeSyntax(name: .identifier(typeDescription.asSource)),
			)
		}
	}

	public func asPropertyAssignment(withTrailingNewline trailingNewline: Bool = false) -> CodeBlockItemSyntax {
		.init(
			item: .expr(ExprSyntax(InfixOperatorExprSyntax(
				leadingTrivia: .newline,
				leftOperand: MemberAccessExprSyntax(
					base: DeclReferenceExprSyntax(baseName: TokenSyntax.keyword(.`self`)),
					name: TokenSyntax.identifier(label),
				),
				operator: AssignmentExprSyntax(
					leadingTrivia: .space,
					trailingTrivia: .space,
				),
				rightOperand: DeclReferenceExprSyntax(
					baseName: TokenSyntax.identifier(label),
					trailingTrivia: trailingNewline ? .newline : nil,
				),
			))),
		)
	}

	// MARK: Internal

	/// The coding keys of the stored properties a `Property` encodes: not its hash, which Swift seeds
	/// differently in every process, so a hash written by one run would be wrong in the next.
	enum CodingKeys: String, CodingKey {
		case label
		case typeDescription
	}

	var asTupleElement: TupleTypeElementSyntax {
		TupleTypeElementSyntax(
			firstName: .identifier(label),
			colon: .colonToken(),
			type: IdentifierTypeSyntax(name: .identifier(typeDescription.asSource)),
		)
	}

	var propertyType: PropertyType {
		typeDescription.propertyType
	}

	var generics: [TypeDescription]? {
		typeDescription.simpleNameAndGenerics?.generics
	}

	/// The property with its optional type unwrapped, or this property when its type is not optional. Most
	/// properties are not optional, and creating a property hashes its whole type description.
	var asUnwrappedProperty: Property {
		if case let .optional(unwrapped) = typeDescription {
			Property(label: label, typeDescription: unwrapped)
		} else {
			self
		}
	}

	/// The property with which a type receives the instance of an `@Instantiated` lazily instantiated dependency
	/// rather than its `LazilyInstantiated` wrapper: `service: LazilyInstantiated<Service>` is received by value
	/// as `service: Service`. The generated wrapper is never optional, so neither is this property.
	/// `nil` when the property is not lazily instantiated, and when the instance it creates is itself
	/// optional (`LazilyInstantiated<Service?>`): an instance that may be `nil` cannot be received by value.
	var asLazilyInstantiatedInstanceProperty: Property? {
		guard let instanceType = typeDescription.unwrapped.lazilyInstantiatedInstanceType,
		      !instanceType.isOptional
		else { return nil }
		return Property(label: label, typeDescription: instanceType)
	}

	/// The by-value property a `@Forwarded` or aliased `LazilyInstantiated` property offers. Such a property is
	/// bound with exactly the type it declares, and the instance of an optional wrapper cannot be read
	/// unconditionally, so an optional property offers none.
	var asLazilyInstantiatedInstancePropertyOfDeclaredBinding: Property? {
		if typeDescription.isOptional {
			nil
		} else {
			asLazilyInstantiatedInstanceProperty
		}
	}

	/// The property as dependency cycle validation sees it: the constant a lazily instantiated property stands
	/// for, optional when the property is. A lazily instantiated dependency is created at most once, exactly
	/// like a constant, so it cannot break a dependency cycle: a tree is valid with a lazily instantiated
	/// property if and only if it is valid with that constant.
	var asValidatedForDependencyCycles: Property {
		if let instanceType = typeDescription.lazilyInstantiatedInstanceType {
			Property(label: label, typeDescription: instanceType)
		} else {
			self
		}
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
		/// A `LazilyInstantiated` property.
		/// The instance is created once, the first time it is requested. Types further down the dependency tree can receive the instance itself.
		case lazilyInstantiated
		/// A `SendableLazilyInstantiated` property.
		/// The instance is created once, the first time it is requested. Types further down the dependency tree can receive the instance itself.
		case sendableLazilyInstantiated

		public var isConstant: Bool {
			switch self {
			case .constant:
				true
			case .instantiator, .erasedInstantiator, .sendableInstantiator, .sendableErasedInstantiator, .lazilyInstantiated, .sendableLazilyInstantiated:
				false
			}
		}

		public var isInstantiator: Bool {
			switch self {
			case .instantiator, .sendableInstantiator:
				true
			case .constant, .erasedInstantiator, .sendableErasedInstantiator, .lazilyInstantiated, .sendableLazilyInstantiated:
				false
			}
		}

		public var isErasedInstantiator: Bool {
			switch self {
			case .erasedInstantiator, .sendableErasedInstantiator:
				true
			case .constant, .instantiator, .sendableInstantiator, .lazilyInstantiated, .sendableLazilyInstantiated:
				false
			}
		}

		public var isLazilyInstantiated: Bool {
			switch self {
			case .lazilyInstantiated, .sendableLazilyInstantiated:
				true
			case .constant, .instantiator, .erasedInstantiator, .sendableInstantiator, .sendableErasedInstantiator:
				false
			}
		}

		public var isSendable: Bool {
			switch self {
			case .instantiator, .erasedInstantiator, .constant, .lazilyInstantiated:
				false
			case .sendableInstantiator, .sendableErasedInstantiator, .sendableLazilyInstantiated:
				true
			}
		}
	}

	// MARK: Private

	/// The hash of `label` and `typeDescription`, computed once by the initializer every
	/// property is created through. Not encoded, and not compared by `==`.
	private let hashOfLabelAndTypeDescription: Int
}
