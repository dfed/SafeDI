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
	/// The values the call hands the called body's function besides its labels' answers, one per passed argument its
	/// record declares (`BuiltPlaceRecord.passedArguments`), in that order.
	var passedArguments = [PassedArgument]()

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

/// Why the type key does not lay out a root's body from a per-type plan, so that the root keeps the path key's body. Each
/// names the body of the plan, and the path of the place in it, where the layout stopped.
enum TypeKeyRefusal: Error, Hashable, Sendable {
	/// A call of `body` is of the root's own body, which no function builds, or of a body the plan does not have.
	case callOfBodyOutsidePlan(body: Int, calledBody: Int)
	/// Two calls of `body` are at the place at `path`.
	case twoCallsAtOnePlace(body: Int, path: [Int])
	/// `body`'s generator builds no place the type key reads.
	case bodyBuildsNoPlace(body: Int)
	/// A statement beneath the place at `path` in `body` is not a place.
	case statementIsNoPlace(body: Int, path: [Int])
	/// The place at `path` in `body` holds more places than its generator has children.
	case placesOutnumberChildren(body: Int, path: [Int])
	/// The place at `path` in `body` holds fewer places than its generator has children.
	case childrenOutnumberPlaces(body: Int, path: [Int])
	/// The call place at `path` in `body` is a rename, which no call can be.
	case callAtRename(body: Int, path: [Int])
	/// The call at `path` in `body` answers other labels than the body it calls takes.
	case answersDifferFromLabels(body: Int, path: [Int])
	/// The call at `path` in `body` passes other arguments than the body it calls declares.
	case passedArgumentsDifferFromParameters(body: Int, path: [Int])
	/// The call at `path` in `body` names no place of the body.
	case callNamesNoPlace(body: Int, path: [Int])

	// The layout of the root's body and its variants, in the order of its stages (`TypeKeyBody.layOut`).

	/// A root function a place calls is declared in place, where the type key spells no place written as text.
	case rootFunctionKeptInPlace
	/// A place is not one the walk of the bodies reads (`TypeKeyLayout.read(_:)`).
	case placeNotRead
	/// A view's reads from outside it do not resolve (`computeReads`).
	case readsNotResolved
	/// A variant's body reads a label it takes no cycle parameter of.
	case variantReadsLabelItTakesNoParameterOf
	/// A loop of builders the path key writes once (`laysOutLoops`).
	case loopWrittenOnce
	/// A function has no place every call of it sees (`computePlacement`).
	case functionNotPlaced
	/// No one type takes what every call of a function passes for a label (`computeParameterTypes`).
	case parameterHasNoType
	/// A read resolves at a place to another declaration than its view's (`checkEveryRead`).
	case readResolvesOtherwise
	/// A value path resolves at a place to another declaration than its view's (`checkValuePaths`).
	case valuePathResolvesOtherwise
	/// A function's `@Sendable` mark differs from the path key's (`checkSendableMarks`).
	case sendableMarkDiffers
	/// A statement is not spelled (`spelledRootStatements`).
	case statementNotSpelled
}

extension TypeKeyBody {
	/// The statements of a root's body laid out from the per-type plan `plan`: the root's own body is the root's
	/// statements, each other body a variant whose function the root declares, and each call place a closing record of the
	/// body it calls. Throws a `TypeKeyRefusal` where the root keeps the path key's body.
	static func statements(ofPlan plan: some TypeKeyVariantPlan, outerDeclarations: [Property] = [], namesInScope: Set<String> = []) throws(TypeKeyRefusal) -> [GeneratedCode] {
		let rootStatements = try resolvingCalls(in: plan.rootStatements, ofBody: 0, plan: plan)
		var variants = [CycleVariantRecord]()
		for body in 1..<max(plan.bodyCount, 1) {
			guard let record = plan.record(ofBody: body) else { throw .bodyBuildsNoPlace(body: body) }
			let children = try resolvingCalls(in: TypeKeyLayout.statementCodes(of: record.children), ofBody: body, plan: plan)
			variants.append(CycleVariantRecord(
				record: record.with(children: children),
				isInSendableFamily: plan.isInSendableFamily(body),
				labels: plan.labels(of: body),
				answers: plan.answers(of: body),
			))
		}
		return try layOut(rootStatements, variants: variants, outerDeclarations: outerDeclarations, namesInScope: namesInScope).get()
	}

