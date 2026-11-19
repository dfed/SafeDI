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

/// A value generated code writes, with one spelling for each kind.
indirect enum Expression: Hashable, Sendable {
	/// A construction: the target's function called with `arguments`, spelled as the call's argument list.
	case construction(ConstructionTarget, arguments: String)
	/// A call of the builder function named `function`, with `arguments` spelled as the call's argument list.
	case call(function: String, arguments: String)
	/// `expression` wrapped in the eraser of `erasedType`: the type an `erasedToConcreteExistential` property is
	/// declared as, or the type an erased wrapper builds.
	case erasure(Expression, as: TypeDescription)
	/// `expression`, unless the optional builder `override` holds a function, which is then called with `arguments`: the
	/// one hook through which a body that can be configured (a `mock()`) replaces a construction.
	case overridable(Expression, override: String, arguments: String)

	/// How generated code spells the expression.
	var spelled: String {
		switch self {
		case let .construction(target, arguments):
			"\(target.callee)(\(arguments))"
		case let .call(function, arguments):
			"\(function)(\(arguments))"
		case let .erasure(expression, erasedType):
			"\(erasedType.asSource)(\(expression.spelled))"
		case let .overridable(expression, override, arguments):
			"if let \(ReservedName.configurationBuilderPropertyName) = \(override) { \(ReservedName.configurationBuilderPropertyName)(\(arguments)) } else { \(expression.spelled) }"
		}
	}

	/// This expression, replaced where `override` holds a builder.
	func overridden(by override: ConstructionOverride?) -> Expression {
		guard let override else { return self }
		return .overridable(self, override: override.expression, arguments: override.arguments)
	}

	/// This expression wrapped in the eraser of `erasedType` where `isErased`, and otherwise itself.
	func erased(to erasedType: TypeDescription, where isErased: Bool) -> Expression {
		isErased ? .erasure(self, as: erasedType) : self
	}
}

/// What a configurable body consults before it constructs one place: the optional builder, and the values it is handed.
struct ConstructionOverride: Hashable, Sendable {
	/// The expression that reads the optional builder.
	let expression: String
	/// The builder's arguments, spelled as the call's argument list.
	let arguments: String
}

/// The overrides of one configurable body, keyed by the scope whose construction each replaces.
struct ConstructionOverrides: Sendable {
	let byScope: [ObjectIdentifier: ConstructionOverride]
}
