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
	// MARK: Outcomes

	/// The nearest declaration of `label` the type key's code sees before the statement at `index` of `owner`'s body.
	func typeLookUp(_ label: String, inClass owner: Int, before index: Int) -> TypeDeclaration {
		if let position = lastPosition(of: label, inClass: owner, before: index) {
			.statement(owner: owner, index: position)
		} else if owner == 0 {
			.none
		} else if parameterLabelsByClass[owner].contains(label) {
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
	func lastPosition(of label: String, inClass owner: Int, before index: Int) -> Int? {
		Self.lastPosition(in: bodies[owner == 0 ? 0 : membersByClass[owner][0]].positionsByLabel[label], before: index)
	}

	/// The last of `positions`, which ascend, before `index`: a binary search, since a look-up reads it for every label at
	/// every place, so a body of many statements costs a look-up no more than a few.
	static func lastPosition(in positions: [Int]?, before index: Int) -> Int? {
		guard let positions else { return nil }
		var lower = 0
		var upper = positions.count
		while lower < upper {
			let middle = (lower + upper) / 2
			if positions[middle] < index {
				lower = middle + 1
			} else {
				upper = middle
			}
		}
		return lower > 0 ? positions[lower - 1] : nil
	}

	/// The type key's declaration for a path declaration.
	func typeDeclaration(for value: PathValue) -> TypeDeclaration {
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
					// A view's places can resolve a label to other declarations outside it, alike in kind and type, each of
					// which its call passes.
					for edge in bodies[member].edges {
						declarations.append(typeDeclaration(for: resolution(of: label, atPlace: member, edge: edge)))
					}
					for closer in closersByTarget[member] ?? [] {
						declarations.append(typeDeclaration(for: closerValue(of: label, closing: closer, onPlace: member)))
					}
				}
				let outcome: ReadOutcome = if declarations.allSatisfy({ $0 == .none }) {
					.none
				} else if let first = declarations.first,
				          declarations.allSatisfy({ $0 == first }),
				          typeLookUp(label, inClass: placementOwner[owner], before: placementIndex[owner]) == first
				{
					.captured(first)
				} else {
					.passed
				}
				outcomes[owner][label] = outcome
			}
		}
		self.outcomes = outcomes
	}

	/// What the closing statement `closer` passes the function of `place` for `label`: its argument for a cycle parameter,
	/// else what the place resolves the label to.
	func closerValue(of label: String, closing closer: (body: Int, index: Int), onPlace place: Int) -> PathValue {
		guard bodies[place].cycleParameterLabels.contains(label) else { return resolution(of: label, atPlace: place) }
		guard case let .closer(record, _) = bodies[closer.body].statements[closer.index],
		      let argument = record.cycleArguments.first(where: { $0.label == label })
		else { return .none }
		return pathValue(of: argument, inBody: closer.body, before: closer.index)
	}

	// MARK: Parameter types

	/// The type of a type key's declaration, `nil` for none or a parameter not typed yet.
	func type(of declaration: TypeDeclaration, label readLabel: String) -> TypeDescription? {
		switch declaration {
		case .none:
			nil
		case let .statement(owner, index):
			property(of: statements(ofClass: owner)[index], label: readLabel)?.typeDescription
		case let .forwarded(owner, label):
			representative(of: owner)?.parameterProperties.first(where: { $0.label == label })?.typeDescription
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
						if case .read = declaration, type(of: declaration, label: label) == nil {
							// A parameter whose type is not known yet passes a value of some type, never `nil`: it is
							// left out until it is known, so it never makes this parameter optional.
							isComplete = false
						} else {
							types.append(type(of: declaration, label: label))
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
	static func parameterType(combining types: [TypeDescription?]) -> TypeDescription? {
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
}
