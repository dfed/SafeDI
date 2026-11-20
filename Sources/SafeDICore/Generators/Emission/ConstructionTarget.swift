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

/// What a builder function or a binding constructs, and the function its construction calls.
enum ConstructionTarget: Hashable, Sendable {
	/// `Concrete(…)`.
	case initializer(TypeDescription)
	/// `Concrete.instantiate(…)`: a type declared through an extension.
	case instantiate(TypeDescription)
	/// A mock method of `Concrete`, by name: `mock`, a `customMockName`, or the function of a public mock's tier.
	case mock(TypeDescription, name: String)

	/// The function the construction calls, spelled through `TypeDescription`: the concrete type itself for an
	/// initializer, and the method as a member of the concrete type otherwise.
	var callee: String {
		switch self {
		case let .initializer(concreteType):
			concreteType.asSource
		case let .instantiate(concreteType):
			TypeDescription.nested(name: InstantiableVisitor.instantiateMethodName, parentType: concreteType, generics: []).asSource
		case let .mock(concreteType, name):
			TypeDescription.nested(name: name, parentType: concreteType, generics: []).asSource
		}
	}
}
