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

	/// Per level, the cycle of the graph's edges it is on, or `nil` where it is on none: its strongly connected component,
	/// numbered in the order Tarjan's algorithm completes them, where that holds more than one level or the level is its own
	/// parent. Found iteratively, in one pass over the edges.
	func cycleComponents(children: [[Int]]) -> [Int?] {
		var componentOfLevel = [Int?](repeating: nil, count: levels.count)
		var isOwnParent = [Bool](repeating: false, count: levels.count)
		var componentCount = 0
		var indexOfLevel = [Int?](repeating: nil, count: levels.count)
		var lowLink = [Int](repeating: 0, count: levels.count)
		var isOnStack = [Bool](repeating: false, count: levels.count)
		var stack = [Int]()
		var nextIndex = 0
		for root in levels.indices where indexOfLevel[root] == nil {
			// Each frame is a level and the position of the next child to visit.
			var frames = [(level: root, child: 0)]
			indexOfLevel[root] = nextIndex
			lowLink[root] = nextIndex
			nextIndex += 1
			stack.append(root)
			isOnStack[root] = true
			while let frame = frames.last {
				let level = frame.level
				if frame.child < children[level].count {
					frames[frames.count - 1].child += 1
					let child = children[level][frame.child]
					if child == level {
						isOwnParent[level] = true
					}
					if let childIndex = indexOfLevel[child] {
						if isOnStack[child] {
							lowLink[level] = min(lowLink[level], childIndex)
						}
					} else {
						indexOfLevel[child] = nextIndex
						lowLink[child] = nextIndex
						nextIndex += 1
						stack.append(child)
						isOnStack[child] = true
						frames.append((level: child, child: 0))
					}
					continue
				}
				frames.removeLast()
				if let parent = frames.last?.level {
					lowLink[parent] = min(lowLink[parent], lowLink[level])
				}
				guard lowLink[level] == indexOfLevel[level] else { continue }
				var component = [Int]()
				while let member = stack.popLast() {
					isOnStack[member] = false
					component.append(member)
					if member == level {
						break
					}
				}
				if component.count > 1 || isOwnParent[level] {
					for member in component {
						componentOfLevel[member] = componentCount
					}
					componentCount += 1
				}
			}
		}
		return componentOfLevel
	}

	/// What the derivation of cycle re-entries reads of the graph, found once per graph.
	public struct CycleContext: Sendable {
		/// The levels each level encloses (`childLevels()`).
		public let children: [[Int]]
		/// Per level, the cycle of the graph's edges it is on (`cycleComponents(children:)`).
		public let cycleComponent: [Int?]
		/// The entries some call of the graph closes a cycle on: the `closesOn` of its levels.
		public let closedOnEntries: Set<StackEntry>
		/// Per level, the entries that can come again on a route through it: those the edges of each cycle of the graph at
		/// or beneath the level stack. Two builds alike are one level of the graph, so a route through a cycle of levels can
		/// pass a build already on it, which no tree builds; it stacks again an entry of the cycle, which the route can have
		/// stacked before it entered the cycle too. An entry outside every cycle comes once on any route.
		public let entriesComingAgain: [Set<StackEntry>]
	}

	/// The graph's `CycleContext`.
	public func cycleContext() -> CycleContext {
		let children = childLevels()
		let cycleComponent = cycleComponents(children: children)
		var entries = [Set<StackEntry>](repeating: [], count: levels.count)
		var changedLevels = [Int]()
		for (index, level) in levels.enumerated() {
			for parent in level.parents {
				guard let component = cycleComponent[index], cycleComponent[parent] == component,
				      let property = levels[parent].key.nextProperty, let builtType = level.key.builtType
				else { continue }
				let entry = StackEntry(property: property, concreteType: builtType)
				entries[index].insert(entry)
				entries[parent].insert(entry)
				changedLevels += [index, parent]
			}
		}
		// What a level holds, each of its parents holds: a route through the parent can go on down to the level.
		while let level = changedLevels.popLast() {
			for parent in levels[level].parents where !entries[level].isSubset(of: entries[parent]) {
				entries[parent].formUnion(entries[level])
				changedLevels.append(parent)
			}
		}
		return CycleContext(children: children, cycleComponent: cycleComponent, closedOnEntries: Set(levels.compactMap(\.closesOn)), entriesComingAgain: entries)
	}

	/// What a cycle that closes on the scope of `level`, built beneath `parent`, hands the type built again, first per label
	/// (`SeamBuilderParameters.declarationsBetween(closedOnScope:closedOnDeclaration:)`): for each closing call on the
	/// scope's entry (a level whose `closesOn` is it), the nearest declaration of each label on the way down from the scope,
	/// in the order the scope's tree builds the calls, but the labels the scope declares itself. A parameter of a nested
	/// cycle's builder function is the declaration beneath that function's scope that a call closing on it passes, and a
	/// scope between that a nested cycle closes on stands for what that cycle declares of the labels it does not bind.
	///
	/// The way down is read from the graph, where a level can enclose levels of several builds alike, as the tree beneath
	/// the scope builds it where a route stacks `entriesAbove` above the scope: a child whose entry the way already stacks
	/// is a call that closes a cycle, not a build. Each step of a way down that can come again holds the entries of the way
	/// that can (`CycleContext.entriesComingAgain`), so the steps grow with those sets, not with the ways; `statesVisited`
	/// counts them, and the walk stops once it passes `stateLimit`, which leaves the answer partial.
	public func cycleReentries(ofLevel level: Int, beneath parent: Int, context: CycleContext, excluding entriesAbove: Set<StackEntry>, statesVisited: inout Int, stateLimit: Int = .max) -> [CycleReentry] {
		let reentered = levels[level]
		guard let builtType = reentered.key.builtType, let closedOnProperty = levels[parent].key.nextProperty else { return [] }
		let closedOn = StackEntry(property: closedOnProperty, concreteType: builtType)
		let reenteredScope = Scope(parent: parent, declarationList: reentered.declarationList, builtType: builtType)

		var ownLabels: Set<String> = [closedOnProperty.label]
		for declaration in declarationLists[reentered.declarationList] where Self.isBound(declaration) {
			ownLabels.insert(declaration.field.property.label)
		}
		ownLabels.subtract(declarationLists[reentered.declarationList].filter(\.isCycleParameter).map(\.field.property.label))

		var outcomesByKey = [OutcomesKey: [String: [Outcome]]]()
		var keysInProgress = Set<OutcomesKey>()
		let statesBefore = statesVisited
		var steps = 0
		defer { statesVisited += steps }
		/// What the calls beneath `scope` that close on its entry take, per label (`closedOutcomes`); where
		/// `includingNestedCycles`, a scope between that a cycle nested inside closes on also stands for what that cycle
		/// declares.
		func outcomes(beneath scope: ScopeOnWay, includingNestedCycles: Bool) -> [String: [Outcome]] {
			let key = OutcomesKey(scope: scope, includesNestedCycles: includingNestedCycles)
			if let known = outcomesByKey[key] {
				return known
			}
			// No way down passes a scope twice, but a nested cycle's way down asks for its own scope's.
			guard keysInProgress.insert(key).inserted, let entry = entry(of: scope.scope), statesBefore + steps <= stateLimit else { return [:] }
			let (found, stepsRead) = closedOutcomes(beneath: scope, closingOn: entry, context: context, stepLimit: stateLimit - statesBefore - steps) { nestedScope in
				guard includingNestedCycles else { return [:] }
				return nestedCycleDeclarations(of: nestedScope)
			}
			steps += stepsRead
			keysInProgress.remove(key)
			outcomesByKey[key] = found
			return found
		}
		/// What a cycle nested inside closes on `scope` declares again, the first of each label, as `scope`'s own
		/// declarations of the labels it does not bind itself: inline, its builder function takes each wherever its tree
		/// receives it, and what it builds beneath receives that parameter.
		func nestedCycleDeclarations(of scope: ScopeOnWay) -> [String: DeclarationOnWayDown] {
			guard let entry = entry(of: scope.scope), context.closedOnEntries.contains(entry) else { return [:] }
			var boundLabels = Set(declarationsByLabel(of: scope).keys)
			boundLabels.insert(entry.property.label)
			var declarations = [String: DeclarationOnWayDown]()
			for (label, labelOutcomes) in outcomes(beneath: scope, includingNestedCycles: true) where !boundLabels.contains(label) {
				guard var declaration = labelOutcomes.first?.declaration else { continue }
				declaration.typeOfScopeNestedCyclePassesIt = scope.scope.builtType
				declarations[label] = declaration
			}
			return declarations
		}
		let root = ScopeOnWay(scope: reenteredScope, entriesAbove: entriesAbove.union([closedOn]).intersection(context.entriesComingAgain[parent]))
		let outcomesByLabel = outcomes(beneath: root, includingNestedCycles: true)
		var reentries = [CycleReentry]()
		for label in outcomesByLabel.keys.sorted() where !ownLabels.contains(label) {
			var seen = Set<CycleReentry>()
			for outcome in outcomesByLabel[label] ?? [] {
				// A nested cycle's parameter is bound by a declaration beneath the scope that takes it, so the chain ends.
				guard let declaration = outcome.declaration else { continue }
				var binding = declaration
				var scopesPassed = Set<ScopeOnWay>()
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
	/// One pass over the steps of the ways down, which it counts and stops past `stepLimit`, each a scope with the entries above it that can come again, in post-order:
	/// a step leads only to steps that stack more, so the steps hold no cycle, and a step two ways share is read once.
	private func closedOutcomes(beneath root: ScopeOnWay, closingOn entry: StackEntry, context: CycleContext, stepLimit: Int, nestedDeclarations: (ScopeOnWay) -> [String: DeclarationOnWayDown]) -> (outcomes: [String: [Outcome]], steps: Int) {
		// The steps beneath, each with what it does in order: a level's call closing on `entry`, or a step it leads to.
		var stepsByScope = [ScopeOnWay: [ScopeStep]]()
		var scopesInPostOrder = [ScopeOnWay]()
		var toVisit = [(scope: root, isExpanded: false)]
		var visited: Set<ScopeOnWay> = [root]
		while visited.count <= stepLimit, let (scope, isExpanded) = toVisit.popLast() {
			if isExpanded {
				scopesInPostOrder.append(scope)
				continue
			}
			toVisit.append((scope, true))
			var steps = [ScopeStep]()
			for scopeLevel in levelsOf(scope.scope, children: context.children) {
				if let closesOn = levels[scopeLevel].closesOn {
					if closesOn == entry {
						steps.append(.closingCall)
					}
					continue
				}
				guard let nextProperty = levels[scopeLevel].key.nextProperty else { continue }
				for childScope in scopes(beneath: scopeLevel, children: context.children) {
					let childEntry = StackEntry(property: nextProperty, concreteType: childScope.builtType)
					guard childEntry != entry, !scope.entriesAbove.contains(childEntry) else { continue }
					let comingAgain = context.entriesComingAgain[scopeLevel]
					var childAbove = scope.entriesAbove.intersection(comingAgain)
					if comingAgain.contains(childEntry) {
						childAbove.insert(childEntry)
					}
					let child = ScopeOnWay(scope: childScope, entriesAbove: childAbove)
					steps.append(.scope(child))
					if visited.insert(child).inserted {
						toVisit.append((child, false))
					}
				}
			}
			stepsByScope[scope] = steps
		}
		// Per step: the types making the calls beneath it, and per label declared at or beneath it, each call's outcome.
		var callersByScope = [ScopeOnWay: [TypeDescription]]()
		var outcomesByScope = [ScopeOnWay: [String: [Outcome]]]()
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
					appending([scope.scope.builtType], to: &callers, seen: &seenCallers)
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
						appending([Outcome(declaration: nil, reenteringType: scope.scope.builtType)], to: &sequence, seen: &seen)
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
		let closedOutcomes = (outcomesByScope[root] ?? [:]).compactMapValues { outcomes -> [Outcome]? in
			let closed = outcomes.filter { $0.declaration != nil }
			return closed.isEmpty ? nil : closed
		}
		return (closedOutcomes, visited.count)
	}

	/// The nearest declaration of each label `scope` binds for the scopes beneath it: a parameter of its builder function a
	/// cycle closes on hides its other declarations of the label.
	private func declarationsByLabel(of scope: ScopeOnWay) -> [String: DeclarationOnWayDown] {
		var declarationsByLabel = [String: DeclarationOnWayDown]()
		for declaration in declarationLists[scope.scope.declarationList] where Self.isBound(declaration) || declaration.isCycleParameter {
			declarationsByLabel[declaration.field.property.label] = declaration.isCycleParameter
				? DeclarationOnWayDown(property: declaration.field.property, declaringType: scope.scope.builtType, declarationLocation: nil, parameterOfScope: scope)
				: DeclarationOnWayDown(property: declaration.field.property, declaringType: declaration.field.declaringType, declarationLocation: declaration.field.declarationLocation, parameterOfScope: nil)
		}
		return declarationsByLabel
	}

	private enum ScopeStep {
		case closingCall
		case scope(ScopeOnWay)
	}

	private struct Outcome: Hashable {
		/// The nearest declaration of the label on the way down to the call, or `nil` where none is beneath the scope.
		let declaration: DeclarationOnWayDown?
		/// The type that makes the call.
		let reenteringType: TypeDescription
	}

	private struct OutcomesKey: Hashable {
		let scope: ScopeOnWay
		let includesNestedCycles: Bool
	}

	/// A build on a way down, with the entries the stack above it holds that can come again beneath it: its own included.
	private struct ScopeOnWay: Hashable {
		let scope: Scope
		let entriesAbove: Set<StackEntry>
	}

	/// The entries `route` stacks from its root to each of its levels, its root's empty: an edge into a level that builds a
	/// type stacks its property and that type, and a fill starts a stack of its own.
	public func stackEntries(along route: [Int]) -> [Set<StackEntry>] {
		var entries = Set<StackEntry>()
		var entriesByPosition = [entries]
		for (parent, level) in zip(route, route.dropFirst()) {
			if let property = levels[parent].key.nextProperty, let builtType = levels[level].key.builtType {
				entries.insert(StackEntry(property: property, concreteType: builtType))
			} else {
				entries = []
			}
			entriesByPosition.append(entries)
		}
		return entriesByPosition
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
		let parameterOfScope: ScopeOnWay?
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
