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

extension DependencyTreeGenerator {
	/// The layout of `instantiable`'s code from the node records of its world, the root `constructionScope` builds, and
	/// what forces its tree (`TreeForcer`): the kind node records refused, then `readersOfEveryTree`. The layout is `nil`
	/// wherever anything forces the tree, and for a world that holds a cycle, whose records are only compared.
	/// Anything the records throw refuses the world (`NodeRecords.refusingWhatRecordsThrow(_:)`), whose tree reports it.
	static func nodeRecordsLayout(
		of instantiable: Instantiable,
		constructionScope: ConstructionScope,
		declaredTypeNames: DeclaredTypeNames,
		readersOfEveryTree: [TreeForcer],
	) -> (layout: NodeRecordsLayout?, treeForcers: [TreeForcer]) {
		// A root every tree's reader forces is built from its tree, so only a test that observes node records makes its
		// world, to name what they refuse.
		guard readersOfEveryTree.isEmpty || NodeRecordsObservation.observer != nil else { return (nil, readersOfEveryTree) }
		let world = TypeFactsGraph(root: constructionScope, forMockGeneration: false)
		switch NodeRecords.refusingWhatRecordsThrow({ () throws -> NodeRecordsLayout? in
			let nodeRecords = try NodeRecords(world: world, declaredTypeNames: declaredTypeNames)
			// A world that holds a cycle keeps its tree, or its plan by type, until node records write every production
			// cycle root as today's tree does: its records are made and compared beside the tree where a test observes
			// them (`plannedRootCode(of:declaredTypeNames:)`), and what forces the tree is named as the kind they refused
			// before they made any cycle's records.
			guard !(0..<Int32(world.declarationCount)).contains(where: world.isOnCycle) else { return nil }
			return try NodeRecordsLayout(of: instantiable, nodeRecords: nodeRecords)
		}) {
		case let .success(layout):
			guard let layout else { return (nil, [.nodeRecordKind(NodeRecordRefusal.cycle.rawValue)] + readersOfEveryTree) }
			return (readersOfEveryTree.isEmpty ? layout : nil, readersOfEveryTree)
		case let .failure(refusal):
			return (nil, [.nodeRecordKind(refusal.rawValue)] + readersOfEveryTree)
		}
	}

	/// The kind node records refuse the world of `rootInfo`, a root of a module with seams, with; empty where they make its
	/// records, or the root is of a module without seams, whose forcers name the kind already.
	static func nodeRecordRefusal(ofSeamWorldRoot rootInfo: RootScopeInfo, declaredTypeNames: DeclaredTypeNames) -> [TreeForcer] {
		guard rootInfo.treeForcers.contains(.seamWorld), let rootScope = rootInfo.rootScope else { return [] }
		let world = TypeFactsGraph(root: rootScope, forMockGeneration: false)
		guard case let .failure(refusal) = NodeRecords.refusingWhatRecordsThrow({ try NodeRecords(world: world, seamTree: rootInfo.seamTree, declaredTypeNames: declaredTypeNames) }) else { return [] }
		return [.nodeRecordKind(refusal.rawValue)]
	}

