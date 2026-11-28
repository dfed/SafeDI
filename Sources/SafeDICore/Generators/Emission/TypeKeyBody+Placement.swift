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
			// Every function is declared in the root's body, never nested in another, but under
			// `declaresLoopMembersAsThePathKeyDoes`: Swift 6.2's compile time doubles with each level of nested local functions
			// past about twenty. Under the flag the nesting is the path key's own, a cycle's functions included, which the tree
			// writes too, so the type key adds no depth.
			guard let firstSite = externalSites.first else { return false }
			// Where the path key writes each loop once, it declares each function in the body that calls it, a loop's
			// functions in the body that builds the loop. A component the path key writes once per calling body, which the
			// type key keys as one view, has no one body to be declared in, so the root keeps the path key's body.
			let isNested = declaresLoopMembersAsThePathKeyDoes
			guard !isNested || externalSites.allSatisfy({ $0.owner == firstSite.owner }) else { return false }
			let owner = isNested ? firstSite.owner : 0
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
			// A loop of builders whose members the root's statements each build once, and nothing else reaches, declares each
			// member's function right before the statement that builds it, as the path key does: a member's function may call
			// a later one's, which `keepsCapturesOfLoopMembersDeclaredAsThePathKeyDoes()` checks once captures are known.
			let sitesByMember = members.map { member in callSitesByClass[member].filter { !memberSet.contains($0.owner) } }
			if isNested, members.count > 1, sitesByMember.allSatisfy({ $0.count == 1 && $0.first?.owner == owner }) {
				for (member, sites) in zip(members, sitesByMember) {
					for site in sites {
						placementIndex[member] = site.index
						attachedFunction[site] = member
					}
				}
				loopMembersDeclaredAsThePathKeyDoes.append(contentsOf: members)
			} else if isNested, members.count > 1 {
				// The path key declares each function of a cycle in the body of the place that builds it, nested as deep as
				// that place, and a call that closes the cycle names one of them: only the function a body outside the
				// component calls is declared there. A component it would write otherwise keeps the path key's body.
				guard let nesting = nestingAsThePathKeyDoes(members, memberSet: memberSet) else { return false }
				hoistedFunctions[CallSite(owner: owner, index: index), default: []].append(nesting.entry)
				for (member, site) in nesting.nested {
					placementOwner[member] = site.owner
					placementIndex[member] = site.index
					placementDepth[member] = placementDepth[site.owner] + 1
					attachedFunction[site] = member
				}
				// A member declared before its statement can be called by a closing call before a value its function captures
				// is bound, which `keepsCapturesOfLoopMembersDeclaredAsThePathKeyDoes()` checks as for a loop's members.
				loopMembersDeclaredAsThePathKeyDoes.append(contentsOf: nesting.nested.map(\.member))
			} else if isAttached {
				attachedFunction[CallSite(owner: owner, index: index)] = members[0]
			} else {
				hoistedFunctions[CallSite(owner: owner, index: index), default: []].append(contentsOf: members)
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

	/// The member of `members`, a component of the calls between classes, that a body outside it calls, and each other
	/// member with the statement of a member's body that builds it, entry first and each member after the one whose body
	/// builds it: or `nil` where the component has several entries, a member that no one statement of the component
	/// builds, which the path key would write in several places, or a closing call inside it whose target the nesting
	/// declares in a body that does not enclose the call, where Swift would not find the name. A closing call names a
	/// function and builds nothing. The members' bodies are read from the places' nesting, so the bodies that build them
	/// form a tree under the entry, and a walk of it reaches every member.
	func nestingAsThePathKeyDoes(_ members: [Int], memberSet: Set<Int>) -> (entry: Int, nested: [(member: Int, site: CallSite)])? {
		let entries = members.filter { callSitesByClass[$0].contains { !memberSet.contains($0.owner) } }
		var builtByOwner = [Int: [(member: Int, site: CallSite)]]()
		var isBuiltOnce = true
		for member in members where !entries.contains(member) {
			let buildingSites = callSitesByClass[member].filter { site in
				guard memberSet.contains(site.owner), case .built = statements(ofClass: site.owner)[site.index] else { return false }
				return true
			}
			isBuiltOnce = isBuiltOnce && buildingSites.count == 1
			if let site = buildingSites.first {
				builtByOwner[site.owner, default: []].append((member, site))
			}
		}
		guard entries.count == 1, let entry = entries.first, isBuiltOnce else { return nil }
		// Each member's place in a depth-first walk of the nesting from the entry, and the number of members nested in it,
		// itself included, so a body encloses another exactly where the other's place falls in its span.
		var nested = [(member: Int, site: CallSite)]()
		var walkIndex = [Int: Int]()
		var walkOrder = [Int]()
		var declaringOwner = [Int: Int]()
		var pending = [(member: entry, owner: -1)]
		while let (member, owner) = pending.popLast() {
			walkIndex[member] = walkOrder.count
			walkOrder.append(member)
			declaringOwner[member] = owner
			for built in (builtByOwner[member] ?? []).reversed() {
				nested.append(built)
				pending.append((built.member, member))
			}
		}
		var span = [Int](repeating: 1, count: walkOrder.count)
		for (position, member) in walkOrder.enumerated().reversed() {
			if let owner = declaringOwner[member], let ownerIndex = walkIndex[owner] {
				span[ownerIndex] += span[position]
			}
		}
		var enclosed = [Int: Range<Int>]()
		for (position, member) in walkOrder.enumerated() {
			enclosed[member] = position..<(position + span[position])
		}
		// The entry is declared outside the component, around every member; any other member is declared in the body that
		// builds it, which must enclose each closing call of it.
		let everyCloserSeesItsTarget = members.allSatisfy { caller in
			statements(ofClass: caller).allSatisfy { statement in
				guard case let .closer(_, target) = statement, memberSet.contains(classByBody[target]), classByBody[target] != entry else { return true }
				return declaringOwner[classByBody[target]].flatMap { enclosed[$0] }?.contains(walkIndex[caller] ?? -1) ?? false
			}
		}
		guard everyCloserSeesItsTarget else { return nil }
		return (entry, nested)
	}
}

extension TypeKeyLayout {
	/// Whether each loop member declared right before the statement that builds it (`declaresLoopMembersAsThePathKeyDoes`)
	/// reaches, through every function it calls, only captures the body declaring it binds before that statement. Its statement uses
	/// its function, and Swift rejects the use of a function before a value any function it calls captures ("closure
	/// captures 'x' before it is declared"): a member declared before a later member's statement calls that member's
	/// function, which captures what the root binds before its own statement. Read after `computeOutcomes()`, which
	/// settles what each function captures from where `computePlacement()` declares it, so placement cannot check it.
	func keepsCapturesOfLoopMembersDeclaredAsThePathKeyDoes() -> Bool {
		loopMembersDeclaredAsThePathKeyDoes.allSatisfy { member in
			let declaringOwner = placementOwner[member]
			let use = placementIndex[member]
			var reached: Set = [member]
			var pending = [member]
			var capturesOnlyWhatIsBoundBefore = true
			while capturesOnlyWhatIsBoundBefore, let owner = pending.popLast() {
				capturesOnlyWhatIsBoundBefore = !outcomes[owner].values.contains { outcome in
					guard case let .captured(.statement(capturedOwner, index)) = outcome else { return false }
					return capturedOwner == declaringOwner && index >= use
				}
				for callee in calleesByClass[owner] where reached.insert(callee).inserted {
					pending.append(callee)
				}
			}
			return capturesOnlyWhatIsBoundBefore
		}
	}
}
