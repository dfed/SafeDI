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

import Foundation

/// Stage D1, lane D: the mocked type's own construction, through its hand-written mock where it has one, as
/// `generateMockRootCode` builds it: the call of the mock, its `instantiate()` or its initializer, and the type the mock
/// returns.
extension MockLowering {
	/// The construction `mock()` returns: `instantiable`'s hand-written mock, its `instantiate(…)` or its initializer,
	/// called with `argumentList`.
	static func rootConstruction(of instantiable: Instantiable, argumentList: String) -> String {
		let typeName = instantiable.concreteInstantiable.asSource
		return if instantiable.mockInitializer != nil {
			"\(typeName).\(instantiable.customMockName ?? InstantiableVisitor.mockMethodName)(\(argumentList))"
		} else if instantiable.declarationType.isExtension {
			"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
		} else {
			"\(typeName)(\(argumentList))"
		}
	}

	/// The initializer whose arguments `mock()` passes the mocked type's construction: its hand-written mock's, else its
	/// initializer's.
	static func rootConstructionInitializer(of instantiable: Instantiable) -> Initializer? {
		instantiable.mockInitializer ?? instantiable.initializer
	}

	/// The type `mock()` returns: what the hand-written mock returns, else the type itself.
	static func rootReturnType(of instantiable: Instantiable) -> String {
		(instantiable.mockCallReturnType ?? instantiable.concreteInstantiable).asSource
	}
}
