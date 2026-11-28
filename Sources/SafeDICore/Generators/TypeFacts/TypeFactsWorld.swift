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

// The interface every reader of a world builds against. Each ID is a dense 32-bit position in the order the world's
// walk first reaches it, so nothing sorts by name. A column no producer fills yet is declared here with its final type
// and answers empty; its doc comment says so. One part is not settled: `Read` in a mock world, which gains the override
// read about a concrete type (a `TypeClassID`), not a label. Its answer is an argument, with one key and one body per
// declaration: the places entered above, an optional slot for each of the body's own properties a path can close on,
// none for a body outside every cycle. A step to a property already on the path returns to that place and forgets the
// places beneath it, as 2.4.0 does. The slot is keyed as `cycle(of:)` keys a cycle.
//
// Twins: `cycle(of:)` is the identity in both worlds, so a value and a `LazilyInstantiated` of one label share it, and
// plain and `@Sendable` builders do not. Which twin a path builds is an argument, never a key: the `madeAgain` producer's
// key projects that choice to one key, as rule 1 does. Owed with the cycles producer: per identity, its declarations in
// first-reach order; per node, the twinned identities its subtree can close on, a union fact like the reads. A value or
// wrapper still being built keys once per identity, by its label, on a required channel; on the optional channels it
// keys as `nil` does, since 2.4.0 passes `nil` to a receive only if available of a declaration not yet built.
//
// Rule 3 is staged, and both keys are planned states. Stage 1, today: an only-if-available read keys a lazy wrapper by
// its kind (-3, -4) and `nil` apart from it, so a lazy answer beside none is two bodies. Stage 2: where a value and a
// lazy wrapper both reach one declaration for one read, the parameter is the wrapper and their keys project to one.
// "Both reach" is a fact per (root, declaration, read): a union over the answers not being built that are bound for that
// read at every call into the node within one root's tree, since a root's functions are local to its code, so two roots
// that disagree on it share no variant. It is computed before the variants fold so that `key` can ask it, never decided
// per call or by arrival order. It projects a value beside a plain wrapper, or wrappers alone; a value beside a
// `SendableLazilyInstantiated` answering one read of a body in the `@Sendable` family keeps its form in the key, a
// deliberate gap, since no wrapper can carry a value that need not be `Sendable`. Where one form alone reaches, stage 1's
// key stands. Read neither stage's count of bodies as permanent.

/// A node of a world's graph: a declaration, its position in `OrderedGraph`.
typealias DeclarationID = Int32
/// A body: a position in `TypeFactsVariants`.
typealias VariantID = Int32
/// A label as one world's reads name it, interned per world in first-reach order (`TypeFactsGraph`'s labels). Columns
/// the table builds name labels, properties and types by the run's IDs instead (`LabelID`, `PropertyID`,
/// `TypeClassID`, `ConstructionInterner`); the reads move to them once the run's snapshot can look a property's label
/// up.
typealias WorldLabelID = Int32
/// A read of `ReadsFromAbove`'s rows, interned per world.
typealias ReadID = Int32
/// An answer by value (`TypeFactsAnswer`), interned per world.
typealias AnswerID = Int32
/// A module's name, interned per world.
typealias ModuleID = Int32
/// A strongly connected component of the graph.
typealias ComponentID = Int32
/// A cycle's identity (A4): the property as cycle validation sees it with the concrete type built.
typealias CycleID = Int32

/// What one read of a variant comes to in its body (the outcomes fold, `TypeFactsOutcomes`), which the mock writer reads:
/// passing `nil` is `none` here, and a read bound before a `@Sendable` function is `readBeforeSendableFunction`;
/// `keysVariant` is a read with no outcome of its own, whose answer keys the variant.
enum TypeFactsOutcome: UInt8, Sendable {
	/// Nothing answers the read: the body is passed `nil`, or the read has no value.
	case none
	/// The body reads the value its enclosing body binds, by capture.
	case captured
	/// The value is bound before the `@Sendable` function that would capture it, outside that function
	/// (`boundBefore(of:)` names the edge that opens it).
	case readBeforeSendableFunction
	/// The body takes the value as a parameter of its function.
	case parameter
	/// The answer keys the variant and is no value the body is handed (family, carrier, what a mock root pins).
	case keysVariant
}

