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
	indirect case attributed(TypeDescription, specifiers: [String], attributes: [String])
	/// An array. e.g. [Int]
	indirect case array(element: TypeDescription)
	/// A dictionary. e.g. [Int: String]
	indirect case dictionary(key: TypeDescription, value: TypeDescription)
	/// A tuple. e.g. (Int, string: String)
	indirect case tuple([TupleElement])
	/// A closure. e.g. (Int, Double) throws -> String
	/// `thrownType` is the type a closure that throws names in `throws(E)`, and `nil` for a bare `throws`.
	indirect case closure(arguments: [TypeDescription], isAsync: Bool, doesThrow: Bool, thrownType: TypeDescription? = nil, returnType: TypeDescription)
	/// A variadic parameter of a closure. e.g. the `Int...` of (Int...) -> Void
	indirect case variadic(TypeDescription)
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
						generics: simpleNameAndGenerics.generics,
					)
				} else {
					.nested(
						name: simpleNameAndGenerics.name,
						parentType: outer,
						generics: simpleNameAndGenerics.generics,
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

	/// The receiver with the type it instantiates qualified as the compiler resolves that type’s name where the
	/// receiver is written: `Instantiator<Service>` written within `Feature.Root` becomes
	/// `Instantiator<Feature.Service>` when `Feature.Service` is an instantiable type. The most qualified of the
	/// `nestedOptions` that is an instantiable type wins, so a nested type is chosen over a top-level type of the same name.
	/// - Parameters:
	///   - parentType: The type within which the receiver is written.
	///   - instantiableTypes: The types that `@Instantiable` declarations fulfill.
	///   - searchingTypesEnclosingIt: Whether the types enclosing `parentType` are searched, as they are for a
	///     member of `parentType`'s declaration; a member of an extension of `parentType` is written at file scope,
	///     where only `parentType`'s own nested types and the name as written are options.
	///   - namesOfNestedInstantiableTypes: The name of each nested type among `instantiableTypes`, without the type
	///     enclosing it. Every option but the name as written nests the instantiated type's own name, so when no nested
	///     instantiable type has that name, the options before it are not searched.
	/// - Returns: The qualified type, or `nil` when no option of the instantiated type is an instantiable type.
	func qualifyingInstantiatedType(
		within parentType: TypeDescription,
		amongInstantiableTypes instantiableTypes: Set<TypeDescription>,
		searchingTypesEnclosingIt: Bool,
		namesOfNestedInstantiableTypes: Set<String>,
	) -> TypeDescription? {
		replacingInstantiatedType { instantiatedType in
			let searchesNestedOptions = instantiatedType.simpleNameAndGenerics.map { namesOfNestedInstantiableTypes.contains($0.name) } ?? false
			guard searchesNestedOptions else {
				// The name as written is the only option that can be an instantiable type.
				return instantiableTypes.contains(instantiatedType) ? instantiatedType : nil
			}
			let options = Self.nestedOptions(
				referencedType: instantiatedType,
				within: parentType,
			)
			// A member of an extension is written at file scope: the extended type's own members, then the top level.
			return (searchingTypesEnclosingIt ? options : Array(options.prefix(1) + options.suffix(1)))
				.first(where: instantiableTypes.contains)
		}
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
			// Specifiers come before attributes per the Swift reference manual:
			// https://docs.swift.org/swift-book/ReferenceManual/Types.html#grammar_type
			let prefix = [
				specifiers.isEmpty ? nil : specifiers.joined(separator: " "),
				attributes.isEmpty ? nil : attributes.map { "@\($0)" }.joined(separator: " "),
			].compactMap(\.self).joined(separator: " ")
			return "\(prefix) \(type.asSource)"
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
		case let .closure(arguments, isAsync, doesThrow, thrownType, returnType):
			let throwsClause = if doesThrow {
				thrownType.map { " throws(\($0.asSource))" } ?? " throws"
			} else {
				""
			}
			return "(\(arguments.map(\.asSource).joined(separator: ", ")))\([isAsync ? " async" : "", throwsClause].removingEmpty().joined()) -> \(returnType.asSource)"
		case let .variadic(type):
			return "\(type.wrappedIfAmbiguous.asSource)..."
		case let .unknown(text):
			return text
		}
	}

	public static func < (lhs: TypeDescription, rhs: TypeDescription) -> Bool {
		let lhsSpellingWithoutAny = lhs.withoutAny.asSource
		let rhsSpellingWithoutAny = rhs.withoutAny.asSource
		return if lhsSpellingWithoutAny != rhsSpellingWithoutAny {
			lhsSpellingWithoutAny < rhsSpellingWithoutAny
		} else {
			lhs.asSource < rhs.asSource
		}
	}

	/// This type as a seam names a hole type: without `any` at every depth, each composition's members in the order of their
	/// identifiers, so spellings of one type name one hole type.
	var spelledCanonically: TypeDescription {
		let type = withoutAny
		switch type {
		case let .simple(name, generics):
			return .simple(name: name, generics: generics.map(\.spelledCanonically))
		case let .nested(name, parentType, generics):
			return .nested(name: name, parentType: parentType.spelledCanonically, generics: generics.map(\.spelledCanonically))
		case let .composition(types):
			return .composition(UnorderedEquatingCollection(types.map(\.spelledCanonically).sorted { $0.asIdentifier < $1.asIdentifier }))
		case let .optional(wrappedType):
			return .optional(wrappedType.spelledCanonically)
		case let .implicitlyUnwrappedOptional(wrappedType):
			// The macro rejects `!` at the top of an `@Instantiated` property's type and of the type its wrapper builds, but
			// not inside the type a `fulfilledByType:` string names, such as `"Box<(any Q & P)!>"`.
			return .implicitlyUnwrappedOptional(wrappedType.spelledCanonically)
		case let .array(element):
			return .array(element: element.spelledCanonically)
		case let .dictionary(key, value):
			return .dictionary(key: key.spelledCanonically, value: value.spelledCanonically)
		case let .tuple(elements):
			return .tuple(elements.map { TupleElement(label: $0.label, $0.typeDescription.spelledCanonically) })
		case let .closure(arguments, isAsync, doesThrow, thrownType, returnType):
			return .closure(arguments: arguments.map(\.spelledCanonically), isAsync: isAsync, doesThrow: doesThrow, thrownType: thrownType?.spelledCanonically, returnType: returnType.spelledCanonically)
		case let .attributed(attributedType, specifiers, attributes):
			return .attributed(attributedType.spelledCanonically, specifiers: specifiers, attributes: attributes)
		case let .metatype(instanceType, isType):
			// `withoutAny` has already decided whether the metatype is existential from the instance type's `any`.
			return .metatype(instanceType.spelledCanonically, isType: isType)
		case let .variadic(elementType):
			// A variadic parameter of a function type a generic argument spells: `Box<(Int...) -> Void>`.
			return .variadic(elementType.spelledCanonically)
		case .void,
		     .unknown,
		     .any,
		     .some:
			// `Void` and a spelling SafeDI does not parse, such as a value generic argument, hold no type to spell canonically.
			// No hole type spells the others: `withoutAny` removes `any`; Swift accepts `some` in a stored property's type
			// only beside an initial value, which a `let` its initializer sets cannot have, and never in a function type's
			// parameter.
			return type
		}
	}

	/// This type with `any` stripped at every depth: the spelling `==` compares, and what the seam guard hashes.
	var withoutAny: TypeDescription {
		switch self {
		case .void, .unknown:
			self
		case let .any(constraint):
			constraint.withoutAny
		case let .simple(name, generics):
			.simple(name: name, generics: generics.map(\.withoutAny))
		case let .nested(name, parentType, generics):
			.nested(name: name, parentType: parentType.withoutAny, generics: generics.map(\.withoutAny))
		case let .composition(types):
			.composition(UnorderedEquatingCollection(types.map(\.withoutAny)))
		case let .optional(type):
			.optional(type.withoutAny)
		case let .implicitlyUnwrappedOptional(type):
			.implicitlyUnwrappedOptional(type.withoutAny)
		case let .some(type):
			.some(type.withoutAny)
		case let .metatype(type, isType):
			.metatype(type.withoutAny, isType: Self.isExistentialMetatype(ofInstanceType: type, isType: isType))
		case let .attributed(type, specifiers, attributes):
			.attributed(type.withoutAny, specifiers: specifiers, attributes: attributes)
		case let .array(element):
			.array(element: element.withoutAny)
		case let .dictionary(key, value):
			.dictionary(key: key.withoutAny, value: value.withoutAny)
		case let .tuple(elements):
			.tuple(elements.map { TupleElement(label: $0.label, $0.typeDescription.withoutAny) })
		case let .closure(arguments, isAsync, doesThrow, thrownType, returnType):
			.closure(arguments: arguments.map(\.withoutAny), isAsync: isAsync, doesThrow: doesThrow, thrownType: thrownType?.withoutAny, returnType: returnType.withoutAny)
		case let .variadic(type):
			.variadic(type.withoutAny)
		}
	}

	/// This type with the differences removed that a declaration's spelling alone shows do not change the type, at every
	/// depth: `Optional<Int>` is `Int?`, `Array<Int>` is `[Int]`, `Dictionary<String, Int>` is `[String: Int]`, a type
	/// qualified by one of `moduleNames` is the type without that qualifier, and a type's attributes are in sorted order. A
	/// name in `declaredTypeNames` is a type a module declares, which hides the standard library's type or the module of
	/// that name, so neither is seen through. A type qualified by one of `declaringModuleNames` is the type without that
	/// qualifier only when no other module declares a type of its name, since generated code spells a bare name in another
	/// module than the one that wrote it, where that declaration would be what the name means.
	/// Compare two of these to ask whether two spellings name one type; never spell a type with one.
	func withoutSpellingDifferences(
		qualifiedByModulesNamed moduleNames: [String],
		orDeclaringModulesNamed declaringModuleNames: [String] = [],
		declaredTypeNames: DeclaredTypeNames,
	) -> TypeDescription {
		func withoutDifferences(_ type: TypeDescription) -> TypeDescription {
			type.withoutSpellingDifferences(qualifiedByModulesNamed: moduleNames, orDeclaringModulesNamed: declaringModuleNames, declaredTypeNames: declaredTypeNames)
		}
		switch self {
		case .void, .unknown:
			return self
		case let .simple(name, generics):
			let generics = generics.map(withoutDifferences)
			guard !declaredTypeNames.contains(name) else {
				return .simple(name: name, generics: generics)
			}
			return switch (name, generics.count) {
			case ("Void", 0):
				.void(.identifier)
			case ("Optional", 1):
				.optional(generics[0])
			case ("Array", 1):
				.array(element: generics[0])
			case ("Dictionary", 2):
				.dictionary(key: generics[0], value: generics[1])
			default:
				.simple(name: name, generics: generics)
			}
		case let .nested(name, parentType, generics):
			if case let .simple(parentName, parentGenerics) = parentType,
			   parentGenerics.isEmpty,
			   !declaredTypeNames.contains(parentName),
			   moduleNames.contains(parentName) || (declaringModuleNames.contains(parentName) && !declaredTypeNames.isDeclared(name, outsideModuleNamed: parentName))
			{
				return withoutDifferences(.simple(name: name, generics: generics))
			} else {
				return .nested(name: name, parentType: withoutDifferences(parentType), generics: generics.map(withoutDifferences))
			}
		case let .composition(types):
			return .composition(UnorderedEquatingCollection(types.map(withoutDifferences)))
		case let .optional(type):
			return .optional(withoutDifferences(type))
		case let .implicitlyUnwrappedOptional(type):
			return .implicitlyUnwrappedOptional(withoutDifferences(type))
		case let .some(type):
			return .some(withoutDifferences(type))
		case let .any(type):
			return .any(withoutDifferences(type))
		case let .metatype(type, isType):
			return .metatype(withoutDifferences(type), isType: isType)
		case let .attributed(type, specifiers, attributes):
			return .attributed(withoutDifferences(type), specifiers: specifiers, attributes: attributes.sorted())
		case let .array(element):
			return .array(element: withoutDifferences(element))
		case let .dictionary(key, value):
			return .dictionary(key: withoutDifferences(key), value: withoutDifferences(value))
		case let .tuple(elements):
			return .tuple(elements.map { TupleElement(label: $0.label, withoutDifferences($0.typeDescription)) })
		case let .closure(arguments, isAsync, doesThrow, thrownType, returnType):
			return .closure(arguments: arguments.map(withoutDifferences), isAsync: isAsync, doesThrow: doesThrow, thrownType: thrownType.map(withoutDifferences), returnType: withoutDifferences(returnType))
		case let .variadic(type):
			return .variadic(withoutDifferences(type))
		}
	}

	// MARK: Equatable

	/// Whether the two types are the same type. A protocol spelled with `any` is the same existential type as the
	/// protocol spelled without it, at any depth: `any Service` equals `Service`, `(any Service)?` equals
	/// `Service?`, and `Instantiator<any Service>` equals `Instantiator<Service>`. `some Service` is a different type.
	/// Each type keeps its own spelling in `asSource` and `asIdentifier`.
	public static func == (lhs: TypeDescription, rhs: TypeDescription) -> Bool {
		if case let .any(constraint) = rhs {
			lhs == constraint
		} else {
			lhs.isSameType(asTypeNotSpelledWithAny: rhs)
		}
	}

	/// The type a closure's `throws(E)` names, or `nil` when it names `any Error`: Swift reads `throws(any Error)` and
	/// `throws` as one type, so neither `==` nor `hash` tells them apart, while `asSource` keeps each spelling.
	private static func thrownTypeBeyondAnyError(_ thrownType: TypeDescription?) -> TypeDescription? {
		thrownType == .simple(name: "Error") || thrownType == .nested(name: "Error", parentType: .simple(name: "Swift"))
			? nil
			: thrownType
	}

	/// Whether the receiver is the same type as `other`, which is not spelled with `any` at its top level.
	private func isSameType(asTypeNotSpelledWithAny other: TypeDescription) -> Bool {
		switch self {
		case let .any(constraint):
			return constraint == other
		case let .void(spelling):
			guard case let .void(otherSpelling) = other else { return false }
			return spelling == otherSpelling
		case let .simple(name, generics):
			guard case let .simple(otherName, otherGenerics) = other else { return false }
			return name == otherName && generics == otherGenerics
		case let .nested(name, parentType, generics):
			guard case let .nested(otherName, otherParentType, otherGenerics) = other else { return false }
			return name == otherName && parentType == otherParentType && generics == otherGenerics
		case let .composition(types):
			guard case let .composition(otherTypes) = other else { return false }
			return types == otherTypes
		case let .optional(type):
			guard case let .optional(otherType) = other else { return false }
			return type == otherType
		case let .implicitlyUnwrappedOptional(type):
			guard case let .implicitlyUnwrappedOptional(otherType) = other else { return false }
			return type == otherType
		case let .some(type):
			guard case let .some(otherType) = other else { return false }
			return type == otherType
		case let .metatype(type, isType):
			guard case let .metatype(otherType, otherIsType) = other else { return false }
			return type == otherType
				&& Self.isExistentialMetatype(ofInstanceType: type, isType: isType) == Self.isExistentialMetatype(ofInstanceType: otherType, isType: otherIsType)
		case let .attributed(type, specifiers, attributes):
			guard case let .attributed(otherType, otherSpecifiers, otherAttributes) = other else { return false }
			return type == otherType && specifiers == otherSpecifiers && attributes == otherAttributes
		case let .array(element):
			guard case let .array(otherElement) = other else { return false }
			return element == otherElement
		case let .dictionary(key, value):
			guard case let .dictionary(otherKey, otherValue) = other else { return false }
			return key == otherKey && value == otherValue
		case let .tuple(elements):
			guard case let .tuple(otherElements) = other else { return false }
			return elements == otherElements
		case let .closure(arguments, isAsync, doesThrow, thrownType, returnType):
			guard case let .closure(otherArguments, otherIsAsync, otherDoesThrow, otherThrownType, otherReturnType) = other else { return false }
			return arguments == otherArguments
				&& isAsync == otherIsAsync
				&& doesThrow == otherDoesThrow
				&& Self.thrownTypeBeyondAnyError(thrownType) == Self.thrownTypeBeyondAnyError(otherThrownType)
				&& returnType == otherReturnType
		case let .variadic(type):
			guard case let .variadic(otherType) = other else { return false }
			return type == otherType
		case let .unknown(text):
			guard case let .unknown(otherText) = other else { return false }
			return text == otherText
		}
	}

	// MARK: Hashable

	/// Hashes the type so that types `==` considers the same hash alike: an existential hashes as its constraint.
	public func hash(into hasher: inout Hasher) {
		switch self {
		case let .void(spelling):
			hasher.combine(0)
			hasher.combine(spelling)
		case let .simple(name, generics):
			hasher.combine(1)
			hasher.combine(name)
			hasher.combine(generics)
		case let .nested(name, parentType, generics):
			hasher.combine(2)
			hasher.combine(name)
			hasher.combine(parentType)
			hasher.combine(generics)
		case let .composition(types):
			hasher.combine(3)
			hasher.combine(types)
		case let .optional(type):
			hasher.combine(4)
			hasher.combine(type)
		case let .implicitlyUnwrappedOptional(type):
			hasher.combine(5)
			hasher.combine(type)
		case let .some(type):
			hasher.combine(6)
			hasher.combine(type)
		case let .any(constraint):
			constraint.hash(into: &hasher)
		case let .metatype(type, isType):
			hasher.combine(7)
			hasher.combine(type)
			hasher.combine(Self.isExistentialMetatype(ofInstanceType: type, isType: isType))
		case let .attributed(type, specifiers, attributes):
			hasher.combine(8)
			hasher.combine(type)
			hasher.combine(specifiers)
			hasher.combine(attributes)
		case let .array(element):
			hasher.combine(9)
			hasher.combine(element)
		case let .dictionary(key, value):
			hasher.combine(10)
			hasher.combine(key)
			hasher.combine(value)
		case let .tuple(elements):
			hasher.combine(11)
			hasher.combine(elements)
		case let .closure(arguments, isAsync, doesThrow, thrownType, returnType):
			hasher.combine(12)
			hasher.combine(arguments)
			hasher.combine(isAsync)
			hasher.combine(doesThrow)
			hasher.combine(Self.thrownTypeBeyondAnyError(thrownType))
			hasher.combine(returnType)
		case let .unknown(text):
			hasher.combine(13)
			hasher.combine(text)
		case let .variadic(type):
			hasher.combine(14)
			hasher.combine(type)
		}
	}

	/// Whether a metatype of `instanceType` spelled with `.Type` (`isType`) or `.Protocol` is the existential
	/// metatype: `Service.Type` and `any Service.Type` are, while `(any Service).Type` is the metatype of the
	/// existential itself, `Service.Protocol`.
	private static func isExistentialMetatype(ofInstanceType instanceType: TypeDescription, isType: Bool) -> Bool {
		switch instanceType {
		case .any:
			false
		case .array, .attributed, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .nested, .optional, .simple, .some, .tuple, .unknown, .variadic, .void:
			isType
		}
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
		public init(label: String? = nil, _ typeDescription: TypeDescription) {
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
			} else if name == Dependency.lazilyInstantiatedType {
				.lazilyInstantiated
			} else if name == Dependency.sendableLazilyInstantiatedType {
				.sendableLazilyInstantiated
			} else {
				.constant
			}
		case
			let .optional(type),
			let .implicitlyUnwrappedOptional(type):
			type.propertyType
		case .any, .array, .attributed, .closure, .composition, .dictionary, .metatype, .nested, .some, .tuple, .unknown, .variadic, .void:
			.constant
		}
	}

	/// The type of the instance a `LazilyInstantiated` or `SendableLazilyInstantiated` creates, exactly as it is
	/// spelled: `any Service` for `LazilyInstantiated<any Service>`. An optional wrapper creates an optional
	/// instance type. `nil` when this is neither.
	var lazilyInstantiatedInstanceType: TypeDescription? {
		switch self {
		case let .simple(name, generics):
			// Checked for every property in generation’s hottest loops, so it compares names only for a generic type.
			if let instanceType = generics.first,
			   name == Dependency.lazilyInstantiatedType || name == Dependency.sendableLazilyInstantiatedType
			{
				instanceType
			} else {
				nil
			}
		case let .optional(type),
		     let .implicitlyUnwrappedOptional(type):
			type.lazilyInstantiatedInstanceType.map { .optional($0) }
		case .any, .array, .attributed, .closure, .composition, .dictionary, .metatype, .nested, .some, .tuple, .unknown, .variadic, .void:
			nil
		}
	}

	/// The type a property of this type builds, exactly as it is spelled: `any Service` for
	/// `LazilyInstantiated<any Service>` and `Service` for `ErasedInstantiator<Int, Service>?`. The receiver itself when
	/// it is no wrapper of SafeDI's.
	var builtTypeOfWrapper: TypeDescription {
		guard case let .simple(name, generics) = unwrapped, let builtGeneric = Self.builtGeneric(inGenerics: generics, ofTypeNamed: name) else {
			return self
		}
		return generics[builtGeneric.index]
	}

	/// The type of the value an instantiator of this type forwards: `ErasedInstantiator`'s first generic, unless it is
	/// spelled `()` or `Void`, and `T.ForwardedProperties` for `Instantiator<T>`, whose `T` may forward nothing, which code
	/// that sees only `T`'s conformance cannot tell. `nil` for every other type. Spelled as a function parameter takes it.
	var forwardedTypeOfWrapper: TypeDescription? {
		guard case let .simple(_, generics) = unwrapped, let firstGeneric = generics.first else { return nil }
		switch propertyType {
		case .instantiator, .sendableInstantiator:
			return .nested(name: Dependency.forwardedPropertiesType, parentType: firstGeneric, generics: [])
		case .erasedInstantiator, .sendableErasedInstantiator:
			if case .void = firstGeneric {
				return nil
			} else {
				return firstGeneric.asFunctionParameter
			}
		case .constant, .lazilyInstantiated, .sendableLazilyInstantiated:
			return nil
		}
	}

	/// This function type, `@Sendable`.
	var asSendableFunction: TypeDescription {
		.attributed(self, specifiers: [], attributes: ["Sendable"])
	}

	/// Whether this type is spelled with `@Sendable` at its top: a function type `asSendableFunction` made.
	var isSendableFunction: Bool {
		if case let .attributed(_, _, attributes) = self {
			attributes.contains("Sendable")
		} else {
			false
		}
	}

	public var asFunctionParameter: TypeDescription {
		switch self {
		case .any,
		     .array,
		     .composition,
		     .dictionary,
		     .implicitlyUnwrappedOptional,
		     .metatype,
		     .nested,
		     .optional,
		     .simple,
		     .some,
		     .tuple,
		     .unknown,
		     .variadic,
		     .void:
			self
		case .closure:
			.attributed(self, specifiers: [], attributes: ["escaping"])
		case let .attributed(type, specifiers, attributes):
			if attributes.contains(where: { $0 == "escaping" }) {
				.attributed(type, specifiers: specifiers, attributes: attributes)
			} else {
				.attributed(type, specifiers: specifiers, attributes: ["escaping"] + attributes)
			}
		}
	}

	/// This type as a parameter of a function generated code declares: `asFunctionParameter`, or, for one of
	/// `typesDeclaredEscaping` (`nameDeclaredEscaping`), `@escaping`, which SafeDI cannot tell a name needs from the name.
	func asFunctionParameter(amongTypesDeclaredEscaping typesDeclaredEscaping: Set<TypeDescription>) -> TypeDescription {
		typesDeclaredEscaping.contains(self) ? .attributed(self, specifiers: [], attributes: ["escaping"]) : asFunctionParameter
	}

	/// The name this parameter type declares `@escaping`, or `nil` for any other type. SafeDI cannot see that a name is
	/// a typealias of a function type, but Swift accepts `@escaping` only on a function type, so a parameter spelled
	/// `@escaping OnTap` takes a property spelled `OnTap`. Any other attribute or specifier beside it (`@autoclosure`,
	/// `@Sendable`, `sending`) changes what the parameter takes, or what it can be passed, so that is another type.
	var nameDeclaredEscaping: TypeDescription? {
		guard case let .attributed(type, specifiers, attributes) = self,
		      specifiers.isEmpty,
		      attributes == ["escaping"]
		else { return nil }
		switch type {
		case .nested,
		     .simple:
			return type
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
		     .unknown,
		     .variadic,
		     .void:
			return nil
		}
	}

	/// Whether this type is a closure (function) type, possibly wrapped in attributes.
	public var isClosure: Bool {
		switch self {
		case .closure:
			true
		case let .attributed(type, _, _):
			type.isClosure
		case .any,
		     .array,
		     .composition,
		     .dictionary,
		     .implicitlyUnwrappedOptional,
		     .metatype,
		     .nested,
		     .optional,
		     .simple,
		     .some,
		     .tuple,
		     .unknown,
		     .variadic,
		     .void:
			false
		}
	}

	/// Whether this type is attributed `@escaping`, which Swift accepts only on a function type, so that a parameter
	/// declared `@escaping` is of a function type even when it is spelled as a typealias SafeDI cannot see through.
	public var isEscaping: Bool {
		switch self {
		case let .attributed(_, _, attributes):
			attributes.contains("escaping")
		case .any,
		     .array,
		     .closure,
		     .composition,
		     .dictionary,
		     .implicitlyUnwrappedOptional,
		     .metatype,
		     .nested,
		     .optional,
		     .simple,
		     .some,
		     .tuple,
		     .unknown,
		     .variadic,
		     .void:
			false
		}
	}

	/// Recursively strips wrappers that are irrelevant for disambiguation:
	/// attributes (`@Sendable`, `@escaping`), optionality (`?`, `!`),
	/// existential wrappers (`some`, `any`), and metatype (`.Type`, `.Protocol`).
	/// The result is the core type that a human would use to distinguish parameters.
	public var simplified: TypeDescription {
		switch self {
		case .void,
		     .simple,
		     .nested,
		     .composition,
		     .array,
		     .dictionary,
		     .tuple,
		     .closure,
		     .unknown,
		     .variadic:
			self
		case let .optional(type):
			type.simplified
		case let .implicitlyUnwrappedOptional(type):
			type.simplified
		case let .some(type):
			type.simplified
		case let .any(type):
			type.simplified
		case let .metatype(type, _):
			type.simplified
		case let .attributed(type, _, _):
			type.simplified
		}
	}

	/// A valid Swift identifier fragment derived from this type's structure.
	/// Used as a disambiguation suffix in generated mock parameter names.
	public var asIdentifier: String {
		switch self {
		case .void:
			return "Void"
		case let .simple(name, generics):
			return if generics.isEmpty {
				name
			} else {
				"\(name)__\(generics.map(\.asIdentifier).joined(separator: "__"))"
			}
		case let .nested(name, parentType, generics):
			return if generics.isEmpty {
				"\(parentType.asIdentifier)_\(name)"
			} else {
				"\(parentType.asIdentifier)_\(name)__\(generics.map(\.asIdentifier).joined(separator: "__"))"
			}
		case let .composition(types):
			return types.map(\.asIdentifier).joined(separator: "_and_")
		case let .optional(type):
			return "\(type.asIdentifier)_Optional"
		case let .implicitlyUnwrappedOptional(type):
			return "\(type.asIdentifier)_Optional"
		case let .some(type):
			return "some_\(type.asIdentifier)"
		case let .any(type):
			return "any_\(type.asIdentifier)"
		case let .metatype(type, isType):
			return "\(type.asIdentifier)_\(isType ? "Type" : "Protocol")"
		case let .attributed(type, specifiers, attributes):
			let prefix = [
				specifiers.isEmpty ? nil : specifiers.joined(separator: "_"),
				attributes.isEmpty ? nil : attributes.map { $0.filter { $0.isLetter || $0.isNumber || $0 == "_" } }.joined(separator: "_"),
			].compactMap(\.self).joined(separator: "_")
			return "\(prefix)_\(type.asIdentifier)"
		case let .array(element):
			return "Array_\(element.asIdentifier)"
		case let .dictionary(key, value):
			return "Dictionary_\(key.asIdentifier)_\(value.asIdentifier)"
		case let .tuple(elements):
			return elements.isEmpty ? "Void" : elements.map(\.typeDescription.asIdentifier).joined(separator: "_and_")
		case let .closure(arguments, isAsync, doesThrow, thrownType, returnType):
			let args = arguments.isEmpty ? "Void" : arguments.map(\.asIdentifier).joined(separator: "_")
			let throwsModifier = if doesThrow {
				thrownType.map { "throws_\($0.asIdentifier)" } ?? "throws"
			} else {
				String?.none
			}
			let modifiers = [isAsync ? "async" : nil, throwsModifier].compactMap(\.self)
			let parts = [args] + modifiers + ["to", returnType.asIdentifier]
			return parts.joined(separator: "_")
		case let .variadic(type):
			return "\(type.asIdentifier)_Variadic"
		case let .unknown(text):
			return text.filter(\.isLetter)
		}
	}

	/// The type of the value an `@autoclosure` parameter of this type takes: the closure's return type (`Int` for
	/// `@autoclosure () -> Int`, `@escaping` or not), or `nil` for a type that is not an `@autoclosure`.
	public var autoclosureValueType: TypeDescription? {
		guard case let .attributed(.closure(_, _, _, _, returnType), _, attributes) = self,
		      attributes.contains("autoclosure")
		else { return nil }
		return returnType
	}

	/// Strips the `@escaping` attribute, if present. Returns `self` unchanged for non-attributed types.
	/// Used when a type will appear in a position where `@escaping` is invalid (e.g., closure return types).
	public var strippingEscaping: TypeDescription {
		switch self {
		case let .attributed(type, specifiers, attributes):
			let filtered = attributes.filter { $0 != "escaping" }
			if !filtered.isEmpty {
				return .attributed(type, specifiers: specifiers, attributes: filtered)
			} else if !specifiers.isEmpty {
				return .attributed(type, specifiers: specifiers, attributes: [])
			} else {
				return type
			}
		case .any,
		     .array,
		     .closure,
		     .composition,
		     .dictionary,
		     .implicitlyUnwrappedOptional,
		     .metatype,
		     .nested,
		     .optional,
		     .simple,
		     .some,
		     .tuple,
		     .unknown,
		     .variadic,
		     .void:
			return self
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
		     .variadic,
		     .void:
			false
		case .optional:
			true
		}
	}

	public var unwrapped: TypeDescription {
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
		     .variadic,
		     .void:
			self
		case let .optional(unwrapped):
			unwrapped
		}
	}

	/// The name of the outermost type enclosing this nested type, or of this type when it is not nested: the name the
	/// declaration that encloses it in its file spells at the file's top level. `nil` when that type is not spelled by a
	/// name alone.
	public var outermostTypeName: String? {
		var outermostType = self
		while let enclosingType = outermostType.popNested {
			outermostType = enclosingType
		}
		guard case let .simple(name, _) = outermostType else { return nil }
		return name
	}

	/// The generic arguments spelled on this type and on the types enclosing it, the outermost type's first.
	var genericArgumentsOfThisAndEnclosingTypes: [TypeDescription] {
		var genericArgumentsFromInnermost = [[TypeDescription]]()
		var enclosingType = self
		while case let .nested(_, parentType, generics) = enclosingType {
			genericArgumentsFromInnermost.append(generics)
			enclosingType = parentType
		}
		if case let .simple(_, generics) = enclosingType {
			genericArgumentsFromInnermost.append(generics)
		}
		return genericArgumentsFromInnermost.reversed().flatMap(\.self)
	}

	/// The nominal type this names, with no generic arguments at any level – what a declaration of it records – or
	/// `nil` when this names no nominal type.
	public var withoutGenericArguments: TypeDescription? {
		switch self {
		case let .simple(name, _):
			.simple(name: name)
		case let .nested(name, parentType, _):
			parentType.withoutGenericArguments.map { .nested(name: name, parentType: $0) }
		case .any, .array, .attributed, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .optional, .some, .tuple, .unknown, .variadic, .void:
			nil
		}
	}

	/// This nested type without its outermost enclosing type – `Inner.Leaf` for `Outer.Inner.Leaf` – or `nil` for a type
	/// nested in nothing.
	public var droppingOutermostType: TypeDescription? {
		switch self {
		case let .nested(name, .simple, generics):
			.simple(name: name, generics: generics)
		case let .nested(name, parentType, generics):
			parentType.droppingOutermostType.map { .nested(name: name, parentType: $0, generics: generics) }
		case .any, .array, .attributed, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .optional, .simple, .some, .tuple, .unknown, .variadic, .void:
			nil
		}
	}

	public var popNested: TypeDescription? {
		switch self {
		case let .nested(_, parentType, _):
			parentType
		case .any, .array, .attributed, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .optional, .simple, .some, .tuple, .unknown, .variadic, .void:
			nil
		}
	}

	public var strippingGenerics: TypeDescription {
		switch self {
		case let .simple(name, _):
			.simple(name: name, generics: [])
		case let .nested(name, parentType, _):
			.nested(name: name, parentType: parentType, generics: [])
		case .array, .attributed, .any, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .optional, .some, .tuple, .unknown, .variadic, .void:
			self
		}
	}

	/// The receiver as an `@Instantiable` type.
	var asInstantiatedType: TypeDescription {
		switch self {
		case let .simple(name, generics):
			if let builtGeneric = Self.builtGeneric(inGenerics: generics, ofTypeNamed: name) {
				if builtGeneric.mayWrapInstantiatedType {
					generics[builtGeneric.index].asInstantiatedType
				} else {
					generics[builtGeneric.index]
				}
			} else {
				self
			}
		case let .any(typeDescription),
		     let .implicitlyUnwrappedOptional(typeDescription),
		     let .optional(typeDescription),
		     let .some(typeDescription):
			typeDescription.asInstantiatedType
		case .array, .attributed, .closure, .composition, .dictionary, .metatype, .nested, .tuple, .unknown, .variadic, .void:
			self
		}
	}

	/// The receiver with the type that `asInstantiatedType` returns replaced, wherever in the receiver that type sits:
	/// `Instantiator<Service>?` becomes `Instantiator<Feature.Service>?` and `LazilyInstantiated<any Service>` becomes
	/// `LazilyInstantiated<any Feature.Service>` when `replacement` maps `Service` to `Feature.Service`. Every other
	/// part of the receiver, such as the forwarded properties of an `ErasedInstantiator`, is unchanged. This walks the
	/// same path through the receiver as `asInstantiatedType`, so the two must change together.
	/// - Parameter replacement: Returns the type with which to replace the instantiated type, or `nil` to keep it.
	/// - Returns: The receiver with its instantiated type replaced, or `nil` when `replacement` keeps it.
	public func replacingInstantiatedType(_ replacement: (TypeDescription) -> TypeDescription?) -> TypeDescription? {
		switch self {
		case let .simple(name, generics):
			guard let builtGeneric = Self.builtGeneric(inGenerics: generics, ofTypeNamed: name) else {
				return replacement(self)
			}
			let builtType = generics[builtGeneric.index]
			let replacedBuiltType = if builtGeneric.mayWrapInstantiatedType {
				builtType.replacingInstantiatedType(replacement)
			} else {
				replacement(builtType)
			}
			guard let replacedBuiltType else {
				return nil
			}
			var replacedGenerics = generics
			replacedGenerics[builtGeneric.index] = replacedBuiltType
			return .simple(name: name, generics: replacedGenerics)
		case let .any(typeDescription):
			return typeDescription.replacingInstantiatedType(replacement).map { .any($0) }
		case let .implicitlyUnwrappedOptional(typeDescription):
			return typeDescription.replacingInstantiatedType(replacement).map { .implicitlyUnwrappedOptional($0) }
		case let .optional(typeDescription):
			return typeDescription.replacingInstantiatedType(replacement).map { .optional($0) }
		case let .some(typeDescription):
			return typeDescription.replacingInstantiatedType(replacement).map { .some($0) }
		case .array, .attributed, .closure, .composition, .dictionary, .metatype, .nested, .tuple, .unknown, .variadic, .void:
			return replacement(self)
		}
	}

	/// The generic argument that a type which instantiates another builds.
	private struct BuiltGeneric {
		/// The index of the built type among the generic arguments.
		let index: Int
		/// Whether the built type may be spelled in every way a constant’s type can, such as `any Service`, so that
		/// the instantiated type is the built type’s own instantiated type rather than the built type itself.
		let mayWrapInstantiatedType: Bool
	}

	/// The receiver with each type `replacements` holds replaced, wherever in the receiver that type sits, or `nil` when it
	/// holds none of them, so that a caller keeps the receiver without rebuilding it: `Instantiator<Store>?` becomes
	/// `Instantiator<ModA.Store>?` when `replacements` maps `Store` to `ModA.Store`. A name after the outermost of a nested
	/// type is a member of the type before it, so `Store.Config` is replaced only when `replacements` holds it whole.
	public func replacingTypes(_ replacements: [TypeDescription: TypeDescription]) -> TypeDescription? {
		// Only a named type is looked up: `any Store` equals `Store`, and its `any` is kept.
		switch self {
		case let .simple(name, generics):
			return replacements[self] ?? generics.replacingElementsIfAny { $0.replacingTypes(replacements) }.map { .simple(name: name, generics: $0) }
		case let .nested(name, parentType, generics):
			return replacements[self] ?? generics.replacingElementsIfAny { $0.replacingTypes(replacements) }.map { .nested(name: name, parentType: parentType, generics: $0) }
		case let .composition(types):
			return Array(types).replacingElementsIfAny { $0.replacingTypes(replacements) }.map { .composition(UnorderedEquatingCollection($0)) }
		case let .optional(type):
			return type.replacingTypes(replacements).map { .optional($0) }
		case let .implicitlyUnwrappedOptional(type):
			return type.replacingTypes(replacements).map { .implicitlyUnwrappedOptional($0) }
		case let .some(type):
			return type.replacingTypes(replacements).map { .some($0) }
		case let .any(type):
			return type.replacingTypes(replacements).map { .any($0) }
		case let .metatype(type, isType):
			return type.replacingTypes(replacements).map { .metatype($0, isType: isType) }
		case let .attributed(type, specifiers, attributes):
			return type.replacingTypes(replacements).map { .attributed($0, specifiers: specifiers, attributes: attributes) }
		case let .array(element):
			return element.replacingTypes(replacements).map { .array(element: $0) }
		case let .dictionary(key, value):
			let replacedKey = key.replacingTypes(replacements)
			let replacedValue = value.replacingTypes(replacements)
			guard replacedKey != nil || replacedValue != nil else { return nil }
			return .dictionary(key: replacedKey ?? key, value: replacedValue ?? value)
		case let .tuple(elements):
			return elements
				.replacingElementsIfAny { element in
					element.typeDescription.replacingTypes(replacements).map { TupleElement(label: element.label, $0) }
				}
				.map { .tuple($0) }
		case let .closure(arguments, isAsync, doesThrow, thrownType, returnType):
			let replacedArguments = arguments.replacingElementsIfAny { $0.replacingTypes(replacements) }
			let replacedThrownType = thrownType?.replacingTypes(replacements)
			let replacedReturnType = returnType.replacingTypes(replacements)
			guard replacedArguments != nil || replacedThrownType != nil || replacedReturnType != nil else { return nil }
			return .closure(
				arguments: replacedArguments ?? arguments,
				isAsync: isAsync,
				doesThrow: doesThrow,
				thrownType: replacedThrownType ?? thrownType,
				returnType: replacedReturnType ?? returnType,
			)
		case let .variadic(type):
			return type.replacingTypes(replacements).map { .variadic($0) }
		case .unknown, .void:
			return nil
		}
	}

	/// The receiver spelled with `moduleName` before its outermost name, as a mention of the module's own type is
	/// (`ModA.Store`, `ModA.Feature.Store`), or `nil` for a spelling that is not a named type.
	public func qualified(byModuleNamed moduleName: String) -> TypeDescription? {
		switch self {
		case let .simple(name, generics):
			.nested(name: name, parentType: .simple(name: moduleName), generics: generics)
		case let .nested(name, parentType, generics):
			parentType.qualified(byModuleNamed: moduleName).map { .nested(name: name, parentType: $0, generics: generics) }
		case .any, .array, .attributed, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .optional, .some, .tuple, .unknown, .variadic, .void:
			nil
		}
	}

	/// The generic argument that a type which instantiates another builds, or `nil` when the type named `name` with
	/// `generics` is not such a type.
	private static func builtGeneric(inGenerics generics: [TypeDescription], ofTypeNamed name: String) -> BuiltGeneric? {
		if name == Dependency.instantiatorType || name == Dependency.sendableInstantiatorType,
		   !generics.isEmpty
		{
			// This is a type that is lazily instantiated.
			// The first generic is the built type.
			BuiltGeneric(index: 0, mayWrapInstantiatedType: false)
		} else if name == Dependency.erasedInstantiatorType || name == Dependency.sendableErasedInstantiatorType,
		          generics.count > 1
		{
			// This is a type that is lazily instantiated with explicitly declared forwarded arguments due to type erasure.
			// The second generic is the built type.
			BuiltGeneric(index: 1, mayWrapInstantiatedType: false)
		} else if name == Dependency.lazilyInstantiatedType || name == Dependency.sendableLazilyInstantiatedType,
		          !generics.isEmpty
		{
			// This is a type that is instantiated once, the first time it is requested.
			// The first generic is the built type. It has no `Instantiable` constraint, so it can be spelled
			// in every way a constant’s type can, such as `any Service`.
			BuiltGeneric(index: 0, mayWrapInstantiatedType: true)
		} else {
			nil
		}
	}

	/// The spelling that constructs this wrapper type in an expression, such as `ErasedInstantiator<Int, Screen> { … }`.
	/// Swift's expression parser does not read a `nonisolated(nonsending)` specifier in a generic argument, though its
	/// type parser does: for such a type this is the wrapper's name alone, whose generic arguments come from the type
	/// annotation `isConstructedByAnnotation` then calls for.
	var spelledForConstruction: String {
		if isConstructedByAnnotation, let name = simpleNameAndGenerics?.name {
			name
		} else {
			asSource
		}
	}

	/// Whether a binding of this wrapper type must state the type in an annotation. See `spelledForConstruction`.
	var isConstructedByAnnotation: Bool {
		simpleNameAndGenerics != nil && asSource.contains("nonisolated(")
	}

	/// Whether `Self` appears anywhere inside this type. Walks recursively
	/// into generics, wrappers, and composed sub-types. Used by the
	/// `@Instantiable` macro to diagnose default expressions whose type
	/// references — e.g. `Optional<Self>`, `Result<Self, E>`, `[Self]` —
	/// would resolve against the caller's scope if the default were promoted
	/// onto another type's `SafeDIOverrides` struct.
	public var containsSelf: Bool {
		namesType(where: { $0.first == "Self" })
	}

	/// Whether the receiver names a type whose path satisfies `predicate`, wherever in the receiver that type sits. A
	/// path is a named type's names from the outermost, such as `["Child", "Config"]` for `Child.Config<Int>`, and each
	/// path a nested type's path starts with is named too: `Child.Config` names `["Child"]` and `["Child", "Config"]`.
	/// So `$0.first == "Config"` finds `Config` named without qualification in `Config?`, `[String: Config]`,
	/// `Box<Config>`, `(Config) -> Void`, and `Config.Options`, and not in `Child.Config`. The text of an `unknown`
	/// type is not inspected.
	public func namesType(where predicate: ([String]) -> Bool) -> Bool {
		switch self {
		case let .simple(name, generics):
			predicate([name]) || generics.contains(where: { $0.namesType(where: predicate) })
		case let .nested(name, parentType, generics):
			parentType.namesType(where: predicate)
				|| (parentType.namePath.map { predicate($0 + [name]) } ?? false)
				|| generics.contains(where: { $0.namesType(where: predicate) })
		case let .any(wrapped),
		     let .implicitlyUnwrappedOptional(wrapped),
		     let .optional(wrapped),
		     let .some(wrapped):
			wrapped.namesType(where: predicate)
		case let .array(element):
			element.namesType(where: predicate)
		case let .dictionary(key, value):
			key.namesType(where: predicate) || value.namesType(where: predicate)
		case let .tuple(elements):
			elements.contains(where: { $0.typeDescription.namesType(where: predicate) })
		case let .composition(elements):
			elements.contains(where: { $0.namesType(where: predicate) })
		case let .closure(arguments, _, _, thrownType, returnType):
			arguments.contains(where: { $0.namesType(where: predicate) })
				|| (thrownType?.namesType(where: predicate) ?? false)
				|| returnType.namesType(where: predicate)
		case let .variadic(wrapped):
			wrapped.namesType(where: predicate)
		case let .metatype(wrapped, _):
			wrapped.namesType(where: predicate)
		case let .attributed(wrapped, _, _):
			wrapped.namesType(where: predicate)
		case .unknown, .void:
			false
		}
	}

	/// The receiver with each type it names, wherever in the receiver that type sits, nested in the type `enclosingType`
	/// returns for the type's outermost name – the name Swift looks up where the receiver is written – and every other
	/// part kept: `Theme?` becomes `Child.Theme?`, `Box<Theme>` becomes `Child.Box<Child.Theme>`, and `Inner.Palette`
	/// becomes `Child.Inner.Palette` when `enclosingType` returns `Child` for `Theme`, `Box` and `Inner`. A name after the
	/// outermost is a member of the type before it, so it is kept, as is the text of an `unknown` type.
	/// - Parameter enclosingType: Returns the type to nest a type of the given outermost name in, or `nil` to keep the
	///   name as written.
	public func nestingOutermostNames(in enclosingType: (String) -> TypeDescription?) -> TypeDescription {
		nestingOutermostNamesIfAny(in: enclosingType) ?? self
	}

	/// The receiver with each type it names nested as `nestingOutermostNames(in:)` nests it, or `nil` when
	/// `enclosingType` returns `nil` for every outermost name, so that a caller keeps the receiver without rebuilding it.
	public func nestingOutermostNamesIfAny(in enclosingType: (String) -> TypeDescription?) -> TypeDescription? {
		switch self {
		case let .simple(name, generics):
			let nestedGenerics = generics.replacingElementsIfAny { $0.nestingOutermostNamesIfAny(in: enclosingType) }
			return if let parentType = enclosingType(name) {
				.nested(name: name, parentType: parentType, generics: nestedGenerics ?? generics)
			} else {
				nestedGenerics.map { .simple(name: name, generics: $0) }
			}
		case let .nested(name, parentType, generics):
			let nestedParentType = parentType.nestingOutermostNamesIfAny(in: enclosingType)
			let nestedGenerics = generics.replacingElementsIfAny { $0.nestingOutermostNamesIfAny(in: enclosingType) }
			guard nestedParentType != nil || nestedGenerics != nil else { return nil }
			return .nested(name: name, parentType: nestedParentType ?? parentType, generics: nestedGenerics ?? generics)
		case let .composition(types):
			return Array(types).replacingElementsIfAny { $0.nestingOutermostNamesIfAny(in: enclosingType) }.map { .composition(UnorderedEquatingCollection($0)) }
		case let .optional(type):
			return type.nestingOutermostNamesIfAny(in: enclosingType).map { .optional($0) }
		case let .implicitlyUnwrappedOptional(type):
			return type.nestingOutermostNamesIfAny(in: enclosingType).map { .implicitlyUnwrappedOptional($0) }
		case let .some(type):
			return type.nestingOutermostNamesIfAny(in: enclosingType).map { .some($0) }
		case let .any(type):
			return type.nestingOutermostNamesIfAny(in: enclosingType).map { .any($0) }
		case let .metatype(type, isType):
			return type.nestingOutermostNamesIfAny(in: enclosingType).map { .metatype($0, isType: isType) }
		case let .attributed(type, specifiers, attributes):
			return type.nestingOutermostNamesIfAny(in: enclosingType).map { .attributed($0, specifiers: specifiers, attributes: attributes) }
		case let .array(element):
			return element.nestingOutermostNamesIfAny(in: enclosingType).map { .array(element: $0) }
		case let .dictionary(key, value):
			let nestedKey = key.nestingOutermostNamesIfAny(in: enclosingType)
			let nestedValue = value.nestingOutermostNamesIfAny(in: enclosingType)
			guard nestedKey != nil || nestedValue != nil else { return nil }
			return .dictionary(key: nestedKey ?? key, value: nestedValue ?? value)
		case let .tuple(elements):
			return elements
				.replacingElementsIfAny { element in
					element.typeDescription.nestingOutermostNamesIfAny(in: enclosingType).map { TupleElement(label: element.label, $0) }
				}
				.map { .tuple($0) }
		case let .closure(arguments, isAsync, doesThrow, thrownType, returnType):
			return Self.closureNestingOutermostNamesIfAny(
				arguments: arguments,
				isAsync: isAsync,
				doesThrow: doesThrow,
				thrownType: thrownType,
				returnType: returnType,
				in: enclosingType,
			)
		case let .variadic(type):
			return type.nestingOutermostNamesIfAny(in: enclosingType).map { .variadic($0) }
		case .unknown, .void:
			return nil
		}
	}

	/// The closure with these parts, with each type it names nested as `nestingOutermostNames(in:)` nests it, or `nil` when
	/// that nests nothing. It is apart from `nestingOutermostNamesIfAny(in:)` so that its locals do not add to the frame
	/// of each level of a deeply nested type, which a debug build's task stack holds at most 128 of (`BinaryReader`).
	private static func closureNestingOutermostNamesIfAny(
		arguments: [TypeDescription],
		isAsync: Bool,
		doesThrow: Bool,
		thrownType: TypeDescription?,
		returnType: TypeDescription,
		in enclosingType: (String) -> TypeDescription?,
	) -> TypeDescription? {
		let nestedArguments = arguments.replacingElementsIfAny { $0.nestingOutermostNamesIfAny(in: enclosingType) }
		let nestedThrownType = thrownType?.nestingOutermostNamesIfAny(in: enclosingType)
		let nestedReturnType = returnType.nestingOutermostNamesIfAny(in: enclosingType)
		guard nestedArguments != nil || nestedThrownType != nil || nestedReturnType != nil else { return nil }
		return .closure(
			arguments: nestedArguments ?? arguments,
			isAsync: isAsync,
			doesThrow: doesThrow,
			thrownType: nestedThrownType ?? thrownType,
			returnType: nestedReturnType ?? returnType,
		)
	}

	/// The names of a simple or nested type from the outermost, such as `["Child", "Config"]` for `Child.Config`, or
	/// `nil` for any other type, such as the `[Config]` of `[Config].Element`.
	public var namePath: [String]? {
		switch self {
		case let .simple(name, _):
			[name]
		case let .nested(name, parentType, _):
			parentType.namePath.map { $0 + [name] }
		case .any, .array, .attributed, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .optional, .some, .tuple, .unknown, .variadic, .void:
			nil
		}
	}

	/// The name of a simple type sans nesting, with associated generics.
	var simpleNameAndGenerics: (name: String, generics: [TypeDescription])? {
		switch self {
		case let .simple(name, generics),
		     let .nested(name, _, generics):
			(name, generics)
		case .any, .array, .attributed, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .optional, .some, .tuple, .unknown, .variadic, .void:
			nil
		}
	}

	/// The type literal that names this type, as `@Received(ofType:)` takes it: `Service.self`, or `(any Service).self`.
	var asTypeLiteralSource: String {
		"\(wrappedIfAmbiguous.asSource).self"
	}

	/// A representation of this type that may be wrapped in a single element tuple to ensure cohesiveness of the type description.
	private var wrappedIfAmbiguous: Self {
		switch self {
		case .void, .simple, .optional, .implicitlyUnwrappedOptional, .metatype, .nested, .array, .dictionary, .tuple, .unknown, .variadic:
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
					generics: genericTypeVisitor.genericArguments,
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
				generics: genericTypeVisitor.genericArguments,
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
				isType: typeIdentifier.metatypeSpecifier.text == "Type",
			)

		} else if let typeIdentifier = AttributedTypeSyntax(self) {
			// An attribute is kept as its tokens spell it, without the `@`: `Sendable`, `Space.Act`, `convention(c)`.
			let attributes: [String] = typeIdentifier.attributes.compactMap {
				AttributeSyntax($0)?.tokens(viewMode: .sourceAccurate).dropFirst().map(\.text).joined()
			}
			return .attributed(
				typeIdentifier.baseType.typeDescription,
				// A specifier that follows the attributes, such as `nonisolated(nonsending)`, also parses before them.
				specifiers: (typeIdentifier.specifiers.textRepresentation ?? []) + (typeIdentifier.lateSpecifiers.textRepresentation ?? []),
				attributes: attributes,
			)

		} else if let typeIdentifier = ArrayTypeSyntax(self) {
			return .array(element: typeIdentifier.element.typeDescription)

		} else if let typeIdentifier = DictionaryTypeSyntax(self) {
			return .dictionary(
				key: typeIdentifier.key.typeDescription,
				value: typeIdentifier.value.typeDescription,
			)

		} else if let typeIdentifier = TupleTypeSyntax(self) {
			let elements = typeIdentifier.elements.map {
				TypeDescription.TupleElement(
					label: ($0.secondName ?? $0.firstName)?.spelledAsParameterName,
					$0.type.typeDescription,
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
				arguments: typeIdentifier.parameters.map { parameter in
					parameter.ellipsis == nil ? parameter.type.typeDescription : .variadic(parameter.type.typeDescription)
				},
				isAsync: typeIdentifier.effectSpecifiers?.asyncSpecifier != nil,
				doesThrow: typeIdentifier.effectSpecifiers?.throwsClause?.throwsSpecifier != nil,
				thrownType: typeIdentifier.effectSpecifiers?.throwsClause?.type?.typeDescription,
				returnType: typeIdentifier.returnClause.type.typeDescription,
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
					genericArgumentClause: nil,
				),
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
					generics: [],
				)
			}
		} else if let genericExpr = GenericSpecializationExprSyntax(self) {
			let genericTypeVisitor = GenericArgumentVisitor(viewMode: .sourceAccurate)
			genericTypeVisitor.walk(genericExpr.genericArgumentClause)
			if let declReferenceExpr = DeclReferenceExprSyntax(genericExpr.expression) {
				return .simple(
					name: declReferenceExpr.baseName.text,
					generics: genericTypeVisitor.genericArguments,
				)
			} else if let memberAccessExpr = MemberAccessExprSyntax(genericExpr.expression),
			          let base = memberAccessExpr.base
			{
				return .nested(
					name: memberAccessExpr.declName.baseName.text,
					parentType: base.typeDescription,
					generics: genericTypeVisitor.genericArguments,
				)
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
						label: $0.label?.spelledAsParameterName,
						$0.expression.typeDescription,
					)
				})
			}
		} else if let sequenceExpr = SequenceExprSyntax(self) {
			if sequenceExpr.elements.contains(where: { BinaryOperatorExprSyntax($0) != nil }) {
				return .composition(UnorderedEquatingCollection(
					sequenceExpr
						.elements
						.filter { BinaryOperatorExprSyntax($0) == nil }
						.map(\.typeDescription),
				))
			} else if sequenceExpr.elements.count == 3,
			          let arguments = TupleExprSyntax(sequenceExpr.elements.first),
			          let arrow = ArrowExprSyntax(sequenceExpr.elements[
			          	sequenceExpr.elements.index(after: sequenceExpr.elements.startIndex),
			          ]),
			          let returnType = sequenceExpr.elements.last
			{
				return .closure(
					arguments: arguments.elements.map(\.expression.typeDescription),
					isAsync: arrow.effectSpecifiers?.asyncSpecifier != nil,
					doesThrow: arrow.effectSpecifiers?.throwsClause?.throwsSpecifier != nil,
					thrownType: arrow.effectSpecifiers?.throwsClause?.type?.typeDescription,
					returnType: returnType.typeDescription,
				)
			}
		} else if let optionalChainingExpr = OptionalChainingExprSyntax(self) {
			return .optional(optionalChainingExpr.expression.typeDescription)
		} else if let postfixOperatorExpr = PostfixOperatorExprSyntax(self), postfixOperatorExpr.operator.text == "..." {
			return .variadic(postfixOperatorExpr.expression.typeDescription)
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
				value: onlyElement.value.typeDescription,
			)
		}
		return .unknown(text: trimmedDescription)
	}
}

// MARK: - GenericArgumentVisitor

private final class GenericArgumentVisitor: SyntaxVisitor {
	private(set) var genericArguments = [TypeDescription]()

	override func visit(_ node: GenericArgumentSyntax) -> SyntaxVisitorContinueKind {
		if let typeSyntax = TypeSyntax(node.argument) {
			genericArguments.append(typeSyntax.typeDescription)
		} else {
			// A value generic argument, such as the `3` of `InlineArray<3, Int>`.
			genericArguments.append(.unknown(text: node.argument.trimmedDescription))
		}
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

extension Array {
	/// This array with each element that `replacement` returns a value for replaced by that value, or `nil` when it
	/// returns `nil` for every element, so that a caller keeps the array without copying it.
	fileprivate func replacingElementsIfAny(_ replacement: (Element) -> Element?) -> [Element]? {
		var replacedElements: [Element]?
		for index in indices {
			if let replacedElement = replacement(self[index]) {
				if replacedElements == nil {
					replacedElements = self
				}
				replacedElements?[index] = replacedElement
			}
		}
		return replacedElements
	}
}
