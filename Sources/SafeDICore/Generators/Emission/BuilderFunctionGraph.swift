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

// The plan of a generated body (a root's `init()`, a seam's initializer, a `mock()`), which kept code decides and one
// spelling per kind of statement writes. Every type here is a value, so a plan built on one task can be read on
// another. Today's emitter builds the pieces it spells through them: a root's body, hosted as the text its children
// generate; the builder functions of a constant, an instantiator and a lazy wrapper; and a constant's binding. A
// statement kind, an expression kind or an argument source arrives with the first code that plans one.

/// One generated body: its statements in the order the body writes them.
struct BuilderFunctionGraph: Sendable {
	let body: [Statement]

	/// The body's code: each statement's, on lines of its own.
	var spelled: GeneratedCode {
		.lines(body.map(\.spelled))
	}
}

/// One line, or one block, a body writes, with one spelling for each kind.
indirect enum Statement: Sendable {
	/// The `func` block of a builder function, its closing line ended.
	case function(BuilderNode)
	/// `let label[: Type] = value`, and what ends its line.
	case binding(BindingDeclaration, Expression, lineEnd: String)
	/// Code an emitter that is not planned yet generated, hosted in a planned body as it is.
	case verbatim(GeneratedCode)

	var spelled: GeneratedCode {
		switch self {
		case let .function(node):
			node.spelled()
		case let .binding(declaration, value, lineEnd):
			.text("\(declaration.spelled) = \(value.spelled)\(lineEnd)")
		case let .verbatim(code):
			code
		}
	}
}

/// One local function SafeDI writes: a builder function, which constructs the value of one place.
struct BuilderNode: Sendable {
	/// The function's name, from its body's naming policy.
	let name: String
	/// Whether the function is written `@Sendable`.
	let isSendable: Bool
	/// Whether a `@Sendable` function is also written `nonisolated` (`ScopeGenerator.localFunctionPrefix`).
	let isNonisolated: Bool
	/// In order: the forwarded properties, sorted, then the cycle parameters, in the order the body first receives them.
	let parameters: [Property]
	/// The types a parameter is declared `@escaping` for (`ScopeGenerator.typesDeclaredEscaping`).
	let typesDeclaredEscaping: Set<TypeDescription>
	/// The concrete type the function returns.
	let returnType: TypeDescription
	/// The statements before the value.
	let body: BuilderBody
	/// The value the function returns: its place's construction.
	let value: Expression
	/// What ends the line that returns the value.
	let lineEnd: String

	/// The `func` block, its closing line ended, between `prefix` and `suffix`. A body without statements still writes the
	/// line they would take, as builder functions always have: the scope above drops it where it indents the block.
	///
	/// The block holds its statements' code, which holds its scope's whole subtree, as it is: no text of the subtree is
	/// copied to write the block.
	func spelled(after prefix: String = "", followedBy suffix: String = "") -> GeneratedCode {
		let parameterList = parameters.isEmpty ? "" : parameters.initializerFunctionParameters(amongTypesDeclaredEscaping: typesDeclaredEscaping).map(\.description).joined()
		return .sequence([
			.text("\(prefix)\(ScopeGenerator.localFunctionPrefix(isSendable: isSendable, isNonisolated: isNonisolated))func \(name)(\(parameterList)) -> \(returnType.asSource) {\n"),
			.lines(body.statements),
			.text("\n\(ScopeGenerator.standardIndent)\(body.returnKeyword)\(value.spelled)\(lineEnd)\n}\n\(suffix)"),
		])
	}
}

/// What makes two places the same builder function.
///
/// Equality is a projection, as `CLAUDE.md`'s "Compare for meaning through a projection" requires, and the synthesized
/// conformance is that projection: `built` and `form` hold `TypeDescription`s, never `Instantiable`s; `place` holds only a
/// walk index; `plan` only a class index. No field carries diagnostic payload; a field added later that does compares
/// through its own projection, or the conformance is written out.
///
/// With `place` set, every key is unique, so every place has a function of its own and output is today's. Without it,
/// two places share a function where every other field agrees. Nothing builds a key yet: the production emitter does
/// once it numbers its places.
struct BuilderKey: Hashable, Sendable {
	/// The concrete type, and how it is constructed.
	let built: ConstructionTarget
	/// The form the place provides its value in.
	let form: ProvidedForm
	/// Plain or `@Sendable`.
	let family: Family
	/// The labels the function reads and does not bind, transitively, one per label, in first-read order.
	let reads: [String]
	/// Mocks only: whether the function takes its own configuration.
	let readsConfiguration: Bool
	/// The class of the place's plan, with names abstracted away.
	let plan: PlanClass
	/// The place, where every place keeps a function of its own; `nil` where places share functions.
	let place: PlaceIdentity?
}

/// The form a place provides its value in, and the type an erased instantiator erases to.
struct ProvidedForm: Hashable, Sendable {
	let kind: Kind
	/// The type an `ErasedInstantiator` or `SendableErasedInstantiator` erases to; `nil` for every other form.
	let erasedToType: TypeDescription?

	/// `Property.PropertyType`'s cases, as a `Sendable` value.
	enum Kind: Hashable, Sendable {
		case constant
		case instantiator
		case erasedInstantiator
		case sendableInstantiator
		case sendableErasedInstantiator
		case lazilyInstantiated
		case sendableLazilyInstantiated
	}
}

/// Whether a place is in the `@Sendable` family: it is when its own builder function, or any builder function enclosing it
/// up to the body's root, is `@Sendable`. A family is not a decorator: `BuilderNode.isSendable` is.
enum Family: Hashable, Sendable {
	case plain
	case sendable
}

/// A place's first-reach index in its body's ordered walk (ordered children, depth first). Never a scope's or a
/// generator's identity, which places can share.
struct PlaceIdentity: Hashable, Sendable {
	let firstReachIndex: Int
}

/// The index of a class of places whose plans agree once names are abstracted away.
struct PlanClass: Hashable, Sendable {
	let index: Int
}
