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

/// The production type key (R1): a root's body laid out so that the places that build one type alike share one builder
/// function. Places are alike when they build one type in one way, in one family (plain or `@Sendable`), read the same
/// labels they do not bind, write bodies of the same shape whose calls reach alike places, and resolve each read to a
/// declaration of one form, or none. Each shared function is declared once, in the root's body, never nested in another,
/// before the first statement of the root's that reaches it; the functions of a cycle are declared together. A read every
/// call resolves to the declaration visible where the function is declared is captured, a read no call provides is `nil`
/// inside the function, and every other read is a parameter, which each call passes its own declaration, as a wrapper
/// where any call holds one.
///
/// The layout is read from the path key's plan (`PlaceRecord`), and every read of every place is checked against what the
/// path key reads there: where any read would resolve to another declaration, or a place records nothing, the root keeps
/// the path key's body. So the type key never changes a value the path key builds.
enum TypeKeyBody {
	/// The statements of a root's body in the type key's layout, each indented as a root's statements are, or `nil` where the
	/// root keeps `rootBody`, the path key's statements. `outerDeclarations` are the declarations in scope before the root's
	/// body that it does not write: a seam's parameters, as its narrowest tier binds them. A read the path key resolves to one
	/// is resolved to it in the type key's layout too, never to `nil`. No function the layout declares takes a name of
	/// `namesInScope`, the names bound around the body, such as a seam's parameters' internal names. A value path of the
	/// root's body may name each of `rootPassedArgumentNames`, the parameters of the function the body is written in that
	/// its places read as a function's place reads a passed argument; the layout takes each as a name in scope too. A mock,
	/// whose body the type key's layout replaces whatever it holds, lays out every loop of builders (`laysOutEveryLoop`);
	/// production keeps the path key's body where it writes each member's function once. Where
	/// `declaresLoopMembersAsThePathKeyDoes` is set, the function of each member of a loop of builders that one statement of
	/// the root's body builds is declared right before that statement, as the path key declares a loop it writes once,
	/// rather than with the loop's other functions, and every other function is declared in the body that calls it, as the
	/// path key nests it. It applies only where the path key writes each loop once, and exists
	/// so that a root laid out from node records writes the path key's bytes where the path key keeps 2.4.0's form for a
	/// loop; once the records place functions themselves, placement comes from them and this goes.
	/// `nodeFacts` holds what the layout reads of the plan nodes the root shares with other roots, worked out once for them.
	static func statements(
		ofRootBody rootBody: [GeneratedCode],
		outerDeclarations: [Property] = [],
		namesInScope: Set<String> = [],
		rootPassedArgumentNames: Set<String> = [],
		laysOutEveryLoop: Bool = false,
		declaresLoopMembersAsThePathKeyDoes: Bool = false,
		nodeFacts: NodeLayoutFacts = .none,
	) -> [GeneratedCode]? {
		var layout = TypeKeyLayout()
		layout.nodeFacts = nodeFacts
		layout.declareOuter(outerDeclarations)
		layout.namesInScope = namesInScope.union(rootPassedArgumentNames)
		layout.rootPassedArgumentNames = rootPassedArgumentNames
		guard case let .success(statements) = layOut(rootBody, in: &layout, laysOutEveryLoop: laysOutEveryLoop, declaresLoopMembersAsThePathKeyDoes: declaresLoopMembersAsThePathKeyDoes) else { return nil }
		return statements
	}

	/// The statements of a root's body laid out from the per-type plan of its cycles, or `nil` where the root keeps the path
	/// key's body: `rootBody`'s places, and the body of each variant a call place calls, each built once. A call place of a
	/// cyclic member is a closing record whose target is its variant's index (`ClosingPlaceRecord.targetVariant`), whether or not the
	/// path key would build the member there, and passes every label the variant's body reads from above as a cycle
	/// argument read where the call is made. So a variant's function takes as a parameter only what its calls resolve to
	/// different declarations, captures what they all resolve to the declaration visible where it is declared, and reads
	/// `nil` where none provides it, by the rules the path key's plan is laid out by; its name is the layout's, claimed as
	/// every other function's is. A root with a variant whose body reads a label it does not take as a cycle parameter, or a
	/// call of a variant `variants` does not hold, keeps the path key's body.
	static func statements(ofRootBody rootBody: [GeneratedCode], variants: [CycleVariantRecord], outerDeclarations: [Property] = [], namesInScope: Set<String> = []) -> [GeneratedCode]? {
		guard case let .success(statements) = layOut(rootBody, variants: variants, outerDeclarations: outerDeclarations, namesInScope: namesInScope) else { return nil }
		return statements
	}

