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

/// Lets a test see the code a production root's per-type plan lays out (`TypeKeyBody.statements(ofPlan:)`): one
/// function per body, declared in the root's body. Test only, until an emitter writes it.
public enum PlanCodeObservation {
	/// Called for each root that reaches a cycle with the root's type and the code its plan lays out, `nil` where the type
	/// key keeps the path key's body.
	@TaskLocal public static var observer: (@Sendable (_ root: String, _ code: String?) -> Void)?
}

/// Lets a test see, for each production root that reaches a cycle in a module that generates no seam, whether its code
/// is laid out from its per-type plan or its tree is built per path, and why; and lets it have every root's tree built
/// per path. Test only.
public enum RootTreeChoiceObservation {
	/// Why a root that reaches a cycle has its tree built per path.
	public enum PerPathReason: String, Sendable {
		/// A type of the root’s tree holds a `SendableLazilyInstantiated`.
		case holdsLazilyInstantiated
		/// A type of the root's tree receives, renames or instantiates a value only if available, or holds an optional one.
		case holdsValueOnlyIfAvailable
		/// A type of the root's tree holds a `@Sendable` function.
		case holdsSendableFunction
		/// A type of the root's tree declares a loop of builders: builders each of whose trees receives, or renames, the
		/// next one's label, back to the first, or one builder whose tree receives its own.
		case declaresLoopOfBuilders
		/// The root's tree calls a seam's generated initializer or a public mock with a builder.
		case buildsSeam
		/// A type on a cycle of the root's tree receives a label that no type of its cycle declares, and that a type other
		/// than the root declares, or the root does not: today's function captures that declaration, and a function of
		/// the plan captures only the root's own statements.
		case receivesLabelDeclaredOutsideItsCycle
		/// The root's tree may hold a label no one parameter of a cycle's function can pass
		/// (`DependencyTreeGenerator.mayHaveUnpassableCycleLabel(inTreeOf:cache:)`).
		case mayHaveUnpassableCycleLabel
		/// The root has no per-type plan.
		case noPlan
		/// A call of the plan passes a member of a loop of builders made again at the call.
		case passesLoopMemberMadeAgainAtCall
		/// A `@Sendable` function of a body of the root's plan may capture a wrapper that is not `Sendable`
		/// (`WrittenVariantPlan.Unplanned.mayCaptureNonSendableWrapper()`): today's tree reports the capture.
		case mayCaptureNonSendableWrapper
		/// The type key lays out none of the plan.
		case noLayout
		/// Planning the root threw an error, which is discarded: today's tree reports what a build with no plan reports.
		case planningThrew
	}

	/// Called once per such root with the root's type and `nil` where its code is laid out from its plan.
	@TaskLocal public static var observer: (@Sendable (_ root: String, _ perPathReason: PerPathReason?) -> Void)?

	/// The number of places a root's tree per path may hold before it is abandoned for the root's plan by type, in place of
	/// `DependencyTreeGenerator.scopeGeneratorLimitOfTodaysTree`: a test lowers it to plan a small root, or raises it to
	/// keep a root's tree per path. Nothing else sets it.
	@TaskLocal public static var scopeGeneratorLimitOverride: Int?

	/// Whether the comparisons of a root's plan with today's tree run only for a root whose shape the plan admits. The
	/// checks every test runs under set it, where no test observes a comparison itself: a root of another shape keeps
	/// today's tree whatever its size, so the plan's bodies of it are no code any build emits. A test that observes a
	/// comparison compares every root that reaches a cycle.
	@TaskLocal public static var comparesOnlyRootsThePlanAdmits = false
}

/// Lets a test compare, for each production root that reaches a cycle, which of its plan's bodies the plan marks
/// `@Sendable` (`VariantBodies.isSendable(_:)`) with which the type key lays out as `@Sendable` (`WrittenVariantPlan`'s
/// family), each body at its position in the plan, the root's own first. Test only, until one of the two is removed.
/// Lets a test see, for each production root whose code is laid out from its per-type plan, whether the `@Sendable`
/// capture walk of the root's tree per path finds a capture (`ScopeGenerator.nonSendableWrapperCaptures(ofTreeRootedAt:)`).
/// The walk reads no root laid out from its plan, so it must find none. Test only.
public enum PlanCaptureObservation {
	/// Called once per such root, where today's tree is built too, with the root's type and whether today's walk finds a
	/// capture.
	@TaskLocal public static var observer: (@Sendable (_ root: String, _ todaysWalkFindsCapture: Bool) -> Void)?
}