/// What a declaration's property is: its form, beside how its type is built (`TypeFactsConstruction`).
enum TypeFactsKind: UInt8, Sendable {
	case constant
	case instantiator
	case sendableInstantiator
	case erasedInstantiator
	case sendableErasedInstantiator
	case lazy
	case sendableLazy
	case alias
	case hole
}

/// Which function an edge opens around its child.
enum TypeFactsFunctionOpened: UInt8, Sendable {
	case none
	case instantiatorBuilder
	case sendableInstantiatorBuilder
	case sendableLazyWrapper
	case otherSendableFunction
}

/// One edge's facts, parallel to the graph's edge targets.
struct TypeFactsEdge: Equatable, Sendable {
	let child: DeclarationID
	/// The child's position in the order its parent builds its children, after the sibling-order fixed point.
	let buildPosition: Int32
	/// The loop of builders the edge is a member of, -1 for none.
	let loop: Int32
	let opens: TypeFactsFunctionOpened
	let isFill: Bool
	/// How many of the parent's bindings (`bindings(of:)`) are bound before the edge: a prefix of that list.
	let bindingsBefore: Int32
	/// Whether the target is on a cycle with the source: a call, never a child built in line.
	let isCallEdge: Bool
}

/// One declaration a node binds, in its binding order.
struct TypeFactsBinding: Equatable, Sendable {
	let label: LabelID
	let property: PropertyID
	let declaringType: TypeClassID
	let parameterTakingType: TypeClassID?
	let declaringModule: ModuleID
	let isReceivedOnlyIfAvailable: Bool
	let isSeamParameter: Bool
	let isCycleParameter: Bool
	let isReboundByBuilderFunction: Bool
	let isForwarded: Bool
}

/// A node that has an edge to another, with the properties declared on the way as a run of a flat column.
struct TypeFactsParent: Equatable, Sendable {
	let parent: DeclarationID
	let segmentStart: Int32
	let segmentCount: Int32
}

/// A hole: the type no declaration of the module fulfills.
struct TypeFactsHole: Equatable, Sendable {
	let instantiatedType: TypeClassID
	let isErased: Bool
}

/// A property a subtree receives from above, with whether some receive requires it.
struct TypeFactsReceived: Equatable, Sendable {
	let property: PropertyID
	let isRequired: Bool
	/// Required only through an alias received only if available.
	let isRequiredThroughAlias: Bool
}

/// One receive a node's own type makes: the read it makes, the properties that fulfill it (which no world reports yet),
/// whether it is required, and the alias it is read through.
struct TypeFactsReceive: Equatable, Sendable {
	let read: ReadID
	let acceptedStart: Int32
	let acceptedCount: Int32
	let isRequired: Bool
	/// The `PropertyID.raw` of the alias the receive is read through, -1 for a direct receive.
	let alias: Int32
}

/// An answer to a read, by value: compared by its form and what it provides, never by the declaration that gives it.
struct TypeFactsAnswer: Equatable, Sendable {
	enum Form: UInt8, Sendable {
		/// No declaration above answers the read.
		case none
		/// A declaration answers it with the forms it provides.
		case declared
		/// The declaration is still being built where it answers.
		case beingBuilt
		/// A key only: a read only if available, whose `nil` or value is an optional parameter (rule 1).
		case optionalParameter
		/// As `optionalParameter`, answered by a `LazilyInstantiated`, which the parameter is.
		case optionalLazilyInstantiatedParameter
		/// As `optionalParameter`, answered by a `SendableLazilyInstantiated`, which the parameter is.
		case optionalSendableLazilyInstantiatedParameter
		/// A member of a loop of builders, which the node answering rebinds at the top of its body: made again from the
		/// member's one function, never being built.
		case madeAgain
	}

