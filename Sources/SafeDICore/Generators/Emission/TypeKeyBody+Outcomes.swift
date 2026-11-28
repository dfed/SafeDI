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
			// A function that captures its read, or reads none, sees the declarations of the body that declares it
			// (`computePlacement`) before its own: the root's, or, as the path key nests a loop's, a function's. One that
			// reads none has no declaration there: the first statement that reaches it is before the path that resolved the
			// read to none.
			typeLookUp(label, inClass: placementOwner[owner], before: placementIndex[owner])
		}
	}

	/// The declaration a call made before the statement at `index` of `owner`'s body passes `callee`'s parameter `label`:
	/// the nearest declaration of the label, or none where that declaration provides no form of the optional parameter's
	/// type. Hiding is by label, so the nearest declaration hides every one above it whatever its form, and a forward of
	/// `mark: Mark?` above a parameter `mark: Stamp?` passes `nil`, as today's tree does.
	func passedDeclaration(_ label: String, toParameterOf callee: Int, inClass owner: Int, before index: Int) -> TypeDeclaration {
		let declaration = typeLookUp(label, inClass: owner, before: index)
		guard let parameterType = parameterTypes[callee][label],
		      parameterType.isOptional,
		      let declaredType = type(of: declaration, label: label),
		      !Self.provides(declaredType, parameterType)
		else { return declaration }
		return .none
	}

	/// Whether a declaration typed `declaredType` provides a parameter typed `parameterType`: the type itself, its
	/// unwrapped type where the parameter is optional, or the instance of the lazy wrapper the parameter takes.
	static func provides(_ declaredType: TypeDescription, _ parameterType: TypeDescription) -> Bool {
		declaredType == parameterType
			|| (parameterType.isOptional && parameterType.unwrapped == declaredType)
			|| (parameterType.unwrapped.lazilyInstantiatedInstanceType == declaredType && !declaredType.isOptional)
	}

	/// The position of the last statement of `owner`'s body before `index` that declares `label`.
	func lastPosition(of label: String, inClass owner: Int, before index: Int) -> Int? {
		// The body `statements(ofClass:)` reads, whose positions of each label are indexed in order: a lookup in the root's
		// long body stays logarithmic.
		Self.lastPosition(in: bodies[owner == 0 ? 0 : membersByClass[owner][0]].positionsByLabel[label], before: index)
	}

	/// The last of `positions`, which ascend, before `index`: a binary search, since a look-up reads it for every label at
	/// every place, so a body of many statements costs a look-up no more than a few.
	static func lastPosition(in positions: [Int]?, before index: Int) -> Int? {
		guard let positions else { return nil }
		var low = 0
		var high = positions.count
		while low < high {
			let middle = (low + high) / 2
			if positions[middle] < index {
				low = middle + 1
			} else {
				high = middle
			}
		}
		return low == 0 ? nil : positions[low - 1]
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
			// A variant of the per-type plan whose function captures the root's statement every call passes it holds that
			// statement throughout its body, so a function built inside the body reads the statement, as today's function
			// captures it. The variants' outcomes are settled before any other class asks (`computeOutcomes`).
			if let position = rootStatementsCapturedByVariant[body]?[label],
			   outcomes[classByBody[body]][label] == .captured(.statement(owner: 0, index: position))
			{
				.statement(owner: 0, index: position)
			} else {
				// Any other function reads its cycle parameter from its caller, whatever the outcome of its label: no graph
				// of the fuzzer's corpora settles one as captured or none, and a layout that reads it so is still checked
				// against the path key read by read (`checkEveryRead`).
				.read(owner: classByBody[body], label: label)
			}
		}
	}

	/// Where `owner`'s function is declared: its placement, or, for a function a place written as text declares, each
	/// member's statement, since each member is spelled where its statement is.
	func declarationSites(ofClass owner: Int) -> [CallSite] {
		guard isCallingFunctionClass(owner) else { return [CallSite(owner: placementOwner[owner], index: placementIndex[owner])] }
		return membersByClass[owner].map { member in CallSite(owner: classByBody[bodies[member].parent], index: bodies[member].position) }
	}

	/// Whether no function a place written as text declares reads a label its calls pass: the text's binding hands its
	/// wrapper the function by name, with only what the wrapper forwards.
	func callingFunctionsTakeNoParameters() -> Bool {
		membersByClass.indices.allSatisfy { owner in
			!isCallingFunctionClass(owner) || !outcomes[owner].values.contains(.passed)
		}
	}

	/// What each class's function does with each label it reads. Every function is declared in the root's body
	/// (`computePlacement`), and a cycle parameter is read from the caller, or, where a variant captures it, is the
	/// root's statement, so the variants' classes are settled first. Every other function's outcomes depend only on those
	/// of the functions declaring it (`computePlacement`), so one pass after them, outer functions first, settles them.
	mutating func computeOutcomes() {
		rootStatementsCapturedByVariant = rootStatementsCapturedByVariants()
		outcomes = [[String: ReadOutcome]](repeating: [:], count: membersByClass.count)
		for owner in membersByClass.indices.dropFirst() {
			guard let variant = membersByClass[owner].first(where: { variantBodies.contains($0) }) else { continue }
			for label in reads[membersByClass[owner][0]] {
				// Every label a variant of the per-type plan reads from above is a parameter of its body
				// (`CycleVariantRecord.parameters`), or one its body was built with `nil` for, which it reads as `nil`
				// (`variantsReadOnlyTheirCycleParameters`). Its function captures a parameter every call passes one statement of
				// the root's body, declared before the function, and takes every other one.
				let capturedPositions = Set(membersByClass[owner].map { rootStatementsCapturedByVariant[$0]?[label] })
				if !bodies[variant].cycleParameterLabels.contains(label) {
					outcomes[owner][label] = ReadOutcome.none
				} else if capturedPositions.count == 1,
				          let position = capturedPositions.first ?? nil,
				          typeLookUp(label, inClass: placementOwner[owner], before: placementIndex[owner]) == .statement(owner: 0, index: position)
				{
					outcomes[owner][label] = .captured(.statement(owner: 0, index: position))
				} else {
					outcomes[owner][label] = .passed
				}
			}
		}
		for owner in membersByClass.indices.dropFirst().sorted(by: { (placementDepth[$0], $0) < (placementDepth[$1], $1) }) where !membersByClass[owner].contains(where: { variantBodies.contains($0) }) {
			for label in reads[membersByClass[owner][0]] {
				var declarations = [TypeDeclaration]()
				for member in membersByClass[owner] {
					// A view's places can resolve a label to other declarations outside it, alike in kind and type, each of
					// which its call passes.
					// A place that declares only its function makes no call of it: only its closers pass it anything.
					for edge in bodies[member].edges where bodies[member].record?.bindsProperty != false {
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
				          declarationSites(ofClass: owner).allSatisfy({ typeLookUp(label, inClass: $0.owner, before: $0.index) == first })
				{
					.captured(first)
				} else {
					.passed
				}
				outcomes[owner][label] = outcome
			}
		}
	}

	/// For each variant body, the cycle parameters every call passes one statement of the root's body, by its position:
	/// the greatest set where each call passes that statement or the same parameter of a variant body in the set, which
	/// holds that statement. A call of a variant made inside another variant's body passes on that body's parameter, so
	/// the variants of one cycle hold each other's parameters, and only the greatest set finds that they all hold the
	/// root's statement. Each parameter's candidate is the statement its calls pass, directly or through the parameters
	/// that pass it on, found from the calls of the root's body outward; then every candidate some call contradicts is
	/// dropped, until none is.
	func rootStatementsCapturedByVariants() -> [Int: [String: Int]] {
		var captured = [Int: [String: Int]]()
		var assigned = true
		while assigned {
			assigned = false
			for variant in variantBodies.sorted() {
				for label in bodies[variant].cycleParameterLabels.sorted() where captured[variant]?[label] == nil {
					var positions = Set<Int>()
					var passesOtherValue = false
					for closer in closersByTarget[variant] ?? [] {
						switch closerValue(of: label, closing: closer, onPlace: variant) {
						case let .statement(body, index):
							if body == 0 {
								positions.insert(index)
							} else {
								passesOtherValue = true
							}
						case let .cycleParameter(body, passedLabel):
							if passedLabel == label, let position = captured[body]?[label] {
								positions.insert(position)
							}
						case .forwarded,
						     .none:
							passesOtherValue = true
						}
					}
					if !passesOtherValue, positions.count == 1, let position = positions.first {
						captured[variant, default: [:]][label] = position
						assigned = true
					}
				}
			}
		}
		var changed = true
		while changed {
			changed = false
			for variant in captured.keys.sorted() {
				for (label, position) in captured[variant, default: [:]].sorted(by: { $0.key < $1.key }) {
					// The loop above captured the label only where no call passes another statement, a forwarded value or
					// nothing, and every root statement a call passes is the one at `position`; it set aside a cycle parameter
					// it could not judge yet. So only a call that passes a cycle parameter can fail here: one of another label,
					// or of a function that captures the label at no position, or at another.
					let everyCallPassesStatement = (closersByTarget[variant] ?? []).allSatisfy { closer in
						guard case let .cycleParameter(body, passedLabel) = closerValue(of: label, closing: closer, onPlace: variant) else { return true }
						return passedLabel == label && captured[body]?[label] == position
					}
					if !everyCallPassesStatement {
						captured[variant]?[label] = nil
						changed = true
					}
				}
			}
		}
		return captured
	}

	/// What the closing statement `closer` passes the function of `place` for `label`: its argument for a cycle parameter,
	/// else what the place resolves the label to.
	func closerValue(of label: String, closing closer: (body: Int, index: Int), onPlace place: Int) -> PathValue {
		guard bodies[place].cycleParameterLabels.contains(label) else { return resolution(of: label, atPlace: place) }
		guard let argument = cycleArgumentsByCloser[CallSite(owner: closer.body, index: closer.index)]?[label] else { return .none }
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
					// A variant's parameter takes the type of the declaration its body's answer names, which every call passes,
					// since bodies are told apart by their answers.
					if let parameter = variantParameter(labeled: label, inClass: owner) {
						parameterTypes[owner][label] = parameter.typeDescription
					} else {
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

	/// The parameter labeled `label` of the variant of the per-type plan among the members of class `owner`, if any.
	func variantParameter(labeled label: String, inClass owner: Int) -> Property? {
		membersByClass[owner].lazy
			.filter { variantBodies.contains($0) }
			.compactMap { self.bodies[$0].cycleParameters.first(where: { $0.label == label }) }
			.first
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