	/// `statements(ofRootBody:variants:outerDeclarations:namesInScope:)`, or the stage of the layout that kept the path
	/// key's body.
	static func layOut(_ rootBody: [GeneratedCode], variants: [CycleVariantRecord], outerDeclarations: [Property], namesInScope: Set<String>) -> Result<[GeneratedCode], TypeKeyRefusal> {
		var layout = TypeKeyLayout()
		layout.declareOuter(outerDeclarations)
		layout.namesInScope = namesInScope
		layout.variants = variants
		return layOut(rootBody, in: &layout)
	}

	/// `rootBody` laid out by `layout`, which holds the declarations before it and the variants its call places call, or
	/// the stage of the layout that kept the path key's body. Where `laysOutEveryLoop` holds, a loop of builders the path key
	/// writes once is laid out too, and where `declaresLoopMembersAsThePathKeyDoes` holds, its members are declared as
	/// `statements(ofRootBody:…)` says.
	private static func layOut(_ rootBody: [GeneratedCode], in layout: inout TypeKeyLayout, laysOutEveryLoop: Bool = false, declaresLoopMembersAsThePathKeyDoes: Bool = false) -> Result<[GeneratedCode], TypeKeyRefusal> {
		// The root functions the plan's places call are declared once, before every statement, as the path key declares
		// them (`RootFunctionHoisting`); a root that keeps one in place keeps the path key's body, since the type key spells
		// a place written as text without them.
		let rootFunctionNames = Set(RootFunctionHoisting.records(in: rootBody).map(\.name))
		var rootFunctionDeclarations = [GeneratedCode]()
		if !rootFunctionNames.isEmpty {
			let hoisted = RootFunctionHoisting.hoisted(rootBody, indentation: rootStatementIndentation)
			guard let body = hoisted.last, case let .omittingRootFunctions(_, declaredNames) = body.node, declaredNames == rootFunctionNames else { return .failure(.rootFunctionKeptInPlace) }
			rootFunctionDeclarations = hoisted.dropLast()
			layout.rootFunctionNames = rootFunctionNames
			layout.namesInScope.formUnion(rootFunctionNames)
		}
		guard layout.read(rootBody) else { return .failure(.placeNotRead) }
		GenerationWork.record(layout.bodies.count - 1, by: .layingOutTypeKeyViews)
		guard layout.computeReads() else { return .failure(.readsNotResolved) }
		guard layout.variantsReadOnlyTheirCycleParameters() else { return .failure(.variantReadsLabelItTakesNoParameterOf) }
		layout.computeClasses()
		// A root whose loops of builders the path key writes once each keeps the path key's body, the members' functions
		// nested as before the type key laid loops out.
		let laysOutLoops = layout.laysOutLoops()
		layout.declaresLoopMembersAsThePathKeyDoes = declaresLoopMembersAsThePathKeyDoes && !laysOutLoops
		guard laysOutEveryLoop || laysOutLoops else { return .failure(.loopWrittenOnce) }
		guard layout.computePlacement() else { return .failure(.functionNotPlaced) }
		layout.computeOutcomes()
		guard layout.keepsCapturesOfLoopMembersDeclaredAsThePathKeyDoes() else { return .failure(.loopMemberCapturesLaterBinding) }
		guard layout.computeParameterTypes() else { return .failure(.parameterHasNoType) }
		guard layout.checkEveryRead() else { return .failure(.readResolvesOtherwise) }
		guard layout.checkValuePaths() else { return .failure(.valuePathResolvesOtherwise) }
		layout.computeDecoratorsAndNames()
		guard layout.checkSendableMarks() else { return .failure(.sendableMarkDiffers) }
		guard let statements = layout.spelledRootStatements() else { return .failure(.statementNotSpelled) }
		return .success(rootFunctionDeclarations + statements)
	}

	/// The indentation of a root's statements, which every root body is written after.
	static let rootStatementIndentation = "        "
}

/// The body of one variant of the per-type plan of a root's cycles: the record of the variant's one place, whose children
/// are its body's statements, and whether the body is in the `@Sendable` family.
struct CycleVariantRecord: Sendable {
	let record: BuiltPlaceRecord
	let isInSendableFamily: Bool
	/// The function's parameters after the forwarded value: one per label the variant's declaration reads from above whose
	/// answer is a declaration that is not still being built, typed as that declaration, or as its instance where the
	/// answer is a lazily instantiated declaration's instance. Every call of the variant passes one value for each.
	let parameters: [Property]

