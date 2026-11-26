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

extension MockLowering.Walk {
	/// The code of the mock root's body laid out from its per-type plan `plan`, or `nil` and why the root keeps the walk's
	/// body: the root's places are the walk's, each other body is laid out from the walk's record of the first of today's
	/// places that takes it, and each call place calls its body's function, handing it what the place's own record hands
	/// (`TypeKeyBody.statements(ofPlan:outerDeclarations:namesInScope:)`). Reads the records `recordBuiltPlaces()` made.
	/// - Parameter rootDeclarations: The values `mock()` declares before its tree.
	func cyclePlanCode(of plan: MockCyclePlan, declaredAtRoot rootDeclarations: [Property]) -> (code: String?, outcome: String) {
		if let reason = plan.keptPerPathBecause {
			return (nil, reason)
		}
		guard firstUnrecordedPath == nil else { return (nil, "unrecorded") }
		guard pathsCoveredByLoopUnits.isEmpty else { return (nil, "loopOfBuilders") }
		var childPathsByParent = [[Int]: [Int]]()
		for path in placePathsInWalkOrder {
			childPathsByParent[Array(path.dropLast()), default: []].append(path[path.count - 1])
		}
		let rootStatements = childPathsByParent[[], default: []].map { placeCode(at: [$0]) }
		guard let childIndicesByPath = Self.childIndicesByPath(of: rootStatements, childPathsByParent: childPathsByParent) else { return (nil, "unrecorded") }
		var representativePaths = [[Int]]()
		var records = [BuiltPlaceRecord]()
		for paths in plan.todaysPaths.dropFirst() {
			// A body is laid out from a place that builds it in a function of its own, as the plan's body does.
			guard let (path, record) = paths.lazy.compactMap({ path in
				Self.builtRecord(at: path, in: rootStatements, childIndicesByPath: childIndicesByPath).map { (path, $0) }
			}).first(where: { $0.1.hasFunction })
			else { return (nil, "noPlaceTakesBody") }
			representativePaths.append(path)
			records.append(record)
		}
		let written = WrittenMockVariantPlan(
			plan: plan,
			rootStatements: rootStatements,
			records: records,
			representativePaths: representativePaths,
			childIndicesByPath: childIndicesByPath,
		)
		guard let statements = TypeKeyBody.statements(ofPlan: written, outerDeclarations: rootDeclarations) else { return (nil, "engineRefused") }
		var lines = [String]()
		for statement in statements {
			let spelled = statement.spelled()
			guard !spelled.allSatisfy(\.isWhitespace) else { continue }
			lines.append(spelled)
		}
		return (lines.joined(separator: "\n"), "laidOut")
	}

	/// The index of each statement of each place's body among the places `rootStatements` hold, by the place's path: the
	/// walk's index of each child place (`childPathsByParent`), after an index below zero, which no call's path holds, for
	/// each statement the place's builder function begins with (`leadingBodyPlaces`: a receive named apart bound again),
	/// which no path of the walk names. `nil` where a body holds fewer statements than the walk's places.
	private static func childIndicesByPath(of rootStatements: [GeneratedCode], childPathsByParent: [[Int]: [Int]]) -> [[Int]: [Int]]? {
		var childIndicesByPath = [[Int]: [Int]]()
		var pending: [(path: [Int], statements: [GeneratedCode])] = [([], rootStatements)]
		while let (path, statements) = pending.popLast() {
			let childPaths = childPathsByParent[path, default: []]
			guard statements.count >= childPaths.count else { return nil }
			let leadingCount = statements.count - childPaths.count
			let indices = (0..<leadingCount).map { -1 - $0 } + childPaths
			childIndicesByPath[path] = indices
			for (index, statement) in zip(indices, statements) where index >= 0 {
				guard case let .built(built)? = TypeKeyLayout.record(of: statement), !built.children.isEmpty else { continue }
				pending.append((path + [index], TypeKeyLayout.statementCodes(of: built.children)))
			}
		}
		return childIndicesByPath
	}

	/// The record of the built place at `path` among the places `rootStatements` hold, each level's statements in the
	/// order of `childIndicesByPath`; `nil` where the place is no built place, or a level holds statements no path names.
	private static func builtRecord(at path: [Int], in rootStatements: [GeneratedCode], childIndicesByPath: [[Int]: [Int]]) -> BuiltPlaceRecord? {
		var statements = rootStatements
		var record: BuiltPlaceRecord?
		for depth in path.indices {
			let siblings = childIndicesByPath[Array(path.prefix(depth)), default: []]
			guard siblings.count == statements.count,
			      let position = siblings.firstIndex(of: path[depth]),
			      case let .built(built)? = TypeKeyLayout.record(of: statements[position])
			else { return nil }
			record = built
			statements = TypeKeyLayout.statementCodes(of: built.children)
		}
		return record
	}
}

/// A mock root's per-type plan as the type key reads it (`TypeKeyVariantPlan`): the walk's places of the root's own body,
/// and each other body the walk's record of a place that takes it, its children at that place's paths.
private struct WrittenMockVariantPlan: TypeKeyVariantPlan {
	let plan: MockCyclePlan
	let rootStatements: [GeneratedCode]
	/// The record of each called body, at its position less one.
	let records: [BuiltPlaceRecord]
	/// The path of the place each called body is laid out from, at its position less one.
	let representativePaths: [[Int]]
	/// The indices of the children of each place the walk recorded, by the place's path from the mock's root.
	let childIndicesByPath: [[Int]: [Int]]

	var bodyCount: Int {
		plan.calls.count
	}

	func record(ofBody body: Int) -> BuiltPlaceRecord? {
		records[body - 1]
	}

	func childIndices(ofPlaceAt path: [Int], inBody body: Int) -> [Int] {
		let base = body == 0 ? [] : representativePaths[body - 1]
		return childIndicesByPath[base + path, default: []]
	}

	func calls(of body: Int) -> [VariantCall] {
		plan.calls[body]
	}

	func labels(of body: Int) -> [String] {
		plan.labels[body]
	}

	func answers(of body: Int) -> [Answer] {
		plan.answers[body]
	}

	func isInSendableFamily(_ body: Int) -> Bool {
		plan.isSendable[body]
	}
}
