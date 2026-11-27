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
	/// Whether a wrapper built around a call of the place's function that is handed arguments spells its closure on one
	/// line, `Instantiator<T> { f(…) }`, rather than the call on a line of its own between the braces.
	var wrapsCallOnOneLine = false

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
		set { sharingFields = PlaceSharingFields(passedArguments: newValue, constructionValue: constructionValue, alternatives: alternatives, argumentValues: argumentValues, functionReturnType: functionReturnType) }
	}

	/// Where set, the construction is this value (a `ValuePath.call`) in place of the call of `target`.
	var constructionValue: ConstructionValue? {
		get { sharingFields?.constructionValue }
		set { sharingFields = PlaceSharingFields(passedArguments: passedArguments, constructionValue: newValue, alternatives: alternatives, argumentValues: argumentValues, functionReturnType: functionReturnType) }
	}

	/// The optional closures the construction tries first, in order, before calling `target` or its construction value.
	var alternatives: [ConstructionAlternative] {
		get { sharingFields?.alternatives ?? [] }
		set { sharingFields = PlaceSharingFields(passedArguments: passedArguments, constructionValue: constructionValue, alternatives: newValue, argumentValues: argumentValues, functionReturnType: functionReturnType) }
	}

	/// The values of the construction's arguments that are no read, by the argument's position in `arguments`, whose read
	/// still names the parameter and its type: a member of a value, or a call of one, which the construction evaluates
	/// once, where the argument is passed.
	var argumentValues: [Int: ValuePath] {
		get { sharingFields?.argumentValues ?? [:] }
		set { sharingFields = PlaceSharingFields(passedArguments: passedArguments, constructionValue: constructionValue, alternatives: alternatives, argumentValues: newValue, functionReturnType: functionReturnType) }
	}

	/// Where set, the type the place's function returns in place of `concreteType`: its construction and every
	/// alternative are made this type inside the function, an erased place's erasure among them, so its calls read the
	/// value as it is.
	var functionReturnType: TypeDescription? {
		get { sharingFields?.functionReturnType }
		set { sharingFields = PlaceSharingFields(passedArguments: passedArguments, constructionValue: constructionValue, alternatives: alternatives, argumentValues: argumentValues, functionReturnType: newValue) }
	}
}

/// The box of `BuiltPlaceRecord.sharingFields`. It holds its values for as long as a record holds it.
final class PlaceSharingFields: Sendable {
	let passedArguments: [PassedArgument]
	let constructionValue: ConstructionValue?
	let alternatives: [ConstructionAlternative]
	let argumentValues: [Int: ValuePath]
	let functionReturnType: TypeDescription?

	init(passedArguments: [PassedArgument], constructionValue: ConstructionValue?, alternatives: [ConstructionAlternative], argumentValues: [Int: ValuePath], functionReturnType: TypeDescription?) {
		self.passedArguments = passedArguments
		self.constructionValue = constructionValue
		self.alternatives = alternatives
		self.argumentValues = argumentValues
		self.functionReturnType = functionReturnType
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
	/// The variant of the per-type plan of the root's cycles the place calls, by its index among the variants the layout is
	/// handed, or `nil` where the place closes on the enclosing function `closedOnFunctionName` names. The layout names a
	/// variant's function, so a call of one is never resolved by name.
	var targetVariant: Int?
	/// Whether the place is a member of a loop of builders wrapped again inside a sibling's function
	/// (`ScopeGenerator.LoopRebinding`).
	var rebindsLoopMember = false
}

extension ClosingPlaceRecord {
	/// The record of a call place of the per-type plan (`PlanStatement.call`): a call of the function of the variant at
	/// index `variant`, which builds `property`, handing each parameter the variant's `answers` give it (its cycle
	/// parameters, one per label its declaration reads from above, in the order of `labels`) what `arguments` answers
	/// where the call is made: the nearest declaration, the instance of a lazily instantiated one, or `nil` where nothing
	/// provides a label the variant takes optionally. A call answers a label as the variant does, but for one the variant
	/// takes optionally, which each call answers by its own declaration or `nil`.
	init(callingVariant variant: Int, property: Property, isErased: Bool, isExtension: Bool, forwardedProperties: [Property], labels: [String], answers: [Answer], arguments: [Answer]) {
		self.init(
			property: property,
			isErased: isErased,
			isExtension: isExtension,
			closedOnFunctionName: ScopeGenerator.functionName(toBuildPropertyNamed: property.label),
			forwardedProperties: forwardedProperties,
			cycleArguments: zip(labels, zip(answers, arguments)).compactMap { label, answerAndArgument in
				answerAndArgument.0.parameter(labeled: label).map { parameter in
					PlaceRead(argumentLabel: label, label: label, property: parameter, source: answerAndArgument.1.argumentSource(labeled: label))
				}
			},
		)
		targetVariant = variant
	}
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
	/// Whether the rename reads `fulfillingProperty` only if available where the path key binds it optionally, so the
	/// text takes `nil` and requires nothing of the function it is in: the path key takes that cycle parameter
	/// optionally. A rename only if available of a value the path holds non-optional is written for that value, and
	/// requires it.
	var readsOnlyIfAvailable = false
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
/// so it reads what it captures there by its label.
struct InPlaceCall: Sendable {
	/// The construction and the function: its name, `@Sendable` mark, escaping types, leading statement and line end.
	let record: BuiltPlaceRecord
	/// The statements of the function's body before its leading statement, and after it, as the tree writes them.
	let statementsBeforeLeadingStatement: [GeneratedCode]
	let statementsAfterLeadingStatement: [GeneratedCode]
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
	/// The member `name` of a value (`member(_:of:)`).
	case memberRead(String, of: ValuePathBase)
	/// The member `name` of an optional value, read through the optional (`optionalMember(_:of:)`).
	case optionalMemberRead(String, of: ValuePathBase)
	/// A call of the member `name` of a value, spelled `<value>.<name>(<argumentsWrapper>(<label>: <source>, …))`, or
	/// `<value>.<name>(<label>: <source>, …)` where `argumentsWrapper` is `nil`: each argument a read the engine checks.
	case call(String, of: ValuePath, arguments: [PlaceRead], argumentsWrapper: TypeDescription?)
	/// A new value of a type made by its initializer that takes no argument, spelled `<type>()`: it reads no declaration,
	/// so it is a value of every call alike, and keyed as itself.
	case emptyInitialization(TypeDescription)
	/// Values, text and functions spelled one after another, as an argument written as an expression the engine does not
	/// otherwise model: each value a read the engine checks, each text as written, and each function one a statement
	/// before the value's in the same body declares (`ValueSegment.declaredFunction`).
	case spliced([ValueSegment])
}

extension ValuePath {
	/// The member `name` of `base`.
	static func member(_ name: String, of base: ValuePath) -> ValuePath {
		.memberRead(name, of: ValuePathBase(base))
	}

