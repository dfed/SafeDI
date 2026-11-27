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

/// A kind of mock node the node records refuse today (`NodeRecordRefusal`), which the base corpus draws in two places
/// (`GraphFuzzerGenerator.addingMockKindShapes`): inside a lazy cycle in a mocked type's tree, so that its override is read
/// where the cycle builds it again, and named apart at the mock root, so that its override is a field under a second
/// label. Each kind rolls on a stream of its own, so a kind added later redraws no graph of another kind.
enum GraphFuzzerMockKind: String, CaseIterable {
	case lazy
	case renameOrHole
	case onlyIfAvailable
	case erased
	case sendable
	case mockRootBindsOtherThanNodes
	case mockDefaultValuedParameter
	case unavailableOrInlineSeam
	case mockOverrideNotParentField
	case mockActor
	case builderLoop

	/// The stem of the names of the types the kind's draw declares, after the graph's prefix.
	var typeStem: String {
		"MK" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
	}

	/// The stem of the labels of the properties the kind's draw declares.
	var labelStem: String {
		"mk" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
	}

	/// The mask of the kind's own stream, `seed ^ randomSeedMask`.
	var randomSeedMask: UInt64 {
		switch self {
		case .lazy:
			0xF35C32D0112E7C15
		case .renameOrHole:
			0x5105B81B90F0F82A
		case .onlyIfAvailable:
			0xB7CD264513BB743F
		case .erased:
			0x15B6AD8C934DF054
		case .sendable:
			0x7A7E2BF612106C69
		case .mockRootBindsOtherThanNodes:
			0xD827913195DAE87E
		case .mockDefaultValuedParameter:
			0x3EEF1F7B156D6493
		case .unavailableOrInlineSeam:
			0x9CD086A29437E0A8
		case .mockOverrideNotParentField:
			0xE2980CEC17FA5CBD
		case .mockActor:
			0x43418A57968CD8D2
		case .builderLoop:
			0xA1097191165754E7
		}
	}

	/// The feature of a graph that draws the kind's node inside a lazy cycle.
	var insideCycleFeature: GraphFuzzerFeature {
		switch self {
		case .lazy:
			.mockKindLazyInsideCycle
		case .renameOrHole:
			.mockKindRenameOrHoleInsideCycle
		case .onlyIfAvailable:
			.mockKindOnlyIfAvailableInsideCycle
		case .erased:
			.mockKindErasedInsideCycle
		case .sendable:
			.mockKindSendableInsideCycle
		case .mockRootBindsOtherThanNodes:
			.mockKindMockRootBindsOtherThanNodesInsideCycle
		case .mockDefaultValuedParameter:
			.mockKindMockDefaultValuedParameterInsideCycle
		case .unavailableOrInlineSeam:
			.mockKindUnavailableOrInlineSeamInsideCycle
		case .mockOverrideNotParentField:
			.mockKindMockOverrideNotParentFieldInsideCycle
		case .mockActor:
			.mockKindMockActorInsideCycle
		case .builderLoop:
			.mockKindBuilderLoopInsideCycle
		}
	}

	/// The feature of a graph that draws the kind's node, or the value it binds at the mock root, named apart there.
	var underSecondLabelFeature: GraphFuzzerFeature {
		switch self {
		case .lazy:
			.mockKindLazyUnderSecondLabel
		case .renameOrHole:
			.mockKindRenameOrHoleUnderSecondLabel
		case .onlyIfAvailable:
			.mockKindOnlyIfAvailableUnderSecondLabel
		case .erased:
			.mockKindErasedUnderSecondLabel
		case .sendable:
			.mockKindSendableUnderSecondLabel
		case .mockRootBindsOtherThanNodes:
			.mockKindMockRootBindsOtherThanNodesUnderSecondLabel
		case .mockDefaultValuedParameter:
			.mockKindMockDefaultValuedParameterUnderSecondLabel
		case .unavailableOrInlineSeam:
			.mockKindUnavailableOrInlineSeamUnderSecondLabel
		case .mockOverrideNotParentField:
			.mockKindMockOverrideNotParentFieldUnderSecondLabel
		case .mockActor:
			.mockKindMockActorUnderSecondLabel
		case .builderLoop:
			.mockKindBuilderLoopUnderSecondLabel
		}
	}

	/// The kind's features `fixture` draws, read from the names of the types its draw declares: the cycle's `Loop`, and the
	/// `Peer` the mock promotes, whose tree receives the label a second time.
	func features(drawnIn fixture: GraphFuzzerFixture) -> Set<GraphFuzzerFeature> {
		var features = Set<GraphFuzzerFeature>()
		if fixture.swiftFileContent.contains(where: { $0.contains("\(typeStem)Loop: ") }) {
			features.insert(insideCycleFeature)
		}
		if fixture.swiftFileContent.contains(where: { $0.contains("\(typeStem)Peer: ") }) {
			features.insert(underSecondLabelFeature)
		}
		return features
	}
}
