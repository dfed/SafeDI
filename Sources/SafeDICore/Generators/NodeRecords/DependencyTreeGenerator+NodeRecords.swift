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
	/// wherever anything forces the tree.
	/// - Throws: What an initializer's arguments throw, as the tree's construction of the same place throws it.
	static func nodeRecordsLayout(
		of instantiable: Instantiable,
		constructionScope: ConstructionScope,
		readersOfEveryTree: [TreeForcer],
	) throws -> (layout: NodeRecordsLayout?, treeForcers: [TreeForcer]) {
		let world = TypeFactsGraph(root: constructionScope, forMockGeneration: false)
		do {
			let layout = try NodeRecordsLayout(of: instantiable, world: world, nodeRecords: NodeRecords(world: world))
			return (readersOfEveryTree.isEmpty ? layout : nil, readersOfEveryTree)
		} catch let refusal as NodeRecordRefusal {
			return (nil, [.nodeRecordKind(refusal.rawValue)] + readersOfEveryTree)
		}
	}

	/// The plan of `rootInfo`'s code: its node records' layout where nothing forces its tree, and its tree's places
	/// otherwise. Where a test observes node records (`NodeRecordsObservation`), each root's records are compared with its
	/// tree's at every place, and a root laid out from them is compared with the tree built beside them: its code, its
	/// imports, and the checks its records stand in for (`TreeForcer`). A forced root whose world node records accept is
	/// laid out from them where the test turns `NodeRecordsObservation.laysOutRoots` on. A run no test observes builds
	/// no tree beside the records.
	static func plannedRootCode(of rootInfo: RootScopeInfo) async throws -> GeneratedCode {
		let root = rootInfo.instantiable.concreteInstantiable.asSource
		switch rootInfo.built {
		case let .nodeRecords(layout, comparisonTree):
			if let comparisonTree, let observer = NodeRecordsObservation.observer {
				try await observer(comparison(of: layout, with: comparisonTree, of: rootInfo.instantiable))
			}
			return layout.code
		case let .tree(scopeGenerator):
			guard let constructionScope = rootInfo.constructionScope, let observer = NodeRecordsObservation.observer else {
				return try await scopeGenerator.generatePlan()
			}
			let world = TypeFactsGraph(root: constructionScope, forMockGeneration: false)
			let nodeRecords: NodeRecords
			do {
				nodeRecords = try NodeRecords(world: world)
			} catch let refusal as NodeRecordRefusal {
				observer(NodeRecordsReport(root: root, refusal: refusal.rawValue, everyRefusal: NodeRecords.refusals(in: world).map(\.rawValue), isLaidOutFromNodeRecords: false, differences: [], recordCount: 0, treePlaceCount: 0, treeForcers: rootInfo.treeForcers))
				return try await scopeGenerator.generatePlan()
			}
			let laidOutCode: GeneratedCode? = if NodeRecordsObservation.laysOutRoots {
				try laidOutRootCode(of: rootInfo.instantiable, body: nodeRecords.rootBody)
			} else {
				nil
			}
			// The tree's places are planned beside node records' so that the two are compared, even where the root is
			// laid out from node records.
			let (treeCode, comparisons) = try await treeCode(of: scopeGenerator, besideRecordsBody: nodeRecords.rootBody)
			// A root whose tree's body holds nothing is compared nowhere.
			for comparison in comparisons {
				observer(NodeRecordsReport(
					root: root,
					refusal: laidOutCode == nil && NodeRecordsObservation.laysOutRoots ? NodeRecordRefusal.notLaidOut.rawValue : nil,
					everyRefusal: [],
					isLaidOutFromNodeRecords: laidOutCode != nil,
					differences: comparison.differences,
					recordCount: nodeRecords.recordCount,
					treePlaceCount: comparison.treePlaceCount,
					treeForcers: rootInfo.treeForcers,
				))
			}
			return laidOutCode ?? treeCode
		}
	}

	/// The report of a root laid out from `layout`, its node records, beside `tree`, the tree a test builds for it: every
	/// way the records differ from the tree's places, and each fact a check of the tree reads that the records' answer
	/// for it misses (`TreeForcer`).
	private static func comparison(of layout: NodeRecordsLayout, with tree: ScopeGenerator, of instantiable: Instantiable) async throws -> NodeRecordsReport {
		// The work of planning it is no run's, so the tests that count a run's work count none of it.
		let (treeCode, comparisons) = try await GenerationWork.$observer.withValue(nil) {
			try await Self.treeCode(of: tree, besideRecordsBody: layout.rootBody)
		}
		let treeFulfillers = await tree.fulfillersOfTree(buildingMock: false)
		let captures = await tree.nonSendableWrapperCaptures(ofTreeRootedAt: instantiable)
		let factsTheRecordsMiss: [(holds: Bool, difference: String)] = [
			(treeCode.spelled() == layout.code.spelled(), "root: the code laid out from node records differs from the tree’s"),
			(treeFulfillers == layout.fulfillers, "root: node records import other declarations than the tree’s places build"),
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

	/// The plan of `tree`'s code, and, for each time it laid out the root's body, each way that body differs from
	/// `recordsBody`, node records' root body, and how many places it holds (`NodeRecordsObservation.differences(between:and:)`).
	private static func treeCode(of tree: ScopeGenerator, besideRecordsBody recordsBody: [GeneratedCode]) async throws -> (code: GeneratedCode, comparisons: [(differences: [String], treePlaceCount: Int)]) {
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
}
