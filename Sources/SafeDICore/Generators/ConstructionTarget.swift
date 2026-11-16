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

/// What generated code calls to construct a type: its initializer, an extension-based type's `instantiate(…)`, or a mock
/// method. Every call SafeDITool generates of one of these, in production trees, seams, fills and mocks, is spelled
/// through it, so the call takes one form wherever the type is built. Two constructions are not: the construction
/// function a public mock declares in the configured type's extension (`__safeDI_init`, `__safeDI_mock`), a generated
/// function rather than one of the type's, and the macro's fix-its, which the macro target spells without `Generators/`.
enum ConstructionTarget: Hashable, Sendable {
	/// The type's initializer: `T(…)`.
	case initializer
	/// An extension-based type's `instantiate(…)`: `T.instantiate(…)`.
	case instantiate
	/// A mock method, generated or hand-written: `T.mock(…)`, or `T.<customMockName>(…)`.
	case mock(methodName: String)

	/// The target that constructs a type with its mock method named `mockMethodName` when there is one, and otherwise
	/// with its `instantiate(…)` when it is extension-based, else with its initializer.
	init(mockMethodName: String?, isExtensionBased: Bool) {
		self = if let mockMethodName {
			.mock(methodName: mockMethodName)
		} else if isExtensionBased {
			.instantiate
		} else {
			.initializer
		}
	}

	/// What a call of this target names before its argument list, for `concreteType`: `T`, `T.instantiate` or `T.mock`.
	func callee(constructing concreteType: TypeDescription) -> String {
		switch self {
		case .initializer:
			concreteType.asSource
		case .instantiate:
			"\(concreteType.asSource).\(InstantiableVisitor.instantiateMethodName)"
		case let .mock(methodName):
			"\(concreteType.asSource).\(methodName)"
		}
	}

	/// The call that constructs `concreteType` with `arguments`, already labeled and joined.
	func call(constructing concreteType: TypeDescription, arguments: String) -> String {
		"\(callee(constructing: concreteType))(\(arguments))"
	}
}

extension TypeDescription {
	/// `expression` erased to this type, as `erasedToConcreteExistential: true` asks: `AnyService(expression)`.
	func erasing(_ expression: String) -> String {
		"\(asSource)(\(expression))"
	}
}
