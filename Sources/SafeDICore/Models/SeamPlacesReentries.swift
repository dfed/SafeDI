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
	func childLevels() -> [[Int]] {
		var children = [[Int]](repeating: [], count: levels.count)
		for (index, level) in levels.enumerated() {
			for parent in level.parents {
				children[parent].append(index)
			}
		}
		return children
	}

	/// Per level, whether it is on a cycle of the graph's edges: in a strongly connected component of more than one level,
	/// or its own parent. Found by Tarjan's algorithm, iteratively, in one pass over the edges.
	func levelsOnCycles(children: [[Int]]) -> [Bool] {
		var isOnCycle = [Bool](repeating: false, count: levels.count)
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
						isOnCycle[level] = true
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
				if component.count > 1 {
					for member in component {
						isOnCycle[member] = true
					}
				}
			}
		}
		return isOnCycle
	}

	/// What a cycle that closes on the scope of `level`, built beneath `parent`, hands the type built again, first per label
	/// (`SeamBuilderParameters.declarationsBetween(closedOnScope:closedOnDeclaration:)`): for each closing call on the
	/// scope's entry (a level whose `closesOn` is it), the nearest declaration of each label on the way down from the scope,
	/// in the order the scope's tree builds the calls, but the labels the scope declares itself. A parameter of a nested
	/// cycle's builder function is the declaration beneath that function's scope that a call closing on it passes.
	///
	/// The way down is read from the graph, where a level can enclose levels of several builds alike: it never stacks an
	/// entry twice, but can join the tree of one build to another's.
	func cycleReentries(ofLevel level: Int, beneath parent: Int, children: [[Int]]) -> [CycleReentry] {
		let reentered = levels[level]
		guard let builtType = reentered.key.builtType, let closedOnProperty = levels[parent].key.nextProperty else { return [] }
		let closedOn = StackEntry(property: closedOnProperty, concreteType: builtType)
		let reenteredScope = Scope(parent: parent, declarationList: reentered.declarationList, builtType: builtType)

		var ownLabels: Set<String> = [closedOnProperty.label]
		for declaration in declarationLists[reentered.declarationList] where Self.isBound(declaration) {
			ownLabels.insert(declaration.field.property.label)
		}
		ownLabels.subtract(declarationLists[reentered.declarationList].filter(\.isCycleParameter).map(\.field.property.label))

		var declarationsMet = [(declaration: DeclarationOnWayDown, reenteringType: TypeDescription)]()
		var labelsOfDeclarationsMet = Set<String>()
		var bindingByNestedParameter = [NestedParameter: DeclarationOnWayDown]()
		/// What the walk down does next, in the order a walk of the scope's tree would: enter a scope, or take one of its levels.
		enum Step {
			case scope(Scope, pathDeclarations: [DeclarationOnWayDown], nestedScopes: [NestedScope], entriesOnWay: Set<StackEntry>)
			case level(Int, of: Scope, pathDeclarations: [DeclarationOnWayDown], nestedScopes: [NestedScope], entriesOnWay: Set<StackEntry>)
		}
		// A stack, not recursion: a tree can be deeper than a thread's stack allows.
		var steps = [Step.scope(reenteredScope, pathDeclarations: [], nestedScopes: [], entriesOnWay: [closedOn])]
		while let step = steps.popLast() {
			switch step {
			case let .scope(scope, pathDeclarations, nestedScopes, entriesOnWay):
				var pathDeclarations = pathDeclarations
				var nestedScopes = nestedScopes
				if scope != reenteredScope {
					let declarations = declarationLists[scope.declarationList]
					for declaration in declarations where Self.isBound(declaration) || declaration.isCycleParameter {
						pathDeclarations.append(DeclarationOnWayDown(property: declaration.field.property, declaringType: declaration.field.declaringType, declarationLocation: declaration.field.declarationLocation, parameterOfScope: nil))
					}
					let parameterLabels = declarations.filter(\.isCycleParameter).map(\.field.property.label)
					for declaration in declarations where declaration.isCycleParameter {
						pathDeclarations.append(DeclarationOnWayDown(property: declaration.field.property, declaringType: scope.builtType, declarationLocation: nil, parameterOfScope: scope))
					}
					if !parameterLabels.isEmpty, let property = levels[scope.parent].key.nextProperty {
						nestedScopes.append(NestedScope(scope: scope, entry: StackEntry(property: property, concreteType: scope.builtType), parameterLabels: parameterLabels, firstDeclarationBeneath: pathDeclarations.count))
					}
				}
				for scopeLevel in levelsOf(scope, children: children).reversed() {
					steps.append(.level(scopeLevel, of: scope, pathDeclarations: pathDeclarations, nestedScopes: nestedScopes, entriesOnWay: entriesOnWay))
				}
			case let .level(scopeLevel, scope, pathDeclarations, nestedScopes, entriesOnWay):
				if let closesOn = levels[scopeLevel].closesOn {
					if closesOn == closedOn {
						// The nearest declaration of each label on the way, which the cycle-closing scope passes the function.
						var labelsMet = Set<String>()
						for pathDeclaration in pathDeclarations.reversed()
							where labelsMet.insert(pathDeclaration.property.label).inserted
							&& !ownLabels.contains(pathDeclaration.property.label)
							&& labelsOfDeclarationsMet.insert(pathDeclaration.property.label).inserted
						{
							declarationsMet.append((pathDeclaration, scope.builtType))
						}
					} else if let nestedScope = nestedScopes.last(where: { $0.entry == closesOn }) {
						let declarationsBeneath = pathDeclarations[nestedScope.firstDeclarationBeneath...]
						for label in nestedScope.parameterLabels where bindingByNestedParameter[NestedParameter(scope: nestedScope.scope, label: label)] == nil {
							bindingByNestedParameter[NestedParameter(scope: nestedScope.scope, label: label)] = declarationsBeneath.last { $0.property.label == label }
						}
					}
					continue
				}
				guard let nextProperty = levels[scopeLevel].key.nextProperty else { continue }
				for childScope in scopes(beneath: scopeLevel, children: children).reversed() {
					var entriesOnWay = entriesOnWay
					guard entriesOnWay.insert(StackEntry(property: nextProperty, concreteType: childScope.builtType)).inserted else { continue }
					steps.append(.scope(childScope, pathDeclarations: pathDeclarations, nestedScopes: nestedScopes, entriesOnWay: entriesOnWay))
				}
			}
		}

		return declarationsMet.map { pathDeclaration, reenteringType in
			// A nested cycle's parameter is bound by a declaration beneath the scope that takes it, so the chain ends.
			var binding = pathDeclaration
			while let scope = binding.parameterOfScope, let next = bindingByNestedParameter[NestedParameter(scope: scope, label: binding.property.label)] {
				binding = next
			}
			return CycleReentry(
				property: binding.property,
				declaringType: binding.declaringType,
				declarationLocation: binding.declarationLocation,
				parameterTakingType: pathDeclaration.parameterOfScope.map { _ in pathDeclaration.declaringType },
				closedOnProperty: closedOnProperty,
				closedOnBuiltType: builtType,
				reenteringType: reenteringType,
			)
		}
	}

	/// One build of a type beneath a level: the levels beneath `parent` that build `builtType` with `declarationList`.
	private struct Scope: Hashable {
		let parent: Int
		let declarationList: Int
		let builtType: TypeDescription
	}

	private struct DeclarationOnWayDown {
		let property: Property
		let declaringType: TypeDescription
		let declarationLocation: Dependency.DeclarationLocation?
		/// For a parameter of a builder function a cycle closes on, the scope whose function takes it.
		let parameterOfScope: Scope?
	}

	private struct NestedScope {
		let scope: Scope
		let entry: StackEntry
		let parameterLabels: [String]
		let firstDeclarationBeneath: Int
	}

	private struct NestedParameter: Hashable {
		let scope: Scope
		let label: String
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