	let form: Form
	/// The forms the declaration provides, interned per world; -1 for `none`.
	let forms: Int32
}

/// The facts a producer still owes a declaration's answers: where two places of one variant can answer a read apart
/// until that producer lands. Each producer's commit clears its own bit, and the world answers empty once every one has.
/// Wider than what is owed: each bit is set wherever its producer's fact can differ, which the sweep's check 10 findings
/// test, class by class.
struct TypeFactsOwedFacts: OptionSet, Sendable {
	let rawValue: UInt8

	/// The fill channel (track C): whether a hole's property is still being built inside its own fill. Set on a fill the
	/// channel refuses (`TypeFactsFillRefusal`) and on every declaration beneath one.
	static let fillBeingBuilt = TypeFactsOwedFacts(rawValue: 1 << 0)
	/// The mock root's pins: whether a mock read is pinned. Set on every declaration of a mock world.
	static let mockRootPin = TypeFactsOwedFacts(rawValue: 1 << 1)
	/// The mock root's required-receive records: what a read finds pinned or read above it. Set on every
	/// declaration of a mock world.
	static let mockRootRecord = TypeFactsOwedFacts(rawValue: 1 << 2)
	/// The mock root's bindings: whether the mock root binds a read. Set on every declaration of a mock world.
	static let mockRootBinding = TypeFactsOwedFacts(rawValue: 1 << 3)
}

/// What every track reads of one world.
protocol TypeFactsWorld {
	var declarationCount: Int { get }
	func kind(of declaration: DeclarationID) -> TypeFactsKind
	func construction(of declaration: DeclarationID) -> TypeFactsConstruction
	/// The `PropertyID.raw` of the property the declaration is built as, -1 for the root.
	func propertyID(of declaration: DeclarationID) -> Int32
	func builtType(of declaration: DeclarationID) -> TypeID
	func cycle(of declaration: DeclarationID) -> CycleID
	func component(of declaration: DeclarationID) -> ComponentID
	func isOnCycle(_ declaration: DeclarationID) -> Bool
	/// The first route from the root in declaration order, root first: diagnostics only.
	func firstRoute(to declaration: DeclarationID) -> [DeclarationID]

	func edges(from declaration: DeclarationID) -> ArraySlice<Int32>
	/// The members of loops of builders the declaration's body makes again at its top, in the order it rebinds them: a
	/// column of its own beside `edges(from:)`, which the reads closure and the variants read and the build order,
	/// `isOnCycle` and `firstRoute` do not.
	///
	/// A writer reads the member's own arguments from here too: its argument for a label of `madeAgainLabels(from:)` is
	/// always that label's rebinding, whatever source its read's answer names. The rebinding shadows the member's own
	/// receives of the labels it makes again, so those reads leave its row, but for one: the read of the label it is built
	/// as, which a loop of one makes again too and still reaches above, answered as its parent's declaration being built.
	func madeAgain(from declaration: DeclarationID) -> ArraySlice<Int32>
	/// The label the declaration rebinds each member of `madeAgain(from:)` as, in that order.
	func madeAgainLabels(from declaration: DeclarationID) -> ArraySlice<WorldLabelID>
	/// The loop members whose parents' loops make different members again, which a stage that writes from nodes refuses.
	var loopMembersSharedApart: [Int32] { get }
	func edgeFacts(from declaration: DeclarationID) -> ArraySlice<TypeFactsEdge>
	/// Owed: the graph's bindings carry the world's IDs (`TypeFactsGraph.worldBindings(of:)`) until the snapshot looks a
	/// value up to its run ID.
	func bindings(of declaration: DeclarationID) -> ArraySlice<TypeFactsBinding>
	func parents(of declaration: DeclarationID) -> ArraySlice<TypeFactsParent>
	/// Owed by the table-side columns.
	func hole(_ declaration: DeclarationID) -> TypeFactsHole?
	/// The union fact of what the subtree receives from above. Owed: the graph's union rows carry the world's IDs
	/// (`TypeFactsGraph.receives`) until the snapshot looks a value up to its run ID.
	func received(by declaration: DeclarationID) -> ArraySlice<TypeFactsReceived>
	/// The receives the declaration's own type makes, in declaration order; `reads(of:)` is its subtree's. Owed by the
	/// table-side columns.
	func receives(of declaration: DeclarationID) -> ArraySlice<TypeFactsReceive>