	/// The plan of `rootInfo`'s code: its node records' layout where nothing forces its tree, and its tree's places
	/// otherwise. Where a test observes node records (`NodeRecordsObservation`), each root's records are compared with its
	/// tree's at every place, and a root laid out from them is compared with the tree built beside them: its code, its
	/// imports, and the checks its records stand in for (`TreeForcer`). A forced root whose world node records accept is
	/// laid out from them where `NodeRecordsObservation.laysOutRoots` is on, whether or not a test observes them. A run no
	/// test observes builds no tree beside the records.
	static func plannedRootCode(of rootInfo: RootScopeInfo, declaredTypeNames: DeclaredTypeNames) async throws -> GeneratedCode {
		let root = rootInfo.instantiable.concreteInstantiable.asSource
		switch rootInfo.built {
		case let .perType(code, _):
			// A root laid out from the per-type plan of its cycles, which node records refuse (`cycle`).
			return code
		case let .nodeRecords(layout, comparisonTree):
			if let comparisonTree, let observer = NodeRecordsObservation.observer {
				try await observer(comparison(of: layout, with: comparisonTree, of: rootInfo.instantiable))
			}
			return layout.code
		case let .tree(scopeGenerator):
			guard let rootScope = rootInfo.rootScope, NodeRecordsObservation.observer != nil || NodeRecordsObservation.laysOutRoots else {
				return try await scopeGenerator.generatePlan()
			}
			let seamTree = rootInfo.seamTree
			// A run with `laysOutRoots` on and no observer lays the root out as an observed run does, and plans its tree only
			// where the records refuse its world or the engine cannot lay it out: the observer records, and chooses nothing.
			guard let observer = NodeRecordsObservation.observer else {
				// A seam's own root is never laid out here, so its records are not made.
				guard rootInfo.ownSeamRoot == nil else { return try await scopeGenerator.generatePlan() }
				let records = NodeRecords.refusingWhatRecordsThrow { try NodeRecords(world: TypeFactsGraph(root: rootScope, forMockGeneration: false), seamTree: seamTree, seamHoles: seamTree.map { $0.makeSeamHoles() }, declaredTypeNames: declaredTypeNames) }
				guard case let .success(nodeRecords) = records, let code = laidOutCode(of: rootInfo, nodeRecords: nodeRecords) else {
					return try await scopeGenerator.generatePlan()
				}
				return code
			}
			// The work of making the records is no run's, so the tests that count a run's work count none of it.
			let (world, records) = GenerationWork.$observer.withValue(nil) {
				let world = TypeFactsGraph(root: rootScope, forMockGeneration: false)
				let seamHoles = seamTree.map { $0.makeSeamHoles() }
				return (world, NodeRecords.refusingWhatRecordsThrow { try NodeRecords(world: world, seamTree: seamTree, seamHoles: seamHoles, declaredTypeNames: declaredTypeNames) })
			}
			let nodeRecords: NodeRecords
			switch records {
			case let .success(made):
				nodeRecords = made
			case let .failure(refusal):
				let everyRefusal = GenerationWork.$observer.withValue(nil) { NodeRecords.refusals(in: world, seamTree: seamTree, declaredTypeNames: declaredTypeNames) }
				observer(NodeRecordsReport(root: root, refusal: refusal.rawValue, everyRefusal: everyRefusal.map(\.rawValue), isLaidOutFromNodeRecords: false, differences: [], recordCount: 0, treePlaceCount: 0, treeForcers: rootInfo.treeForcers))
				return try await scopeGenerator.generatePlan()
			}
			// A seam's own tree is compared and never laid out here: its initializers are written around its body. A root its
			// records cannot lay out keeps its tree's code.
			let laidOutCode: GeneratedCode? = if NodeRecordsObservation.laysOutRoots {
				Self.laidOutCode(of: rootInfo, nodeRecords: nodeRecords)
			} else {
				nil
			}
			// The tree's places are planned beside node records' so that the two are compared, even where the root is
			// laid out from node records. There the laid-out code is the run's, so the tests that count a run's work count
			// none of the tree's planning; the operation is typed for the reason `comparison(of:with:of:)` gives.
			let observerOfTreeWork = laidOutCode == nil ? GenerationWork.observer : nil
			let planned: PlannedTree = try await GenerationWork.$observer.withValue(observerOfTreeWork, operation: { () async throws -> PlannedTree in
				try await Self.treeCode(of: scopeGenerator, besideRecordsBody: nodeRecords.rootBody)
			})
			let (treeCode, comparisons) = planned
			// A root that keeps its tree's code is still laid out from its records where they differ from the tree's by an
			// optional parameter's argument, for the comparison alone: a test approves that difference only where the two
			// texts are equal. A seam's own tree is never laid out here, so the difference fails there.
			let holdsDifferenceOfOptionalParameter = comparisons.contains { comparison in
				// safedi-source-rule: allow stringScan — only where a test observes node records, once for each difference of a root that keeps its tree.
				comparison.differences.contains { $0.contains(": \(NodeRecordsReport.argumentsOfOptionalParameterDifferenceName) is ") }
			}
			let comparedCode: GeneratedCode? = if laidOutCode == nil, holdsDifferenceOfOptionalParameter, rootInfo.ownSeamRoot == nil,
			                                      case let .success(code) = NodeRecords.refusingWhatRecordsThrow({ try laidOutRootCode(of: rootInfo.instantiable, body: nodeRecords.rootBody) })
			{
				code
			} else {
				laidOutCode
			}
			// A root the engine cannot lay out even for the comparison shows no text to approve that difference against, so
			// where its records differ from the tree's in no other way its world is reported as one function cannot serve
			// (`onlyIfAvailableAnsweredApart`), and it keeps its tree's code.
			if comparedCode == nil, holdsDifferenceOfOptionalParameter, rootInfo.ownSeamRoot == nil,
			   // safedi-source-rule: allow stringScan — only where a test observes node records, once for each difference of a root that keeps its tree.
			   comparisons.allSatisfy({ $0.differences.allSatisfy { $0.contains(": \(NodeRecordsReport.argumentsOfOptionalParameterDifferenceName) is ") } })
			{
				let refusal = NodeRecordRefusal.onlyIfAvailableAnsweredApart.rawValue
				observer(NodeRecordsReport(root: root, refusal: refusal, everyRefusal: [refusal], isLaidOutFromNodeRecords: false, differences: [], recordCount: 0, treePlaceCount: 0, treeForcers: rootInfo.treeForcers))
				return treeCode
			}
			// A root whose tree's body holds nothing is compared nowhere.
			for comparison in comparisons {
				var report = NodeRecordsReport(
					root: root,
					refusal: laidOutCode == nil && NodeRecordsObservation.laysOutRoots ? (rootInfo.ownSeamRoot == nil ? NodeRecordRefusal.notLaidOut : .ownSeamRoot).rawValue : nil,
					everyRefusal: [],
					isLaidOutFromNodeRecords: laidOutCode != nil,
					differences: comparison.differences,
					recordCount: nodeRecords.recordCount,
					treePlaceCount: comparison.treePlaceCount,
					treeForcers: rootInfo.treeForcers,
				)
				report.comparedTexts = comparedCode.map { NodeRecordsComparedTexts(tree: treeCode.spelled(), nodeRecords: $0.spelled()) }
				observer(report)
			}
			return laidOutCode ?? treeCode
		}
	}

