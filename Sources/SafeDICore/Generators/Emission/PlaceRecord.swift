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

extension PlaceRecord {
	/// The property the place binds.
	var boundProperty: Property {
		switch self {
		case let .built(record):
			record.property
		case let .closer(record):
			record.property
		case let .alias(record):
			record.property
		}
	}
}

/// A read a construction or a call makes: the argument it passes, the label it reads, the property its receiver declares,
/// and where the path key reads it from.
struct PlaceRead: Hashable, Sendable {
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
	/// What a place records beyond a call of its target, held in one box that most places leave `nil`, so a record stays
	/// as small to copy as one that holds none of it.
	var sharingFields: PlaceSharingFields?
	/// What a place that calls another module's code records beyond a built place (`CallFields`), in a box of its own
	/// that every other place leaves `nil`.
	var callFields: CallFields?
	/// Whether the place's function returns the property's type, its construction erased to it where the place is erased,
	/// so that its call erases nothing: a mock's erased node, whose override returns the property's type
	/// (`NodeRecords+MockErased.swift`). Every other place's function returns `concreteType`.
	var returnsPropertyType = false
	/// Whether the place's function writes `return` before its value though its body holds no statement: a constant a kind
	/// builds in a function of its own whatever its body holds (`NodeRecords+MockConstruction.swift`). Every other
	/// function writes it only after statements (`BuilderBody.returnKeyword`).
	var functionAlwaysWritesReturn = false
	/// Whether the place declares its builder function and binds its value nowhere: other places call the function, and
	/// nothing reads the value.
	var declaresOnlyItsFunction = false

	/// The statement the place's builder function begins with, before its children.
	var leadingStatement: LeadingStatement? {
		callFields?.leadingStatement
	}

	/// What the construction hands each closure parameter after `arguments`.
	var closureArguments: [ClosureArgumentEntry] {
		callFields?.closureArguments ?? []
	}

	/// The closures the place builds for the builders its call hands on (`CallFields.builtClosures`).
	var builtClosures: [BuiltClosure] {
		callFields?.builtClosures ?? []
	}

	/// The values the place's function is handed on every call (`PassedArgument`), after `cycleParameters`.
	var passedArguments: [PassedArgument] {
		get { sharingFields?.passedArguments ?? [] }
		set { sharingFields = PlaceSharingFields(passedArguments: newValue, constructionValue: constructionValue, alternatives: alternatives, argumentValues: argumentValues) }
	}

	/// Where set, the construction is this value (a `ValuePath.call`) in place of the call of `target`.
	var constructionValue: ConstructionValue? {
		get { sharingFields?.constructionValue }
		set { sharingFields = PlaceSharingFields(passedArguments: passedArguments, constructionValue: newValue, alternatives: alternatives, argumentValues: argumentValues) }
	}

	/// The optional closures the construction tries first, in order, before calling `target` or its construction value.
	var alternatives: [ConstructionAlternative] {
		get { sharingFields?.alternatives ?? [] }
		set { sharingFields = PlaceSharingFields(passedArguments: passedArguments, constructionValue: constructionValue, alternatives: newValue, argumentValues: argumentValues) }
	}

	/// The values of the construction's arguments that are no read, by the argument's position in `arguments`, whose read
	/// still names the parameter and its type: a member of a value, or a call of one, which the construction evaluates
	/// once, where the argument is passed.
	var argumentValues: [Int: ValuePath] {
		get { sharingFields?.argumentValues ?? [:] }
		set { sharingFields = PlaceSharingFields(passedArguments: passedArguments, constructionValue: constructionValue, alternatives: alternatives, argumentValues: newValue) }
	}
}

/// The box of `BuiltPlaceRecord.sharingFields`. It holds its values for as long as a record holds it.
final class PlaceSharingFields: Sendable {
	let passedArguments: [PassedArgument]
	let constructionValue: ConstructionValue?
	let alternatives: [ConstructionAlternative]
	let argumentValues: [Int: ValuePath]

	init(passedArguments: [PassedArgument], constructionValue: ConstructionValue?, alternatives: [ConstructionAlternative], argumentValues: [Int: ValuePath]) {
		self.passedArguments = passedArguments
		self.constructionValue = constructionValue
		self.alternatives = alternatives
		self.argumentValues = argumentValues
	}
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
	/// Unlike a built place's, these and their count are part of the closer's structural key: the closer's call must match
	/// the function it closes on.
	var passedArguments = [PassedArgument]()
	/// Whether the place is a member of a loop of builders wrapped again inside a sibling's function
	/// (`ScopeGenerator.LoopRebinding`).
	var rebindsLoopMember = false
}