	/// What the node's subtree reads from above it, by read ID in increasing order.
	func reads(of declaration: DeclarationID) -> ArraySlice<ReadID>
	func read(_ read: ReadID) -> Read
	/// The labels the node's subtree reads from above it, each once, in read order.
	func labels(of declaration: DeclarationID) -> ArraySlice<WorldLabelID>

	/// The roots the world is built from: one tonight. A world of several roots (every production root and seam, or every
	/// mock root, of one validation call) seeds a variant per root from that root's answers and shares the rest where
	/// they agree; nothing per root lives on a variant.
	var rootCount: Int { get }
	/// The variant a root's body is.
	func rootVariant(_ root: Int) -> VariantID
	var variantCount: Int { get }
	func declaration(of variant: VariantID) -> DeclarationID
	func family(of variant: VariantID) -> VariantFamily
	/// The key every call into the variant shares, one per read of `reads(of:)` of its declaration, in that order: an
	/// answer ID with what a parameter carries left out. A call's own answers are `sources(ofCall:of:)`.
	func keys(of variant: VariantID) -> ArraySlice<AnswerID>
	func answer(_ answer: AnswerID) -> TypeFactsAnswer
	/// The forms an answer's declaration provides, by value, interned apart from the channel that reads them. Owed with
	/// answers interned by ID (answers are interned by text tonight).
	func forms(of answer: AnswerID) -> ArraySlice<PropertyID>
	/// The variant each edge of the variant's declaration calls, in edge order.
	func calls(of variant: VariantID) -> ArraySlice<VariantID>
	/// Where each answer a call hands its callee comes from, in the callee's read order.
	func sources(ofCall edgeIndex: Int, of variant: VariantID) -> ArraySlice<AnswerSource>
	/// The variant each member the variant's declaration makes again calls, in `madeAgain(from:)`'s order: a call from the
	/// top of the declaration's body, handed its answers there.
	func madeAgainCalls(of variant: VariantID) -> ArraySlice<VariantID>
	/// Where each answer a made-again call hands its callee comes from, in the callee's read order: `bound` by the caller
	/// for a label it rebinds, else passed through from the caller's own answers.
	func sources(ofMadeAgainCall index: Int, of variant: VariantID) -> ArraySlice<AnswerSource>
	/// Called by exactly one call and off every cycle; not whether the body is a function (`BuiltPlaceRecord.hasFunction`).
	func isCalledOnce(_ variant: VariantID) -> Bool
	/// What each read of the variant comes to, parallel to `keys(of:)` (the outcomes fold).
	func outcomes(of variant: VariantID) -> ArraySlice<TypeFactsOutcome>
	/// For each read of the variant, parallel to `keys(of:)`: the offset of the edge that opens the `@Sendable` function a
	/// `readBeforeSendableFunction` read is bound before (the outermost such edge), -1 for every other outcome.
	func boundBefore(of variant: VariantID) -> ArraySlice<Int32>
	/// The facts producers still owe the declaration's answers (`TypeFactsOwedFacts`).
	func owedFacts(of declaration: DeclarationID) -> TypeFactsOwedFacts
	/// Whether the declaration an answer binds provides a form that a receive of the read's label in the declaration's
	/// subtree reads: where it does not, a call passes the read `nil` (a receive only if available) though the answer is
	/// bound. A declaration being built provides its own label's reads. `forms(of:)` and `provides(_:_:)` answer the same by the run's property IDs once the world holds them; this
	/// answers by the world's own, which no `PropertyID` may carry.
	func providesFormRead(by answer: AnswerID, _ read: ReadID, beneath declaration: DeclarationID) -> Bool
	/// The labels the declaration's subtree reads from above it (`labels(of:)`) in the order a walk of its body first
	/// receives each, the order of its builder function's parameters (`ScopeGenerator.inOrderTheBodyFirstReceives`): its
	/// own type's receives, then each child's subtree depth first, each type's receives before its children's, all in
	/// declaration order, each declaration visited once; a label first met at a call that closes a cycle comes there, in
	/// the order the closed-on declaration reads it. The declaration's own label is none. It depends on where labels are
	/// received, never on their spelling.
	/// Walked when asked, never while the world is built.
	func parameterOrder(of declaration: DeclarationID) -> [WorldLabelID]

