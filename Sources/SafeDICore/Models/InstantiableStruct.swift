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

public struct Instantiable: Codable, Hashable, Sendable {
	// MARK: Initialization

	public init(
		instantiableType: TypeDescription,
		isRoot: Bool,
		initializer: Initializer?,
		additionalInstantiables: [TypeDescription]?,
		dependencies: [Dependency],
		declarationType: DeclarationType,
		mockAttributes: String = "",
		generateMock: Bool = false,
		mockOnly: Bool = false,
		mockInitializer: Initializer? = nil,
		mockReturnType: TypeDescription? = nil,
		customMockName: String? = nil,
		mockDeclarationLocation: Dependency.DeclarationLocation? = nil,
		declarationLocation: Dependency.DeclarationLocation? = nil,
	) {
		instantiableTypes = [instantiableType] + (additionalInstantiables ?? [])
		self.declarationLocation = declarationLocation
		self.isRoot = isRoot
		self.initializer = initializer
		self.dependencies = dependencies
		self.declarationType = declarationType
		self.mockAttributes = mockAttributes
		self.generateMock = generateMock
		self.mockOnly = mockOnly
		self.mockInitializer = mockInitializer
		self.mockReturnType = mockReturnType
		self.customMockName = customMockName
		self.mockDeclarationLocation = mockDeclarationLocation
	}

	// MARK: Public

	/// The types that can be fulfilled with this Instantiable.
	public let instantiableTypes: [TypeDescription]
	/// The concrete type that fulfills `instantiableTypes`.
	public var concreteInstantiable: TypeDescription {
		instantiableTypes[0]
	}

	/// Whether the instantiable type is a root of a dependency graph.
	public let isRoot: Bool
	/// A memberwise initializer for the concrete instantiable type.
	/// If `nil`, the Instantiable type is incorrectly configured.
	public let initializer: Initializer?
	/// The ordered dependencies of this Instantiable.
	public private(set) var dependencies: [Dependency]
	/// The declaration type of the Instantiable’s concrete type.
	public let declarationType: DeclarationType
	/// Attributes to add to the generated `mock()` method (e.g. `"@MainActor"`).
	public let mockAttributes: String
	/// Whether to generate a `mock()` method for this type.
	public let generateMock: Bool
	/// Whether this declaration exists solely for mock generation (user provides a hand-written mock method).
	/// When `true`, no `init`/`instantiate()` or `Instantiable` conformance is required.
	public let mockOnly: Bool
	/// A user-defined `static func mock(...)` method, if one exists.
	/// When present, mock generation calls this method instead of `init` or `instantiate`.
	public var mockInitializer: Initializer?
	/// The return type of the user-defined `mock()` method, if one exists.
	/// Used to determine whether to use the mock method or fall through to `init` based on the property type.
	public var mockReturnType: TypeDescription?
	/// The name of the user's custom mock method. With `generateMock`, the generated `mock()` calls
	/// through to this method. With `mockOnly`, SafeDI uses this method as the mock provider.
	public var customMockName: String?
	/// Where the user-defined mock method begins in source: its first attribute or modifier. Travels with
	/// `mockInitializer` when a `mockOnly` declaration's mock is merged into a production entry, so diagnostics
	/// about the hand-written mock point at the method rather than at the production declaration.
	public var mockDeclarationLocation: Dependency.DeclarationLocation?

	/// Returns a copy of this Instantiable with mock-related fields replaced by those from `mockProvider`.
	/// Used when merging a production `@Instantiable` with a `mockOnly` declaration for the same type.
	public func mergedWithMockProvider(_ mockProvider: Instantiable) -> Instantiable {
		var merged = self
		merged.mockInitializer = mockProvider.mockInitializer
		merged.mockReturnType = mockProvider.mockReturnType
		merged.customMockName = mockProvider.customMockName
		merged.mockDeclarationLocation = mockProvider.mockDeclarationLocation
		return merged
	}

	/// The dependencies `handWrittenMock`, this type's hand-written mock, is not passed. A generated mock passes
	/// a dependency to the argument that shares its label, so these are the dependencies whose label no argument
	/// has. A mock method declared with the type takes every dependency, so only one merged in from a `mockOnly`
	/// declaration leaves any out. A `@Forwarded` dependency is never left out: it is an argument of the type's
	/// `Instantiator` whatever the mock method does with it.
	public func dependenciesNotPassed(to handWrittenMock: Initializer) -> [Dependency] {
		let argumentLabels = Set(handWrittenMock.arguments.map(\.innerLabel))
		return dependencies.filter { $0.source != .forwarded && !argumentLabels.contains($0.property.label) }
	}

	/// Returns a copy of this Instantiable that declares only the dependencies `isKept` accepts.
	public func keepingDependencies(where isKept: (Dependency) -> Bool) -> Instantiable {
		var instantiable = self
		instantiable.dependencies = dependencies.filter(isKept)
		return instantiable
	}

	/// Whether the user-defined mock() method's return type is compatible with the given property type.
	/// Returns `true` when the mock returns the concrete type, `Self`, or the exact property type.
	/// Returns `false` when there is no mock method.
	public func mockReturnTypeIsCompatible(withPropertyType propertyType: TypeDescription) -> Bool {
		guard let mockReturnType else { return false }
		return mockReturnType == propertyType
			|| mockReturnType == concreteInstantiable
			|| mockReturnType == .simple(name: "Self", generics: [])
	}

	/// The path to the source file that declared this Instantiable, as the build system supplied it.
	/// `scan` rewrites it to a project-relative form so cached module info matches manifest entries;
	/// `declarationLocation.filePath` keeps the path exactly as parsed for diagnostics.
	public var sourceFilePath: String?
	/// Where the decorated declaration begins in source: its first attribute, as for `Dependency.declarationLocation`.
	/// `nil` only when the declaration was parsed without a file context – macro expansion walks a detached
	/// declaration – and such values never reach the dependency tree generator, which only consumes
	/// instantiables that `SafeDITool` parsed from files.
	public let declarationLocation: Dependency.DeclarationLocation?

	/// The type of declaration where this Instantiable was defined.
	public enum DeclarationType: Codable, Hashable, Sendable {
		case classType
		case actorType
		case structType
		case extensionType

		public var isExtension: Bool {
			switch self {
			case .extensionType:
				true
			case .actorType, .classType, .structType:
				false
			}
		}
	}
}

extension [Instantiable] {
	/// Orders instantiables by source file path while keeping each file's declarations in
	/// the order they appear in that file. Parsing runs in parallel, so without this the
	/// order in which instantiables reach `resolveSafeDIFulfilledTypes` would depend on
	/// which file finished parsing first. Sorted once per parsed module; serialized
	/// module info keeps the order, so consumers never need to sort again.
	public func sortedByDeclaration() -> [Instantiable] {
		enumerated()
			.sorted { lhs, rhs in
				(lhs.element.sourceFilePath ?? "", lhs.offset) < (rhs.element.sourceFilePath ?? "", rhs.offset)
			}
			.map(\.element)
	}
}
