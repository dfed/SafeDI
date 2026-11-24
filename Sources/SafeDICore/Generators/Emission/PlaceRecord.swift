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

/// What the type key (`TypeKeyBody`) reads of one place of a production body's walk, recorded where the path key's emitter
/// writes the place: enough to spell the place again in the type key's layout, and to check that layout against the path
/// key's. A place the emitter writes with anything the type key does not plan yet – a seam's call or hosted code, a fill, a
/// public mock's call, a hand-written mock, a member of a loop of builders, a payload binding – records nothing, and its
/// root keeps the path key's body.
enum PlaceRecord: Sendable {
	/// A property the place builds: by a builder function of its own, or, for a constant whose function would write nothing
	/// but its value, in place.
	case built(BuiltPlaceRecord)
	/// A scope that closes a cycle on the function of an enclosing place.
	case closer(ClosingPlaceRecord)
	/// A rename of a value.
	case alias(AliasPlaceRecord)
}

/// A read a construction or a call makes: the argument it passes, the label it reads, the property its receiver declares,
/// and where the path key reads it from.
struct PlaceRead: Sendable {
	/// The argument's label at the call.
	let argumentLabel: String
	/// The label the argument reads.
	let label: String
	/// The property the receiver declares.
	let property: Property
	/// Where the path key reads the value: the nearest declaration of `label`, its lazy wrapper's instance, or `nil`.
	let source: ArgumentSource
	/// Whether the value cannot cross into a `@Sendable` function, so that no function sharing puts its read in one
	/// captures it.
	var staysOutsideSendableFunctions = false
}

/// A place that builds `property`.
struct BuiltPlaceRecord: Sendable {
	let property: Property
	let isErased: Bool
	let concreteType: TypeDescription
	/// Whether the built type is declared through an extension, which decides how its bindings are annotated.
	let isExtension: Bool
	let target: ConstructionTarget
	/// The construction's arguments, in the initializer's order.
	let arguments: [PlaceRead]
	/// The properties the place's wrapper forwards, sorted.
	let forwardedProperties: [Property]
	/// The parameters the path key's function takes for a lazy cycle that closes on it.
	let cycleParameters: [Property]
	/// What the place's binding passes those parameters.
	let callCycleArguments: [PlaceRead]
	/// The path key's name of the place's function.
	let functionName: String
	let isSendable: Bool
	let typesDeclaredEscaping: Set<TypeDescription>
	/// What ends the line that constructs the type.
	let lineEnd: String
	/// Whether the place declares a builder function: `false` only for a constant built in place.
	let hasFunction: Bool
	/// The code of the places the function's body builds, in order.
	let children: [GeneratedCode]
	/// The place's code as one node of the plan: made once each time a generator writes its code for a context, and
	/// shared by every place that reads that code from the generator's cache.
	let node: PlanNode
	/// The values the place's function is handed on every call (`PassedArgument`), after `cycleParameters`.
	var passedArguments = [PassedArgument]()
	/// Where set, the construction calls this member of a value it reads in place of `target`.
	var calledMember: CalledMember?
	/// The optional closures the construction tries first, in order, before calling `target` or `calledMember`.
	var alternatives = [ConstructionAlternative]()
}

/// The identity of one node of a root's plan (`BuiltPlaceRecord.node`), compared by identity.
final class PlanNode: Hashable, Sendable {
	static func == (lhs: PlanNode, rhs: PlanNode) -> Bool {
		lhs === rhs
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(ObjectIdentifier(self))
	}
}

/// A place that closes a cycle on the function the path key names `closedOnFunctionName`.
struct ClosingPlaceRecord: Sendable {
	let property: Property
	let isErased: Bool
	/// Whether the type the closed-on function builds is declared through an extension.
	let isExtension: Bool
	let closedOnFunctionName: String
	/// The properties the place's wrapper forwards, sorted.
	let forwardedProperties: [Property]
	/// What the place passes the parameters of the function it calls.
	let cycleArguments: [PlaceRead]
	/// What the place hands the passed arguments of the function it calls (`BuiltPlaceRecord.passedArguments`), in order.
	var passedArguments = [PassedArgument]()
}

/// A rename of a value, written as the path key writes it.
struct AliasPlaceRecord: Sendable {
	let property: Property
	/// The property the rename reads, or `nil` where it is bound to `nil`.
	let fulfillingProperty: Property?
	/// The rename's code, its lines unindented.
	let text: String
}

/// A value reached from a declaration by members: what a passed argument or an alternative reads.
indirect enum ValuePath: Hashable, Sendable {
	/// A declaration at the root's top (`RootDeclarationRecord`), which a function that reads it captures.
	case rootDeclaration(String)
	/// A passed argument of the enclosing function, by its parameter's name, which the function is handed on every call.
	case passedArgument(String)
	/// The member `name` of a value.
	case member(String, of: ValuePath)
	/// The member `name` of an optional value, read through the optional.
	case optionalMember(String, of: ValuePath)
}

/// A value a call hands the function it calls on every call, which the function never captures: places that share one
/// function can each be handed another value. A call spells it from the values it reads itself (`ValuePath`), so it is a
/// read of every call site that the engine checks as it checks a `PlaceRead`, and part of a place's structural key only
/// through its parameter's name and type.
struct PassedArgument: Hashable, Sendable {
	/// The parameter's name in the called function.
	let parameterName: String
	/// The parameter's type.
	let type: TypeDescription
	/// The value the call hands it.
	let value: ValuePath
}

/// A member of a value the place reads, which its construction calls (`<value>.<name>(<arguments>)`).
struct CalledMember: Sendable {
	/// The value whose member is called.
	let value: ValuePath
	let name: String
	/// The type the member returns, where it differs from the place's: the place wraps it in its property's type.
	let wrappedIn: TypeDescription?
}

/// An optional closure a construction tries before its call: `if let <bindingName> = <closure>, <each absent> == nil {
/// <closure's result> } else <the next alternative, or the call>`.
struct ConstructionAlternative: Sendable {
	/// The closure.
	let closure: ValuePath
	/// The name the closure is bound to where it is optional; `nil` where it is not, and is used as read.
	let bindingName: String?
	/// Values that must be `nil` for the closure to be used.
	let requiresAbsent: [ValuePath]
	/// How the closure gives the place's value.
	let use: Use
	/// The type the closure's result is wrapped in, as the call's result is erased; `nil` where it returns the value.
	let resultWrapper: TypeDescription?

	enum Use: Hashable, Sendable {
		/// Called with the values of the construction's arguments, by position.
		case calledWithConstructionArguments
		/// Called with no arguments.
		case calledWithNoArguments
		/// Handed to the place's wrapper of this type, which calls it with what it forwards.
		case wrapped(in: TypeDescription)
	}
}

/// A value a root binds at its top that is no place. The engine reads it as a declaration of the root, which every
/// function that reads it captures; it never moves.
struct RootDeclarationRecord: Sendable {
	let property: Property
	/// The name the root binds it as: its label, or a name apart from it.
	let bindingName: String
	/// Whether the value cannot cross into a `@Sendable` function.
	let staysOutsideSendableFunctions: Bool
	/// The statement, its lines unindented.
	let text: String
}