	/// The variant whose body is `record`, whose declaration reads `labels` from above, the body answering them `answers`.
	init(record: BuiltPlaceRecord, isInSendableFamily: Bool, labels: [String], answers: [Answer]) {
		self.record = record
		self.isInSendableFamily = isInSendableFamily
		parameters = zip(labels, answers).compactMap { label, answer in answer.parameter(labeled: label) }
	}
}

/// A declaration of the path key's body: a statement of a body, a forwarded property or a cycle parameter of a place's
/// function, or none.
enum PathValue: Hashable {
	case none
	case statement(body: Int, index: Int)
	case forwarded(body: Int, label: String)
	case cycleParameter(body: Int, label: String)
}

/// A declaration of the type key's body: a statement of a class's body or the root's (class 0), a forwarded property of a
/// class's function, a read a class's function takes as a parameter, or none.
enum TypeDeclaration: Hashable {
	case none
	case statement(owner: Int, index: Int)
	case forwarded(owner: Int, label: String)
	case read(owner: Int, label: String)
}

/// What a class's function does with a label it reads and does not bind.
enum ReadOutcome: Hashable {
	/// No call provides it: the function reads `nil`.
	case none
	/// Every call resolves it to the declaration visible where the function is declared, which the function captures.
	case captured(TypeDeclaration)
	/// The function takes it as a parameter.
	case passed
}

/// A position in a class's body (or the root's, class 0) at which a call of a class's function is made.
struct CallSite: Hashable {
	let owner: Int
	let index: Int
}

struct TypeKeyLayout {
	/// A body of the path key's walk, laid out once for each view (R1b §2a): the root's (body 0), or the builder function
	/// of the places of one plan node, in one family, whose look-ups outside it resolve to declarations alike and whose
	/// cycle parameters are passed declarations alike (`KeyedDeclaration`). Every step asks a view what it would ask each of
	/// its places through the view's first place, since every place answers alike inside the view, but asks what the view
	/// resolves a label to outside it at each of its edges (`resolution(of:atPlace:edge:)`): the outcome of each read takes
	/// every edge, and each place's call is checked where its parent makes it (`checkEveryRead`'s `.built` case, run for
	/// every body that holds a place of the view).
	struct Body {
		/// The body holding the view's first place, which the walk reached it through.
		let parent: Int
		/// The index of the first place's statement in `parent`.
		let position: Int
		/// The parent bodies and statement indices of the view's other places, which count the places the view stands for.
		var otherEdges = [(parent: Int, position: Int)]()
		let record: BuiltPlaceRecord?
		/// Whether the body is in the `@Sendable` family: its own function is `@Sendable`, or one enclosing it is.
		let isInSendableFamily: Bool
		/// The labels the body looks up outside it: its plan node's `Domain`, and the domains of the functions its closers
		/// call.
		let domainLabels: Set<String>
		/// What each label of `domainLabels` resolves to at the view's first place, where the walk first reached the view:
		/// the nearest declaration outside the body (`lookUp(_:inBody:before:)` from `parent` before `position`), so that a
		/// look-up climbing out of the body, which climbs through that place, stops here rather than walking every body
		/// above it. The view's key holds each one as `keyed(_:label:byKind:)` gives it.
		let outerView: [String: PathValue]
		var statements = [Statement]()
		/// The positions of the statements that bind each label, ascending.
		var positionsByLabel = [String: [Int]]()
		/// The positions of the statements that declare each function, by its name (`AliasPlaceRecord.declaredFunctionNames`),
		/// apart from the labels the statements bind, so no read of a label resolves to a function.
		var positionsByDeclaredFunction = [String: [Int]]()
		let forwardedLabels: Set<String>
		/// The parameters of the body's function a cycle closes on, or of a variant's function: what its calls pass it.
		let cycleParameters: [Property]
		/// The labels of `cycleParameters`, which every look-up through the body reads.
		let cycleParameterLabels: Set<String>

		/// The parent body and statement index of each of the view's places.
		var edges: [(parent: Int, position: Int)] {
			[(parent, position)] + otherEdges
		}
	}

	/// What a plan node's reads look up outside its own body, whatever context it is in: the labels, and the names of the
	/// functions its closers call.
	struct Domain {
		var labels = Set<String>()
		var closedOnFunctionNames = Set<String>()
		/// Whether a closer beneath the node's own body, rather than one of its own statements, calls a function declared
		/// outside it.
		var closesBeneathItsBody = false
	}

