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

/// A call the per-type plan makes in a body: the child at `path`, indices into `propertiesToGenerate` from the body's
/// root to the call place, builds `property` by calling the body `calledBody`, answering its labels with `arguments`.
struct VariantCall: Sendable {
	let path: [Int]
	let property: Property
	let calledBody: Int
	let arguments: [Answer]

	/// The paths of the places beneath which one of `calls` is made: each proper prefix of a call's path, `[]` included.
	static func pathsLeadingTo(_ calls: [VariantCall]) -> Set<[Int]> {
		var paths = Set<[Int]>()
		for call in calls {
			var path = [Int]()
			paths.insert(path)
			for index in call.path.dropLast() {
				path.append(index)
				paths.insert(path)
			}
		}
		return paths
	}
}

/// What the type key reads of the per-type plan of one root's cycles: its bodies, the root's own first, each with its
/// generator's places, the calls each makes, and the answers it is keyed by. The plan's bodies (`VariantBodies`, through
/// `generator(of:)` and `calls(of:)`) are one; a test's fake is another.
protocol TypeKeyVariantPlan {
	/// How many bodies the plan builds, the root's own at position 0.
	var bodyCount: Int { get }
	/// The places of the root's own body, in the order its generator builds its children.
	var rootStatements: [GeneratedCode] { get }
	/// The record of the place body `body`'s generator builds as its property, its children's places in it, or `nil`
	/// where the generator builds no place the type key reads. Never asked of the root's own body.
	func record(ofBody body: Int) -> BuiltPlaceRecord?
	/// The indices into `propertiesToGenerate` of the children of the place at `path` in body `body`, in the order its
	/// generator builds them, `[]` being the body's root.
	func childIndices(ofPlaceAt path: [Int], inBody body: Int) -> [Int]
	/// The calls body `body` makes, each at its call place.
	func calls(of body: Int) -> [VariantCall]
	/// The labels body `body`'s declaration reads from above, in the order its function takes them, and what its calls
	/// answer each.
	func labels(of body: Int) -> [String]
	func answers(of body: Int) -> [Answer]
	func isInSendableFamily(_ body: Int) -> Bool
}

extension TypeKeyBody {
	/// The statements of a root's body laid out from the per-type plan `plan`, or `nil` where the root keeps the path key's
	/// body: the root's own body is the root's statements, each other body a variant whose function the root declares, and
	/// each call place a closing record of the body it calls.
	static func statements(ofPlan plan: some TypeKeyVariantPlan, outerDeclarations: [Property] = [], namesInScope: Set<String> = []) -> [GeneratedCode]? {
		guard let rootStatements = resolvingCalls(in: plan.rootStatements, ofBody: 0, plan: plan) else { return nil }
		var variants = [CycleVariantRecord]()
		for body in 1..<max(plan.bodyCount, 1) {
			guard let record = plan.record(ofBody: body),
			      let children = resolvingCalls(in: TypeKeyLayout.statementCodes(of: record.children), ofBody: body, plan: plan)
			else { return nil }
			variants.append(CycleVariantRecord(
				record: record.with(children: children),
				isInSendableFamily: plan.isInSendableFamily(body),
				labels: plan.labels(of: body),
				answers: plan.answers(of: body),
			))
		}
		return statements(ofRootBody: rootStatements, variants: variants, outerDeclarations: outerDeclarations, namesInScope: namesInScope)
	}