	/// `statements`, the places of body `body`'s root, with each call place `plan` gives the body a closing record of the
	/// body it calls, at every depth. Throws where a call's path names no place, a place is not one a call place can be, or a
	/// call is of the root's own body, which no function builds.
	private static func resolvingCalls(in statements: [GeneratedCode], ofBody body: Int, plan: some TypeKeyVariantPlan) throws(TypeKeyRefusal) -> [GeneratedCode] {
		let calls = plan.calls(of: body)
		var callsByPath = [[Int]: VariantCall]()
		for call in calls {
			guard call.calledBody > 0, call.calledBody < plan.bodyCount else { throw .callOfBodyOutsidePlan(body: body, calledBody: call.calledBody) }
			guard callsByPath.updateValue(call, forKey: call.path) == nil else { throw .twoCallsAtOnePlace(body: body, path: call.path) }
		}
		// Only a place on the path to a call changes; every other is kept as its statement is.
		let pathsToCalls = VariantCall.pathsLeadingTo(calls)
		var resolvedPaths = Set<[Int]>()
		var resolvedStatements = [GeneratedCode]()
		var frames = [CallResolutionFrame(path: [], statements: statements, childIndices: plan.childIndices(ofPlaceAt: [], inBody: body), owner: nil)]
		while var frame = frames.popLast() {
			guard frame.next < frame.statements.count else {
				// Every child of the place's generator is a place of its body, in the order the generator builds them.
				guard frame.places == frame.childIndices.count else { throw .childrenOutnumberPlaces(body: body, path: frame.path) }
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
			guard let record = TypeKeyLayout.record(of: statement) else { throw .statementIsNoPlace(body: body, path: frame.path) }
			guard frame.places < frame.childIndices.count else { throw .placesOutnumberChildren(body: body, path: frame.path) }
			let path = frame.path + [frame.childIndices[frame.places]]
			frame.places += 1
			if let call = callsByPath[path] {
				let closer = try closingRecord(of: call, at: record, inBody: body, plan: plan)
				resolvedPaths.insert(path)
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
		for call in calls where !resolvedPaths.contains(call.path) {
			throw .callNamesNoPlace(body: body, path: call.path)
		}
		return resolvedStatements
	}

	/// The closing record of `call`, made at a call place whose own record is `record`: the call's property, built by
	/// calling its body's function, which takes the called body's labels.
	private static func closingRecord(of call: VariantCall, at record: PlaceRecord, inBody body: Int, plan: some TypeKeyVariantPlan) throws(TypeKeyRefusal) -> ClosingPlaceRecord {
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
			throw .callAtRename(body: body, path: call.path)
		}
		let labels = plan.labels(of: call.calledBody)
		guard labels.count == call.arguments.count else { throw .answersDifferFromLabels(body: body, path: call.path) }
		let parameters = plan.record(ofBody: call.calledBody)?.passedArguments ?? []
		guard call.passedArguments.map(\.parameterName) == parameters.map(\.parameterName),
		      call.passedArguments.map(\.type) == parameters.map(\.type)
		else { throw .passedArgumentsDifferFromParameters(body: body, path: call.path) }
		var closer = ClosingPlaceRecord(
			callingVariant: call.calledBody - 1,
			property: call.property,
			isErased: isErased,
			isExtension: isExtension,
			forwardedProperties: forwardedProperties,
			labels: labels,
			arguments: call.arguments,
		)
		closer.passedArguments = call.passedArguments
		return closer
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