	/// The report of a root laid out from `layout`, its node records, beside `tree`, the tree a test builds for it: every
	/// way the records differ from the tree's places, and each fact a check of the tree reads that the records' answer
	/// for it misses (`TreeForcer`).
	private static func comparison(of layout: NodeRecordsLayout, with tree: ScopeGenerator, of instantiable: Instantiable) async throws -> NodeRecordsReport {
		// The work of planning it is no run's, so the tests that count a run's work count none of it. Swift 6.4 (Xcode 27.2)
		// reports "ambiguous use of 'withValue'" between `TaskLocal.withValue`'s two async overloads, one of them
		// `nonisolated(nonsending)`, where the operation's type is inferred, so the operation and its result are typed.
		let planned: PlannedTree = try await GenerationWork.$observer.withValue(nil, operation: { () async throws -> PlannedTree in
			try await Self.treeCode(of: tree, besideRecordsBody: layout.rootBody)
		})
		let (treeCode, comparisons) = planned
		let captures = await tree.nonSendableWrapperCaptures(ofTreeRootedAt: instantiable)
		let texts = NodeRecordsComparedTexts(tree: treeCode.spelled(), nodeRecords: layout.code.spelled())
		// The texts' difference comes first, and what no text shows after it, which a test that accepts an approved
		// difference of the texts still reports (`NodeRecordsReport.differencesNoTextShows`).
		let factsTheRecordsMiss: [(holds: Bool, difference: String)] = [
			(texts.tree == texts.nodeRecords, "root: the code laid out from node records differs from the tree’s"),
			(captures.isEmpty, "root: the tree’s @Sendable builder functions capture a wrapper, which node records cannot see"),
			(tree.unpassableCycleLabelsInTree.isEmpty, "root: the tree holds a label no cycle parameter can pass, which node records cannot see"),
		]
		var report = NodeRecordsReport(
			root: instantiable.concreteInstantiable.asSource,
			refusal: nil,
			everyRefusal: [],
			isLaidOutFromNodeRecords: true,
			differences: comparisons.flatMap(\.differences) + factsTheRecordsMiss.filter { !$0.holds }.map(\.difference),
			recordCount: layout.recordCount,
			treePlaceCount: comparisons.map(\.treePlaceCount).reduce(0, +),
			treeForcers: [],
		)
		report.comparedTexts = texts
		report.differencesNoTextShows = factsTheRecordsMiss.dropFirst().filter { !$0.holds }.map(\.difference)
		return report
	}