public enum PlanSendableObservation {
	@TaskLocal public static var observer: (@Sendable (_ root: String, _ marksOfPlan: [Bool], _ familyOfLayout: [Bool]) -> Void)?
}

/// The per-type plan of one root's cycles as the type key reads it, written from the plan's bodies once their code is
/// planned: `generator(of:)` plans its code asynchronously, so each body's places are planned before the type key lays
/// the root out. The root's own body is at position 0, and each body the plan calls follows in the order the plan first
/// calls it.
///
/// Built only where a test observes the plan's code. Holds each body's places and calls until the root is laid out.
struct WrittenVariantPlan: TypeKeyVariantPlan {
	let rootStatements: [GeneratedCode]
	/// The record of each called body's place, at its position less one.
	private let records: [PlaceRecord?]
	/// For each body, the indices of the children of each place on the path to a call, by the place's path.
	private let childIndicesByPath: [[[Int]: [Int]]]
	private let callsByBody: [[VariantCall]]
	private let labelsByBody: [[String]]
	private let answersByBody: [[Answer]]
	private let sendableFamily: [Bool]

	var bodyCount: Int {
		callsByBody.count
	}

	/// What the type key reads of a plan's bodies before their code is planned, each body at its position in the plan: the
	/// root's own first, then each body it calls in the order the plan first calls it. Holds only values a task can send.
	struct Unplanned: Sendable {
		let generators: [ScopeGenerator]
		let calls: [[VariantCall]]
		let labels: [[String]]
		let answers: [[Answer]]
		/// Whether the plan marks each body `@Sendable` (`VariantBodies.isSendable(_:)`).
		let sendableMarks: [Bool]
		/// The type each body builds, and the declarations that answer the labels it reads from above.
		let instantiables: [Instantiable]
		let answerDeclarations: [[NearestDeclaration]]

		/// Whether a `@Sendable` function of some body may capture a wrapper that is not `Sendable` declared outside it:
		/// today's capture walk over each body's tree, each label it reads from above declared where its answer is, outside
		/// every `@Sendable` function of the body (`ScopeGenerator.mayCaptureNonSendableWrapper(asBodyOf:answeredBy:)`). A
		/// call of another body is a call place that receives every label the called body's tree receives, so a call
		/// inside a `@Sendable` function reads, at the call, what the called body reads from above.
		func mayCaptureNonSendableWrapper() async -> Bool {
			for (body, generator) in generators.enumerated() where await generator.mayCaptureNonSendableWrapper(asBodyOf: instantiables[body], answeredBy: answerDeclarations[body]) {
				return true
			}
			return false
		}

		/// The bodies of `plan` in `bodies`, each call of the body it calls by its position here, and each body's labels,
		/// with their answers and each call's arguments, in the order its function takes them, which every call of it
		/// gives (`VariantBodies.Call.argumentOrder`): the label it is built as, then the others as its tree first
		/// receives them.
		/// - Parameter plan: The positions of the root's body and the bodies it calls (`VariantBodies.plan(ofRoot:shadow:cache:)`).
		init(of bodies: DependencyTreeGenerator.VariantBodies, plan: (rootBody: Int, calledBodies: [Int])) {
			let positions = [plan.rootBody] + plan.calledBodies
			var bodyByPosition = [Int: Int]()
			for (body, position) in positions.enumerated() {
				bodyByPosition[position] = body
			}
			var argumentOrders = [[Int]](repeating: [], count: positions.count)
			var calls = [[VariantCall]]()
			for position in positions {
				calls.append(bodies.calls(of: position).map { call in
					// Every body called is among `plan.calledBodies`; a position that were not would be the root's, which
					// no function builds, and the type key would keep the path key's body.
					let calledBody = bodyByPosition[call.calledBody, default: 0]
					argumentOrders[calledBody] = call.argumentOrder
					return VariantCall(path: call.path, property: call.property, calledBody: calledBody, arguments: call.argumentOrder.map { call.arguments[$0] })
				})
			}
			generators = positions.map { bodies.generator(of: $0) }
			sendableMarks = positions.map { bodies.isSendable($0) }
			instantiables = positions.map { bodies.bodies[$0].copy.instantiable }
			answerDeclarations = positions.map { bodies.bodies[$0].answers.compactMap(\.self) }
			self.calls = calls
			labels = zip(positions, argumentOrders).map { position, order in order.map { bodies.bodies[position].labels[$0] } }
			answers = zip(positions, argumentOrders).map { position, order in order.map { bodies.bodies[position].planAnswers[$0] } }
		}
	}

