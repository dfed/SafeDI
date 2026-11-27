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

extension ScopeGenerator {
	/// The statements that build the nodes of `instantiable`'s mock, laid out from the node records of its world, the
	/// root `worldRoot` builds, or `nil` where the mock's walk writes them: node records refuse the world, the mock binds a
	/// value that is no node of it (`bindsOnlyNodes` is false), or the engine cannot lay the records out. Where no test turns
	/// `NodeRecordsObservation.laysOutMockRoots` on, the records owe the mock root's facts, so node records refuse every
	/// mock world (`NodeRecords.owesFacts(_:in:)`). Each node reads its override from the overrides its body's function was
	/// handed (`NodeRecords.mockConfigurationField(named:)`), which the root's body reads of `mock()`'s own parameter. The
	/// root is reported to the test that observes node records (`NodeRecordsObservation.observer`), which alone hands a
	/// mock root its world.
	///
	/// The function awaits nothing and is kept out of the frame of the mock's walk, which every root's lowering holds.
	/// Anything the records throw refuses the world (`NodeRecords.refusingWhatRecordsThrow(_:)`), whose walk reports it.
	@inline(never)
	static func nodeRecordsMockStatements(of instantiable: Instantiable, worldRoot: ConstructionScope, bindsOnlyNodes: Bool) -> String? {
		let world = TypeFactsGraph(root: worldRoot, forMockGeneration: true)
		func report(refusal: NodeRecordRefusal?, everyRefusal: [NodeRecordRefusal], isLaidOut: Bool, recordCount: Int) {
			var report = NodeRecordsReport(
				root: instantiable.concreteInstantiable.asSource,
				refusal: refusal?.rawValue,
				everyRefusal: everyRefusal.map(\.rawValue),
				isLaidOutFromNodeRecords: isLaidOut,
				differences: [],
				recordCount: recordCount,
				treePlaceCount: 0,
				treeForcers: [],
			)
			report.isMockRoot = true
			NodeRecordsObservation.observer?(report)
		}
		let nodeRecords: NodeRecords
		// No kind claims an erased instantiator in a mock root's world, so its first generic argument is the mock's tree's to
		// check.
		switch NodeRecords.refusingWhatRecordsThrow({ try NodeRecords(world: world, declaredTypeNames: nil) }) {
		case let .success(made):
			nodeRecords = made
		case let .failure(refusal):
			report(refusal: refusal, everyRefusal: refusal == .recordsThrew ? [.recordsThrew] : NodeRecords.refusals(in: world, declaredTypeNames: nil), isLaidOut: false, recordCount: 0)
			return nil
		}
		// A read of a value the mock binds beside its nodes would resolve to no declaration of the records' body.
		guard bindsOnlyNodes else {
			report(refusal: .mockRootBindsOtherThanNodes, everyRefusal: [.mockRootBindsOtherThanNodes], isLaidOut: false, recordCount: 0)
			return nil
		}
		let statements = TypeKeyBody.statements(ofRootBody: nodeRecords.rootBody, rootPassedArgumentNames: [ReservedName.mockOverridesParameterName])
		report(refusal: statements == nil ? .notLaidOut : nil, everyRefusal: [], isLaidOut: statements != nil, recordCount: nodeRecords.recordCount)
		return statements.map { GeneratedCode.lines($0).spelled() }
	}
}
