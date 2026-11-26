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

/// Lets a test see the code a mock root's per-type plan lays out: the walk's records of the places that take each body,
/// one function per body, each call place a call of the body it calls handed its own configuration. Test only, until
/// the mock's code is written from it.
enum MockPlanCodeObservation {
	/// Called for each internal mock root that reaches a cycle, with the mocked type, the code its plan lays out, and
	/// `laidOut`, or `nil` and why the root keeps the walk's body.
	@TaskLocal static var observer: (@Sendable (_ mockedType: String, _ code: String?, _ outcome: String) -> Void)?
	/// Whether a mock root the plan lays out is written from the plan's code in place of the walk's: the switch-on twin a
	/// test compiles and compares the values of. Never set by the tool.
	@TaskLocal static var writesPlanCode = false

	/// Whether the lowering lays out mock roots' plans: a test observes the code or writes it.
	static var laysOutPlans: Bool {
		observer != nil || writesPlanCode
	}
}

/// What the mock's lowering reads of a mock root's per-type plan, built where a test observes the plan's code: each body
/// at its position, the root's own first, then each body it calls in the order the plan first calls it, with its calls,
/// its labels and their answers in the order its function takes them (as `WrittenVariantPlan.Unplanned` writes a
/// production root's), whether it is `@Sendable`, and the paths of today's places that take it.
///
/// Holds no body's generator: the walk records today's places, and each body is laid out from the record of a place that
/// takes it. Lives until the root is lowered.
struct MockCyclePlan: Sendable {
	/// Why the root keeps the walk's body whole, before any body is laid out; `nil` where its bodies are laid out.
	let keptPerPathBecause: String?
	let calls: [[VariantCall]]
	let labels: [[String]]
	let answers: [[Answer]]
	let isSendable: [Bool]
	/// For each body, the paths of today's places that take it, in the order the comparison's walk meets them, each an
	/// index into `propertiesToGenerate` per level from the mock's root; none for the root's own.
	let todaysPaths: [[[Int]]]

	/// The plan of `plan` in `bodies`, each call of the body it calls by its position here.
	/// - Parameters:
	///   - plan: The positions of the root's body and the bodies it calls (`VariantBodies.plan(ofMockRoot:…)`).
	///   - todaysPathsByBody: The paths of today's places that take each body, by the body's position in `bodies`.
	init(of bodies: DependencyTreeGenerator.VariantBodies, plan: (rootBody: Int, calledBodies: [Int]), todaysPathsByBody: [Int: [[Int]]]) {
		let positions = [plan.rootBody] + plan.calledBodies
		var bodyByPosition = [Int: Int]()
		for (body, position) in positions.enumerated() {
			bodyByPosition[position] = body
		}
		var argumentOrders = [[Int]](repeating: [], count: positions.count)
		var calls = [[VariantCall]]()
		for position in positions {
			calls.append(bodies.calls(of: position).map { call in
				// Every body called is among `plan.calledBodies`; a position that were not would be the root's, which no
				// function builds, and the layout would keep the walk's body.
				let calledBody = bodyByPosition[call.calledBody, default: 0]
				argumentOrders[calledBody] = call.argumentOrder
				return VariantCall(path: call.path, property: call.property, calledBody: calledBody, arguments: call.argumentOrder.map { call.arguments[$0] })
			})
		}
		keptPerPathBecause = nil
		self.calls = calls
		labels = zip(positions, argumentOrders).map { position, order in order.map { bodies.bodies[position].labels[$0] } }
		answers = zip(positions, argumentOrders).map { position, order in order.map { bodies.bodies[position].planAnswers[$0] } }
		isSendable = positions.map { bodies.isSendable($0) }
		todaysPaths = positions.enumerated().map { body, position in body == 0 ? [] : todaysPathsByBody[position, default: []] }
	}

	/// A root that keeps the walk's body whole, for `reason`.
	init(keptPerPathBecause reason: String) {
		keptPerPathBecause = reason
		calls = []
		labels = []
		answers = []
		isSendable = []
		todaysPaths = []
	}
}