	// The fill channel: the fills each call passes, in edge order.
	var fillCount: Int { get }
	/// The fill at `index`: its edge, the seam it fills a place of, and why the channel does not model it yet, if it does not.
	func fill(_ index: Int) -> TypeFactsFill
	/// The fields the fill at `index` binds for its tree, in their declared order: the call's edge to the fill answers a read
	/// of one, and every other read of the fill's tree but its place's own label, which the fill builds, goes on to the
	/// call's caller.
	func fields(ofFill index: Int) -> ArraySlice<TypeFactsFillField>
	/// The parameter the variant's function takes for a read its subtree makes from above, were the read a parameter,
	/// or `nil` where it takes none: the read has no answer, its answer is still being built where the function is
	/// called (a call that closes a cycle on it, a twin being built), it asks about no value of a label, or no one
	/// parameter can pass the forms of its label the subtree receives (`CycleParameter.property(passing:requiredForms:)`).
	/// A function takes one parameter per label, so every read of a label is typed alike: by the forms of the label
	/// the declaration's subtree receives from above and those some receiver requires, as the function a lazy cycle
	/// closes on types its parameter today. Whether the function takes the read as a parameter at all is the outcomes
	/// fold's answer (`outcomes(of:)`), which `parameters(of:)` joins with this.
	/// Computed when asked, never while the world is built.
	func parameterType(of variant: VariantID, _ read: ReadID) -> TypeFactsParameter?
	/// Exactly the parameters the variant's function takes: each label one of whose reads comes to a parameter
	/// (`outcomes(of:)`), in the order of `parameterOrder(of:)` for its declaration, typed by `parameterType(of:_:)`.
	/// Computed when asked, never while the world is built.
	func parameters(of variant: VariantID) -> [TypeFactsParameter]
}

/// A parameter of a variant's function: what it takes for one label its subtree reads from above.
struct TypeFactsParameter: Hashable, Sendable {
	/// The parameter as the function declares it: the label, and the form of it that provides every form the body
	/// receives, optional where no receiver requires the label.
	let property: Property
	/// Whether a receive by value in the body reads the parameter through its wrapper's `instance`: the parameter is a
	/// lazily instantiated wrapper, and the body receives the instance it creates.
	let readsInstanceOfWrapper: Bool
}

extension TypeFactsGraph: TypeFactsWorld {
	var declarationCount: Int {
		graph.nodes.count
	}

	/// The form of the property the declaration is built as: a leaf's as its leaf, the root's `constant`.
	func kind(of declaration: DeclarationID) -> TypeFactsKind {
		kinds[Int(declaration)]
	}

	func construction(of declaration: DeclarationID) -> TypeFactsConstruction {
		constructions[Int(declaration)]
	}

	func propertyID(of declaration: DeclarationID) -> Int32 {
		graph.nodes[Int(declaration)].key.property
	}

	func builtType(of declaration: DeclarationID) -> TypeID {
		graph.nodes[Int(declaration)].scope.concreteTypeID
	}

	func cycle(of declaration: DeclarationID) -> CycleID {
		cycleIDs[Int(declaration)]
	}

	func component(of declaration: DeclarationID) -> ComponentID {
		graph.componentByNode[Int(declaration)]
	}

