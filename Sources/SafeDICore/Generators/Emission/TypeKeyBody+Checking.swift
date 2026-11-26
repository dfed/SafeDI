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
	// MARK: Checking every read

	/// The body of class `owner` that encloses `body`, where `owner` is `body`'s class or the root's: what `typeLookUp`
	/// finds in `body`'s class is declared in `body` itself or, since every function is declared in the root's body
	/// (`computePlacement`), in the root's.
	func instance(ofClass owner: Int, enclosing body: Int) -> Int {
		owner == 0 ? 0 : body
	}

	/// What the type key's `declaration`, which `typeLookUp` found in the class of `body`, holds in `body`, as a path
	/// declaration.
	func evaluate(_ declaration: TypeDeclaration, inBody body: Int) -> PathValue {
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
	func normalized(_ value: PathValue) -> PathValue {
		if case let .cycleParameter(body, label) = value, let passed = normalizedCycleParameters[body]?[label] {
			passed
		} else {
			value
		}
	}

	mutating func normalizeCycleParameters() {
		for body in bodies.indices.dropFirst() {
			guard let record = bodies[body].record else { continue }
			// The call passes each cycle parameter one argument of its label (`ScopeGenerator.cycleParameterReads`).
			for argument in record.callCycleArguments {
				let first = normalized(pathValue(of: argument, inBody: bodies[body].parent, before: bodies[body].position))
				var values = [first]
				for edge in bodies[body].otherEdges {
					values.append(normalized(pathValue(of: argument, inBody: edge.parent, before: edge.position)))
				}
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
		// Whether each read is `nil` in every member of its class, asked once per class rather than once per member: the
		// answer is the class's, and asking it for every member walked every member again.
		var isNilByRead = [NilReadKey: Bool]()
		for body in bodies.indices {
			let owner = classByBody[body]
			let statements = bodies[body].statements
			if let record = bodies[body].record {
				for (position, argument) in record.arguments.enumerated() where record.argumentValues[position] == nil {
					let isNil = Self.memoized(&isNilByRead, NilReadKey(owner: owner, statement: -1, position: position)) {
						isNilAtEveryMember(owner: owner) { $0.arguments[position] }
					}
					guard checkRead(argument, inBody: body, before: statements.count, owner: owner, isNilAtEveryMember: isNil) else { return false }
				}
			}
			for (index, statement) in statements.enumerated() {
				switch statement {
				case let .inline(record):
					for position in record.arguments.indices where record.argumentValues[position] == nil {
						let isNil = Self.memoized(&isNilByRead, NilReadKey(owner: owner, statement: index, position: position)) {
							isNilAtEveryMember(owner: owner, inlineStatement: index, argument: position)
						}
						guard checkRead(record.arguments[position], inBody: body, before: index, owner: owner, isNilAtEveryMember: isNil) else { return false }
					}
				case let .alias(record):
					for position in record.listedReads.indices {
						let isNil = Self.memoized(&isNilByRead, NilReadKey(owner: owner, statement: index, position: position)) {
							isNilAtEveryMember(owner: owner, aliasStatement: index, read: position)
						}
						guard checkRead(record.listedReads[position], inBody: body, before: index, owner: owner, isNilAtEveryMember: isNil),
						      isNil || readsDeclarationOfSameType(record.listedReads[position], inBody: body, before: index, owner: owner)
						else { return false }
					}
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

	/// A read of a class's statement at `statement` (-1 for the arguments of the class's own place), the read at
	/// `position` of it.
	struct NilReadKey: Hashable {
		let owner: Int
		let statement: Int
		let position: Int
	}

	static func memoized(_ answers: inout [NilReadKey: Bool], _ key: NilReadKey, _ answer: () -> Bool) -> Bool {
		if let known = answers[key] {
			return known
		}
		let computed = answer()
		answers[key] = computed
		return computed
	}

	func isNilAtEveryMember(owner: Int, read: (BuiltPlaceRecord) -> PlaceRead) -> Bool {
		guard owner != 0 else { return false }
		GenerationWork.record(membersByClass[owner].count, by: .checkingReadsAtEveryMember)
		return membersByClass[owner].allSatisfy { member in
			bodies[member].record.map { read($0).source == .nil } ?? false
		}
	}

	/// Whether the argument at `position` of the inline place at `index` is `nil` in every member of `owner`'s class. Every
	/// member's statement at `index` is of one kind, since a class's key holds each statement's shape, which names its kind
	/// (`statementShape`).
	func isNilAtEveryMember(owner: Int, inlineStatement index: Int, argument position: Int) -> Bool {
		for case let .inline(record) in statements(at: index, ofEveryMemberOf: owner) where record.arguments[position].source != .nil {
			return false
		}
		return true
	}

	/// Whether the read at `position` of the text place at `index` is `nil` in every member of `owner`'s class, as
	/// `isNilAtEveryMember(owner:inlineStatement:argument:)` judges an inline place's.
	func isNilAtEveryMember(owner: Int, aliasStatement index: Int, read position: Int) -> Bool {
		for case let .alias(record) in statements(at: index, ofEveryMemberOf: owner) where record.listedReads[position].source != .nil {
			return false
		}
		return true
	}

	/// The statement at `index` of each member of `owner`'s class, or of the root's body.
	func statements(at index: Int, ofEveryMemberOf owner: Int) -> LazyMapSequence<[Int], Statement> {
		let members = owner == 0 ? [0] : membersByClass[owner]
		GenerationWork.record(members.count, by: .checkingReadsAtEveryMember)
		return members.lazy.map { bodies[$0].statements[index] }
	}

	func checkRead(_ read: PlaceRead, inBody body: Int, before index: Int, owner: Int, isNilAtEveryMember: Bool) -> Bool {
		guard !isNilAtEveryMember else { return true }
		let expected = normalized(pathValue(of: read, inBody: body, before: index))
		let declaration = typeLookUp(read.label, inClass: owner, before: index)
		return normalized(evaluate(declaration, inBody: body)) == expected
	}

	/// Whether `read`, which a text place spells as written, names a declaration of the type in the type key's code that it
	/// names in the path key's. The engine adds `.instance` only to the reads it spells, so where two places of one
	/// function hand it a value and its `LazilyInstantiated`, the merged function's wrapper would reach the text unread.
	/// The types are compared by exact spelling (`any P` and `P`, `Optional<X>` and `X?`, differ), which is what text
	/// copied as written needs: a looser match would only share more places, never one the copy reads alike.
	func readsDeclarationOfSameType(_ read: PlaceRead, inBody body: Int, before index: Int, owner: Int) -> Bool {
		type(of: typeLookUp(read.label, inClass: owner, before: index))?.asSource == type(of: normalized(pathValue(of: read, inBody: body, before: index)))?.asSource
	}

	/// Whether the call of `place`'s function from the statement at `index` of `body` passes each parameter what the path
	/// key's call does. Every function is declared in the root's body (`computePlacement`), so a closing call captures
	/// what the path key's function captures.
	func checkCall(of place: Int, from body: Int, at index: Int, closer: ClosingPlaceRecord?) -> Bool {
		let callee = classByBody[place]
		let owner = classByBody[body]
		var siblingEdges: [(edge: (parent: Int, position: Int), sibling: (parent: Int, position: Int))]?
		if let closer, closesOnSibling(closer, from: body) {
			guard let edges = edgesOfSibling(place, closedOnBy: closer, from: body) else { return false }
			siblingEdges = edges
		}
		for label in reads[membersByClass[callee][0]] where outcomes[callee][label] == .passed {
			let declaration = typeLookUp(label, inClass: owner, before: index)
			let actual = normalized(evaluate(declaration, inBody: body))
			if let siblingEdges {
				// A member of a loop of builders calls a sibling's function: at each of its own places, the sibling its body's
				// own parent declares, which reads there what that parent holds before it. The closer passes what its function
				// was passed for the label, which each place's call passes from that same parent, or a declaration of its own.
				guard !bodies[place].cycleParameterLabels.contains(label) else { return false }
				let readsOwnParameter = declaration == .read(owner: owner, label: label) && !bodies[body].cycleParameterLabels.contains(label)
				for pair in siblingEdges {
					let passed = readsOwnParameter ? normalized(resolution(of: label, atPlace: body, edge: pair.edge)) : actual
					guard passed == normalized(resolution(of: label, atPlace: place, edge: pair.sibling)) else { return false }
				}
			} else if closer == nil {
				// The call is an edge of the place: it passes what the place resolves the label to there.
				guard actual == normalized(resolution(of: label, atPlace: place, edge: (parent: body, position: index))) else { return false }
			} else if bodies[place].cycleParameterLabels.contains(label) {
				guard actual == normalized(closerValue(of: label, closing: (body: body, index: index), onPlace: place)) else { return false }
			} else if !passesOwnParameter(declaration, inBody: body, of: place) {
				// A closer that hands on what the place it calls was passed passes, beneath each edge of that place, what that
				// edge resolves the label to, which the call at the edge is checked for. Any other value is the one every
				// edge of the place resolves the label to.
				for edge in bodies[place].edges {
					guard actual == normalized(resolution(of: label, atPlace: place, edge: edge)) else { return false }
				}
			}
		}
		return true
	}

	/// Whether `closer`, a statement of `body`, calls the function of a statement of the body that declares `body`'s own
	/// place: a member of a loop of builders calling a sibling's. Any other closer calls an enclosing place's function or a
	/// statement the view's key pins (`KeyedDeclaration.absolute`).
	func closesOnSibling(_ closer: ClosingPlaceRecord, from body: Int) -> Bool {
		guard closer.rebindsLoopMember, body != 0, case let .statement(declaringBody, _, _) = resolvedFunction(named: closer.closedOnFunctionName, from: body) else { return false }
		return declaringBody == bodies[body].parent
	}

	/// Where `closer`, a statement of `body` that calls a sibling's function (`closesOnSibling(_:from:)`), calls the function
	/// of `place`: each edge of `body` with the edge of `place` that the edge's parent declares under the name, which the
	/// closer calls beneath that edge. `nil` where an edge's parent declares no place of `place`'s view under it.
	func edgesOfSibling(_ place: Int, closedOnBy closer: ClosingPlaceRecord, from body: Int) -> [(edge: (parent: Int, position: Int), sibling: (parent: Int, position: Int))]? {
		var pairs = [(edge: (parent: Int, position: Int), sibling: (parent: Int, position: Int))]()
		for edge in bodies[body].edges {
			guard case let .statement(siblingBody, index, _) = resolvedFunction(named: closer.closedOnFunctionName, from: edge.parent),
			      siblingBody == edge.parent,
			      index < bodies[siblingBody].statements.count,
			      case let .built(sibling) = bodies[siblingBody].statements[index],
			      sibling == place
			else { return nil }
			pairs.append((edge, (siblingBody, index)))
		}
		return pairs
	}

	/// Whether `declaration`, which `typeLookUp` found in the class of `body`, holds there what the function of `place`, a
	/// view enclosing `body` along its first edges, was passed as its parameter of the label.
	func passesOwnParameter(_ declaration: TypeDeclaration, inBody body: Int, of place: Int) -> Bool {
		var declaration = declaration
		var body = body
		while case let .read(owner, label) = declaration {
			guard body != place else { return owner == classByBody[place] }
			guard !bodies[body].cycleParameterLabels.contains(label) else { return false }
			declaration = typeLookUp(label, inClass: classByBody[bodies[body].parent], before: bodies[body].position)
			body = bodies[body].parent
		}
		return false
	}
}
