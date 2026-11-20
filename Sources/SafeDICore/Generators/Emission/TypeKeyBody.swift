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
		guard layout.read(rootBody),
		      layout.computeReads(),
		      layout.computeClasses(),
		      layout.computePlacement(),
		      layout.computeOutcomes(),
		      layout.computeParameterTypes(),
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

	/// The body that declares the value, or `nil` for none.
	var body: Int? {
		switch self {
		case .none:
			nil
		case let .statement(body, _),
		     let .forwarded(body, _),
		     let .cycleParameter(body, _):
			body
		}
	}
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
	/// A body of the path key's walk: the root's (body 0), or a place's builder function.
	struct Body {
		let parent: Int
		/// The index of the place's statement in its parent's body.
		let position: Int
		let record: BuiltPlaceRecord?
		var statements = [Statement]()
		var positionsByLabel = [String: [Int]]()
		let forwardedLabels: Set<String>
		let cycleParameterLabels: Set<String>
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
		bodies.append(Body(parent: -1, position: 0, record: nil, forwardedLabels: [], cycleParameterLabels: []))
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
				guard Self.areReads(built.arguments), Self.areReads(built.callCycleArguments) else { return false }
				label = built.property.label
				if built.hasFunction {
					let newBody = bodies.count
					bodies.append(Body(
						parent: body,
						position: position,
						record: built,
						forwardedLabels: Set(built.forwardedProperties.map(\.label)),
						cycleParameterLabels: Set(built.cycleParameters.map(\.label)),
					))
					statement = .built(body: newBody)
					frames.append((body: newBody, children: built.children, next: 0))
				} else {
					guard built.children.isEmpty, built.cycleParameters.isEmpty else { return false }
					statement = .inline(built)
				}
			case let .closer(closer):
				guard Self.areReads(closer.cycleArguments) else { return false }
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

	/// The record of a place's code, as a body holds it: indented, around the place's plan.
	private static func record(of code: GeneratedCode) -> PlaceRecord? {
		var code = code
		while true {
			switch code {
			case let .indented(inner, _):
				code = inner
			case let .place(plan):
				return plan.record
			case .text, .sequence, .lines, .laidOut:
				return nil
			}
		}
	}

	/// Whether each of `reads` reads a declaration of its label, its lazy wrapper's instance, or `nil`.
	private static func areReads(_ reads: [PlaceRead]) -> Bool {
		reads.allSatisfy { read in
			switch read.source {
			case .binding, .lazyInstance, .nil:
				true
			case .forwardedSpread, .wrapper, .optionalWrapper, .builderArgument, .holeArgument:
				false
			}
		}
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
		while true {
			if let positions = bodies[body].positionsByLabel[label], let position = positions.last(where: { $0 < index }) {
				return .statement(body: body, index: position)
			}
			guard body != 0 else { return .none }
			if bodies[body].forwardedLabels.contains(label) {
				return .forwarded(body: body, label: label)
			} else if bodies[body].cycleParameterLabels.contains(label) {
				return .cycleParameter(body: body, label: label)
			} else {
				index = bodies[body].position
				body = bodies[body].parent
			}
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
		let place = bodies[body]
		if place.cycleParameterLabels.contains(label) {
			return place.record?.callCycleArguments.first(where: { $0.label == label }).map {
				pathValue(of: $0, inBody: place.parent, before: place.position)
			} ?? .none
		} else if let value = escapingReads[body][label] {
			return value
		} else {
			return lookUp(label, inBody: place.parent, before: place.position)
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
		reads = Array(repeating: [], count: bodies.count)
		guard settle(dependents: dependents, recompute: { layout, body in
			let bodyReads = layout.readsOfBody(body)
			guard bodyReads != layout.reads[body] else { return false }
			layout.reads[body] = bodyReads
			return true
		}) else { return false }
		escapingReads = Array(repeating: [:], count: bodies.count)
		for body in bodies.indices.dropFirst().reversed() {
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

	/// Runs passes over the bodies in reverse order until no body changes, recomputing a body only where it is dirty: never
	/// computed, or a body it reads changed since. `recompute` returns whether the body changed. `false` where the passes
	/// do not settle.
	private mutating func settle(dependents: [[Int]], recompute: (inout TypeKeyLayout, Int) -> Bool) -> Bool {
		var dirty = [Bool](repeating: true, count: bodies.count)
		var anyDirty = true
		var passes = 0
		while anyDirty {
			anyDirty = false
			passes += 1
			guard passes <= bodies.count + 2 else { return false }
			for body in bodies.indices.dropFirst().reversed() where dirty[body] {
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
		let bound = bodies[body].forwardedLabels.union(bodies[body].positionsByLabel.keys)
		return list.filter { !bound.contains($0) }
	}

	private func escapingReadsOfBody(_ body: Int) -> [String: PathValue] {
		var escaping = [String: PathValue]()
		func note(_ label: String, _ value: PathValue) {
			if value == .none {
				if escaping[label] == nil {
					escaping[label] = PathValue.none
				}
			} else if value.body != body, escaping[label] == nil || escaping[label] == PathValue.none {
				escaping[label] = value
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
		let bound = bodies[body].forwardedLabels.union(bodies[body].cycleParameterLabels).union(bodies[body].positionsByLabel.keys)
		return escaping.filter { !bound.contains($0.key) }
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
	mutating func computeClasses() -> Bool {
		let count = bodies.count
		var families = [Bool](repeating: false, count: count)
		for body in bodies.indices.dropFirst() {
			families[body] = (bodies[body].record?.isSendable ?? false) || families[bodies[body].parent]
		}
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
		guard var refined = refine(classes) else { return false }
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
		guard let final = refine(classesWithForms) else { return false }
		refined = final
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
		return true
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
	/// reach. `nil` where the partition does not settle.
	private func refine(_ classes: [Int]) -> [Int]? {
		var previous = classes
		var previousCount = Set(classes.dropFirst()).count
		for _ in 0...bodies.count {
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
			guard interned.count != previousCount else { return next }
			previousCount = interned.count
			previous = next
		}
		return nil
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
			let index: Int
			let isAttached = members.count == 1 && externalSites.count == 1 && allSites.count == 1 && firstSite.owner == owner
			if isAttached {
				index = firstSite.index
			} else {
				guard let firstReaching = firstStatement(of: owner, reaching: memberSet) else { return false }
				index = firstReaching
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

	/// Whether the function of `owner` is declared in the body of `ancestor` or in a body beneath it.
	private func isDeclared(_ owner: Int, within ancestor: Int) -> Bool {
		var current = owner
		while current != 0 {
			let placed = placementOwner[current]
			guard placed >= 0 else { return false }
			if placed == ancestor {
				return true
			}
			current = placed
		}
		return ancestor == 0
	}

	/// The index of the first statement of `owner`'s body whose calls, through the functions declared beneath that body,
	/// reach a class of `targets`.
	private func firstStatement(of owner: Int, reaching targets: Set<Int>) -> Int? {
		var visited = Set<Int>()
		for (index, statement) in statements(ofClass: owner).enumerated() {
			guard let start = callee(of: statement) else { continue }
			var stack = [start]
			while let current = stack.popLast() {
				if targets.contains(current) {
					return index
				}
				guard visited.insert(current).inserted,
				      placementOwner[current] >= 0,
				      isDeclared(current, within: owner)
				else { continue }
				stack.append(contentsOf: calleesByClass[current].sorted())
			}
		}
		return nil
	}

	// MARK: Outcomes

	/// The nearest declaration of `label` the type key's code sees before the statement at `index` of `owner`'s body.
	func typeLookUp(_ searchedLabel: String, inClass owner: Int, before index: Int) -> TypeDeclaration {
		let label = searchedLabel
		var owner = owner
		var index = index
		while true {
			let statements = statements(ofClass: owner)
			for position in stride(from: min(index, statements.count) - 1, through: 0, by: -1) where self.label(of: statements[position]) == label {
				return .statement(owner: owner, index: position)
			}
			guard owner != 0 else { return .none }
			if representative(of: owner)?.forwardedProperties.contains(where: { $0.label == label }) == true {
				return .forwarded(owner: owner, label: label)
			}
			switch outcomes[owner][label] {
			case .passed:
				return .read(owner: owner, label: label)
			case .none?:
				return .none
			case .captured?, nil:
				index = placementIndex[owner]
				owner = placementOwner[owner]
			}
		}
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
			switch outcomes[classByBody[body]][label] {
			case let .captured(declaration)?:
				declaration
			case .none?:
				.none
			case .passed?, nil:
				.read(owner: classByBody[body], label: label)
			}
		}
	}

	/// What each class's function does with each label it reads: `false` where the outcomes do not settle.
	mutating func computeOutcomes() -> Bool {
		outcomes = membersByClass.indices.map { owner in
			guard owner != 0 else { return [:] }
			return Dictionary(reads[membersByClass[owner][0]].map { ($0, ReadOutcome.passed) }, uniquingKeysWith: { first, _ in first })
		}
		for _ in 0..<16 {
			var changed = false
			for owner in membersByClass.indices.dropFirst() {
				for label in reads[membersByClass[owner][0]] {
					var declarations = [TypeDeclaration]()
					for member in membersByClass[owner] {
						declarations.append(typeDeclaration(for: resolution(of: label, atPlace: member)))
						for closer in closersByTarget[member] ?? [] {
							declarations.append(typeDeclaration(for: closerValue(of: label, closing: closer, onPlace: member)))
						}
					}
					let outcome: ReadOutcome
					if declarations.allSatisfy({ $0 == .none }) {
						outcome = .none
					} else if let first = declarations.first,
					          declarations.allSatisfy({ $0 == first }),
					          typeLookUp(label, inClass: placementOwner[owner], before: placementIndex[owner]) == first
					{
						outcome = .captured(first)
					} else {
						outcome = .passed
					}
					if outcomes[owner][label] != outcome {
						outcomes[owner][label] = outcome
						changed = true
					}
				}
			}
			guard changed else { return true }
		}
		return false
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

	/// The innermost body of class `owner` that encloses `body`, the body itself included; the root for class 0.
	private func instance(ofClass owner: Int, enclosing body: Int) -> Int? {
		guard owner != 0 else { return 0 }
		var current = body
		while current != 0 {
			if classByBody[current] == owner {
				return current
			}
			current = bodies[current].parent
		}
		return nil
	}

	/// What the type key's `declaration`, read in `body`, holds there, as a path declaration; `nil` where it is no
	/// declaration of the path key's.
	private func evaluate(_ declaration: TypeDeclaration, inBody body: Int) -> PathValue? {
		var declaration = declaration
		var body = body
		while true {
			switch declaration {
			case .none:
				return PathValue.none
			case let .statement(owner, index):
				return instance(ofClass: owner, enclosing: body).map { .statement(body: $0, index: index) }
			case let .forwarded(owner, label):
				return instance(ofClass: owner, enclosing: body).map { .forwarded(body: $0, label: label) }
			case let .read(owner, label):
				guard let place = instance(ofClass: owner, enclosing: body) else { return nil }
				if bodies[place].cycleParameterLabels.contains(label) {
					return normalized(.cycleParameter(body: place, label: label))
				} else {
					let parent = bodies[place].parent
					declaration = typeLookUp(label, inClass: classByBody[parent], before: bodies[place].position)
					body = parent
				}
			}
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
			for parameter in record.cycleParameters {
				var values = [PathValue]()
				if let argument = record.callCycleArguments.first(where: { $0.label == parameter.label }) {
					values.append(normalized(pathValue(of: argument, inBody: bodies[body].parent, before: bodies[body].position)))
				} else {
					values.append(.none)
				}
				for closer in closersByTarget[body] ?? [] {
					values.append(normalized(closerValue(of: parameter.label, closing: closer, onPlace: body)))
				}
				if let first = values.first, values.allSatisfy({ $0 == first }) {
					normalizedCycleParameters[body, default: [:]][parameter.label] = first
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
					guard evaluate(declaration, inBody: body).map(normalized) == expected,
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
		return evaluate(declaration, inBody: body).map(normalized) == expected
	}

	/// Whether the call of `place`'s function from the statement at `index` of `body` passes each parameter what the path
	/// key's call does, and, for a closing call, captures what the path key's function captures.
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
			guard evaluate(declaration, inBody: body).map(normalized) == expected else { return false }
		}
		if closer != nil, placementOwner[callee] != 0 {
			// A closing call captures what the function captured where the path key's function was declared.
			guard let callerInstance = instance(ofClass: placementOwner[callee], enclosing: body),
			      callerInstance == instance(ofClass: placementOwner[callee], enclosing: bodies[place].parent)
			else { return false }
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
		} else if parameterType.unwrapped.lazilyInstantiatedInstanceType == declaredType, !declaredType.isOptional {
			return "\(parameterType.unwrapped.asSource) { \(label) }"
		} else {
			return nil
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
		} else if let instanceType = declaredType.lazilyInstantiatedInstanceType {
			if !declaredType.isOptional, receivedType.unwrapped == instanceType {
				return "\(read.label).\(Dependency.lazilyInstantiatedInstancePropertyName)"
			} else if declaredType.isOptional, receivedType.isOptional, receivedType == instanceType {
				return "\(read.label)?.\(Dependency.lazilyInstantiatedInstancePropertyName)"
			} else {
				return nil
			}
		} else {
			return nil
		}
	}
}
