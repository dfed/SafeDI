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
	) {
		instantiableTypes = [instantiableType] + (additionalInstantiables ?? [])
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
	public let dependencies: [Dependency]
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
	/// When present, generated mocks call `TypeName.mock(...)` instead of `TypeName(...)`.
	public var mockInitializer: Initializer?
	/// The return type of the user-defined `mock()` method, if one exists.
	/// Used to determine whether to call `.mock` or fall through to `init` based on the property type.
	public var mockReturnType: TypeDescription?
	/// The name of the user's custom mock method when `generateMock` is `true`.
	/// The generated `mock()` calls through to this method instead of `init`.
	public let customMockName: String?

	/// Whether the user-defined mock() method's return type is compatible with the given property type.
	/// Returns `true` when the mock returns the concrete type, `Self`, or the exact property type.
	/// Returns `false` when there is no mock method.
	public func mockReturnTypeIsCompatible(withPropertyType propertyType: TypeDescription) -> Bool {
		guard let mockReturnType else { return false }
		return mockReturnType == propertyType
			|| mockReturnType == concreteInstantiable
			|| mockReturnType == .simple(name: "Self", generics: [])
	}

	/// The path to the source file that declared this Instantiable.
	public var sourceFilePath: String?

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