	func isOnCycle(_ declaration: DeclarationID) -> Bool {
		graph.isOnCycle(Int(declaration))
	}

	func firstRoute(to declaration: DeclarationID) -> [DeclarationID] {
		graph.firstRoute(to: Int(declaration)).map(Int32.init)
	}

	func edges(from declaration: DeclarationID) -> ArraySlice<Int32> {
		graph.edges(from: Int(declaration))
	}

	func madeAgain(from declaration: DeclarationID) -> ArraySlice<Int32> {
		madeAgain?.targets(of: Int(declaration)) ?? []
	}

	func madeAgainLabels(from declaration: DeclarationID) -> ArraySlice<WorldLabelID> {
		madeAgain?.labels(of: Int(declaration)) ?? []
	}

	func edgeFacts(from declaration: DeclarationID) -> ArraySlice<TypeFactsEdge> {
		edgeFacts(from: Int(declaration))
	}

	func bindings(of _: DeclarationID) -> ArraySlice<TypeFactsBinding> {
		[]
	}

	func parents(of declaration: DeclarationID) -> ArraySlice<TypeFactsParent> {
		parents(of: Int(declaration))
	}

	func hole(_: DeclarationID) -> TypeFactsHole? {
		nil
	}

	func received(by _: DeclarationID) -> ArraySlice<TypeFactsReceived> {
		[]
	}

	func receives(of _: DeclarationID) -> ArraySlice<TypeFactsReceive> {
		[]
	}

	func forms(of _: AnswerID) -> ArraySlice<PropertyID> {
		[]
	}

	var rootCount: Int {
		1
	}

	func rootVariant(_: Int) -> VariantID {
		0
	}

	func reads(of declaration: DeclarationID) -> ArraySlice<ReadID> {
		readColumn[Int(readOffsets[Int(declaration)])..<Int(readOffsets[Int(declaration) + 1])]
	}

	func read(_ read: ReadID) -> Read {
		readTable[Int(read)]
	}

	func labels(of declaration: DeclarationID) -> ArraySlice<WorldLabelID> {
		labelColumn[Int(labelOffsets[Int(declaration)])..<Int(labelOffsets[Int(declaration) + 1])]
	}

	var variantCount: Int {
		variants.count
	}

	func declaration(of variant: VariantID) -> DeclarationID {
		variants.node(of: Int(variant))
	}

	func family(of variant: VariantID) -> VariantFamily {
		variants.family(of: Int(variant))
	}

	func keys(of variant: VariantID) -> ArraySlice<AnswerID> {
		variants.keys(of: Int(variant))
	}

	func answer(_ answer: AnswerID) -> TypeFactsAnswer {
		guard answer >= 0 else {
			let form: TypeFactsAnswer.Form = switch answer {
			case TypeFactsGraph.optionalParameterKey:
				.optionalParameter
			case TypeFactsGraph.optionalLazilyInstantiatedParameterKey:
				.optionalLazilyInstantiatedParameter
			case TypeFactsGraph.optionalSendableLazilyInstantiatedParameterKey:
				.optionalSendableLazilyInstantiatedParameter
			default:
				.none
			}
			return TypeFactsAnswer(form: form, forms: -1)
		}
		let form: TypeFactsAnswer.Form = if answerIsMadeAgain[Int(answer)] {
			.madeAgain
		} else if answerIsBeingBuilt[Int(answer)] {
			.beingBuilt
		} else {
			.declared
		}
		return TypeFactsAnswer(form: form, forms: answerKeys[Int(answer)])
	}

	func calls(of variant: VariantID) -> ArraySlice<VariantID> {
		variants.callees(of: Int(variant))
	}

	func sources(ofCall edgeIndex: Int, of variant: VariantID) -> ArraySlice<AnswerSource> {
		variants.sources(ofCall: variants.callOffset(of: Int(variant)) + edgeIndex)
	}

	func madeAgainCalls(of variant: VariantID) -> ArraySlice<VariantID> {
		variants.madeAgainCallees(of: Int(variant))
	}

