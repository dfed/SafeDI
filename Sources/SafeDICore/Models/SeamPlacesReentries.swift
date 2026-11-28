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

extension SeamSignature.Places {
	/// The levels each level encloses, in level order: the levels that list it among their parents.
	public func childLevels() -> [[Int]] {
		var children = [[Int]](repeating: [], count: levels.count)
		for (index, level) in levels.enumerated() {
			for parent in level.parents {
				children[parent].append(index)
			}
		}
		return children
	}

	/// What the derivation of cycle re-entries reads of the graph, found once per graph.
	public struct CycleContext: Sendable {
		/// The levels each level encloses (`childLevels()`).
		public let children: [[Int]]
		/// The entries some call of the graph closes a cycle on: the `closesOn` of its levels.
		public let closedOnEntries: Set<StackEntry>
	}

	/// The graph's `CycleContext`.
	public func cycleContext() -> CycleContext {
		CycleContext(children: childLevels(), closedOnEntries: Set(levels.compactMap(\.closesOn)))
	}

	/// What a cycle that closes on the scope of `level`, built beneath `parent`, hands the type built again, first per label
	/// (`SeamBuilderParameters.declarationsBetween(closedOnScope:closedOnDeclaration:)`): for each closing call on the
	/// scope's entry (a level whose `closesOn` is it), the nearest declaration of each label on the way down from the scope,
	/// in the order the scope's tree builds the calls, but the labels the scope declares itself. A parameter of a nested
	/// cycle's builder function is the declaration beneath that function's scope that a call closing on it passes, and a
	/// scope between that a nested cycle closes on stands for what that cycle declares of the labels it does not bind.
	///
	/// The way down is read from the graph, where a level can enclose levels of several builds alike, as the tree beneath
	/// the scope builds it: a child whose entry is the scope's own is a call that closes the cycle, not a build. The graph
	/// holds no cycle of levels, since a type built again beneath itself is a call that closes a cycle, where the tree
	/// stops, so the steps of the ways down are its levels' builds, each read once.
	public func cycleReentries(ofLevel level: Int, beneath parent: Int, context: CycleContext) -> [CycleReentry] {
		let reentered = levels[level]
		guard let builtType = reentered.key.builtType, let closedOnProperty = levels[parent].key.nextProperty else { return [] }
		let reenteredScope = Scope(parent: parent, declarationList: reentered.declarationList, builtType: builtType)

		var ownLabels: Set<String> = [closedOnProperty.label]
		for declaration in declarationLists[reentered.declarationList] where Self.isBound(declaration) {
			ownLabels.insert(declaration.field.property.label)
		}
		ownLabels.subtract(declarationLists[reentered.declarationList].filter(\.isCycleParameter).map(\.field.property.label))

		var outcomesByKey = [OutcomesKey: [String: [Outcome]]]()
		var keysInProgress = Set<OutcomesKey>()
		/// What the calls beneath `scope` that close on its entry take, per label (`closedOutcomes`); where
		/// `includingNestedCycles`, a scope between that a cycle nested inside closes on also stands for what that cycle
		/// declares.
		func outcomes(beneath scope: Scope, includingNestedCycles: Bool) -> [String: [Outcome]] {
			let key = OutcomesKey(scope: scope, includesNestedCycles: includingNestedCycles)
			if let known = outcomesByKey[key] {
				return known
			}
			// No way down passes a scope twice, but a nested cycle's way down asks for its own scope's.
			guard keysInProgress.insert(key).inserted, let entry = entry(of: scope) else { return [:] }
			let found = closedOutcomes(beneath: scope, closingOn: entry, context: context) { nestedScope in
				guard includingNestedCycles else { return [:] }
				return nestedCycleDeclarations(of: nestedScope)
			}
			keysInProgress.remove(key)
			outcomesByKey[key] = found
			return found
		}
		/// What a cycle nested inside closes on `scope` declares again, the first of each label, as `scope`'s own
		/// declarations of the labels it does not bind itself: inline, its builder function takes each wherever its tree
		/// receives it, and what it builds beneath receives that parameter.
		func nestedCycleDeclarations(of scope: Scope) -> [String: DeclarationOnWayDown] {
			guard let entry = entry(of: scope), context.closedOnEntries.contains(entry) else { return [:] }
			var boundLabels = Set(declarationsByLabel(of: scope).keys)
			boundLabels.insert(entry.property.label)
			var declarations = [String: DeclarationOnWayDown]()
			for (label, labelOutcomes) in outcomes(beneath: scope, includingNestedCycles: true) where !boundLabels.contains(label) {
				guard var declaration = labelOutcomes.first?.declaration else { continue }
				declaration.typeOfScopeNestedCyclePassesIt = scope.builtType
				declarations[label] = declaration
			}
			return declarations
		}
		let outcomesByLabel = outcomes(beneath: reenteredScope, includingNestedCycles: true)
		var reentries = [CycleReentry]()
		for label in outcomesByLabel.keys.sorted() where !ownLabels.contains(label) {
			var seen = Set<CycleReentry>()
			for outcome in outcomesByLabel[label] ?? [] {
				// A nested cycle's parameter is bound by a declaration beneath the scope that takes it, so the chain ends.
				guard let declaration = outcome.declaration else { continue }
				var binding = declaration
				var scopesPassed = Set<Scope>()
				while let scope = binding.parameterOfScope, scopesPassed.insert(scope).inserted, let next = outcomes(beneath: scope, includingNestedCycles: false)[label]?.first {
					binding = next.declaration ?? binding
				}
				let reentry = CycleReentry(
					property: binding.property,
					declaringType: binding.declaringType,
					declarationLocation: binding.declarationLocation,
					parameterTakingType: declaration.parameterOfScope.map { _ in declaration.declaringType } ?? declaration.typeOfScopeNestedCyclePassesIt,
					closedOnProperty: closedOnProperty,
					closedOnBuiltType: builtType,
					reenteringType: outcome.reenteringType,
				)
				if seen.insert(reentry).inserted {
					reentries.append(reentry)
				}
			}
		}
		return reentries
	}