/// A place written as text, as the path key writes it: a rename of a value, or another place whose code the engine copies
/// as written. Two such places are alike when their text, their property and their reads' labels are, and each read
/// resolves to an equal declaration.
struct AliasPlaceRecord: Sendable {
	let property: Property
	/// The property the rename reads, or `nil` where it is bound to `nil`.
	let fulfillingProperty: Property?
	/// The place's code, its lines unindented.
	let text: String
	/// Every read the text makes, as the path key resolves it; `nil` where the emitter cannot list them, which keeps the
	/// place and the bodies enclosing it one per path, unless the place is a rename, whose one read is `fulfillingProperty`.
	var reads: [PlaceRead]?
	/// The labels the text binds besides `property`, which code after it may read.
	var otherBindings = [Property]()
	/// The names of the functions the text calls, compared as text: where sharing would name a callee apart, the engine
	/// rewrites the name in the text or keeps the place one per path, never assuming the name stays.
	var calledFunctionNames = [String]()
	/// The names of the functions the text declares in the body that holds it, which no function the engine declares in
	/// that body or around it takes. A call of one of them is not among `calledFunctionNames`.
	var declaredFunctionNames = [String]()
	/// The names of the root functions the text calls (`RootFunctionRecord`), which the text does not declare: the root
	/// declares them, from the place's plan, and nothing renames them, so none is among `calledFunctionNames`.
	var calledRootFunctionNames = [String]()
	/// The call the engine spells where the place is written, in place of `text`, which it equals; `nil` where the engine
	/// writes `text`.
	var call: InPlaceCall?
}

/// A call written where its place is, in the body that holds it: its builder function, which declares the statements of
/// its body and returns its construction, then the binding of the function's result. The function stays in that body,
/// so it reads what it captures there by its label. A reference, as `CallFields` is, so that an alias place that holds
/// none, every other, stays as small as it was: each `PlaceRecord` is as large as its largest case.
final class InPlaceCall: Sendable {
	/// The construction and the function: its name, `@Sendable` mark, escaping types, leading statement and line end.
	let record: BuiltPlaceRecord
	/// The statements of the function's body before its leading statement, and after it, as the tree writes them.
	let statementsBeforeLeadingStatement: [GeneratedCode]
	let statementsAfterLeadingStatement: [GeneratedCode]

	init(record: BuiltPlaceRecord, statementsBeforeLeadingStatement: [GeneratedCode], statementsAfterLeadingStatement: [GeneratedCode]) {
		self.record = record
		self.statementsBeforeLeadingStatement = statementsBeforeLeadingStatement
		self.statementsAfterLeadingStatement = statementsAfterLeadingStatement
	}
}

/// A value reached from a declaration by members and calls: what a passed argument, an alternative or a construction
/// reads. A value rooted at a root declaration that stays outside `@Sendable` functions stays outside them too.
indirect enum ValuePath: Hashable, Sendable {
	/// A declaration at the root's top (`RootDeclarationRecord`), which a function that reads it captures.
	case rootDeclaration(String)
	/// An ordinary read of the body that holds the value: a statement, a forwarded property, or a parameter, as the path key
	/// reads it.
	case read(PlaceRead)
	/// A passed argument of the enclosing function, by its parameter's name, which the function is handed on every call.
	case passedArgument(String)
	/// The member `name` of a value.
	case member(String, of: ValuePath)
	/// The member `name` of an optional value, read through the optional.
	case optionalMember(String, of: ValuePath)
	/// A call of the member `name` of a value, spelled `<value>.<name>(<argumentsWrapper>(<label>: <source>, …))`, or
	/// `<value>.<name>(<label>: <source>, …)` where `argumentsWrapper` is `nil`: each argument a read the engine checks.
	case call(String, of: ValuePath, arguments: [PlaceRead], argumentsWrapper: TypeDescription?)
	/// A call of the implicit member `name` of the type the value is passed as, spelled `.<name>(<label>: <source>, …)`:
	/// each argument a read the engine checks.
	case implicitMemberCall(String, arguments: [PlaceRead])
	/// A new value of a type made by its initializer that takes no argument, spelled `<type>()`: it reads no declaration,
	/// so it is a value of every call alike, and keyed as itself.
	case emptyInitialization(TypeDescription)
	/// A new value of the type the value is passed as, made by its initializer from `values` under `labels`, spelled
	/// `.init(<label>: <value>, …)`: the parameters it passes nothing take their defaults.
	case implicitInitialization(labels: [String], values: [ValuePath])
}

/// A value a call hands the function it calls on every call, which the function never captures: places that share one
/// function can each be handed another value. A call spells it from the values it reads itself (`ValuePath`), so it is a
/// read of every call site that the engine checks as it checks a `PlaceRead`, and part of a built place's structural key
/// only through its parameter's name and type.
struct PassedArgument: Hashable, Sendable {
	/// The parameter's name in the called function.
	let parameterName: String
	/// The parameter's type.
	let type: TypeDescription
	/// The value the call hands it.
	let value: ValuePath
	/// Whether the value cannot cross into a `@Sendable` function: a call made inside one cannot hand it on, so no
	/// function sharing moves such a call into one.
	let staysOutsideSendableFunctions: Bool
}

/// A construction that is a value other than a call of the built type: `value`, wrapped in `resultWrapper` where set.
struct ConstructionValue: Hashable, Sendable {
	let value: ValuePath
	/// The type the value is wrapped in, where it differs from the place's; `nil` where it is the place's value.
	let resultWrapper: TypeDescription?
}

/// An optional closure a construction tries before its call: `if let <bindingName> = <closure>, <each absent> == nil {
/// <closure's result> } else <the next alternative, or the call>`.
struct ConstructionAlternative: Sendable {
	/// The closure.
	let closure: ValuePath
	/// The name the closure is bound to where it is optional; `nil` where it is not, and is used as read.
	let bindingName: String?
	/// Values that must be `nil` for the closure to be used: a builder a public mock's caller hands a place built inline is
	/// used only where the place's own override is not set (`HoleBuilder.inlinePlaceValue`).
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
