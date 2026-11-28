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
			// A place that declares only its function makes no call of it.
			bodies[child].record?.bindsProperty == false ? nil : classByBody[child]
		case let .closer(_, target):
			classByBody[target]
		case let .function(_, function):
			// The statement declares the function, which is placed there (`computePlacement`), so it stands to the cycles of
			// calls as a call of it does.
			classByBody[function]
		case .inline, .alias:
			nil
		}
	}

	/// Whether `owner` is the class of functions places written as text declare (`AliasPlaceRecord.function`), each
	/// declared where its statement is, under its own name.
	func isCallingFunctionClass(_ owner: Int) -> Bool {
		owner != 0 && bodies[membersByClass[owner][0]].callingFunction != nil
	}

	/// `site`, or, for a call made in a function a place written as text declares, the statement declaring the function, out
	/// to the first that is no such call: where the call is made in the body that declares the function.
	func declaringSite(of site: CallSite) -> CallSite {
		var site = site
		while isCallingFunctionClass(site.owner) {
			let member = membersByClass[site.owner][0]
			site = CallSite(owner: classByBody[bodies[member].parent], index: bodies[member].position)
		}
		return site
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
		// A function a place written as text declares is placed at its statement, in the body of its first member's: the
		// members of its class spell one function, each at its own statement (`spelledStatement`), and a read its function
		// would take from its callers it cannot take (`callingFunctionsTakeNoParameters`).
		let callingFunctionClasses = (1..<max(classCount, 1)).filter(isCallingFunctionClass)
		for owner in callingFunctionClasses {
			let member = membersByClass[owner][0]
			placementOwner[owner] = classByBody[bodies[member].parent]
			placementIndex[owner] = bodies[member].position
		}
		// Tarjan's algorithm finishes a component after every component it reaches, so callers come last: they are placed
		// first.
		for component in classesByComponent.keys.sorted(by: >) {
			guard let componentClasses = classesByComponent[component]?.sorted() else { continue }
			let memberSet = Set(componentClasses)
			let members = componentClasses.filter { !isCallingFunctionClass($0) }
			guard !members.isEmpty else { continue }
			let allSites = members.flatMap { callSitesByClass[$0] }.filter { !memberSet.contains($0.owner) || !isCallingFunctionClass($0.owner) }
			// A call made in a function a place written as text declares is made, for placement, where that function's
			// statement is.
			let externalSites = Set(allSites.filter { !memberSet.contains($0.owner) }.map(declaringSite(of:)).filter { !memberSet.contains($0.owner) })
			// Every function is declared in the root's body, never nested in another: Swift 6.2's compile time doubles with
			// each level of nested local functions past about twenty. Under `declaresLoopMembersAsThePathKeyDoes` the nesting
			// is the path key's own, which the tree writes too, so the type key adds no depth.
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
		// Each member is spelled at its own statement, in whichever body holds it, so the function is spelled before every
		// class one of its statements is in.
		for owner in callingFunctionClasses {
			placementDepth[owner] = (membersByClass[owner].map { placementDepth[classByBody[bodies[$0].parent]] }.max() ?? 0) + 1
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
	///
	/// A function a place written as text declares stays at that place's statement, while a function that calls it is
	/// declared where `computePlacement()` puts it, so each class whose function reaches one (`classesReachingCallingFunctions()`)
	/// is checked the same way.
	func keepsCapturesOfLoopMembersDeclaredAsThePathKeyDoes() -> Bool {
		(loopMembersDeclaredAsThePathKeyDoes + classesReachingCallingFunctions()).allSatisfy { member in
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

	/// The classes whose functions call a function a place written as text declares, directly or through other functions,
	/// in class order.
	func classesReachingCallingFunctions() -> [Int] {
		var callersByClass = [[Int]](repeating: [], count: membersByClass.count)
		for owner in membersByClass.indices.dropFirst() {
			for callee in calleesByClass[owner] {
				callersByClass[callee].append(owner)
			}
		}
		var reached = Set<Int>()
		var pending = membersByClass.indices.filter(isCallingFunctionClass)
		while let callee = pending.popLast() {
			for caller in callersByClass[callee] where reached.insert(caller).inserted {
				pending.append(caller)
			}
		}
		return reached.sorted()
	}
}