	/// The entry the build `scope` stacks: its parent's next property, built as its type.
	private func entry(of scope: Scope) -> StackEntry? {
		levels[scope.parent].key.nextProperty.map { StackEntry(property: $0, concreteType: scope.builtType) }
	}

	/// For each label, every declaration a call beneath `root` that closes on `entry` can take as its nearest of the label
	/// between the scope and the call, with the type that makes the call, in the order the scope's tree builds the calls:
	/// the first is the first call's whose way down declares the label, as a walk of the tree finds it. The scope's own
	/// declarations are left out; `nestedDeclarations` gives, for a scope beneath, what it stands for besides its own.
	///
	/// One pass over the steps of the ways down, each a scope, in post-order: the graph holds no cycle of levels, so the
	/// steps hold none, and a step two ways share is read once.
	private func closedOutcomes(beneath root: Scope, closingOn entry: StackEntry, context: CycleContext, nestedDeclarations: (Scope) -> [String: DeclarationOnWayDown]) -> [String: [Outcome]] {
		// The steps beneath, each with what it does in order: a level's call closing on `entry`, or a step it leads to.
		var stepsByScope = [Scope: [ScopeStep]]()
		var scopesInPostOrder = [Scope]()
		var toVisit = [(scope: root, isExpanded: false)]
		var visited: Set<Scope> = [root]
		while let (scope, isExpanded) = toVisit.popLast() {
			if isExpanded {
				scopesInPostOrder.append(scope)
				continue
			}
			toVisit.append((scope, true))
			var steps = [ScopeStep]()
			for scopeLevel in levelsOf(scope, children: context.children) {
				if let closesOn = levels[scopeLevel].closesOn {
					if closesOn == entry {
						steps.append(.closingCall)
					}
					continue
				}
				guard let nextProperty = levels[scopeLevel].key.nextProperty else { continue }
				for childScope in scopes(beneath: scopeLevel, children: context.children) {
					let childEntry = StackEntry(property: nextProperty, concreteType: childScope.builtType)
					guard childEntry != entry else { continue }
					steps.append(.scope(childScope))
					if visited.insert(childScope).inserted {
						toVisit.append((childScope, false))
					}
				}
			}
			stepsByScope[scope] = steps
		}
		// Per step: the types making the calls beneath it, and per label declared at or beneath it, each call's outcome.
		var callersByScope = [Scope: [TypeDescription]]()
		var outcomesByScope = [Scope: [String: [Outcome]]]()
		func appending<Element: Hashable>(_ elements: [Element], to sequence: inout [Element], seen: inout Set<Element>) {
			for element in elements where seen.insert(element).inserted {
				sequence.append(element)
			}
		}
		for scope in scopesInPostOrder {
			let steps = stepsByScope[scope] ?? []
			var callers = [TypeDescription]()
			var seenCallers = Set<TypeDescription>()
			var labels = Set<String>()
			for step in steps {
				switch step {
				case .closingCall:
					appending([scope.builtType], to: &callers, seen: &seenCallers)
				case let .scope(childScope):
					appending(callersByScope[childScope] ?? [], to: &callers, seen: &seenCallers)
					labels.formUnion((outcomesByScope[childScope] ?? [:]).keys)
				}
			}
			let ownDeclarations = scope == root ? [:] : declarationsByLabel(of: scope).merging(nestedDeclarations(scope)) { own, _ in own }
			labels.formUnion(ownDeclarations.keys)
			var outcomesByLabel = [String: [Outcome]]()
			for label in labels {
				// A call whose way down declares none of the label is open, for a scope above to close.
				var sequence = [Outcome]()
				var seen = Set<Outcome>()
				for step in steps {
					switch step {
					case .closingCall:
						appending([Outcome(declaration: nil, reenteringType: scope.builtType)], to: &sequence, seen: &seen)
					case let .scope(childScope):
						let childOutcomes = outcomesByScope[childScope]?[label] ?? (callersByScope[childScope] ?? []).map { Outcome(declaration: nil, reenteringType: $0) }
						appending(childOutcomes, to: &sequence, seen: &seen)
					}
				}
				// The scope's declaration is the nearest for each call beneath that declares none of the label.
				if let declaration = ownDeclarations[label] {
					var closed = [Outcome]()
					var seenClosed = Set<Outcome>()
					appending(sequence.map { $0.declaration == nil ? Outcome(declaration: declaration, reenteringType: $0.reenteringType) : $0 }, to: &closed, seen: &seenClosed)
					sequence = closed
				}
				outcomesByLabel[label] = sequence
			}
			callersByScope[scope] = callers
			outcomesByScope[scope] = outcomesByLabel
		}
		return (outcomesByScope[root] ?? [:]).compactMapValues { outcomes -> [Outcome]? in
			let closed = outcomes.filter { $0.declaration != nil }
			return closed.isEmpty ? nil : closed
		}
	}

