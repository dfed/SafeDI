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
	/// The plan of `rootInfo`'s code. Where a test observes node records (`NodeRecordsObservation`), they are made for the
	/// root, and the tree's root body is compared with theirs at every place; the code is laid out from them where the test
	/// turns `NodeRecordsObservation.laysOutRoots` on, they accept the root's world and the engine lays out every statement,
	/// and from the tree's places otherwise. A run no test observes plans the tree's places alone.
	static func plannedRootCode(of rootInfo: RootScopeInfo) async throws -> GeneratedCode {
		guard let constructionScope = rootInfo.constructionScope, let observer = NodeRecordsObservation.observer else {
			return try await rootInfo.scopeGenerator.generatePlan()
		}
		let root = rootInfo.instantiable.concreteInstantiable.asSource
		let nodeRecords: NodeRecords
		do {
			nodeRecords = try NodeRecords(world: TypeFactsGraph(root: constructionScope, forMockGeneration: false))
		} catch {
			observer(NodeRecordsReport(root: root, refusal: error.rawValue, isLaidOutFromNodeRecords: false, differences: []))
			return try await rootInfo.scopeGenerator.generatePlan()
		}
		let laidOutCode: GeneratedCode? = if NodeRecordsObservation.laysOutRoots {
			try laidOutRootCode(of: rootInfo.instantiable, body: nodeRecords.rootBody)
		} else {
			nil
		}
		// The tree's places are planned beside node records' so that the two are compared, even where the root is laid out
		// from node records.
		let nodeRecordsBody = nodeRecords.rootBody
		let treeCode = try await NodeRecordsObservation.$rootBodyObserver.withValue({ treeBody in
			observer(NodeRecordsReport(
				root: root,
				refusal: laidOutCode == nil && NodeRecordsObservation.laysOutRoots ? NodeRecordRefusal.notLaidOut.rawValue : nil,
				isLaidOutFromNodeRecords: laidOutCode != nil,
				differences: NodeRecordsObservation.differences(between: treeBody, and: nodeRecordsBody),
			))
		}) {
			try await rootInfo.scopeGenerator.generatePlan()
		}
		return laidOutCode ?? treeCode
	}

	/// The extension that declares `instantiable`'s generated initializer, its body laid out from `body`, node records'
	/// root body, or `nil` where the engine cannot lay out every statement of it, or the root has nothing to build.
	private static func laidOutRootCode(of instantiable: Instantiable, body: [GeneratedCode]) throws -> GeneratedCode? {
		// A statement the engine cannot lay out would be copied as its text, which a node records place does not hold.
		guard body.allSatisfy(\.statementsAreLaidOutByTypeKey),
		      let rootInitializer = try ScopeGenerator.rootInitializer(of: instantiable),
		      let statements = TypeKeyBody.statements(ofRootBody: body)
		else { return nil }
		return rootInitializer.spelled(writing: BuilderFunctionGraph(body: statements.map(Statement.verbatim)))
	}
}