	/// What tells two places of one plan node apart (`Body`).
	struct ViewKey: Hashable {
		let node: PlanNode
		let isInSendableFamily: Bool
		let outerView: [String: KeyedDeclaration]
		let cycleArguments: [KeyedDeclaration]
		/// The statements of enclosing bodies whose functions the view's closers call, a loop of builders' members, in the order
		/// the walk of the names first reaches them (`closedOnFunctions(named:from:closesBeneathItsBody:)`).
		let closedOnStatements: [ClosedOnStatementKey]
		/// The statement each name of that walk resolves to, by its position in `closedOnStatements`, in the walk's order, so
		/// two views share only where their closers' names resolve alike.
		let closedOnResolutions: [Int]
	}

	/// What a view's key holds of a declaration outside it. Nothing inside a view depends on which body declares a value it
	/// reads outside it, only on whether there is one, what kind it is and its type, so places whose reads resolve to
	/// declarations alike in those share a view, wherever the declarations are: each call of the view's function is
	/// checked where its parent makes it (`checkCall`), and each read the view's function takes from its callers is passed by
	/// each call (`computeOutcomes` reads every edge). A statement of the root's body stays itself, since a function can
	/// capture it. A view whose closers call a function declared outside it keeps the declarations themselves (`absolute`):
	/// the closer calls the function its own place's path declares, which a view standing for several paths could not tell.
	/// A member of a loop of builders whose own statements call only its siblings' functions, declared in the body that
	/// declares it, and whose siblings do the same, is keyed by kind: each of its places' calls is checked against the
	/// siblings of that place's own body (`checkCall`).
	enum KeyedDeclaration: Hashable {
		case absolute(PathValue)
		case none
		case root(index: Int)
		case outside(kind: Kind, type: String?)

		enum Kind: Hashable {
			case statement
			case forwarded
			case cycleParameter
		}
	}

	/// What tells apart two statements of enclosing bodies whose functions a view's closers call: the view key of the place
	/// the statement is, its outer view over every label the functions called read, keyed as the view's own.
	struct ClosedOnStatementKey: Hashable {
		let node: PlanNode
		let isInSendableFamily: Bool
		let outerView: [String: KeyedDeclaration]
		let cycleArguments: [KeyedDeclaration]
	}

	/// A statement of a body: a place built by its own function, a constant built in place, a cycle-closing scope, or a
	/// rename.
	enum Statement {
		case built(body: Int)
		case inline(BuiltPlaceRecord)
		case closer(ClosingPlaceRecord, target: Int)
		case alias(AliasPlaceRecord)
	}