	/// The nearest declaration of each label `scope` binds for the scopes beneath it: a parameter of its builder function a
	/// cycle closes on hides its other declarations of the label.
	private func declarationsByLabel(of scope: Scope) -> [String: DeclarationOnWayDown] {
		var declarationsByLabel = [String: DeclarationOnWayDown]()
		for declaration in declarationLists[scope.declarationList] where Self.isBound(declaration) || declaration.isCycleParameter {
			declarationsByLabel[declaration.field.property.label] = declaration.isCycleParameter
				? DeclarationOnWayDown(property: declaration.field.property, declaringType: scope.builtType, declarationLocation: nil, parameterOfScope: scope)
				: DeclarationOnWayDown(property: declaration.field.property, declaringType: declaration.field.declaringType, declarationLocation: declaration.field.declarationLocation, parameterOfScope: nil)
		}
		return declarationsByLabel
	}

	private enum ScopeStep {
		case closingCall
		case scope(Scope)
	}

	private struct Outcome: Hashable {
		/// The nearest declaration of the label on the way down to the call, or `nil` where none is beneath the scope.
		let declaration: DeclarationOnWayDown?
		/// The type that makes the call.
		let reenteringType: TypeDescription
	}

	private struct OutcomesKey: Hashable {
		let scope: Scope
		let includesNestedCycles: Bool
	}

	/// One build of a type beneath a level: the levels beneath `parent` that build `builtType` with `declarationList`.
	private struct Scope: Hashable {
		let parent: Int
		let declarationList: Int
		let builtType: TypeDescription
	}

	private struct DeclarationOnWayDown: Hashable {
		let property: Property
		let declaringType: TypeDescription
		let declarationLocation: Dependency.DeclarationLocation?
		/// For a parameter of a builder function a cycle closes on, the scope whose function takes it.
		let parameterOfScope: Scope?
		/// For a declaration a cycle nested inside a scope between declares, which that scope's builder function is passed
		/// wherever a type in its tree receives the label, the type that scope builds; `nil` for a declaration on the way.
		var typeOfScopeNestedCyclePassesIt: TypeDescription?
	}

	/// Whether `declaration` is one the scope binds for the scopes beneath it, as `declarationsBound(by:)` counts them with
	/// forwarded properties: a child or a forwarded property, but no cycle parameter, rebinding or receive bound again.
	private static func isBound(_ declaration: Declaration) -> Bool {
		!declaration.isCycleParameter && (declaration.child != nil || declaration.isForwarded)
	}

	/// The levels of `scope`, in the order its scope builds their next properties.
	private func levelsOf(_ scope: Scope, children: [[Int]]) -> [Int] {
		children[scope.parent]
			.filter { levels[$0].key.builtType == scope.builtType && levels[$0].declarationList == scope.declarationList }
			.sorted { (levels[$0].nextPosition ?? .max, $0) < (levels[$1].nextPosition ?? .max, $1) }
	}

	/// The builds of a type beneath `level`, in level order: a fill builds none, so the way down never enters one.
	private func scopes(beneath level: Int, children: [[Int]]) -> [Scope] {
		var scopes = [Scope]()
		var seen = Set<Scope>()
		for child in children[level] {
			guard let builtType = levels[child].key.builtType else { continue }
			let scope = Scope(parent: level, declarationList: levels[child].declarationList, builtType: builtType)
			if seen.insert(scope).inserted {
				scopes.append(scope)
			}
		}
		return scopes
	}
}