	/// The member `name` of the optional `base`, read through the optional.
	static func optionalMember(_ name: String, of base: ValuePath) -> ValuePath {
		.optionalMemberRead(name, of: ValuePathBase(base))
	}
}

/// The value a member of a value path is read from. A mock's override of a node reads a member of its parent's, so a
/// path is as deep as the mock's tree, and an indirect case would release each level from within the release of the one
/// above it, which a concurrency thread's stack cannot hold for a tree thousands of types deep: the base holds its value in
/// a `DeferredReleaseSlot`, which releases one level at a time.
final class ValuePathBase: Hashable, Sendable {
	init(_ value: ValuePath) {
		slot = DeferredReleaseSlot([value])
	}

	/// The value the member is read from.
	var value: ValuePath {
		// The slot holds the one value `init` stores until the base is released.
		slot.value[0]
	}

	static func == (lhs: ValuePathBase, rhs: ValuePathBase) -> Bool {
		lhs === rhs || lhs.value == rhs.value
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(value)
	}

	private let slot: DeferredReleaseSlot<[ValuePath]>
}

/// A segment of a spliced value (`ValuePath.spliced`).
enum ValueSegment: Hashable, Sendable {
	/// Text spelled as written, which reads no declaration.
	case text(String)
	/// A value, spelled and checked as any value path is.
	case value(ValuePath)
	/// The name of a function an earlier statement of the body that holds the reading statement declares
	/// (`AliasPlaceRecord.declaredFunctionNames`). A name no such statement declares keeps the root one per path: a
	/// function declared in another body is never in scope where the engine declares the reading statement's function.
	case declaredFunction(String)
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
	/// Whether the call binds the value to a local of its own before it calls the function, and hands it the local. A
	/// call made inside a `Sendable` wrapper's closure then captures the local, never what the value reads: so the value
	/// may read what stays outside `@Sendable` functions only where the local is itself `Sendable`, which whoever sets
	/// this says.
	var bindsBeforeCall = false
}

/// A construction that is a value other than a call of the built type: `value`, wrapped in `resultWrapper` where set.
struct ConstructionValue: Hashable, Sendable {
	let value: ValuePath
	/// The type the value is wrapped in, where it differs from the place's; `nil` where it is the place's value.
	let resultWrapper: TypeDescription?
}

/// An optional closure a construction tries before its call: `if let <bindingName> = <closure>, <each absent> == nil {
/// <closure's result> } else <the next alternative, or the call>`.
struct ConstructionAlternative: Equatable, Sendable {
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

extension Answer {
	/// The parameter a variant's function takes for `label` under this answer: none where nothing above the call provides
	/// the label or the declaration is still being built, since the body is built with `nil` for it; else the
	/// declaration, in its own type. A lazily instantiated declaration whose instance the body reads is taken as the
	/// wrapper, so the instance is created where it is first read and never at the call.
	func parameter(labeled label: String) -> Property? {
		switch self {
		case .none,
		     .declared(_, isBeingBuilt: true):
			nil
		case let .declared(declaration, isBeingBuilt: false),
		     let .declaredMadeAgainAtCall(declaration),
		     let .instance(of: declaration):
			Property(label: label, typeDescription: declaration.typeDescription)
		}
	}

	/// What a call passes for `label` under this answer, to a parameter: the nearest declaration of the label where the
	/// call is made, a wrapper whose instance the body reads included, or `nil` where nothing provides a label the
	/// function takes optionally. The one place a call's argument form is decided.
	///
	/// A deliberate gap while nothing emits from the plan: a member of a loop of builders made again at the call
	/// (`declaredMadeAgainAtCall`) is spelled as its binding here, which the call would read before its declaration.
	/// The layout of a loop member's call owes that wrapper before the plan's code is generated for such a loop.
	func argumentSource(labeled label: String) -> ArgumentSource {
		switch self {
		case .none:
			.nil
		case .declared,
		     .declaredMadeAgainAtCall,
		     .instance:
			.binding(label: label)
		}
	}
}
