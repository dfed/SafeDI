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
	/// wherever anything forces the tree, and wherever the switch to node records is off
	/// (`NodeRecordsObservation.buildsNoTreeForAcceptedRoots`), where nothing but `readersOfEveryTree` is named.
	/// - Throws: What an initializer's arguments throw, as the tree's construction of the same place throws it.
	static func nodeRecordsLayout(
		of instantiable: Instantiable,
		constructionScope: ConstructionScope,
		declaredTypeNames: DeclaredTypeNames,
		readersOfEveryTree: [TreeForcer],
	) throws -> (layout: NodeRecordsLayout?, treeForcers: [TreeForcer]) {
		// Until the switch to node records lands, a run makes no records of a root it builds the tree of anyway.
		guard NodeRecordsObservation.buildsNoTreeForAcceptedRoots else { return (nil, readersOfEveryTree) }
		let world = TypeFactsGraph(root: constructionScope, forMockGeneration: false)
		do {
			let layout = try NodeRecordsLayout(of: instantiable, nodeRecords: NodeRecords(world: world, declaredTypeNames: declaredTypeNames))
			return (readersOfEveryTree.isEmpty ? layout : nil, readersOfEveryTree)
		} catch let refusal as NodeRecordRefusal {
			return (nil, [.nodeRecordKind(refusal.rawValue)] + readersOfEveryTree)
		}
	}

	/// The kind node records refuse the world of `rootInfo`, a root of a module with seams, with; empty where they make its
	/// records, or the root is of a module without seams, whose forcers name the kind already.
	static func nodeRecordRefusal(ofSeamWorldRoot rootInfo: RootScopeInfo, declaredTypeNames: DeclaredTypeNames) -> [TreeForcer] {
		guard rootInfo.treeForcers.contains(.seamWorld) else { return [] }
		let world = TypeFactsGraph(root: rootInfo.rootScope, forMockGeneration: false)
		let records = Result { () throws -> NodeRecords in try NodeRecords(world: world, seamTree: rootInfo.seamTree, declaredTypeNames: declaredTypeNames) }
		guard case let .failure(error) = records, let refusal = error as? NodeRecordRefusal else { return [] }
		return [.nodeRecordKind(refusal.rawValue)]
	}

	/// The plan of `rootInfo`'s code: its node records' layout where nothing forces its tree, and its tree's places
	/// otherwise. Where a test observes node records (`NodeRecordsObservation`), each root's records are compared with its
	/// tree's at every place, and a root laid out from them is compared with the tree built beside them: its code, its
	/// imports, and the checks its records stand in for (`TreeForcer`). A forced root whose world node records accept is
	/// laid out from them where the test turns `NodeRecordsObservation.laysOutRoots` on. A run no test observes builds
	/// no tree beside the records, and lays out a seam's own root from its records where they accept its world.
	static func plannedRootCode(of rootInfo: RootScopeInfo, declaredTypeNames: DeclaredTypeNames) async throws -> GeneratedCode {
		let root = rootInfo.instantiable.concreteInstantiable.asSource
		switch rootInfo.built {
		case let .nodeRecords(layout, comparisonTree):
			if let comparisonTree, let observer = NodeRecordsObservation.observer {
				try await observer(comparison(of: layout, with: comparisonTree, of: rootInfo.instantiable))
			}
			return layout.code
		case let .tree(scopeGenerator):
			guard let observer = NodeRecordsObservation.observer else {
				// A seam's own root is laid out from its node records where they accept its world; its tree is still built,
				// for its signature and the checks that read it, but its places are not planned.
				guard let ownSeamRoot = rootInfo.ownSeamRoot,
				      let code = try laidOutOwnSeamRootCode(of: rootInfo, ownSeamRoot: ownSeamRoot, declaredTypeNames: declaredTypeNames)
				else { return try await scopeGenerator.generatePlan() }
				return code
			}
			let seamTree = rootInfo.seamTree
			// The work of making the records is no run's, so the tests that count a run's work count none of it.
			let (world, records) = GenerationWork.$observer.withValue(nil) {
				let world = TypeFactsGraph(root: rootInfo.rootScope, forMockGeneration: false)
				let seamHoles = seamTree.map { SeamHoles(of: $0.seamRoot, seamType: $0.seamType) }
				return (world, Result { () throws -> NodeRecords in try NodeRecords(world: world, seamTree: seamTree, seamHoles: seamHoles, declaredTypeNames: declaredTypeNames) })
			}
			let nodeRecords: NodeRecords
			do {
				nodeRecords = try records.get()
			} catch let refusal as NodeRecordRefusal {
				let everyRefusal = GenerationWork.$observer.withValue(nil) { NodeRecords.refusals(in: world, seamTree: seamTree, declaredTypeNames: declaredTypeNames) }
				let (code, fillLevelDifferences) = try await planComparingFillLevels(in: world, seamTree: seamTree) { try await scopeGenerator.generatePlan() }
				observer(NodeRecordsReport(root: root, refusal: refusal.rawValue, everyRefusal: everyRefusal.map(\.rawValue), isLaidOutFromNodeRecords: false, differences: fillLevelDifferences, recordCount: 0, treePlaceCount: 0, treeForcers: rootInfo.treeForcers))
				return code
			}
			// A seam's own tree's initializers are written around its body.
			let laidOutCode: GeneratedCode? = if !NodeRecordsObservation.laysOutRoots {
				nil
			} else if let ownSeamRoot = rootInfo.ownSeamRoot {
				try laidOutSeamRootCode(of: rootInfo.instantiable, seamRoot: ownSeamRoot, nodeRecords: nodeRecords)
			} else {
				try laidOutRootCode(of: rootInfo.instantiable, body: nodeRecords.rootBody)
			}
			// The tree's places are planned beside node records' so that the two are compared, even where the root is
			// laid out from node records.
			let (planned, fillLevelDifferences): (PlannedTree, [String]) = try await planComparingFillLevels(in: world, seamTree: seamTree) { () async throws -> PlannedTree in
				try await Self.treeCode(of: scopeGenerator, besideRecordsBody: nodeRecords.rootBody)
			}
			let (treeCode, comparisons) = planned
			// A root whose tree's body holds nothing is compared nowhere.
			let codeDifferences = (laidOutCode.map { $0.spelled() == treeCode.spelled() ? [] : ["root: the code laid out from node records differs from the tree’s"] } ?? []) + fillLevelDifferences
			for comparison in comparisons {
				observer(NodeRecordsReport(
					root: root,
					refusal: laidOutCode == nil && NodeRecordsObservation.laysOutRoots ? NodeRecordRefusal.notLaidOut.rawValue : nil,
					everyRefusal: [],
					isLaidOutFromNodeRecords: laidOutCode != nil,
					differences: comparison.differences + codeDifferences,
					recordCount: nodeRecords.recordCount,
					treePlaceCount: comparison.treePlaceCount,
					treeForcers: rootInfo.treeForcers,
				))
			}
			return laidOutCode ?? treeCode
		}
	}

	/// What `plan` returns, planning a tree of `world`, and each way node records' inner scope levels and dispatchers of the
	/// world's filled calls differ from the tree's (`FillLevelsObservation`).
	private static func planComparingFillLevels<Planned: Sendable>(in world: TypeFactsGraph, seamTree: RootScopeInfo.SeamTree?, _ plan: () async throws -> Planned) async throws -> (Planned, [String]) {
		let (stream, continuation) = AsyncStream.makeStream(of: FillLevelsObservation.self)
		// Typed, as `comparison(of:with:of:)` says why.
		let observer: @Sendable (FillLevelsObservation) -> Void = { _ = continuation.yield($0) }
		let planned: Planned = try await FillLevelsObservation.$observer.withValue(observer, operation: { () async throws -> Planned in
			try await plan()
		})
		continuation.finish()
		var observations = [FillLevelsObservation]()
		for await observation in stream {
			observations.append(observation)
		}
		let differences = GenerationWork.$observer.withValue(nil) { FillLevelsObservation.differences(of: observations, in: world, seamTree: seamTree) }
		return (planned, differences)
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
		let factsTheRecordsMiss: [(holds: Bool, difference: String)] = [
			(treeCode.spelled() == layout.code.spelled(), "root: the code laid out from node records differs from the tree’s"),
			(captures.isEmpty, "root: the tree’s @Sendable builder functions capture a wrapper, which node records cannot see"),
			(tree.unpassableCycleLabelsInTree.isEmpty, "root: the tree holds a label no cycle parameter can pass, which node records cannot see"),
		]
		return NodeRecordsReport(
			root: instantiable.concreteInstantiable.asSource,
			refusal: nil,
			everyRefusal: [],
			isLaidOutFromNodeRecords: true,
			differences: comparisons.flatMap(\.differences) + factsTheRecordsMiss.filter { !$0.holds }.map(\.difference),
			recordCount: layout.recordCount,
			treePlaceCount: comparisons.map(\.treePlaceCount).reduce(0, +),
			treeForcers: [],
		)
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

	/// The extension that declares `instantiable`'s generated initializer, its body laid out from `body`, node records'
	/// root body, or `nil` where the engine cannot lay out every statement of it, or the root has nothing to build.
	static func laidOutRootCode(of instantiable: Instantiable, body: [GeneratedCode]) throws -> GeneratedCode? {
		// A statement the engine cannot lay out would be copied as its text, which a node records place does not hold.
		guard body.allSatisfy(\.statementsAreLaidOutByTypeKey),
		      let rootInitializer = try ScopeGenerator.rootInitializer(of: instantiable),
		      let statements = TypeKeyBody.statements(ofRootBody: body)
		else { return nil }
		return rootInitializer.spelled(writing: BuilderFunctionGraph(body: statements.map(Statement.verbatim)))
	}

	/// The code of `rootInfo`, a seam's own root whose tree's root is `ownSeamRoot`, laid out from its world's node records,
	/// or `nil` where they refuse its world or the engine cannot lay every statement out.
	private static func laidOutOwnSeamRootCode(of rootInfo: RootScopeInfo, ownSeamRoot: ScopeGenerator.SeamRoot, declaredTypeNames: DeclaredTypeNames) throws -> GeneratedCode? {
		let world = TypeFactsGraph(root: rootInfo.rootScope, forMockGeneration: false)
		let seamTree = rootInfo.seamTree
		let nodeRecords: NodeRecords
		do {
			nodeRecords = try NodeRecords(world: world, seamTree: seamTree, seamHoles: seamTree.map { SeamHoles(of: $0.seamRoot, seamType: $0.seamType) }, declaredTypeNames: declaredTypeNames)
		} catch is NodeRecordRefusal {
			return nil
		}
		return try laidOutSeamRootCode(of: rootInfo.instantiable, seamRoot: ownSeamRoot, nodeRecords: nodeRecords)
	}

	/// The initializers and guard enum of `instantiable`, a seam this module generates, written around its tree's body laid
	/// out from `nodeRecords`, its own root's records, or `nil` where the engine cannot lay out every statement of it.
	static func laidOutSeamRootCode(of instantiable: Instantiable, seamRoot: ScopeGenerator.SeamRoot, nodeRecords: NodeRecords) throws -> GeneratedCode? {
		// Only a seam’s tree declares its local functions `@inline(never)` (`LocalFunctionInlining`).
		try LocalFunctionInlining.$isNeverInlined.withValue(true) { () throws -> GeneratedCode? in
			let declarations = ScopeGenerator.seamRootBodyDeclarations(of: instantiable, seamRoot: seamRoot)
			guard nodeRecords.rootBody.allSatisfy(\.statementsAreLaidOutByTypeKey),
			      let statements = TypeKeyBody.statements(ofRootBody: nodeRecords.rootBody, outerDeclarations: declarations.outerDeclarations, namesInScope: declarations.namesInScope)
			else { return nil }
			// Node records make no box of a loop's levels: a world with a loop of builders is refused before.
			return try .text(ScopeGenerator.seamRootCode(
				of: instantiable,
				seamRoot: seamRoot,
				narrowestTierStatements: statements,
				unavailableProperties: [],
				typesDeclaredEscaping: nodeRecords.rootTypesDeclaredEscaping,
				loopLevelsTypesInTree: [:],
			))
		}
	}
}
