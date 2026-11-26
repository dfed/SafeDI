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

extension TypeKeyLayout {
	// MARK: Reading the path key's plan

	/// Reads the places of the root's body, `rootBody`, depth first; `false` where a place records nothing.
	/// Declares the root's body, whose first statements are `properties`, the declarations in scope before it.
	mutating func declareOuter(_ properties: [Property]) {
		bodies.append(Body(parent: -1, position: 0, record: nil, isInSendableFamily: false, domainLabels: [], forwardedLabels: [], cycleParameterLabels: []))
		for property in properties {
			bodies[0].positionsByLabel[property.label, default: []].append(bodies[0].statements.count)
			bodies[0].statements.append(.alias(AliasPlaceRecord(property: property, fulfillingProperty: nil, text: "")))
		}
		outerDeclarationCount = properties.count
	}

	/// Reads the root's body, after `declareOuter(_:)` declared it.
	mutating func read(_ rootBody: [GeneratedCode]) -> Bool {
		var viewsByKey = [ViewKey: Int]()
		let rootChildren = Self.statementCodes(of: rootBody)
		declareChildren(rootChildren, ofBody: 0)
		var frames = [(body: 0, children: rootChildren, next: 0)]
		// Closers on the function of a statement the walk has not reached yet: a member of a loop of builders rebinds the
		// members declared after it in the loop's body.
		var closersOnLaterStatements = [(body: Int, position: Int, declaringBody: Int, index: Int)]()
		while let frame = frames.last {
			guard frame.next < frame.children.count else {
				frames.removeLast()
				continue
			}
			frames[frames.count - 1].next += 1
			let body = frame.body
			guard let record = Self.record(of: frame.children[frame.next]) else { return false }
			// A statement of the root's body whose tree holds a place the type key cannot lay out keeps the path key's code,
			// which reads only the root's declarations before it, as the type key's code declares them: functions are all
			// declared in the root's body, so no function beneath it could keep reads it does not list.
			if body == 0, !Self.laysOut(frame.children[frame.next]) {
				guard case let .built(built) = record, let text = Self.unindentedText(of: frame.children[frame.next], omittingRootFunctionsNamed: rootFunctionNames) else { return false }
				namesInScope.insert(built.functionName)
				bodies[0].statements.append(.alias(AliasPlaceRecord(property: built.property, fulfillingProperty: nil, text: text, reads: [])))
				continue
			}
			let position = bodies[body].statements.count
			let statement: Statement
			switch record {
			case let .built(built):
				if built.hasFunction {
					guard let domain = domain(of: built) else { return false }
					let isInSendableFamily = built.isSendable || bodies[body].isInSendableFamily
					// A closer passes the function it calls what that function reads, which the closer's body looks up outside
					// itself: the labels of the target's domain are this view's too.
					guard let closed = closedOnFunctions(named: domain.closedOnFunctionNames, from: body) else { return false }
					let labels = domain.labels.union(closed.labels)
					// A view whose closers call a function declared outside it keeps the declarations themselves (`KeyedDeclaration`).
					let keysByKind = domain.closedOnFunctionNames.isEmpty
					var outerView = [String: KeyedDeclaration]()
					for label in labels {
						outerView[label] = keyed(lookUp(label, inBody: body, before: position), byKind: keysByKind)
					}
					let key = ViewKey(
						node: built.node,
						isInSendableFamily: isInSendableFamily,
						outerView: outerView,
						cycleArguments: built.callCycleArguments.map { keyed(pathValue(of: $0, inBody: body, before: position), byKind: keysByKind) },
						closedOnStatements: closed.statementKeys,
					)
					passedArgumentsByCall[[body, position]] = built.passedArguments
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
							forwardedLabels: Set(built.parameterProperties.map(\.label)),
							cycleParameterLabels: Set(built.cycleParameters.map(\.label)),
						))
						viewsByKey[key] = newBody
						statement = .built(body: newBody)
						let children = Self.statementCodes(of: built.children)
						declareChildren(children, ofBody: newBody)
						frames.append((body: newBody, children: children, next: 0))
					}
				} else {
					guard built.children.isEmpty, built.cycleParameters.isEmpty else { return false }
					statement = .inline(built)
				}
			case let .closer(closer):
				// The function a closing scope calls is the nearest of its name, as Swift resolves it: an enclosing place's, or,
				// for a member of a loop of builders, one a statement of an enclosing body declares.
				switch resolvedFunction(named: closer.closedOnFunctionName, from: body) {
				case let .enclosing(target):
					statement = .closer(closer, target: target)
					closersByTarget[target, default: []].append((body: body, index: position))
				case let .statement(declaringBody, index, _):
					if index < bodies[declaringBody].statements.count {
						guard case let .built(target) = bodies[declaringBody].statements[index] else { return false }
						statement = .closer(closer, target: target)
						closersByTarget[target, default: []].append((body: body, index: position))
					} else {
						statement = .closer(closer, target: 0)
						closersOnLaterStatements.append((body: body, position: position, declaringBody: declaringBody, index: index))
					}
				case nil:
					return false
				}
			case let .alias(alias):
				// A place written as text whose reads are not listed, that binds labels besides its own, or that calls or
				// refers to a function it does not declare, is never laid out by the type key: two such places of one text can
				// name different functions, which no read tells apart.
				guard alias.listsItsReads, alias.otherBindings.isEmpty, alias.calledFunctionNames.isEmpty else { return false }
				namesInScope.formUnion(alias.declaredFunctionNames)
				statement = .alias(alias)
			}
			bodies[body].statements.append(statement)
		}
		for closer in closersOnLaterStatements {
			guard case let .built(target) = bodies[closer.declaringBody].statements[closer.index],
			      case let .closer(record, _) = bodies[closer.body].statements[closer.position]
			else { return false }
			bodies[closer.body].statements[closer.position] = .closer(record, target: target)
			closersByTarget[target, default: []].append((body: closer.body, index: closer.position))
		}
		return true
	}

	/// Declares the statements of `body`, whose children are `children`: the positions of the labels each binds, which a look-up
	/// before any index of the body reads, so a look-up made from a statement after one the walk has not reached reads what
	/// it would once the walk reaches it; and the children, which a closer's function is resolved among.
	mutating func declareChildren(_ children: [GeneratedCode], ofBody body: Int) {
		let first = bodies[body].statements.count
		for (offset, code) in children.enumerated() {
			guard let label = Self.record(of: code).map(\.boundProperty.label) else { continue }
			bodies[body].positionsByLabel[label, default: []].append(first + offset)
		}
		childCodesByBody[body] = (first: first, children: children)
	}

	/// A function a closer calls: the function of an enclosing place's body, or the function a statement of an enclosing
	/// body declares, at its position in that body, which the walk may not have reached yet.
	enum ResolvedFunction {
		case enclosing(Int)
		case statement(body: Int, index: Int, record: BuiltPlaceRecord)
	}

	/// The function named `name` that code in `body` calls, as Swift resolves the name: from `body` outward, a function a
	/// statement of the body declares, at any position, since a local function is in scope throughout the body declaring
	/// it, then the body's own function. `nil` where no place's function has the name, or a place written as text declares
	/// it.
	func resolvedFunction(named name: String, from body: Int) -> ResolvedFunction? {
		var body = body
		while true {
			if let declared = childCodesByBody[body] {
				for (offset, code) in declared.children.enumerated() {
					switch Self.record(of: code) {
					case let .built(built):
						if built.hasFunction, built.functionName == name {
							return .statement(body: body, index: declared.first + offset, record: built)
						}
					case let .alias(alias):
						if alias.declaredFunctionNames.contains(name) {
							return nil
						}
					case .closer, nil:
						break
					}
				}
			}
			if body == 0 {
				return nil
			} else if bodies[body].record?.functionName == name {
				return .enclosing(body)
			}
			body = bodies[body].parent
		}
	}

	/// The labels the functions named `names` read outside them, which a place whose closers call them, made in `body`,
	/// passes them; and the keys of the statements declaring those that a statement of an enclosing body declares, and of
	/// each such function they call in turn, so two places share a view only where the loops they rebind are alike. `nil`
	/// where a place beneath one of them records nothing.
	mutating func closedOnFunctions(named names: Set<String>, from body: Int) -> (labels: Set<String>, statementKeys: [ClosedOnStatementKey])? {
		var labels = Set<String>()
		var statements = [(body: Int, index: Int, record: BuiltPlaceRecord)]()
		var seen = Set<[Int]>()
		var pending = names.sorted().map { (name: $0, body: body) }
		while let next = pending.popLast() {
			switch resolvedFunction(named: next.name, from: next.body) {
			case let .enclosing(target):
				labels.formUnion(bodies[target].domainLabels)
			case let .statement(declaringBody, index, record):
				guard seen.insert([declaringBody, index]).inserted else { continue }
				guard let domain = domain(of: record) else { return nil }
				labels.formUnion(domain.labels)
				statements.append((declaringBody, index, record))
				pending.append(contentsOf: domain.closedOnFunctionNames.sorted().map { (name: $0, body: declaringBody) })
			case nil:
				break
			}
		}
		let keys = statements.sorted { ($0.body, $0.index) < ($1.body, $1.index) }.map { statement in
			var outerView = [String: PathValue]()
			for label in labels {
				outerView[label] = lookUp(label, inBody: statement.body, before: statement.index)
			}
			return ClosedOnStatementKey(
				node: statement.record.node,
				isInSendableFamily: statement.record.isSendable || bodies[statement.body].isInSendableFamily,
				outerView: outerView,
				cycleArguments: statement.record.callCycleArguments.map { pathValue(of: $0, inBody: statement.body, before: statement.index) },
			)
		}
		return (labels, keys)
	}

	/// What `built`'s body looks up outside itself, or `nil` where a place beneath it records nothing. The plan nodes
	/// beneath it are computed first, each once, with a stack, since a plan can be as deep as the module has types.
	mutating func domain(of built: BuiltPlaceRecord) -> Domain? {
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
			for code in Self.statementCodes(of: current.children) {
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
			let bound = Set(current.parameterProperties.map(\.label)).union(current.cycleParameters.map(\.label))
			var boundBefore = Set<String>()
			var domain = Domain()
			// A read of `nil` is in the domain too: the checks look up every label a function reads, whatever its places read.
			func lookUp(_ read: PlaceRead) {
				if !bound.contains(read.label), !boundBefore.contains(read.label) {
					domain.labels.insert(read.label)
				}
			}
			// A function a place of the body declares is resolved inside it (`resolvedFunction(named:from:)`), as its own is.
			var declaredNames = Set<String>()
			for case let .built(childBuilt) in children where childBuilt.hasFunction {
				declaredNames.insert(childBuilt.functionName)
			}
			func close(_ name: String) {
				if name != current.functionName, !declaredNames.contains(name) {
					domain.closedOnFunctionNames.insert(name)
				}
			}
			for child in children {
				switch child {
				case let .built(childBuilt):
					childBuilt.callSiteReads.forEach(lookUp)
					if childBuilt.hasFunction, let childDomain = domainsByNode[childBuilt.node] {
						for label in childDomain.labels where !bound.contains(label) && !boundBefore.contains(label) {
							domain.labels.insert(label)
						}
						childDomain.closedOnFunctionNames.forEach(close)
					} else {
						childBuilt.constructionReads.forEach(lookUp)
					}
					boundBefore.insert(childBuilt.property.label)
				case let .closer(closer):
					closer.callSiteReads.forEach(lookUp)
					close(closer.closedOnFunctionName)
					boundBefore.insert(closer.property.label)
				case let .alias(alias):
					if let fulfillingProperty = alias.fulfillingProperty, !bound.contains(fulfillingProperty.label), !boundBefore.contains(fulfillingProperty.label) {
						domain.labels.insert(fulfillingProperty.label)
					}
					alias.listedReads.forEach(lookUp)
					boundBefore.insert(alias.property.label)
				}
			}
			current.constructionReads.forEach(lookUp)
			domainsByNode[current.node] = domain
		}
		return domainsByNode[built.node]
	}

	/// Whether the type key can lay out every place of `code`'s tree: each records what it builds, and each written as text
	/// lists its reads, binds no other label and names no function. Each place records it as it is built
	/// (`laysOut(placeRecordedAs:)`), so asking it reads no level beneath: a scope's code is shared by every place that
	/// holds it, so a walk of the tree read each level once per path to it.
	static func laysOut(_ code: GeneratedCode) -> Bool {
		code.isPlaceTheTypeKeyLaysOut
	}

	/// Whether the type key can lay out a place recorded as `record` and every place beneath it, from what each statement
	/// of its function's body recorded when it was built.
	static func laysOut(placeRecordedAs record: PlaceRecord?) -> Bool {
		switch record {
		case nil:
			false
		case let .built(built):
			built.children.allSatisfy(\.statementsAreLaidOutByTypeKey)
		case .closer:
			true
		case let .alias(alias):
			alias.listsItsReads && alias.otherBindings.isEmpty && alias.calledFunctionNames.isEmpty
		}
	}

	/// The text of a statement of the root's body without the indentation the root gives it, which the type key's spelling
	/// gives it again.
	static func unindentedText(of code: GeneratedCode, omittingRootFunctionsNamed names: Set<String>) -> String? {
		guard case let .indented(inner, _) = code.node else { return nil }
		return GeneratedCode.omittingRootFunctions(inner, named: names).spelled()
	}

	/// The statements of a body whose children are `codes`: each child, or each place of a child that is places one after
	/// another, as a scope's payload bindings precede its place (`ScopeGenerator.valuesBindingPlaces`), each indented as
	/// the child is.
	static func statementCodes(of codes: [GeneratedCode]) -> [GeneratedCode] {
		// Most bodies hold no sequence of places, and keep their children as they are, with no copy.
		guard codes.contains(where: isSequenceOfPlaces) else { return codes }
		var statements = [GeneratedCode]()
		for code in codes {
			var indentations = [String]()
			var inner = code
			while case let .indented(wrapped, indentation) = inner.node {
				indentations.append(indentation)
				inner = wrapped
			}
			guard case let .sequence(pieces) = inner.node, pieces.allSatisfy({ record(of: $0) != nil }) else {
				statements.append(code)
				continue
			}
			for piece in pieces {
				statements.append(indentations.reversed().reduce(piece) { code, indentation in .indented(code, by: indentation) })
			}
		}
		return statements
	}

	/// Whether `code`, under its indentations, is pieces one after another, each a place (`statementCodes(of:)`).
	private static func isSequenceOfPlaces(_ code: GeneratedCode) -> Bool {
		var inner = code
		while case let .indented(wrapped, _) = inner.node {
			inner = wrapped
		}
		guard case let .sequence(pieces) = inner.node else { return false }
		return pieces.allSatisfy { record(of: $0) != nil }
	}

	/// The record of a place's code, as a body holds it: indented, around the place's plan.
	static func record(of code: GeneratedCode) -> PlaceRecord? {
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
		     .spelledArgument:
			lookUp(read.label, inBody: body, before: index)
		}
	}

	/// The declaration the place whose function is `body` resolves `label` to where its first place is called from its
	/// parent (`resolution(of:atPlace:edge:)`).
	func resolution(of label: String, atPlace body: Int) -> PathValue {
		resolution(of: label, atPlace: body, edge: (parent: bodies[body].parent, position: bodies[body].position))
	}

	/// The declaration the place of view `body` at `edge`, a statement of its parent that builds it, resolves `label` to:
	/// what that binding passes a cycle parameter, else `.none` where every read of the label inside the view reads `nil`,
	/// else the nearest declaration at that binding, which every read of it inside the view resolves to. Whether every
	/// read is `nil` is the view's own, so the same at each of its edges: the view's key holds which of its labels resolve
	/// to none.
	func resolution(of label: String, atPlace body: Int, edge: (parent: Int, position: Int)) -> PathValue {
		if bodies[body].cycleParameterLabels.contains(label) {
			bodies[body].record?.callCycleArguments.first(where: { $0.label == label }).map {
				pathValue(of: $0, inBody: edge.parent, before: edge.position)
			} ?? .none
		} else if escapingReads[body][label] == PathValue.none {
			.none
		} else {
			lookUp(label, inBody: edge.parent, before: edge.position)
		}
	}

	/// What a view's key holds of `value`, a declaration outside it: the declaration itself, or, keyed `byKind`, whether
	/// there is one, and for one outside the root's body its kind and type.
	func keyed(_ value: PathValue, byKind: Bool) -> KeyedDeclaration {
		guard byKind else { return .absolute(value) }
		switch value {
		case .none:
			return .none
		case let .statement(body, index):
			return body == 0 ? .root(index: index) : .outside(kind: .statement, type: type(of: value)?.asSource)
		case .forwarded:
			return .outside(kind: .forwarded, type: type(of: value)?.asSource)
		case .cycleParameter:
			return .outside(kind: .cycleParameter, type: type(of: value)?.asSource)
		}
	}
}
