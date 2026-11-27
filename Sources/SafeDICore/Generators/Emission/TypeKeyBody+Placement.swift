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
			// Every function is declared in the root's body, never nested in another: Swift 6.2's compile time doubles with
			// each level of nested local functions past about twenty.
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
			while let owner = pending.popLast() {
				for case let .captured(.statement(capturedOwner, index)) in outcomes[owner].values where capturedOwner == declaringOwner && index >= use {
					return false
				}
				for callee in calleesByClass[owner] where reached.insert(callee).inserted {
					pending.append(callee)
				}
			}
			return true
		}
	}
}
