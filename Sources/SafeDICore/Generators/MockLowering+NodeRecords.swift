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
	/// root `worldRoot` builds, or `nil` where the mock's walk writes them: node records refuse the world, as they refuse
	/// every mock root's where no test turns `NodeRecordsObservation.laysOutMockRoots` on (the mock root's facts are
	/// owed there), the mock binds a value that is no node of it (`bindsOnlyNodes` is false), a node's configuration is
	/// among `sendableConfigurationTypeNames` and holds a field its construction reads, or the engine cannot lay the
	/// records out. Each node reads its override from the overrides its body's function was
	/// handed (`NodeRecords.mockConfigurationField(named:)`), which the root's body reads of `mock()`'s own parameter. The
	/// root is reported to the test that observes node records (`NodeRecordsObservation.observer`), which alone hands a
	/// mock root its world. The world answers its records `rootNames`, the names the root's level binds its nodes apart under.
	/// A node's receive only if available reads `outerDeclarations`, the parameters of `mock()` and the overrides it binds
	/// before its nodes, where no node nearer it declares the label, as the walk passes them.
	///
	/// The function awaits nothing and is kept out of the frame of the mock's walk, which every root's lowering holds.
	/// Anything the records throw refuses the world (`NodeRecords.refusingWhatRecordsThrow(_:)`), whose walk reports it.
	@inline(never)
	static func nodeRecordsMockStatements(of instantiable: Instantiable, worldRoot: ConstructionScope, bindsOnlyNodes: Bool, sendableConfigurationTypeNames: Set<String>, rootNames: MockRootNames, outerDeclarations: [Property], levelNamesTaken: MockLowering.RootLevelNamesTaken, renamesAbove: [String: [TypeDescription: String]], handWrittenMockDefaultParameters: [TypeDescription: [ScopeGenerator.DefaultParameter]]) -> (statements: String, surface: MockLowering.RootSurface)? {
		var world = TypeFactsGraph(root: worldRoot, forMockGeneration: true, mockRootNames: rootNames)
		// The names the root binds apart are the world's: what `mock()`'s signature names apart, with each node of the root's
		// level the level names apart, which the world's edges from the root say.
		world.mockRootNames.namesApart = NodeRecords.mockRootNamesApart(in: world, besideNamesTaken: levelNamesTaken, renamesAbove: renamesAbove)
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
		switch NodeRecords.refusingWhatRecordsThrow({ try NodeRecords(world: world, outerDeclarations: outerDeclarations, declaredTypeNames: nil) }) {
		case let .success(made):
			nodeRecords = made
		case let .failure(refusal):
			report(refusal: refusal, everyRefusal: refusal == .recordsThrew ? [.recordsThrew] : NodeRecords.refusals(in: world, outerDeclarations: outerDeclarations, declaredTypeNames: nil), isLaidOut: false, recordCount: 0)
			return nil
		}
		// A read of a value the mock binds beside its nodes would resolve to no declaration of the records' body.
		guard bindsOnlyNodes else {
			report(refusal: .mockRootBindsOtherThanNodes, everyRefusal: [.mockRootBindsOtherThanNodes], isLaidOut: false, recordCount: 0)
			return nil
		}
		// A configuration of the `Sendable` form stores each field that is no function as a `@Sendable` closure, which a
		// construction calls. Which types take that form is a fact of every mock root of the module together, which a root's
		// world does not hold, so the records read each field as a value and such a root keeps the walk's statements.
		let readsFieldStoredAsClosure = (1..<Int32(world.declarationCount)).contains { declaration in
			sendableConfigurationTypeNames.contains(world.scope(of: declaration).instantiable.concreteInstantiable.asSource)
				&& !NodeRecords.mockConfigurationFieldArguments(of: declaration, in: world).isEmpty
		}
		guard !readsFieldStoredAsClosure else {
			report(refusal: .mockDefaultValuedParameter, everyRefusal: [.mockDefaultValuedParameter], isLaidOut: false, recordCount: 0)
			return nil
		}
		// Where the world's cycles enter places, `mock()` declares what holds them and binds a value with none entered
		// before its nodes, which its body and every function that takes no places hand a function that takes them
		// (`NodeRecords+MockCycle.swift`).
		// Where an actor is sent a value a function handed the places builds, the places take their `Sendable` form, so that
		// the value is built of nothing that cannot be sent. That form holds only configurations of the `Sendable` form,
		// which every type built beneath an actor takes: a function handed the places whose type is built beneath none, as
		// one on another cycle of the mock's is, keeps the walk's statements.
		let placesThatMustBeSendable = nodeRecords.mockConfigurationTypeNamesHandedWithPlacesThatMustBeSendable
		let refusalOfPlaces = placesThatMustBeSendable?.refusal(whereConfigurationsOfSendableFormAre: sendableConfigurationTypeNames)
		guard refusalOfPlaces == nil else {
			report(refusal: refusalOfPlaces, everyRefusal: [refusalOfPlaces].compactMap(\.self), isLaidOut: false, recordCount: 0)
			return nil
		}
		let enteredPlaces: [GeneratedCode] = ((nodeRecords.mockEnteredPlacesUse.map { MockEnteredSlot.mockEnteredPlacesDeclaration(isSendable: placesThatMustBeSendable != nil, entersNearest: $0.entersNearest, passes: $0.passes, leavesOut: $0.leavesOut, slotCount: $0.slotCount) } ?? []) + nodeRecords.mockLoopSendableStructDeclarations)
			.map { .text("\(TypeKeyBody.rootStatementIndentation)\($0)") }
		// What the records say the mock declares of its nodes: its overrides' fields and its configurations.
		let layout = nodeRecords.mockRootSurface(in: world, handWrittenMockDefaultParameters: handWrittenMockDefaultParameters).flatMap { surface in
			TypeKeyBody.statements(ofRootBody: nodeRecords.rootBody, outerDeclarations: outerDeclarations, namesInScope: Set(outerDeclarations.map(\.label)), rootPassedArgumentNames: [ReservedName.mockOverridesParameterName], laysOutEveryLoop: true)
				.map { (statements: GeneratedCode.lines(enteredPlaces + $0).spelled(), surface: surface) }
		}
		report(refusal: layout == nil ? .notLaidOut : nil, everyRefusal: [], isLaidOut: layout != nil, recordCount: nodeRecords.recordCount)
		return layout
	}
}
