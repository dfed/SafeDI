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

/// What building an `@Instantiable` type needs when every dependency it receives is provided beside it, which is
/// what the type's `mock()` does: the declarations that build it and its dependencies, and the values a caller
/// has to pass. `SafeDITool query` reports it twice, over the declarations with every hand-written mock removed
/// for what the type needs in production, and over every declaration for what its mock needs, so that a project
/// can be assembled from exactly the modules one type needs. See
/// `DependencyTreeGenerator.requirements(forTypeNamed:generatesMock:)`.
public struct TypeRequirements: Equatable, Sendable {
	// MARK: Initialization

	public init(
		typeDescription: TypeDescription,
		declarations: [Declaration],
		erasures: [Erasure],
		forwardedParameters: [ForwardedParameter],
		requiredParameters: [RequiredParameter],
	) {
		self.typeDescription = typeDescription
		self.declarations = declarations
		self.erasures = erasures
		self.forwardedParameters = forwardedParameters
		self.requiredParameters = requiredParameters
	}

	// MARK: Public

	/// The concrete type these are the requirements of.
	public let typeDescription: TypeDescription
	/// The declarations that build the type and its dependencies, each once, in the order they are reached: the
	/// type's own declarations, then those of every dependency built beside it, then the hand-written mocks that
	/// default its `@Forwarded` parameters. Built from these declarations alone, the type takes no value but
	/// `forwardedParameters` and `requiredParameters`.
	public let declarations: [Declaration]
	/// The received properties built by erasing a concrete type, because no `@Instantiable` declaration
	/// fulfills the property's type. Each is built only where one of its declarations is visible.
	public let erasures: [Erasure]
	/// The `@Forwarded` dependencies of the type, which are parameters of `mock()` in this order.
	public let forwardedParameters: [ForwardedParameter]
	/// The values that no declaration anywhere provides, which a caller passes, in the order `mock()` declares
	/// them as parameters.
	public let requiredParameters: [RequiredParameter]

	/// A declaration that builds the type or one of its dependencies.
	public struct Declaration: Hashable, Sendable {
		public init(typeDescription: TypeDescription, sourceFilePath: String?, kind: Kind) {
			self.typeDescription = typeDescription
			self.sourceFilePath = sourceFilePath
			self.kind = kind
		}

		/// The concrete type the declaration is of.
		public let typeDescription: TypeDescription
		/// The file that holds the declaration, as `Instantiable.sourceFilePath` and
		/// `Instantiable.mockDeclarationLocation` record it.
		public let sourceFilePath: String?
		public let kind: Kind

		public enum Kind: Hashable, Sendable {
			/// The `@Instantiable` declaration of the type, built with `init` or `instantiate()` unless a
			/// hand-written mock is also listed for the type.
			case instantiable
			/// The hand-written mock method that builds the type: `customMockName`, or `mock` on a `mockOnly` declaration.
			case handWrittenMock(methodName: String)
		}
	}

	/// A received property built from a concrete type that an `@Instantiated(erasedToConcreteExistential: true)`
	/// property erases to the received type.
	public struct Erasure: Equatable, Sendable {
		public init(property: Property, concreteType: TypeDescription, declarations: [Declaration]) {
			self.property = property
			self.concreteType = concreteType
			self.declarations = declarations
		}

		/// The received property, built beside the type.
		public let property: Property
		/// The concrete type built and wrapped in the property's type.
		public let concreteType: TypeDescription
		/// The declarations that erase `concreteType` to the property's type, ordered by declaring type and then
		/// by property. The property is built wherever any one of them is visible.
		public let declarations: [Declaration]

		public struct Declaration: Hashable, Sendable {
			public init(declaringType: TypeDescription, property: Property, sourceFilePath: String?) {
				self.declaringType = declaringType
				self.property = property
				self.sourceFilePath = sourceFilePath
			}

			/// The `@Instantiable` type that declares the erasing property.
			public let declaringType: TypeDescription
			/// The `@Instantiated(erasedToConcreteExistential: true)` property.
			public let property: Property
			/// The file that declares `declaringType`.
			public let sourceFilePath: String?
		}
	}

	/// A `@Forwarded` dependency of the type, which is a parameter of `mock()`.
	public struct ForwardedParameter: Equatable, Sendable {
		public init(label: String, typeDescription: TypeDescription, defaultExpression: String?) {
			self.label = label
			self.typeDescription = typeDescription
			self.defaultExpression = defaultExpression
		}

		public let label: String
		public let typeDescription: TypeDescription
		/// The parameter's default: the construction initializer's, or a call of a hand-written mock of the
		/// type that takes no arguments. `nil` when the caller must pass the parameter.
		public let defaultExpression: String?
	}

	/// A value no `@Instantiable` declaration provides, which `mock()` takes as a parameter.
	public struct RequiredParameter: Equatable, Sendable {
		public init(label: String, typeSource: String, reason: Reason) {
			self.label = label
			self.typeSource = typeSource
			self.reason = reason
		}

		/// The label of the dependency, which `mock()` may suffix with the type when another parameter shares it.
		public let label: String
		/// The parameter's type as `mock()` spells it.
		public let typeSource: String
		public let reason: Reason

		public enum Reason: Equatable, Sendable {
			/// No `@Instantiable` declaration fulfills the type, and nothing erases a single concrete type to it.
			case noInstantiableFulfillsType(TypeDescription)
			/// The type's `@Instantiable` declaration has `@Forwarded` properties, so only an `Instantiator` handed
			/// the forwarded values can build it, as in production.
			case typeHasForwardedProperties(TypeDescription, forwardedProperties: [Property])
			/// Properties erase more than one concrete type to the type, so nothing says which one to build.
			case erasedToMultipleConcreteTypes(TypeDescription, concreteTypes: [TypeDescription])
		}
	}
}