	var bodies = [Body]()
	/// The number of the root body's first statements that stand for declarations outside it, which are never spelled.
	var outerDeclarationCount = 0
	/// The root functions the root declares before its statements, which the text of a statement kept as the path key's code
	/// leaves out.
	var rootFunctionNames = Set<String>()
	/// The names bound around the root's body, which no function the layout declares takes.
	var namesInScope = Set<String>()
	/// The parameters of the function the root's body is written in that a value path of the root's body may name as a
	/// passed argument.
	var rootPassedArgumentNames = Set<String>()
	/// The views whose bodies wrap a member of a loop of builders again (`ClosingPlaceRecord.rebindsLoopMember`).
	var loopRebindingBodies = Set<Int>()
	/// The views other than the root's in post-order of the view DAG.
	var postOrder = [Int]()
	/// The domain of each plan node the walk reached.
	var domainsByNode = [PlanNode: Domain]()
	/// The facts of the plan nodes the root shares with other roots, which `domain(of:)` reads rather than computes.
	var nodeFacts = NodeLayoutFacts.none
	/// The functions the statements of each body the walk has reached declare, by name, the first of each name: where a
	/// closer's function is resolved (`resolvedFunction(named:from:)`), in one look-up per enclosing body rather than a scan
	/// of its statements, which a wide body of a cycle would repeat for each of its statements.
	var declaredFunctionsByBody = [Int: [String: DeclaredFunction]]()
	/// The closing statements that call each body's function: their body and their index in it.
	var closersByTarget = [Int: [(body: Int, index: Int)]]()
	/// What each closing statement passes each label it passes, by its body and index (`recordCloser(_:at:closing:)`).
	var cycleArgumentsByCloser = [CallSite: [String: PlaceRead]]()
	/// The labels each body's function reads and does not bind, in the order it first reads them.
	var reads = [[String]]()
	/// The labels of each body's reads that some read inside it requires a value of.
	var requiredReads = [Set<String>]()
	/// For each body, a declaration outside it each label it reads resolves to, `.none` where every such read is `nil`:
	/// only which labels are `.none` is read (`resolution(of:atPlace:edge:)`), since a view a body holds can stand for
	/// places beneath other bodies, whose declarations it holds alike, not the same.
	var escapingReads = [[String: PathValue]]()
	/// Each body's class, numbered from 1 in the order the walk first reaches a member; the root is class 0.
	var classByBody = [Int]()
	/// Each class's members, in walk order.
	var membersByClass = [[Int]]()
	/// The labels each class's function is handed (`BuiltPlaceRecord.parameterProperties`), empty for the root's.
	var parameterLabelsByClass = [Set<String>]()
	/// The classes each class's body calls, and the call sites of each class.
	var calleesByClass = [Set<Int>]()
	var callSitesByClass = [Set<CallSite>]()
	/// Where each class's function is declared: the class whose body declares it (0 for the root's), the index of the
	/// statement it is declared before, and the depth of that body.
	var placementOwner = [Int]()
	var placementIndex = [Int]()
	var placementDepth = [Int]()
	/// The functions declared before each statement of each class's body: those declared for every call in that body,
	/// ordered by the first reach of their cycle and then their own, and last the one whose only call is the statement.
	var hoistedFunctions = [CallSite: [Int]]()
	var attachedFunction = [CallSite: Int]()
	/// Whether each member of a loop of builders whose function one statement of the root's body alone reaches is declared
	/// right before that statement (`TypeKeyBody.statements(ofRootBody:…)`), and the members so declared.
	var declaresLoopMembersAsThePathKeyDoes = false
	var loopMembersDeclaredAsThePathKeyDoes = [Int]()
	var outcomes = [[String: ReadOutcome]]()
	/// For each variant body of the per-type plan, the labels of its cycle parameters that every call passes one
	/// statement of the root's body, by that statement's position: its function captures the statement, as today's does
	/// (`rootStatementsCapturedByVariants()`).
	var rootStatementsCapturedByVariant = [Int: [String: Int]]()
	var parameterTypes = [[String: TypeDescription]]()
	/// The value each cycle parameter of a place holds at every call of its function, where every call passes one.
	var normalizedCycleParameters = [Int: [String: PathValue]]()
	var isDecorated = [Bool]()
	var functionNames = [String]()
	/// The variants of the per-type plan, which call places name by index; empty where the layout reads the path key's plan
	/// alone.
	var variants = [CycleVariantRecord]()
	/// The body of each variant the walk has reached, by the variant's index.
	var variantBodiesByIndex = [Int: Int]()
	/// The bodies of the variants, which have no place of their own: every call of one is a closing statement.
	var variantBodies = Set<Int>()
	/// The passed arguments each call of a place's function hands it, keyed by the body and index of the call: the places
	/// of one view can each hand their own.
	var passedArgumentsByCall = [[Int]: [PassedArgument]]()
	/// The local each call binds a passed argument to before it calls (`PassedArgument.bindsBeforeCall`), by the call's
	/// site and the parameter's name.
	var boundArgumentNames = [CallSite: [String: String]]()
	/// The declaration each label a view reads outside it resolves to at each of its places, keyed by the body and index of
	/// the place's statement: what the walk looked up for the view's key, which `resolution(of:atPlace:edge:)` reads rather
	/// than walking up again.
	var outerDeclarationsByEdge = [[Int]: [String: PathValue]]()
}

extension AliasPlaceRecord {
	/// Whether the type key knows every read the place makes: a rename's one read, or the reads its text lists.
	var listsItsReads: Bool {
		reads != nil || text.isEmpty || fulfillingProperty != nil
	}

	/// The reads the place's text lists, which a rename's read is not among.
	var listedReads: [PlaceRead] {
		reads ?? []
	}
}

extension TypeKeyLayout.Body {
	init(parent: Int, position: Int, record: BuiltPlaceRecord?, isInSendableFamily: Bool, domainLabels: Set<String>, outerView: [String: PathValue], forwardedLabels: Set<String>, cycleParameters: [Property]) {
		self.init(
			parent: parent,
			position: position,
			record: record,
			isInSendableFamily: isInSendableFamily,
			domainLabels: domainLabels,
			outerView: outerView,
			forwardedLabels: forwardedLabels,
			cycleParameters: cycleParameters,
			cycleParameterLabels: Set(cycleParameters.map(\.label)),
		)
	}
}