	/// A tree's planned code, and each comparison of its root body with node records' (`treeCode(of:besideRecordsBody:)`).
	private typealias PlannedTree = (code: GeneratedCode, comparisons: [(differences: [String], treePlaceCount: Int)])

	/// The plan of `tree`'s code, and, for each time it laid out the root's body, each way that body differs from
	/// `recordsBody`, node records' root body, and how many places it holds (`NodeRecordsObservation.differences(between:and:)`).
	private static func treeCode(of tree: ScopeGenerator, besideRecordsBody recordsBody: [GeneratedCode]) async throws -> PlannedTree {
		let (stream, continuation) = AsyncStream.makeStream(of: (differences: [String], treePlaceCount: Int).self)
		let code = try await NodeRecordsObservation.$rootBodyObserver.withValue({ treeBody in
			continuation.yield(NodeRecordsObservation.differences(between: treeBody, and: recordsBody))
		}) {
			try await tree.generatePlan()
		}
		continuation.finish()
		var comparisons = [(differences: [String], treePlaceCount: Int)]()
		for await comparison in stream {
			comparisons.append(comparison)
		}
		return (code, comparisons)
	}

	/// The code of `rootInfo` laid out from `nodeRecords`, its world's records, where `NodeRecordsObservation.laysOutRoots`
	/// is on, or `nil` for a seam's own root, whose initializers are written around its tree's body, and where the engine
	/// cannot lay every statement out. Read alike whether or not a test observes node records.
	private static func laidOutCode(of rootInfo: RootScopeInfo, nodeRecords: NodeRecords) -> GeneratedCode? {
		guard rootInfo.ownSeamRoot == nil,
		      case let .success(code) = NodeRecords.refusingWhatRecordsThrow({ try laidOutRootCode(of: rootInfo.instantiable, body: nodeRecords.rootBody) })
		else { return nil }
		return code
	}

	/// The extension that declares `instantiable`'s generated initializer, its body laid out from `body`, node records'
	/// root body; empty for a root with nothing to build, for which the tree generates nothing too; `nil` where the engine
	/// cannot lay out every statement of the body.
	static func laidOutRootCode(of instantiable: Instantiable, body: [GeneratedCode]) throws -> GeneratedCode? {
		guard let rootInitializer = try ScopeGenerator.rootInitializer(of: instantiable) else { return .empty }
		// A statement the engine cannot lay out would be copied as its text, which a node records place does not hold, so
		// every loop of builders is laid out, as a mock's are, where the tree keeps the path key's body for one written once.
		guard body.allSatisfy(\.statementsAreLaidOutByTypeKey),
		      let statements = TypeKeyBody.statements(ofRootBody: body, laysOutEveryLoop: true, declaresLoopMembersAsThePathKeyDoes: true)
		else { return nil }
		return rootInitializer.spelled(writing: BuilderFunctionGraph(body: statements.map(Statement.verbatim)))
	}
}