	func sources(ofMadeAgainCall index: Int, of variant: VariantID) -> ArraySlice<AnswerSource> {
		variants.sources(ofCall: variants.madeAgainCallOffset(of: Int(variant)) + index)
	}

	func isCalledOnce(_ variant: VariantID) -> Bool {
		variants.isCalledOnce[Int(variant)]
	}

	func outcomes(of variant: VariantID) -> ArraySlice<TypeFactsOutcome> {
		outcomes.forms(of: variant)
	}

	func boundBefore(of variant: VariantID) -> ArraySlice<Int32> {
		outcomes.boundBefore(of: variant)
	}

	func providesFormRead(by answer: AnswerID, _ read: ReadID, beneath declaration: DeclarationID) -> Bool {
		guard answer >= 0 else { return false }
		// A declaration being built is the one its own label's reads beneath it name, around the cycle it closes.
		guard !answerIsBeingBuilt[Int(answer)] else { return true }
		let declared = answerProperties[Int(answer)]
		let label = readTable[Int(read)].label
		return receives.received.columns(inRow: Int(declaration)).contains { received in
			propertyFacts.labels[Int(received)] == label && propertyFacts.provides(declared, aFormReadBy: received)
		}
	}

	func parameterOrder(of declaration: DeclarationID) -> [WorldLabelID] {
		parameterOrder(of: declaration, walking: [])
	}

	func parameterType(of variant: VariantID, _ read: ReadID) -> TypeFactsParameter? {
		let declaration = declaration(of: variant)
		let reads = reads(of: declaration)
		let label = readTable[Int(read)].label
		guard let position = reads.firstIndex(of: read) else { return nil }
		switch readTable[Int(read)].channel {
		case .value, .optional, .optionalValue:
			break
		case .alias, .madeAgain, .mock, .carrier, .fill, .family, .override:
			return nil
		}
		let keys = keys(of: variant)
		switch answer(keys[keys.startIndex + (position - reads.startIndex)]).form {
		case .none, .beingBuilt, .madeAgain:
			return nil
		case .declared, .optionalParameter, .optionalLazilyInstantiatedParameter, .optionalSendableLazilyInstantiatedParameter:
			break
		}
		var forms = Set<Property>()
		for received in receives.received.columns(inRow: Int(declaration)) where propertyFacts.labels[Int(received)] == label {
			forms.insert(propertyTable[Int(received)])
		}
		var requiredForms = Set<Property>()
		for required in receives.required.columns(inRow: Int(declaration)) where propertyFacts.labels[Int(required)] == label {
			requiredForms.insert(propertyTable[Int(required)])
		}
		guard let (property, passedForms) = CycleParameter.property(passing: forms, requiredForms: requiredForms.intersection(forms)) else { return nil }
		let instance = property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding
		return TypeFactsParameter(
			property: property,
			readsInstanceOfWrapper: instance.map { passedForms.contains($0) || passedForms.contains($0.asOptionalProperty) } ?? false,
		)
	}

	func parameters(of variant: VariantID) -> [TypeFactsParameter] {
		let declaration = declaration(of: variant)
		let reads = reads(of: declaration)
		let outcomes = outcomes(of: variant)
		return parameterOrder(of: declaration).compactMap { label in
			reads.indices
				.first { readTable[Int(reads[$0])].label == label && outcomes[outcomes.startIndex + ($0 - reads.startIndex)] == .parameter }
				.flatMap { parameterType(of: variant, reads[$0]) }
		}
	}

