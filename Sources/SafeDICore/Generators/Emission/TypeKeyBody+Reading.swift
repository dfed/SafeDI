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
		var frames = [(body: 0, children: Self.statementCodes(of: rootBody), next: 0)]
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
			// declared in the root's body, so no function beneath it could keep reads it does not list. A closer is never one:
			// it lays out, and its code holds no root function.
			let keepsPathKeyCode = body == 0 && (!Self.laysOut(frame.children[frame.next]) || holdsKeptRootFunction(frame.children[frame.next]))
			let position = bodies[body].statements.count
			let statement: Statement
			let label: String
			switch record {
			case let .built(built):
				if keepsPathKeyCode {
					namesInScope.insert(built.functionName)
					guard keepPathKeyCode(of: frame.children[frame.next], building: built.property) else { return false }
					continue
				}
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
						frames.append((body: newBody, children: Self.statementCodes(of: built.children), next: 0))
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
				// A seam call built by value, or in a wrapper that forwards nothing, is a statement written as text: it is kept as
				// a built place is.
				if keepsPathKeyCode {
					namesInScope.formUnion(alias.declaredFunctionNames)
					guard alias.otherBindings.isEmpty, alias.calledFunctionNames.isEmpty, keepPathKeyCode(of: frame.children[frame.next], building: alias.property) else { return false }
					continue
				}
				// A place written as text whose reads are not listed, that binds labels besides its own, or that calls or
				// refers to a function it does not declare, is never laid out by the type key: two such places of one text can
				// name different functions, which no read tells apart.
				guard alias.listsItsReads, alias.otherBindings.isEmpty, alias.calledFunctionNames.isEmpty else { return false }
				label = alias.property.label
				namesInScope.formUnion(alias.declaredFunctionNames)
				for name in alias.declaredFunctionNames {
					bodies[body].positionsByDeclaredFunction[name, default: []].append(position)
				}
				statement = .alias(alias)
			}
			bodies[body].statements.append(statement)
			bodies[body].positionsByLabel[label, default: []].append(position)
		}
		return true
	}

	/// Keeps `code`, a statement of the root's body that builds `property`, as the path key writes it, or returns `false`
	/// where its code is not a statement of the root.
	private mutating func keepPathKeyCode(of code: GeneratedCode, building property: Property) -> Bool {
		guard let text = Self.unindentedText(of: code, omittingRootFunctionsNamed: rootFunctionNames) else { return false }
		bodies[0].positionsByLabel[property.label, default: []].append(bodies[0].statements.count)
		bodies[0].statements.append(.alias(AliasPlaceRecord(property: property, fulfillingProperty: nil, text: text, reads: [])))
		return true
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
			func close(_ name: String) {
				if name != current.functionName {
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

	/// Whether `code`, a statement of the root's body, holds a root function the path key keeps in place
	/// (`keptRootFunctionNames`).
	func holdsKeptRootFunction(_ code: GeneratedCode) -> Bool {
		!keptRootFunctionNames.isEmpty && RootFunctionHoisting.records(in: [code]).contains { keptRootFunctionNames.contains($0.name) }
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
}
