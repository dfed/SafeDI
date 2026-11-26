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

/// The per-type plan of one root's cycles as the type key reads it, written from the plan's bodies once their code is
/// planned: `generator(of:)` plans its code asynchronously, so each body's places are planned before the type key lays
/// the root out. The root's own body is at position 0, and each body the plan calls follows in the order the plan first
/// calls it.
///
/// Built only where a test observes the plan's code. Holds each body's places and calls until the root is laid out.
struct WrittenVariantPlan: TypeKeyVariantPlan {
	let rootStatements: [GeneratedCode]
	/// The record of each called body's place, at its position less one.
	private let records: [BuiltPlaceRecord?]
	/// For each body, the indices of the children of each place, by the place's path.
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
			self.calls = calls
			labels = zip(positions, argumentOrders).map { position, order in order.map { bodies.bodies[position].labels[$0] } }
			answers = zip(positions, argumentOrders).map { position, order in order.map { bodies.bodies[position].planAnswers[$0] } }
		}
	}

	/// Plans the code of each body of `unplanned`, and writes what the type key reads of them.
	init(planning unplanned: Unplanned) async throws {
		rootStatements = try await unplanned.generators[0].generateChildPlans()
		var records = [BuiltPlaceRecord?]()
		for generator in unplanned.generators.dropFirst() {
			if case let .built(built) = try await TypeKeyLayout.record(of: generator.generatePlan()) {
				records.append(built)
			} else {
				records.append(nil)
			}
		}
		self.records = records
		callsByBody = unplanned.calls
		labelsByBody = unplanned.labels
		answersByBody = unplanned.answers
		childIndicesByPath = unplanned.generators.map(Self.childIndicesByPath(of:))
		sendableFamily = Self.sendableFamily(of: unplanned.generators, callsByBody: unplanned.calls)
	}

	func record(ofBody body: Int) -> BuiltPlaceRecord? {
		records[body - 1]
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

	/// The indices into `propertiesToGenerate` of the children of each place of `generator`'s body, in the order it builds
	/// them, by the place's path, `[]` being the body's root.
	private static func childIndicesByPath(of generator: ScopeGenerator) -> [[Int]: [Int]] {
		var childIndicesByPath = [[Int]: [Int]]()
		var placesToVisit: [(path: [Int], generator: ScopeGenerator)] = [([], generator)]
		while let (path, place) = placesToVisit.popLast() {
			let children = place.orderedChildGeneratorsWithIndices
			childIndicesByPath[path] = children.map(\.index)
			for (index, child) in children {
				placesToVisit.append((path + [index], child))
			}
		}
		return childIndicesByPath
	}

	/// Whether each body's function is `@Sendable`: where the body's own generator builds in a `@Sendable` function, or
	/// some call of it is made inside one, at its call place or on the path to it, or in a body whose function is.
	private static func sendableFamily(of generators: [ScopeGenerator], callsByBody: [[VariantCall]]) -> [Bool] {
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
