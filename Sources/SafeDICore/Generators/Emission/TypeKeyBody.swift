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
	/// root keeps `rootBody`, the path key's statements.
	static func statements(ofRootBody rootBody: [GeneratedCode]) -> [GeneratedCode]? {
		var layout = TypeKeyLayout()
		guard layout.read(rootBody) else { return nil }
		GenerationWork.record(layout.bodies.count - 1, by: .layingOutTypeKeyViews)
		guard layout.computeReads() else { return nil }
		layout.computeClasses()
		guard layout.computePlacement() else { return nil }
		layout.computeOutcomes()
		guard layout.computeParameterTypes(),
		      layout.checkEveryRead()
		else { return nil }
		layout.computeDecoratorsAndNames()
		return layout.spelledRootStatements()
	}
}

/// A declaration of the path key's body: a statement of a body, a forwarded property or a cycle parameter of a place's
/// function, or none.
private enum PathValue: Hashable {
	case none
	case statement(body: Int, index: Int)
	case forwarded(body: Int, label: String)
	case cycleParameter(body: Int, label: String)
}

/// A declaration of the type key's body: a statement of a class's body or the root's (class 0), a forwarded property of a
/// class's function, a read a class's function takes as a parameter, or none.
private enum TypeDeclaration: Hashable {
	case none
	case statement(owner: Int, index: Int)
	case forwarded(owner: Int, label: String)
	case read(owner: Int, label: String)
}

/// What a class's function does with a label it reads and does not bind.
private enum ReadOutcome: Hashable {
	/// No call provides it: the function reads `nil`.
	case none
	/// Every call resolves it to the declaration visible where the function is declared, which the function captures.
	case captured(TypeDeclaration)
	/// The function takes it as a parameter.
	case passed
}

/// A position in a class's body (or the root's, class 0) at which a call of a class's function is made.
private struct CallSite: Hashable {
	let owner: Int
	let index: Int
}

