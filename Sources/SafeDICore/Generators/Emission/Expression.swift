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
	/// one hook through which a body that can be configured (a `mock()`) replaces a construction. The expression has the
	/// override's type: a builder that returns the constructed type is wrapped in `overrideErasure`'s eraser where the
	/// property is erased, as `expression` is.
	case overridable(Expression, override: String, arguments: String, overrideErasure: TypeDescription?)

	/// How generated code spells the expression.
	var spelled: String {
		switch self {
		case let .construction(target, arguments):
			"\(target.callee)(\(arguments))"
		case let .call(function, arguments):
			"\(function)(\(arguments))"
		case let .erasure(expression, erasedType):
			"\(erasedType.asSource)(\(expression.spelled))"
		case let .overridable(expression, override, arguments, overrideErasure):
			"if let \(ReservedName.configurationBuilderPropertyName) = \(override) { \(Expression.call(function: ReservedName.configurationBuilderPropertyName, arguments: arguments).erased(to: overrideErasure).spelled) } else { \(expression.spelled) }"
		}
	}

	/// This expression, replaced where `override` holds a builder: a value the property holds, erased to `erasedType` where
	/// `isErased`, which a builder that returns the constructed type is erased to as well.
	func erasedAndOverridden(by override: ConstructionOverride, to erasedType: TypeDescription, where isErased: Bool) -> Expression {
		.overridable(
			erased(to: erasedType, where: isErased),
			override: override.expression,
			arguments: override.arguments,
			overrideErasure: isErased && override.returnsConstructedType ? erasedType : nil,
		)
	}

	/// This expression wrapped in the eraser of `erasedType`, where there is one.
	private func erased(to erasedType: TypeDescription?) -> Expression {
		erasedType.map { .erasure(self, as: $0) } ?? self
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
	/// Whether the builder returns the constructed type rather than the value the property holds: a configuration's
	/// builder, whose result is erased as the construction's is.
	var returnsConstructedType = false
}

/// The overrides of one place of a configurable body and of the places beneath it, which the emitter descends by child
/// index (`ScopeGenerator.OrderedChild.index`): one generator can sit at several places, each with its own overrides.
struct ConstructionOverrides: Sendable {
	/// The override of this place's construction, where it is replaced.
	var construction: ConstructionOverride?
	/// This place's naming policy: the names it binds and reads where they are not its labels.
	var names: ScopeNames?
	/// The overrides of the places beneath this one, by their index among its scope's `propertiesToGenerate`.
	var children = [Int: ConstructionOverrides]()

	/// The overrides of the place beneath this one at `childIndex`, empty where it has none.
	func child(at childIndex: Int) -> ConstructionOverrides {
		children[childIndex] ?? ConstructionOverrides()
	}
}

/// The names one scope of a configurable body binds and reads where they differ from its labels: a body whose siblings
/// share a label names them apart, and a receiver beneath reads the name its label resolves to.
struct ScopeNames: Hashable, Sendable {
	/// The name the scope binds its value under, where it is not the property's label.
	var bindingName: String?
	/// The lines that bind each label the scope reads again from the name it resolves to, at the top of its builder function.
	var rebindingLines: [String] = []
	/// The name the construction reads for each label it is passed by name.
	var argumentNameByLabel: [String: String] = [:]
	/// The lines before the scope's builder function: the reads of overrides into locals an outermost `@Sendable`
	/// function captures in their place.
	var preludeLines: [String] = []
}
