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

import Foundation
import Testing
@testable import SafeDICore
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The properties of a mock root's tree a path can close on (`NodeRecords.mockEnteredSlots(in:)`): the members of the
/// entered places the slot form of a mock's cycle declares, read from the facts of the mock's own world.
struct SafeDIToolMockEnteredSlotsTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mockEnteredSlots_holdsEachPropertyOfTheCycleOnce_whenRingOfInstantiatorsHasAMemberOffIt() async throws {
		let graph = try await mockWorld(of: [
			Self.type(named: "Root", isMockRoot: true, declarations: ["@Instantiated let ringBuilder: Instantiator<Ring>", "@Instantiated let leaf: Leaf"]),
			Self.type(named: "Ring", declarations: ["@Instantiated let leaf: Leaf", "@Instantiated let ballBuilder: Instantiator<Ball>"]),
			Self.type(named: "Ball", declarations: ["@Instantiated let ringBuilder: Instantiator<Ring>"]),
			Self.type(named: "Leaf", declarations: []),
		])

		#expect(NodeRecords.mockEnteredSlots(in: graph) == [
			MockEnteredSlot(name: "ringBuilder", configurationType: .simple(name: "Ring"), nearestOfTypeSlotName: nil),
			MockEnteredSlot(name: "ballBuilder", configurationType: .simple(name: "Ball"), nearestOfTypeSlotName: nil),
		])
		let ring = try declaration(described: "Ring ", in: graph)
		let ball = try declaration(described: "Ball ", in: graph)
		let leaves = (0..<Int32(graph.declarationCount)).filter { graph.description(ofNode: Int($0)).hasPrefix("Leaf ") }
		#expect(NodeRecords.mockEnteredSlot(of: ring, in: graph)?.name == "ringBuilder")
		#expect(NodeRecords.mockEnteredSlot(of: ball, in: graph)?.name == "ballBuilder")
		#expect(NodeRecords.takesMockEnteredPlaces(ring, in: graph))
		#expect(NodeRecords.takesMockEnteredPlaces(ball, in: graph))
		// Neither the root nor a leaf, under the root or on the cycle's member, is entered or hands the places on.
		#expect(!leaves.isEmpty)
		for declaration in [0] + leaves {
			#expect(NodeRecords.mockEnteredSlot(of: declaration, in: graph) == nil)
			#expect(!NodeRecords.takesMockEnteredPlaces(declaration, in: graph))
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mockEnteredSlots_givesValueTwinTheSlotOfItsLazyTwin_whenOnlyTheLazyTwinIsOnTheCycle() async throws {
		let graph = try await mockWorld(of: [
			Self.type(named: "Root", isMockRoot: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let aBuilder: Instantiator<A>"]),
			Self.type(named: "A", declarations: ["@Instantiated let midBuilder: Instantiator<Mid>"]),
			Self.type(named: "Mid", declarations: ["@Instantiated let theme: LazilyInstantiated<Theme>"]),
			Self.type(named: "Theme", declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
		])

		let themes = (0..<Int32(graph.declarationCount)).filter { graph.description(ofNode: Int($0)).hasPrefix("Theme ") }
		try #require(themes.count == 2, "\(graph.description)")
		// The value is reached first, and is on no cycle; its twin is.
		#expect(!NodeRecords.takesMockEnteredPlaces(themes[0], in: graph))
		#expect(NodeRecords.takesMockEnteredPlaces(themes[1], in: graph))
		#expect(NodeRecords.mockEnteredSlots(in: graph).map(\.name) == ["theme", "aBuilder", "midBuilder"])
		#expect(NodeRecords.mockEnteredSlot(of: themes[0], in: graph) == NodeRecords.mockEnteredSlot(of: themes[1], in: graph))
		#expect(NodeRecords.mockEnteredSlot(of: themes[0], in: graph)?.name == "theme")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mockEnteredSlots_namesTheNearestOfOneTypeOnce_whenTypeIsReachedUnderTwoPropertiesOnTheCycle() async throws {
		let graph = try await mockWorld(of: [
			Self.type(named: "Root", isMockRoot: true, declarations: ["@Instantiated let homeBuilder: Instantiator<Home>"]),
			Self.type(named: "Home", declarations: ["@Instantiated let roomBuilder: Instantiator<Room>"]),
			Self.type(named: "Room", declarations: ["@Instantiated let homeBuilder: Instantiator<Home>", "@Instantiated let otherHomeBuilder: Instantiator<Home>"]),
		])

		let slots = NodeRecords.mockEnteredSlots(in: graph)
		#expect(slots.map(\.name) == ["homeBuilder", "roomBuilder", "otherHomeBuilder"])
		#expect(slots.map(\.nearestOfTypeSlotName) == ["__safeDI_nearest0", nil, "__safeDI_nearest0"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mockEnteredSlots_namesSecondSlotOfOneLabelApart_whenTwoCyclesCloseOnOneLabelOfTwoTypes() async throws {
		let graph = try await mockWorld(of: [
			Self.type(named: "Root", isMockRoot: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			Self.type(named: "First", declarations: ["@Instantiated let homeBuilder: Instantiator<Home>"]),
			Self.type(named: "Second", declarations: ["@Instantiated let homeBuilder: Instantiator<Den>"]),
			Self.type(named: "Home", declarations: ["@Instantiated let roomBuilder: Instantiator<Room>"]),
			Self.type(named: "Room", declarations: ["@Instantiated let homeBuilder: Instantiator<Home>"]),
			Self.type(named: "Den", declarations: ["@Instantiated let caveBuilder: Instantiator<Cave>"]),
			Self.type(named: "Cave", declarations: ["@Instantiated let homeBuilder: Instantiator<Den>"]),
		])

		// Siblings may share a label: each cycle has its slot, and the second takes a reserved name.
		#expect(NodeRecords.mockEnteredSlots(in: graph) == [
			MockEnteredSlot(name: "homeBuilder", configurationType: .simple(name: "Home"), nearestOfTypeSlotName: nil),
			MockEnteredSlot(name: "roomBuilder", configurationType: .simple(name: "Room"), nearestOfTypeSlotName: nil),
			MockEnteredSlot(name: "__safeDI_slot2", configurationType: .simple(name: "Den"), nearestOfTypeSlotName: nil),
			MockEnteredSlot(name: "caveBuilder", configurationType: .simple(name: "Cave"), nearestOfTypeSlotName: nil),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mockEnteredSlots_ordersSlotsAlongTheTree_whenTwentyMembersAreNamedInReverseOrder() async throws {
		// Each member's name and label sort before the one that builds it, so an order that followed names would reverse
		// the list.
		let names = (0..<20).map { "Member\(String(UnicodeScalar(UInt8(ascii: "t") - UInt8($0))))" }
		var types = [Self.type(named: "Root", isMockRoot: true, declarations: ["@Instantiated let \(Self.builderLabel(of: names[0])): Instantiator<\(names[0])>"])]
		for (index, name) in names.enumerated() {
			let next = names[(index + 1) % names.count]
			types.append(Self.type(named: name, declarations: ["@Instantiated let \(Self.builderLabel(of: next)): Instantiator<\(next)>"]))
		}
		let graph = try await mockWorld(of: types)

		#expect(NodeRecords.mockEnteredSlots(in: graph).map(\.name) == names.map(Self.builderLabel(of:)))
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The facts graph of the mock world of the type `Root`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func mockWorld(of types: [String]) async throws -> TypeFactsGraph {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		_ = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
			try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var graphs = [TypeFactsGraph]()
		for await report in stream where report.root == "Root" && report.forMockGeneration {
			graphs.append(report.graph)
		}
		return try #require(graphs.last)
	}

	private func declaration(described prefix: String, in graph: TypeFactsGraph) throws -> DeclarationID {
		try #require((0..<Int32(graph.declarationCount)).first { graph.description(ofNode: Int($0)).hasPrefix(prefix) })
	}

	private static func builderLabel(of typeName: String) -> String {
		"\(typeName.prefix(1).lowercased())\(typeName.dropFirst())Builder"
	}

	/// A final class named `name` that declares `declarations`; the mock root generates its mock.
	private static func type(named name: String, isMockRoot: Bool = false, declarations: [String]) -> String {
		let type = seamFixtureType(named: name, isFinalClass: true, declarations: declarations)
		return isMockRoot ? type.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n") : type
	}
}