	/// `statements`, the places of body `body`'s root, with each call place `plan` gives the body a closing record of the
	/// body it calls, at every depth; `nil` where a call's path names no place, a place is not one a call place can be, or a
	/// call is of the root's own body, which no function builds.
	private static func resolvingCalls(in statements: [GeneratedCode], ofBody body: Int, plan: some TypeKeyVariantPlan) -> [GeneratedCode]? {
		let calls = plan.calls(of: body)
		var callsByPath = [[Int]: VariantCall]()
		for call in calls {
			guard call.calledBody > 0, call.calledBody < plan.bodyCount, callsByPath.updateValue(call, forKey: call.path) == nil else { return nil }
		}
		// Only a place on the path to a call changes; every other is kept as its statement is.
		let pathsToCalls = VariantCall.pathsLeadingTo(calls)
		var resolvedCalls = 0
		var resolvedStatements = [GeneratedCode]()
		var frames = [CallResolutionFrame(path: [], statements: statements, childIndices: plan.childIndices(ofPlaceAt: [], inBody: body), owner: nil)]
		while var frame = frames.popLast() {
			guard frame.next < frame.statements.count else {
				// Every child of the place's generator is a place of its body, in the order the generator builds them.
				guard frame.places == frame.childIndices.count else { return nil }
				if let owner = frame.owner {
					frames[frames.count - 1].resolved.append(replacingRecord(in: owner.statement, with: .built(owner.record.with(children: frame.resolved))))
				} else {
					resolvedStatements = frame.resolved
				}
				continue
			}
			let statement = frame.statements[frame.next]
			frame.next += 1
			// Every statement of a body the type key reads is a place.
			guard let record = TypeKeyLayout.record(of: statement), frame.places < frame.childIndices.count else { return nil }
			let path = frame.path + [frame.childIndices[frame.places]]
			frame.places += 1
			if let call = callsByPath[path] {
				guard let closer = closingRecord(of: call, at: record, plan: plan) else { return nil }
				resolvedCalls += 1
				frame.resolved.append(replacingRecord(in: statement, with: .closer(closer)))
				frames.append(frame)
			} else if case let .built(built) = record, !built.children.isEmpty, pathsToCalls.contains(path) {
				frames.append(frame)
				frames.append(CallResolutionFrame(path: path, statements: TypeKeyLayout.statementCodes(of: built.children), childIndices: plan.childIndices(ofPlaceAt: path, inBody: body), owner: (statement, built)))
			} else {
				frame.resolved.append(statement)
				frames.append(frame)
			}
		}
		// Each call names one place, so a call no place took names none.
		guard resolvedCalls == calls.count else { return nil }
		return resolvedStatements
	}

	/// The closing record of `call`, made at a call place whose own record is `record`: the call's property, built by
	/// calling its body's function, which takes the called body's labels.
	private static func closingRecord(of call: VariantCall, at record: PlaceRecord, plan: some TypeKeyVariantPlan) -> ClosingPlaceRecord? {
		let isErased: Bool
		let isExtension: Bool
		let forwardedProperties: [Property]
		switch record {
		case let .built(built):
			isErased = built.isErased
			isExtension = built.isExtension
			forwardedProperties = built.forwardedProperties.sorted()
		case let .closer(closer):
			isErased = closer.isErased
			isExtension = closer.isExtension
			forwardedProperties = closer.forwardedProperties
		case .alias:
			return nil
		}
		let labels = plan.labels(of: call.calledBody)
		let answers = plan.answers(of: call.calledBody)
		guard labels.count == call.arguments.count, answers.count == call.arguments.count else { return nil }
		return ClosingPlaceRecord(
			callingVariant: call.calledBody - 1,
			property: call.property,
			isErased: isErased,
			isExtension: isExtension,
			forwardedProperties: forwardedProperties,
			labels: labels,
			answers: answers,
			arguments: call.arguments,
		)
	}

	/// `statement`, a place under its indentations, with its record `record`.
	private static func replacingRecord(in statement: GeneratedCode, with record: PlaceRecord) -> GeneratedCode {
		var indentations = [String]()
		var inner = statement
		while case let .indented(wrapped, indentation) = inner.node {
			indentations.append(indentation)
			inner = wrapped
		}
		guard case let .place(plan) = inner.node else { return statement }
		return indentations.reversed().reduce(GeneratedCode.place(plan.with(record: record))) { code, indentation in .indented(code, by: indentation) }
	}
}

extension BuiltPlaceRecord {
	/// This record, holding the places `children` beneath it.
	func with(children: [GeneratedCode]) -> BuiltPlaceRecord {
		var record = BuiltPlaceRecord(
			property: property,
			isErased: isErased,
			concreteType: concreteType,
			isExtension: isExtension,
			target: target,
			arguments: arguments,
			forwardedProperties: forwardedProperties,
			cycleParameters: cycleParameters,
			callCycleArguments: callCycleArguments,
			functionName: functionName,
			isSendable: isSendable,
			typesDeclaredEscaping: typesDeclaredEscaping,
			lineEnd: lineEnd,
			hasFunction: hasFunction,
			children: children,
			node: node,
		)
		record.sharingFields = sharingFields
		return record
	}
}

/// A place whose children `TypeKeyBody.statements(ofPlan:)` is resolving the calls of.
private struct CallResolutionFrame {
	let path: [Int]
	let statements: [GeneratedCode]
	let childIndices: [Int]
	/// The statement of the parent's that holds this frame's place, and its record, `nil` for the body's root.
	let owner: (statement: GeneratedCode, record: BuiltPlaceRecord)?
	var next = 0
	var places = 0
	var resolved = [GeneratedCode]()
}