	/// `parameterOrder(of:)`, inside the walks of `walking`, whose orders a call that closes on one of them meets in
	/// `labels(of:)` order instead.
	private func parameterOrder(of declaration: DeclarationID, walking: Set<DeclarationID>) -> [WorldLabelID] {
		// The declaration's own label is no parameter: every call is made where a declaration of it is being built.
		let ownLabel = graph.nodes[Int(declaration)].property.map(\.label)
		var unmet = Set(labels(of: declaration).filter { labelTexts[Int($0)] != ownLabel })
		var order = [WorldLabelID]()
		func meet(_ label: WorldLabelID) {
			if unmet.remove(label) != nil {
				order.append(label)
			}
		}
		var labelIDs = [String: WorldLabelID]()
		for (index, text) in labelTexts.enumerated() where labelIDs[text] == nil {
			labelIDs[text] = WorldLabelID(index)
		}
		let walking = walking.union([declaration])
		var visited = Set<Int>()
		// Each node with whether a call reaches it. The node visited next is the last on the stack, so the first child goes
		// last: a call that closes a cycle is met where the walk reaches it among its siblings, after the earlier siblings'
		// subtrees, as the plan meets a closing scope.
		var pending = [(node: Int(declaration), isCall: false)]
		while !unmet.isEmpty, let (node, isCall) = pending.popLast() {
			guard visited.insert(node).inserted else {
				// A call that closes a cycle receives the closed-on declaration's parameters, in their order, where its body does.
				if isCall {
					let closedOn = Int32(node)
					if walking.contains(closedOn) {
						labels(of: closedOn).forEach(meet)
					} else {
						parameterOrder(of: closedOn, walking: walking).forEach(meet)
					}
				}
				continue
			}
			let scope = graph.nodes[node].scope
			if graph.nodes[node].key.leaf == .none {
				var declaredLabels = Set<String>()
				for dependency in scope.instantiable.dependencies {
					switch dependency.source {
					case .instantiated, .forwarded:
						declaredLabels.insert(dependency.property.label)
					case .received, .aliased:
						break
					}
				}
				for dependency in scope.instantiable.dependencies {
					switch dependency.source {
					case .received:
						labelIDs[dependency.property.label].map(meet)
					case let .aliased(fulfillingProperty, _, _):
						// An alias of a property its own type declares reads that declaration: it receives nothing.
						if !declaredLabels.contains(fulfillingProperty.label) {
							labelIDs[fulfillingProperty.label].map(meet)
						}
					case .instantiated, .forwarded:
						break
					}
				}
			}
			let targets = graph.edges(from: node)
			let facts = edgeFacts(from: Int32(node))
			pending.append(contentsOf: zip(targets, facts).reversed().map { (node: Int($0.0), isCall: $0.1.isCallEdge) })
		}
		return order
	}

	func owedFacts(of declaration: DeclarationID) -> TypeFactsOwedFacts {
		var owed: TypeFactsOwedFacts = []
		if forMockGeneration {
			owed.formUnion([.mockRootPin, .mockRootRecord, .mockRootBinding])
		}
		// A declaration is beneath a fill the channel refuses where any of its routes enters one: a walk up its parents, past
		// the fills it models.
		var visited: Set = [declaration]
		var pending = [declaration]
		while let current = pending.popLast() {
			guard !isRefusedFill(current) else {
				owed.insert(.fillBeingBuilt)
				break
			}
			for parent in parents(of: current) where visited.insert(parent.parent).inserted {
				pending.append(parent.parent)
			}
		}
		return owed
	}

	/// Whether `declaration` is a fill the channel refuses: a search of the sorted column.
	private func isRefusedFill(_ declaration: DeclarationID) -> Bool {
		var low = 0
		var high = refusedFillDeclarations.count
		while low < high {
			let middle = (low + high) / 2
			if refusedFillDeclarations[middle] < declaration {
				low = middle + 1
			} else {
				high = middle
			}
		}
		return low < refusedFillDeclarations.count && refusedFillDeclarations[low] == declaration
	}

	var fillCount: Int {
		fills.count
	}

	func fill(_ index: Int) -> TypeFactsFill {
		fills[index]
	}

	func fields(ofFill index: Int) -> ArraySlice<TypeFactsFillField> {
		let fill = fills[index]
		return fillFields[Int(fill.fieldStart)..<Int(fill.fieldStart + fill.fieldCount)]
	}
}