	/// Plans the code of each body of `unplanned`, and writes what the type key reads of them.
	init(planning unplanned: Unplanned) async throws {
		rootStatements = try await unplanned.generators[0].generateChildPlans()
		var records = [PlaceRecord?]()
		for generator in unplanned.generators.dropFirst() {
			try await records.append(TypeKeyLayout.record(of: generator.generatePlan()))
		}
		self.records = records
		callsByBody = unplanned.calls
		labelsByBody = unplanned.labels
		answersByBody = unplanned.answers
		childIndicesByPath = zip(unplanned.generators, unplanned.calls).map { Self.childIndicesByPath(of: $0, toward: $1) }
		sendableFamily = Self.sendableFamily(of: unplanned.generators, callsByBody: unplanned.calls)
	}

	func record(ofBody body: Int) -> BuiltPlaceRecord? {
		// A body is built as the property its call place builds, so its place is one its generator builds.
		guard case let .built(built) = records[body - 1] else { return nil }
		return built
	}

	func childIndices(ofPlaceAt path: [Int], inBody body: Int) -> [Int] {
		childIndicesByPath[body][path, default: []]
	}

	func calls(of body: Int) -> [VariantCall] {
		callsByBody[body]
	}

	func labels(of body: Int) -> [String] {
		labelsByBody[body]
	}

	func answers(of body: Int) -> [Answer] {
		answersByBody[body]
	}

	func isInSendableFamily(_ body: Int) -> Bool {
		sendableFamily[body]
	}

	/// The indices into `propertiesToGenerate` of the children of each place of `generator`'s body that leads to one of
	/// `calls`, in the order it builds them, by the place's path, `[]` being the body's root: the layout reads no other
	/// place's children (`TypeKeyLayout.resolvingCalls(in:ofBody:plan:)`).
	private static func childIndicesByPath(of generator: ScopeGenerator, toward calls: [VariantCall]) -> [[Int]: [Int]] {
		let pathsToCalls = VariantCall.pathsLeadingTo(calls)
		var childIndicesByPath = [[Int]: [Int]]()
		var placesToVisit: [(path: [Int], generator: ScopeGenerator)] = [([], generator)]
		while let (path, place) = placesToVisit.popLast() {
			let children = place.orderedChildGeneratorsWithIndices
			childIndicesByPath[path] = children.map(\.index)
			for (index, child) in children where pathsToCalls.contains(path + [index]) {
				placesToVisit.append((path + [index], child))
			}
		}
		return childIndicesByPath
	}

	/// Whether each body's function is `@Sendable`: where the body's own generator builds in a `@Sendable` function, or
	/// some call of it is made inside one, at its call place or on the path to it, or in a body whose function is.
	static func sendableFamily(of generators: [ScopeGenerator], callsByBody: [[VariantCall]]) -> [Bool] {
		var sendableFamily = generators.map(\.buildsInSendableFunction)
		// Each pass only turns bodies `@Sendable`, so the passes end within a pass per body.
		var changed = true
		while changed {
			changed = false
			for (body, calls) in callsByBody.enumerated() {
				for call in calls where !sendableFamily[call.calledBody] {
					var generator = generators[body]
					var isInsideSendableFunction = sendableFamily[body]
					for index in call.path {
						generator = generator.propertiesToGenerate[index]
						isInsideSendableFunction = isInsideSendableFunction || generator.buildsInSendableFunction
					}
					if isInsideSendableFunction {
						sendableFamily[call.calledBody] = true
						changed = true
					}
				}
			}
		}
		return sendableFamily
	}
}