private struct TypeKeyLayout {
	/// A body of the path key's walk, laid out once for each view (R1b §2a): the root's (body 0), or the builder function
	/// of the places of one plan node, in one family, whose look-ups outside it resolve to the same declarations and whose
	/// cycle parameters are passed the same declarations. Every step asks a view what it would ask each of its places, and
	/// asks it through the view's first place only, since every place answers alike: the key holds what each look-up
	/// outside the view resolves to (`ViewKey.outerView`), and each place's call is checked where its parent makes it
	/// (`checkEveryRead`'s `.built` case, run for every body that holds a place of the view).
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
		var statements = [Statement]()
		var positionsByLabel = [String: [Int]]()
		let forwardedLabels: Set<String>
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
	}

	/// What tells two places of one plan node apart (`Body`).
	struct ViewKey: Hashable {
		let node: PlanNode
		let isInSendableFamily: Bool
		let outerView: [String: PathValue]
		let cycleArguments: [PathValue]
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
	/// The views other than the root's in post-order of the view DAG.
	var postOrder = [Int]()
	/// The domain of each plan node the walk reached.
	var domainsByNode = [PlanNode: Domain]()
	/// The closing statements that call each body's function: their body and their index in it.
	var closersByTarget = [Int: [(body: Int, index: Int)]]()
	/// The labels each body's function reads and does not bind, in the order it first reads them.
	var reads = [[String]]()
	/// The labels of each body's reads that some read inside it requires a value of.
	var requiredReads = [Set<String>]()
	/// For each body, the first declaration outside it each label it reads resolves to, `.none` where every such read is
	/// `nil`.
	var escapingReads = [[String: PathValue]]()
	/// Each body's class, numbered from 1 in the order the walk first reaches a member; the root is class 0.
	var classByBody = [Int]()
	/// Each class's members, in walk order.
	var membersByClass = [[Int]]()
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
	var outcomes = [[String: ReadOutcome]]()
	var parameterTypes = [[String: TypeDescription]]()
	/// The value each cycle parameter of a place holds at every call of its function, where every call passes one.
	var normalizedCycleParameters = [Int: [String: PathValue]]()
	var isDecorated = [Bool]()
	var functionNames = [String]()

	// MARK: Reading the path key's plan

	/// Reads the places of the root's body, `rootBody`, depth first; `false` where a place records nothing.
	mutating func read(_ rootBody: [GeneratedCode]) -> Bool {
		bodies.append(Body(parent: -1, position: 0, record: nil, isInSendableFamily: false, domainLabels: [], forwardedLabels: [], cycleParameterLabels: []))
		var viewsByKey = [ViewKey: Int]()
		var frames = [(body: 0, children: rootBody, next: 0)]
		while let frame = frames.last {
			guard frame.next < frame.children.count else {
				frames.removeLast()
				continue
			}
			frames[frames.count - 1].next += 1
			let body = frame.body
			guard let record = Self.record(of: frame.children[frame.next]) else { return false }
			let position = bodies[body].statements.count
			let statement: Statement
			let label: String
			switch record {
			case let .built(built):
				label = built.property.label
				if built.hasFunction {
					guard let domain = domain(of: built) else { return false }
					let isInSendableFamily = built.isSendable || bodies[body].isInSendableFamily
					// A closer passes the function it calls what that function reads, which the closer's body looks up outside
					// itself: the labels of the target's domain are this view's too.
					var labels = domain.labels
					for name in domain.closedOnFunctionNames {
						var target = body
						while target != 0, bodies[target].record?.functionName != name {
							target = bodies[target].parent
						}
						labels.formUnion(bodies[target].domainLabels)
					}
					var outerView = [String: PathValue]()
					for label in labels {
						outerView[label] = lookUp(label, inBody: body, before: position)
					}
					let key = ViewKey(
						node: built.node,
						isInSendableFamily: isInSendableFamily,
						outerView: outerView,
						cycleArguments: built.callCycleArguments.map { pathValue(of: $0, inBody: body, before: position) },
					)
					if let view = viewsByKey[key] {
						bodies[view].otherEdges.append((parent: body, position: position))
						statement = .built(body: view)
					} else {
						let newBody = bodies.count
						bodies.append(Body(
							parent: body,
							position: position,
							record: built,
							isInSendableFamily: isInSendableFamily,
							domainLabels: labels,
							forwardedLabels: Set(built.forwardedProperties.map(\.label)),
							cycleParameterLabels: Set(built.cycleParameters.map(\.label)),
						))
						viewsByKey[key] = newBody
						statement = .built(body: newBody)
						frames.append((body: newBody, children: built.children, next: 0))
					}
				} else {
					guard built.children.isEmpty, built.cycleParameters.isEmpty else { return false }
					statement = .inline(built)
				}
			case let .closer(closer):
				label = closer.property.label
				// The function a closing scope calls is the nearest enclosing one of its name, as Swift resolves it.
				var target = body
				while target != 0, bodies[target].record?.functionName != closer.closedOnFunctionName {
					target = bodies[target].parent
				}
				guard target != 0 else { return false }
				statement = .closer(closer, target: target)
				closersByTarget[target, default: []].append((body: body, index: position))
			case let .alias(alias):
				label = alias.property.label
				statement = .alias(alias)
			}
			bodies[body].statements.append(statement)
			bodies[body].positionsByLabel[label, default: []].append(position)
		}
		return true
	}

	/// What `built`'s body looks up outside itself, or `nil` where a place beneath it records nothing. The plan nodes
	/// beneath it are computed first, each once, with a stack, since a plan can be as deep as the module has types.
	private mutating func domain(of built: BuiltPlaceRecord) -> Domain? {
		if let domain = domainsByNode[built.node] {
			return domain
		}
		var stack = [built]
		while let current = stack.last {
			guard domainsByNode[current.node] == nil else {
				stack.removeLast()
				continue
			}
			var children = [PlaceRecord]()
			for code in current.children {
				guard let record = Self.record(of: code) else { return nil }
				children.append(record)
			}
			let pending = children.compactMap { child -> BuiltPlaceRecord? in
				guard case let .built(childBuilt) = child, childBuilt.hasFunction, domainsByNode[childBuilt.node] == nil else { return nil }
				return childBuilt
			}
			guard pending.isEmpty else {
				stack.append(contentsOf: pending)
				continue
			}
			stack.removeLast()
			let bound = Set(current.forwardedProperties.map(\.label)).union(current.cycleParameters.map(\.label))
			var boundBefore = Set<String>()
			var domain = Domain()
			// A read of `nil` is in the domain too: the checks look up every label a function reads, whatever its places read.
			func lookUp(_ read: PlaceRead) {
				if !bound.contains(read.label), !boundBefore.contains(read.label) {
					domain.labels.insert(read.label)
				}
			}
			func close(_ name: String) {
				if name != current.functionName {
					domain.closedOnFunctionNames.insert(name)
				}
			}
			for child in children {
				switch child {
				case let .built(childBuilt):
					childBuilt.callCycleArguments.forEach(lookUp)
					if childBuilt.hasFunction, let childDomain = domainsByNode[childBuilt.node] {
						for label in childDomain.labels where !bound.contains(label) && !boundBefore.contains(label) {
							domain.labels.insert(label)
						}
						childDomain.closedOnFunctionNames.forEach(close)
					} else {
						childBuilt.arguments.forEach(lookUp)
					}
					boundBefore.insert(childBuilt.property.label)
				case let .closer(closer):
					closer.cycleArguments.forEach(lookUp)
					close(closer.closedOnFunctionName)
					boundBefore.insert(closer.property.label)
				case let .alias(alias):
					if let fulfillingProperty = alias.fulfillingProperty, !bound.contains(fulfillingProperty.label), !boundBefore.contains(fulfillingProperty.label) {
						domain.labels.insert(fulfillingProperty.label)
					}
					boundBefore.insert(alias.property.label)
				}
			}
			current.arguments.forEach(lookUp)
			domainsByNode[current.node] = domain
		}
		return domainsByNode[built.node]
	}

	/// The record of a place's code, as a body holds it: indented, around the place's plan.
	private static func record(of code: GeneratedCode) -> PlaceRecord? {
		var code = code
		while case let .indented(inner, _) = code.node {
			code = inner
		}
		guard case let .place(plan) = code.node else { return nil }
		return plan.record
	}

	func label(of statement: Statement) -> String {
		switch statement {
		case let .built(body):
			bodies[body].record?.property.label ?? ""
		case let .inline(record):
			record.property.label
		case let .closer(record, _):
			record.property.label
		case let .alias(record):
			record.property.label
		}
	}

	/// The property `statement` declares.
	func property(of statement: Statement) -> Property? {
		switch statement {
		case let .built(body):
			bodies[body].record?.property
		case let .inline(record):
			record.property
		case let .closer(record, _):
			record.property
		case let .alias(record):
			record.property
		}
	}

	// MARK: The path key's declarations

	/// The nearest declaration of `label` the path key's code sees before the statement at `index` of `body`.
	func lookUp(_ label: String, inBody body: Int, before index: Int) -> PathValue {
		var body = body
		var index = index
		while body != 0,
		      bodies[body].positionsByLabel[label]?.contains(where: { $0 < index }) != true,
		      !bodies[body].forwardedLabels.contains(label),
		      !bodies[body].cycleParameterLabels.contains(label)
		{
			index = bodies[body].position
			body = bodies[body].parent
		}
		if let position = bodies[body].positionsByLabel[label]?.last(where: { $0 < index }) {
			return .statement(body: body, index: position)
		} else if body == 0 {
			return .none
		} else if bodies[body].forwardedLabels.contains(label) {
			return .forwarded(body: body, label: label)
		} else {
			return .cycleParameter(body: body, label: label)
		}
	}

	/// What `read`, made before the statement at `index` of `body`, reads in the path key's code.
	func pathValue(of read: PlaceRead, inBody body: Int, before index: Int) -> PathValue {
		switch read.source {
		case .nil:
			.none
		case .binding,
		     .lazyInstance,
		     .forwardedSpread,
		     .wrapper,
		     .optionalWrapper,
		     .builderArgument,
		     .holeArgument:
			lookUp(read.label, inBody: body, before: index)
		}
	}

	/// The declaration the place whose function is `body` resolves `label` to where it is called from its parent: what its
	/// binding passes a cycle parameter, else the first declaration outside it its reads of the label resolve to, `.none`
	/// where they all read `nil`, else the nearest declaration at its binding.
	func resolution(of label: String, atPlace body: Int) -> PathValue {
		if bodies[body].cycleParameterLabels.contains(label) {
			bodies[body].record?.callCycleArguments.first(where: { $0.label == label }).map {
				pathValue(of: $0, inBody: bodies[body].parent, before: bodies[body].position)
			} ?? .none
		} else if let value = escapingReads[body][label] {
			value
		} else {
			lookUp(label, inBody: bodies[body].parent, before: bodies[body].position)
		}
	}

	// MARK: Reads

	/// The labels each place's function reads and does not bind, and where its reads escape it; `false` where they do not
	/// settle.
	mutating func computeReads() -> Bool {
		// Each pass recomputes, in reverse order, only a body one of whose children or closed-on targets changed since the
		// body was last computed: recomputing any other gives what it holds, so every pass ends as a pass over every body
		// would, at a cost that follows what changes.
		let dependents = dependentsOfBodies()
		postOrder = postOrderOfViews()
		reads = Array(repeating: [], count: bodies.count)
		guard settle(dependents: dependents, recompute: { layout, body in
			let bodyReads = layout.readsOfBody(body)
			guard bodyReads != layout.reads[body] else { return false }
			layout.reads[body] = bodyReads
			return true
		}) else { return false }
		escapingReads = Array(repeating: [:], count: bodies.count)
		for body in postOrder {
			escapingReads[body] = escapingReadsOfBody(body)
		}
		requiredReads = Array(repeating: [], count: bodies.count)
		return settle(dependents: dependents, recompute: { layout, body in
			let required = layout.requiredReadsOfBody(body)
			guard required != layout.requiredReads[body] else { return false }
			layout.requiredReads[body] = required
			return true
		})
	}

	/// The bodies whose reads read each body's: the body holding it as a child, and each body holding a closer on it.
	private func dependentsOfBodies() -> [[Int]] {
		var dependents = [[Int]](repeating: [], count: bodies.count)
		for body in bodies.indices.dropFirst() {
			for statement in bodies[body].statements {
				switch statement {
				case let .built(child):
					dependents[child].append(body)
				case let .closer(_, target):
					dependents[target].append(body)
				case .inline, .alias:
					break
				}
			}
		}
		return dependents
	}

	/// The views other than the root's, each after every view its body builds: post-order of the view DAG.
	private func postOrderOfViews() -> [Int] {
		var order = [Int]()
		var isVisited = [Bool](repeating: false, count: bodies.count)
		var frames = [(body: 0, next: 0)]
		isVisited[0] = true
		while let frame = frames.last {
			let statements = bodies[frame.body].statements
			guard frame.next < statements.count else {
				frames.removeLast()
				if frame.body != 0 {
					order.append(frame.body)
				}
				continue
			}
			frames[frames.count - 1].next += 1
			if case let .built(child) = statements[frame.next], !isVisited[child] {
				isVisited[child] = true
				frames.append((body: child, next: 0))
			}
		}
		return order
	}

	/// How many places the views stand for, saturating at `Int.max`: each view stands for one place at each place of each
	/// body holding it.
	private func placeCount() -> Int {
		var placesByBody = [Int](repeating: 0, count: bodies.count)
		placesByBody[0] = 1
		var total = 0
		for body in postOrder.reversed() {
			var places = 0
			for edge in bodies[body].edges {
				let (sum, overflow) = places.addingReportingOverflow(placesByBody[edge.parent])
				places = overflow ? Int.max : sum
			}
			placesByBody[body] = places
			let (sum, overflow) = total.addingReportingOverflow(places)
			total = overflow ? Int.max : sum
		}
		return total
	}

	/// Runs passes over the views in post-order until no view changes, recomputing a view only where it is dirty: never
	/// computed, or a view it reads changed since. `recompute` returns whether the view changed. `false` where the passes
	/// do not settle within one pass per place, as many as the path key's per-place passes could take.
	private mutating func settle(dependents: [[Int]], recompute: (inout TypeKeyLayout, Int) -> Bool) -> Bool {
		var dirty = [Bool](repeating: true, count: bodies.count)
		var anyDirty = true
		var passes = 0
		let (bound, overflow) = placeCount().addingReportingOverflow(2)
		let passBound = overflow ? Int.max : bound
		while anyDirty {
			anyDirty = false
			passes += 1
			guard passes <= passBound else { return false }
			for body in postOrder where dirty[body] {
				dirty[body] = false
				guard recompute(&self, body) else { continue }
				for dependent in dependents[body] {
					dirty[dependent] = true
					anyDirty = true
				}
			}
		}
		return true
	}

	/// The labels of `body`'s reads that some read inside it requires a value of, as a non-optional receive does.
	private func requiredReadsOfBody(_ body: Int) -> Set<String> {
		var required = Set<String>()
		func note(_ read: PlaceRead) {
			if !read.property.typeDescription.isOptional {
				required.insert(read.label)
			}
		}
		bodies[body].record?.arguments.forEach(note)
		for statement in bodies[body].statements {
			switch statement {
			case let .built(child):
				required.formUnion(requiredReads[child])
				bodies[child].record?.callCycleArguments.forEach(note)
			case let .inline(record):
				record.arguments.forEach(note)
			case let .closer(record, target):
				record.cycleArguments.forEach(note)
				required.formUnion(requiredReads[target])
			case let .alias(record):
				if let fulfillingProperty = record.fulfillingProperty, !fulfillingProperty.typeDescription.isOptional {
					required.insert(fulfillingProperty.label)
				}
			}
		}
		return required.intersection(reads[body])
	}

	private func readsOfBody(_ body: Int) -> [String] {
		var seen = Set<String>()
		var list = [String]()
		func add(_ label: String) {
			if seen.insert(label).inserted {
				list.append(label)
			}
		}
		for argument in bodies[body].record?.arguments ?? [] {
			add(argument.label)
		}
		for statement in bodies[body].statements {
			switch statement {
			case let .built(child):
				reads[child].forEach(add)
				for argument in bodies[child].record?.callCycleArguments ?? [] {
					add(argument.label)
				}
			case let .inline(record):
				record.arguments.forEach { add($0.label) }
			case let .closer(record, target):
				record.cycleArguments.forEach { add($0.label) }
				reads[target].forEach(add)
			case let .alias(record):
				if let fulfillingProperty = record.fulfillingProperty {
					add(fulfillingProperty.label)
				}
			}
		}
		return list.filter { !bodies[body].forwardedLabels.contains($0) && bodies[body].positionsByLabel[$0] == nil }
	}

	private func escapingReadsOfBody(_ body: Int) -> [String: PathValue] {
		var escaping = [String: PathValue]()
		func note(_ label: String, _ value: PathValue) {
			switch value {
			case .none:
				if escaping[label] == nil {
					escaping[label] = PathValue.none
				}
			case let .statement(declaringBody, _),
			     let .forwarded(declaringBody, _),
			     let .cycleParameter(declaringBody, _):
				if declaringBody != body, escaping[label] == nil || escaping[label] == PathValue.none {
					escaping[label] = value
				}
			}
		}
		let statements = bodies[body].statements
		for argument in bodies[body].record?.arguments ?? [] {
			note(argument.label, pathValue(of: argument, inBody: body, before: statements.count))
		}
		for (index, statement) in statements.enumerated() {
			switch statement {
			case let .built(child):
				for (label, value) in escapingReads[child].sorted(by: { $0.key < $1.key }) {
					note(label, value)
				}
				for argument in bodies[child].record?.callCycleArguments ?? [] {
					note(argument.label, pathValue(of: argument, inBody: body, before: index))
				}
			case let .inline(record):
				for argument in record.arguments {
					note(argument.label, pathValue(of: argument, inBody: body, before: index))
				}
			case let .closer(record, _):
				for argument in record.cycleArguments {
					note(argument.label, pathValue(of: argument, inBody: body, before: index))
				}
			case let .alias(record):
				if let fulfillingProperty = record.fulfillingProperty {
					note(fulfillingProperty.label, lookUp(fulfillingProperty.label, inBody: body, before: index))
				}
			}
		}
		return escaping.filter { !bodies[body].forwardedLabels.contains($0.key) && !bodies[body].cycleParameterLabels.contains($0.key) && bodies[body].positionsByLabel[$0.key] == nil }
	}

	// MARK: Classes

	/// The type of a path declaration.
	func type(of value: PathValue) -> TypeDescription? {
		switch value {
		case .none:
			nil
		case let .statement(body, index):
			property(of: bodies[body].statements[index])?.typeDescription
		case let .forwarded(body, label):
			bodies[body].record?.forwardedProperties.first(where: { $0.label == label })?.typeDescription
		case let .cycleParameter(body, label):
			bodies[body].record?.cycleParameters.first(where: { $0.label == label })?.typeDescription
		}
	}

	/// Partitions the places into classes: by what each builds and how, its reads, the shape of its body and the classes its
	/// body calls, and the form of the declaration each read resolves to.
	mutating func computeClasses() {
		let count = bodies.count
		let families = bodies.map(\.isInSendableFamily)
		var structuralKeys = [[String]: Int]()
		var classes = [Int](repeating: 0, count: count)
		for body in bodies.indices.dropFirst() {
			let key = structuralKey(of: body, isInSendableFamily: families[body])
			classes[body] = structuralKeys[key] ?? {
				let id = structuralKeys.count + 1
				structuralKeys[key] = id
				return id
			}()
		}
		var refined = refine(classes)
		// Places alike in every other way are one class only where each read resolves to declarations of one form, or none.
		var groupsByClass = [Int: [[String?]]]()
		var groupedClasses = [[Int]: Int]()
		var classesWithForms = [Int](repeating: 0, count: count)
		for body in bodies.indices.dropFirst() {
			let forms: [String?] = reads[body].map { label in type(of: resolution(of: label, atPlace: body))?.unwrapped.asSource }
			var groups = groupsByClass[refined[body], default: []]
			var groupIndex = groups.firstIndex { group in
				zip(group, forms).allSatisfy { $0 == nil || $1 == nil || $0 == $1 }
			}
			if let existing = groupIndex {
				groups[existing] = zip(groups[existing], forms).map { $0 ?? $1 }
			} else {
				groupIndex = groups.count
				groups.append(forms)
			}
			groupsByClass[refined[body]] = groups
			let key = [refined[body], groupIndex ?? 0]
			classesWithForms[body] = groupedClasses[key] ?? {
				let id = groupedClasses.count + 1
				groupedClasses[key] = id
				return id
			}()
		}
		refined = refine(classesWithForms)
		// Classes are numbered in the order the walk first reaches a member.
		var numbering = [Int: Int]()
		classByBody = [Int](repeating: 0, count: count)
		membersByClass = [[]]
		for body in bodies.indices.dropFirst() {
			let id = numbering[refined[body]] ?? {
				let id = membersByClass.count
				numbering[refined[body]] = id
				membersByClass.append([])
				return id
			}()
			classByBody[body] = id
			membersByClass[id].append(body)
		}
	}

	private func structuralKey(of body: Int, isInSendableFamily: Bool) -> [String] {
		guard let record = bodies[body].record else { return [] }
		var key = [
			record.concreteType.asSource,
			record.target.callee,
			"\(record.isExtension)",
			record.lineEnd,
			"\(isInSendableFamily)",
			"\(record.isNonisolated)",
			record.forwardedProperties.map(\.asSource).joined(separator: ","),
			reads[body].joined(separator: ","),
		]
		for argument in record.arguments {
			key.append("argument|\(argument.argumentLabel)|\(argument.label)|\(argument.property.asSource)")
		}
		for statement in bodies[body].statements {
			key.append(statementShape(statement))
		}
		return key
	}

	private func statementShape(_ statement: Statement) -> String {
		switch statement {
		case let .built(child):
			guard let record = bodies[child].record else { return "" }
			return "call|\(record.property.asSource)|\(record.isErased)|\(record.isExtension)"
		case let .closer(record, _):
			return "call|\(record.property.asSource)|\(record.isErased)|\(record.isExtension)"
		case let .inline(record):
			let arguments = record.arguments.map { "\($0.argumentLabel):\($0.label):\($0.property.asSource)" }.joined(separator: ",")
			return "inline|\(record.property.asSource)|\(record.concreteType.asSource)|\(record.target.callee)|\(record.isErased)|\(record.isExtension)|\(record.lineEnd)|\(arguments)"
		case let .alias(record):
			return "alias|\(record.text)"
		}
	}

	/// `classes` refined until alike places' bodies call alike places: a place's class joins the classes its body's calls
	/// reach. Each pass refines the last, since a body's key starts with its class, so the count of classes grows with
	/// every pass that changes the partition and the passes end within one per body.
	private func refine(_ classes: [Int]) -> [Int] {
		var previousCount = Set(classes.dropFirst()).count
		var next = refinementPass(of: classes)
		while next.count != previousCount {
			previousCount = next.count
			next = refinementPass(of: next.classes)
		}
		return next.classes
	}

	/// One pass of `refine`: each place's class is joined by the classes its body's calls reach, with the count of classes.
	private func refinementPass(of previous: [Int]) -> (classes: [Int], count: Int) {
		var interned = [[Int]: Int]()
		var next = [Int](repeating: 0, count: bodies.count)
		for body in bodies.indices.dropFirst() {
			var key = [previous[body]]
			for statement in bodies[body].statements {
				switch statement {
				case let .built(child):
					key.append(previous[child])
				case let .closer(_, target):
					key.append(previous[target])
				case .inline, .alias:
					key.append(0)
				}
			}
			next[body] = interned[key] ?? {
				let id = interned.count + 1
				interned[key] = id
				return id
			}()
		}
		return (next, interned.count)
	}

	// MARK: Placement

	/// The class a statement of a class's body calls, or `nil` for one that calls none.
	func callee(of statement: Statement) -> Int? {
		switch statement {
		case let .built(child):
			classByBody[child]
		case let .closer(_, target):
			classByBody[target]
		case .inline, .alias:
			nil
		}
	}

	/// The statements of a class's body, which every member's body shares: its first member's, or the root's.
	func statements(ofClass owner: Int) -> [Statement] {
		owner == 0 ? bodies[0].statements : bodies[membersByClass[owner][0]].statements
	}

	func representative(of owner: Int) -> BuiltPlaceRecord? {
		owner == 0 ? nil : bodies[membersByClass[owner][0]].record
	}

	/// Declares each class's function in the root's body, a cycle's functions together.
	mutating func computePlacement() -> Bool {
		let classCount = membersByClass.count
		calleesByClass = Array(repeating: [], count: classCount)
		callSitesByClass = Array(repeating: [], count: classCount)
		for owner in 0..<classCount {
			for (index, statement) in statements(ofClass: owner).enumerated() {
				guard let callee = callee(of: statement) else { continue }
				calleesByClass[owner].insert(callee)
				callSitesByClass[callee].insert(CallSite(owner: owner, index: index))
			}
		}
		let componentByClass = ScopeGenerator.stronglyConnectedComponents(of: calleesByClass)
		var classesByComponent = [Int: [Int]]()
		for owner in 1..<max(classCount, 1) {
			classesByComponent[componentByClass[owner], default: []].append(owner)
		}
		placementOwner = Array(repeating: -1, count: classCount)
		placementIndex = Array(repeating: 0, count: classCount)
		placementDepth = Array(repeating: 0, count: classCount)
		placementOwner[0] = 0
		// Tarjan's algorithm finishes a component after every component it reaches, so callers come last: they are placed
		// first.
		for component in classesByComponent.keys.sorted(by: >) {
			guard let members = classesByComponent[component]?.sorted() else { continue }
			let memberSet = Set(members)
			let allSites = members.flatMap { callSitesByClass[$0] }
			let externalSites = Set(allSites.filter { !memberSet.contains($0.owner) })
			// Every function is declared in the root's body, never nested in another: Swift 6.2's compile time doubles with
			// each level of nested local functions past about twenty.
			guard let firstSite = externalSites.first else { return false }
			let owner = 0
			let isAttached = members.count == 1 && externalSites.count == 1 && allSites.count == 1 && firstSite.owner == owner
			// The functions are declared before the first statement of the root's body that reaches them: one that calls a
			// member, or one that reaches a function that calls one, which is placed already, since callers are placed first.
			let index = externalSites.reduce(Int.max) { first, site in
				min(first, site.owner == owner ? site.index : placementIndex[site.owner])
			}
			for member in members {
				placementOwner[member] = owner
				placementIndex[member] = index
				placementDepth[member] = placementDepth[owner] + 1
			}
			let site = CallSite(owner: owner, index: index)
			if isAttached {
				attachedFunction[site] = members[0]
			} else {
				hoistedFunctions[site, default: []].append(contentsOf: members)
			}
		}
		// Functions declared before one statement are ordered by the first reach of their cycle, then by their own.
		for (site, functions) in hoistedFunctions {
			hoistedFunctions[site] = functions.sorted { lhs, rhs in
				let lhsComponent = componentByClass[lhs]
				let rhsComponent = componentByClass[rhs]
				let lhsFirst = classesByComponent[lhsComponent]?.min() ?? lhs
				let rhsFirst = classesByComponent[rhsComponent]?.min() ?? rhs
				return lhsFirst == rhsFirst ? lhs < rhs : lhsFirst < rhsFirst
			}
		}
		return true
	}

	// MARK: Outcomes

	/// The nearest declaration of `label` the type key's code sees before the statement at `index` of `owner`'s body.
	func typeLookUp(_ label: String, inClass owner: Int, before index: Int) -> TypeDeclaration {
		if let position = lastPosition(of: label, inClass: owner, before: index) {
			.statement(owner: owner, index: position)
		} else if owner == 0 {
			.none
		} else if representative(of: owner)?.forwardedProperties.contains(where: { $0.label == label }) == true {
			.forwarded(owner: owner, label: label)
		} else if outcomes[owner][label] == .passed {
			.read(owner: owner, label: label)
		} else {
			// Every function is declared in the root's body (`computePlacement`), so a function that captures its read, or
			// reads none, sees the root's declarations before its own. One that reads none has no declaration there: the
			// first root statement that reaches it is before the path that resolved the read to none.
			lastPosition(of: label, inClass: 0, before: placementIndex[owner]).map { .statement(owner: 0, index: $0) } ?? .none
		}
	}

	/// The position of the last statement of `owner`'s body before `index` that declares `label`.
	private func lastPosition(of label: String, inClass owner: Int, before index: Int) -> Int? {
		let statements = statements(ofClass: owner)
		return stride(from: min(index, statements.count) - 1, through: 0, by: -1).first { self.label(of: statements[$0]) == label }
	}

	/// The type key's declaration for a path declaration.
	private func typeDeclaration(for value: PathValue) -> TypeDeclaration {
		switch value {
		case .none:
			.none
		case let .statement(body, index):
			.statement(owner: classByBody[body], index: index)
		case let .forwarded(body, label):
			.forwarded(owner: classByBody[body], label: label)
		case let .cycleParameter(body, label):
			// A function reads its cycle parameter from its caller, whatever the outcome of its label: no graph of the
			// fuzzer's corpora settles one as captured or none, and a layout that reads it so is still checked against the
			// path key read by read (`checkEveryRead`).
			.read(owner: classByBody[body], label: label)
		}
	}

	/// What each class's function does with each label it reads. Every function is declared in the root's body
	/// (`computePlacement`), and a cycle parameter is always read from the caller, so no outcome depends on another: one
	/// pass settles them.
	mutating func computeOutcomes() {
		var outcomes = [[String: ReadOutcome]](repeating: [:], count: membersByClass.count)
		for owner in membersByClass.indices.dropFirst() {
			for label in reads[membersByClass[owner][0]] {
				var declarations = [TypeDeclaration]()
				for member in membersByClass[owner] {
					declarations.append(typeDeclaration(for: resolution(of: label, atPlace: member)))
					for closer in closersByTarget[member] ?? [] {
						declarations.append(typeDeclaration(for: closerValue(of: label, closing: closer, onPlace: member)))
					}
				}
				outcomes[owner][label] = if declarations.allSatisfy({ $0 == .none }) {
					.none
				} else if let first = declarations.first,
				          declarations.allSatisfy({ $0 == first }),
				          typeLookUp(label, inClass: placementOwner[owner], before: placementIndex[owner]) == first
				{
					.captured(first)
				} else {
					.passed
				}
			}
		}
		self.outcomes = outcomes
	}

	/// What the closing statement `closer` passes the function of `place` for `label`: its argument for a cycle parameter,
	/// else what the place resolves the label to.
	private func closerValue(of label: String, closing closer: (body: Int, index: Int), onPlace place: Int) -> PathValue {
		guard bodies[place].cycleParameterLabels.contains(label) else { return resolution(of: label, atPlace: place) }
		guard case let .closer(record, _) = bodies[closer.body].statements[closer.index],
		      let argument = record.cycleArguments.first(where: { $0.label == label })
		else { return .none }
		return pathValue(of: argument, inBody: closer.body, before: closer.index)
	}

	// MARK: Parameter types

	/// The type of a type key's declaration, `nil` for none or a parameter not typed yet.
	func type(of declaration: TypeDeclaration) -> TypeDescription? {
		switch declaration {
		case .none:
			nil
		case let .statement(owner, index):
			property(of: statements(ofClass: owner)[index])?.typeDescription
		case let .forwarded(owner, label):
			representative(of: owner)?.forwardedProperties.first(where: { $0.label == label })?.typeDescription
		case let .read(owner, label):
			parameterTypes[owner][label]
		}
	}

	/// The type of each parameter: the type its calls' declarations share, optional where a call passes `nil` or an
	/// optional value, and the wrapper where any call holds a lazy wrapper. `false` where calls hold types no one parameter
	/// takes.
	mutating func computeParameterTypes() -> Bool {
		parameterTypes = Array(repeating: [:], count: membersByClass.count)
		for _ in 0..<16 {
			var changed = false
			for owner in membersByClass.indices.dropFirst() {
				for label in reads[membersByClass[owner][0]] where outcomes[owner][label] == .passed {
					var types = [TypeDescription?]()
					var isComplete = true
					for site in callSitesByClass[owner].sorted(by: { ($0.owner, $0.index) < ($1.owner, $1.index) }) {
						let declaration = typeLookUp(label, inClass: site.owner, before: site.index)
						if case .read = declaration, type(of: declaration) == nil {
							// A parameter whose type is not known yet passes a value of some type, never `nil`: it is
							// left out until it is known, so it never makes this parameter optional.
							isComplete = false
						} else {
							types.append(type(of: declaration))
						}
					}
					guard isComplete || parameterTypes[owner][label] == nil else { continue }
					var combined = Self.parameterType(combining: types)
					// A value nothing in the function requires is taken optionally, as the path key types a cycle's parameter.
					if let value = combined, !value.isOptional, value.lazilyInstantiatedInstanceType == nil,
					   !membersByClass[owner].contains(where: { requiredReads[$0].contains(label) })
					{
						combined = .optional(value)
					}
					if let combined, parameterTypes[owner][label]?.asSource != combined.asSource {
						parameterTypes[owner][label] = combined
						changed = true
					}
				}
			}
			guard changed else { break }
		}
		for owner in membersByClass.indices.dropFirst() {
			for label in reads[membersByClass[owner][0]] where outcomes[owner][label] == .passed {
				guard parameterTypes[owner][label] != nil else { return false }
			}
		}
		return true
	}

	/// The parameter type that takes each of `types`, `nil` for a call that passes `nil`; `nil` where none does.
	private static func parameterType(combining types: [TypeDescription?]) -> TypeDescription? {
		let values = types.compactMap(\.self)
		guard let first = values.first else { return nil }
		let passesNone = values.count < types.count
		let wrappers = values.filter { $0.unwrapped.lazilyInstantiatedInstanceType != nil }
		if let wrapper = wrappers.first?.unwrapped {
			guard wrappers.allSatisfy({ $0.unwrapped == wrapper }),
			      let instanceType = wrapper.lazilyInstantiatedInstanceType
			else { return nil }
			let instances = values.filter { $0.unwrapped.lazilyInstantiatedInstanceType == nil }
			guard instances.allSatisfy({ !$0.isOptional && $0 == instanceType }) else { return nil }
			if passesNone || wrappers.contains(where: \.isOptional) {
				guard instances.isEmpty else { return nil }
				return .optional(wrapper)
			} else {
				return wrapper
			}
		} else {
			let base = first.unwrapped
			guard values.allSatisfy({ $0.unwrapped == base }) else { return nil }
			if let optional = values.first(where: \.isOptional) {
				return optional
			} else if passesNone {
				return .optional(base)
			} else {
				return first
			}
		}
	}

	// MARK: Checking every read

	/// The body of class `owner` that encloses `body`, where `owner` is `body`'s class or the root's: what `typeLookUp`
	/// finds in `body`'s class is declared in `body` itself or, since every function is declared in the root's body
	/// (`computePlacement`), in the root's.
	private func instance(ofClass owner: Int, enclosing body: Int) -> Int {
		owner == 0 ? 0 : body
	}

	/// What the type key's `declaration`, which `typeLookUp` found in the class of `body`, holds in `body`, as a path
	/// declaration.
	private func evaluate(_ declaration: TypeDeclaration, inBody body: Int) -> PathValue {
		var declaration = declaration
		var body = body
		// A read that is no cycle parameter is what the call passes: the declaration the caller's class sees.
		while case let .read(owner, label) = declaration, !bodies[instance(ofClass: owner, enclosing: body)].cycleParameterLabels.contains(label) {
			let place = instance(ofClass: owner, enclosing: body)
			let parent = bodies[place].parent
			declaration = typeLookUp(label, inClass: classByBody[parent], before: bodies[place].position)
			body = parent
		}
		switch declaration {
		case .none:
			return PathValue.none
		case let .statement(owner, index):
			return .statement(body: instance(ofClass: owner, enclosing: body), index: index)
		case let .forwarded(owner, label):
			return .forwarded(body: instance(ofClass: owner, enclosing: body), label: label)
		case let .read(owner, label):
			return normalized(.cycleParameter(body: instance(ofClass: owner, enclosing: body), label: label))
		}
	}

	/// `value`, a cycle parameter replaced by what every call of its function passes it, where every call passes one value.
	private func normalized(_ value: PathValue) -> PathValue {
		if case let .cycleParameter(body, label) = value, let passed = normalizedCycleParameters[body]?[label] {
			passed
		} else {
			value
		}
	}

	private mutating func normalizeCycleParameters() {
		for body in bodies.indices.dropFirst() {
			guard let record = bodies[body].record else { continue }
			// The call passes each cycle parameter one argument of its label (`ScopeGenerator.cycleParameterReads`).
			for argument in record.callCycleArguments {
				let first = normalized(pathValue(of: argument, inBody: bodies[body].parent, before: bodies[body].position))
				var values = [first]
				for closer in closersByTarget[body] ?? [] {
					values.append(normalized(closerValue(of: argument.label, closing: closer, onPlace: body)))
				}
				if values.allSatisfy({ $0 == first }) {
					normalizedCycleParameters[body, default: [:]][argument.label] = first
				}
			}
		}
	}

	/// Whether every read of every place reads in the type key's code the declaration it reads in the path key's.
	mutating func checkEveryRead() -> Bool {
		normalizeCycleParameters()
		for body in bodies.indices {
			let owner = classByBody[body]
			let statements = bodies[body].statements
			if let record = bodies[body].record {
				for (position, argument) in record.arguments.enumerated() {
					guard checkRead(argument, inBody: body, before: statements.count, owner: owner, isNilAtEveryMember: isNilAtEveryMember(owner: owner) { $0.arguments[position] }) else { return false }
				}
			}
			for (index, statement) in statements.enumerated() {
				switch statement {
				case let .inline(record):
					for position in record.arguments.indices {
						let isNil = isNilAtEveryMember(owner: owner, statement: index, argument: position)
						guard checkRead(record.arguments[position], inBody: body, before: index, owner: owner, isNilAtEveryMember: isNil) else { return false }
					}
				case let .alias(record):
					guard let fulfillingProperty = record.fulfillingProperty else { continue }
					let expected = normalized(lookUp(fulfillingProperty.label, inBody: body, before: index))
					let declaration = typeLookUp(fulfillingProperty.label, inClass: owner, before: index)
					guard normalized(evaluate(declaration, inBody: body)) == expected,
					      let typeModeType = type(of: declaration),
					      let pathType = type(of: expected),
					      typeModeType.asSource == pathType.asSource
					else { return false }
				case let .built(child):
					guard checkCall(of: child, from: body, at: index, closer: nil) else { return false }
				case let .closer(record, target):
					guard checkCall(of: target, from: body, at: index, closer: record) else { return false }
				}
			}
		}
		return true
	}

	private func isNilAtEveryMember(owner: Int, read: (BuiltPlaceRecord) -> PlaceRead) -> Bool {
		guard owner != 0 else { return false }
		return membersByClass[owner].allSatisfy { member in
			bodies[member].record.map { read($0).source == .nil } ?? false
		}
	}

	private func isNilAtEveryMember(owner: Int, statement index: Int, argument position: Int) -> Bool {
		let members = owner == 0 ? [0] : membersByClass[owner]
		return members.allSatisfy { member in
			guard case let .inline(record) = bodies[member].statements[index] else { return false }
			return record.arguments[position].source == .nil
		}
	}

	private func checkRead(_ read: PlaceRead, inBody body: Int, before index: Int, owner: Int, isNilAtEveryMember: Bool) -> Bool {
		guard !isNilAtEveryMember else { return true }
		let expected = normalized(pathValue(of: read, inBody: body, before: index))
		let declaration = typeLookUp(read.label, inClass: owner, before: index)
		return normalized(evaluate(declaration, inBody: body)) == expected
	}

	/// Whether the call of `place`'s function from the statement at `index` of `body` passes each parameter what the path
	/// key's call does. Every function is declared in the root's body (`computePlacement`), so a closing call captures
	/// what the path key's function captures.
	private func checkCall(of place: Int, from body: Int, at index: Int, closer: ClosingPlaceRecord?) -> Bool {
		let callee = classByBody[place]
		let owner = classByBody[body]
		for label in reads[membersByClass[callee][0]] where outcomes[callee][label] == .passed {
			let expected: PathValue = if closer != nil {
				normalized(closerValue(of: label, closing: (body: body, index: index), onPlace: place))
			} else {
				normalized(resolution(of: label, atPlace: place))
			}
			let declaration = typeLookUp(label, inClass: owner, before: index)
			guard normalized(evaluate(declaration, inBody: body)) == expected else { return false }
		}
		return true
	}

	// MARK: Decorators and names

	mutating func computeDecoratorsAndNames() {
		let classCount = membersByClass.count
		isDecorated = membersByClass.indices.map { owner in
			owner != 0 && membersByClass[owner].contains { bodies[$0].record?.isSendable == true }
		}
		// A function a `@Sendable` function declared beneath it calls is captured by that function, so it is `@Sendable` too.
		var changed = true
		while changed {
			changed = false
			for owner in 1..<max(classCount, 1) where !isDecorated[owner] {
				let decorated = callSitesByClass[owner].contains { site in
					var current = site.owner
					while current != 0, current != placementOwner[owner] {
						if isDecorated[current] {
							return true
						}
						current = placementOwner[current]
					}
					return false
				}
				if decorated {
					isDecorated[owner] = true
					changed = true
				}
			}
		}
		var allocator = GeneratedNameAllocator(reserving: Set<String>())
		functionNames = membersByClass.indices.map { owner in
			guard let representative = representative(of: owner) else { return "" }
			return allocator.claim(ScopeGenerator.functionName(toBuildPropertyNamed: representative.property.label))
		}
	}

	// MARK: Spelling

	mutating func spelledRootStatements() -> [GeneratedCode]? {
		var functionCode = [GeneratedCode](repeating: .empty, count: membersByClass.count)
		let classesByDepth = membersByClass.indices.dropFirst().sorted { placementDepth[$0] > placementDepth[$1] }
		for owner in classesByDepth {
			guard let representative = representative(of: owner),
			      let body = spelledStatements(ofClass: owner, indentation: ScopeGenerator.standardIndent, functionCode: functionCode),
			      let arguments = spelledArguments(representative.arguments, inClass: owner, before: statements(ofClass: owner).count, sourceAtMember: { member, position in bodies[member].record?.arguments[position].source })
			else { return nil }
			var parameters = representative.forwardedProperties
			var typesDeclaredEscaping = representative.typesDeclaredEscaping
			for label in reads[membersByClass[owner][0]] where outcomes[owner][label] == .passed {
				guard let parameterType = parameterTypes[owner][label] else { return nil }
				parameters.append(Property(label: label, typeDescription: parameterType))
				if parameterType.isClosure {
					typesDeclaredEscaping.insert(parameterType)
				}
			}
			functionCode[owner] = BuilderNode(
				name: functionNames[owner],
				isSendable: isDecorated[owner],
				isNonisolated: representative.isNonisolated,
				parameters: parameters,
				typesDeclaredEscaping: typesDeclaredEscaping,
				returnType: representative.concreteType,
				body: BuilderBody(statements: body),
				value: .construction(representative.target, arguments: arguments),
				lineEnd: representative.lineEnd,
			).spelled()
		}
		return spelledStatements(ofClass: 0, indentation: "        ", functionCode: functionCode)
	}

	/// The statements of `owner`'s body, each with the functions declared before it, each indented by `indentation`.
	private func spelledStatements(ofClass owner: Int, indentation: String, functionCode: [GeneratedCode]) -> [GeneratedCode]? {
		var code = [GeneratedCode]()
		for (index, statement) in statements(ofClass: owner).enumerated() {
			let site = CallSite(owner: owner, index: index)
			for function in hoistedFunctions[site] ?? [] {
				code.append(.indented(functionCode[function], by: indentation))
			}
			if let function = attachedFunction[site] {
				code.append(.indented(functionCode[function], by: indentation))
			}
			guard let text = spelledStatement(statement, inClass: owner, at: index) else { return nil }
			code.append(.indented(.text(text), by: indentation))
		}
		return code
	}

	private func spelledStatement(_ statement: Statement, inClass owner: Int, at index: Int) -> String? {
		switch statement {
		case let .inline(record):
			guard let arguments = spelledArguments(record.arguments, inClass: owner, before: index, sourceAtMember: { member, position in
				guard case let .inline(memberRecord) = bodies[member].statements[index] else { return nil }
				return memberRecord.arguments[position].source
			}) else { return nil }
			let declaration = BindingDeclaration(
				property: record.property,
				rule: .constant(
					isErased: record.isErased,
					constructedTypeIsPropertyType: record.concreteType.asSource == record.property.typeDescription.asSource,
					hasBuilderFunction: false,
					isExtension: record.isExtension,
				),
			)
			let value = Expression.construction(record.target, arguments: arguments).erased(to: record.property.typeDescription, where: record.isErased)
			return "\(declaration.spelled) = \(value.spelled)\(record.lineEnd)"
		case let .built(child):
			guard let record = bodies[child].record else { return nil }
			return spelledCall(of: classByBody[child], binding: record.property, isErased: record.isErased, isExtension: record.isExtension, inClass: owner, at: index)
		case let .closer(record, target):
			return spelledCall(of: classByBody[target], binding: record.property, isErased: record.isErased, isExtension: record.isExtension, inClass: owner, at: index)
		case let .alias(record):
			return record.text
		}
	}

	/// The binding of `property` to a call of `callee`'s function, made before the statement at `index` of `owner`'s body.
	private func spelledCall(of callee: Int, binding property: Property, isErased: Bool, isExtension: Bool, inClass owner: Int, at index: Int) -> String? {
		guard let representative = representative(of: callee) else { return nil }
		var arguments = [String]()
		for label in reads[membersByClass[callee][0]] where outcomes[callee][label] == .passed {
			guard let parameterType = parameterTypes[callee][label],
			      let value = spelledArgument(label, passedTo: parameterType, inClass: owner, before: index)
			else { return nil }
			arguments.append("\(label.spelledAsArgumentLabel): \(value)")
		}
		let functionName = functionNames[callee]
		switch property.propertyType {
		case .instantiator,
		     .erasedInstantiator,
		     .sendableInstantiator,
		     .sendableErasedInstantiator:
			let isOnly = representative.forwardedProperties.count == 1
			let forwardedArguments = representative.forwardedProperties.map {
				CallArgument(label: $0.label, source: .forwardedSpread(label: $0.label, isOnly: isOnly, spreadName: "$0")).spelled
			}
			return ScopeGenerator.instantiatorDeclaration(
				of: property,
				isExtension: isExtension,
				isErased: isErased,
				handing: functionName,
				forwardedArguments: (forwardedArguments + arguments).joined(separator: ", "),
			)
		case .lazilyInstantiated,
		     .sendableLazilyInstantiated:
			return "\(BindingDeclaration(property: property, rule: .lazilyInstantiated).spelled) = \(ScopeGenerator.lazilyInstantiatedInstantiation(of: property, callingFunctionNamed: functionName, cycleArguments: arguments.joined(separator: ", "), erasedToConcreteExistential: isErased))"
		case .constant:
			let declaration = BindingDeclaration(
				property: property,
				rule: .constant(
					isErased: isErased,
					constructedTypeIsPropertyType: representative.concreteType.asSource == property.typeDescription.asSource,
					hasBuilderFunction: true,
					isExtension: isExtension,
				),
			)
			return "\(declaration.spelled) = \(Expression.call(function: functionName, arguments: arguments.joined(separator: ", ")).erased(to: property.typeDescription, where: isErased).spelled)"
		}
	}

	/// What a call made before the statement at `index` of `owner`'s body passes a parameter `label` of type
	/// `parameterType`: its nearest declaration, `nil`, or a wrapper made of a value where the parameter takes a wrapper.
	private func spelledArgument(_ label: String, passedTo parameterType: TypeDescription, inClass owner: Int, before index: Int) -> String? {
		let declaration = typeLookUp(label, inClass: owner, before: index)
		guard let declaredType = type(of: declaration) else {
			return parameterType.isOptional ? "nil" : nil
		}
		if declaredType == parameterType || (parameterType.isOptional && parameterType.unwrapped == declaredType) {
			return label
		} else {
			// The call is one of the function's call sites, whose declarations' types `computeParameterTypes` combined into
			// `parameterType` (`parameterType(combining:)`), so a declaration that is not the parameter's type, or its
			// unwrapped type, is the instance of the lazy wrapper the parameter takes.
			guard parameterType.unwrapped.lazilyInstantiatedInstanceType == declaredType, !declaredType.isOptional else { return nil }
			return "\(parameterType.unwrapped.asSource) { \(label) }"
		}
	}

	/// The arguments of a construction made before the statement at `index` of `owner`'s body, each read as the receiver
	/// declares it.
	private func spelledArguments(_ reads: [PlaceRead], inClass owner: Int, before index: Int, sourceAtMember: (Int, Int) -> ArgumentSource?) -> String? {
		var arguments = [String]()
		let members = owner == 0 ? [0] : membersByClass[owner]
		for (position, read) in reads.enumerated() {
			let value: String
			if members.allSatisfy({ sourceAtMember($0, position) == .nil }) {
				value = "nil"
			} else {
				let declaration = typeLookUp(read.label, inClass: owner, before: index)
				if let declaredType = type(of: declaration) {
					guard let spelled = Self.spelledRead(read, declaredAs: declaredType) else { return nil }
					value = spelled
				} else {
					value = "nil"
				}
			}
			arguments.append("\(read.argumentLabel.spelledAsArgumentLabel): \(value)")
		}
		return arguments.joined(separator: ", ")
	}

	/// How `read` reads a declaration of its label typed `declaredType`: the declaration itself, or its lazy wrapper's
	/// instance; `nil` where it reads it in neither way.
	private static func spelledRead(_ read: PlaceRead, declaredAs declaredType: TypeDescription) -> String? {
		let receivedType = read.property.typeDescription
		if receivedType == declaredType || (receivedType.isOptional && receivedType.unwrapped == declaredType) {
			return read.label
		} else if let instanceType = declaredType.lazilyInstantiatedInstanceType, !declaredType.isOptional, receivedType.unwrapped == instanceType {
			return "\(read.label).\(Dependency.lazilyInstantiatedInstancePropertyName)"
		} else {
			guard let instanceType = declaredType.lazilyInstantiatedInstanceType, declaredType.isOptional, receivedType.isOptional, receivedType == instanceType else { return nil }
			return "\(read.label)?.\(Dependency.lazilyInstantiatedInstancePropertyName)"
		}
	}
}
