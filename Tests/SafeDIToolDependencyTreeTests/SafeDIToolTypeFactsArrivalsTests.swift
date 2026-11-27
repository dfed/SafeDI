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

/// What arrives at a read of a variant from every call into it (`TypeFactsReadArrivals`): where `nil` keys with a
/// wrapper (rule 3's second stage), whether the variant's parameter is optional, and whether it is any parameter at all.
struct SafeDIToolTypeFactsArrivalsTests: ~Copyable {
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
	mutating func readArrivals_holdsNilAndTheAnswer_whenOneParentPassesTheWrapperAndAnotherNothing() async throws {
		let graph = try await world(of: Self.leafFixture(places: [("Second", "LazilyInstantiated<Theme>"), ("Third", nil)]))

		#expect(try arrivals(of: "theme", atVariantsOf: "Leaf ", in: graph) == [[.nil, .answer]])
		let arrivals = TypeFactsReadArrivals(world: graph)
		let leaf = try variants(of: "Leaf ", in: graph)[0]
		let position = try position(of: "theme", in: leaf, of: graph)
		#expect(arrivals.nilArrives(at: position, of: leaf))
		#expect(!arrivals.onlyNilArrives(at: position, of: leaf))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func readArrivals_holdsOnlyTheAnswer_whenEveryParentPassesTheWrapper() async throws {
		let graph = try await world(of: Self.leafFixture(places: [("Second", "LazilyInstantiated<Theme>")]))

		#expect(try arrivals(of: "theme", atVariantsOf: "Leaf ", in: graph) == [.answer])
		let leaf = try variants(of: "Leaf ", in: graph)[0]
		#expect(try !TypeFactsReadArrivals(world: graph).nilArrives(at: position(of: "theme", in: leaf, of: graph), of: leaf))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func readArrivals_holdsOnlyNil_whenNoParentPassesAnything() async throws {
		let graph = try await world(of: Self.leafFixture(places: [("Third", nil)]))

		#expect(try arrivals(of: "theme", atVariantsOf: "Leaf ", in: graph) == [.nil])
		let leaf = try variants(of: "Leaf ", in: graph)[0]
		#expect(try TypeFactsReadArrivals(world: graph).onlyNilArrives(at: position(of: "theme", in: leaf, of: graph), of: leaf))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func readArrivals_foldsNilUpThePassedThroughCalls_whenNilAndTheWrapperMeetOnlyBeneathTwoDeclarations() async throws {
		// `nil` is passed at `Third`'s call of `MidB` and the wrapper at `Second`'s of `MidA`; each mid passes its read through
		// to `Leaf`, where the two meet.
		let graph = try await world(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let second: Second", "@Instantiated let third: Third"]),
			seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let theme: LazilyInstantiated<Theme>", "@Instantiated let midA: MidA"]),
			seamFixtureType(named: "Third", isFinalClass: true, declarations: ["@Instantiated let midB: MidB"]),
			seamFixtureType(named: "MidA", isFinalClass: true, declarations: ["@Instantiated let leafBuilder: Instantiator<Leaf>"]),
			seamFixtureType(named: "MidB", isFinalClass: true, declarations: ["@Instantiated let leafBuilder: Instantiator<Leaf>"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let theme: Theme?"]),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
		])

		#expect(try arrivals(of: "theme", atVariantsOf: "MidA ", in: graph) == [.answer])
		#expect(try arrivals(of: "theme", atVariantsOf: "MidB ", in: graph) == [.nil])
		#expect(try arrivals(of: "theme", atVariantsOf: "Leaf ", in: graph) == [[.nil, .answer]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func readArrivals_holdsNilAndTheAnswerWhereverTheWrapperIs_whenTwentyParentsPassNothingAndOneTheWrapper() async throws {
		// The fold reaches a fixed point whichever parent's call it meets first: the one wrapper is at each end and in the
		// middle of twenty parents that pass nothing.
		for wrapperIndex in [0, 10, 20] {
			let places = (0...20).map { index in (name: "Parent\(index)", theme: index == wrapperIndex ? "LazilyInstantiated<Theme>" : nil) }
			let graph = try await world(of: Self.leafFixture(places: places))

			#expect(try arrivals(of: "theme", atVariantsOf: "Leaf ", in: graph) == [[.nil, .answer]], "wrapper at \(wrapperIndex)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func readArrivals_holdsNilAndTheAnswerAtTheRootsReads_whenTheRootIsAMockRoot() async throws {
		// A mock root's reads are its `mock()` parameters, which its caller may pass or leave `nil`.
		let graph = try await world(of: [
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let theme: Theme?", "@Instantiated let leafBuilder: Instantiator<Leaf>"]).replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n"),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
		], root: "Leaf", forMockGeneration: true)

		let root = graph.rootVariant(0)
		#expect(try TypeFactsReadArrivals(world: graph).arrivals(at: position(of: "theme", in: root, of: graph), of: root) == [.nil, .answer])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The facts world of `root`'s tree, or of its mock where `forMockGeneration`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func world(of types: [String], root: String = "Root", forMockGeneration: Bool = false) async throws -> TypeFactsGraph {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		_ = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
			try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var graphs = [TypeFactsGraph]()
		for await report in stream where report.root == root && report.forMockGeneration == forMockGeneration {
			graphs.append(report.graph)
		}
		return try #require(graphs.last)
	}

	/// What arrives at the read of `label` in each variant of the declarations whose description starts with `prefix`, in
	/// variant order.
	private func arrivals(of label: String, atVariantsOf prefix: String, in graph: TypeFactsGraph) throws -> [TypeFactsArrivals] {
		let arrivals = TypeFactsReadArrivals(world: graph)
		return try variants(of: prefix, in: graph).map { variant in
			try arrivals.arrivals(at: position(of: label, in: variant, of: graph), of: variant)
		}
	}

	private func variants(of prefix: String, in graph: TypeFactsGraph) throws -> [VariantID] {
		let variants = (0..<Int32(graph.variantCount)).filter { graph.description(ofNode: Int(graph.declaration(of: $0))).hasPrefix(prefix) }
		try #require(!variants.isEmpty, "\(graph.description)")
		return variants
	}

	private func position(of label: String, in variant: VariantID, of graph: TypeFactsGraph) throws -> Int {
		try #require(graph.reads(of: graph.declaration(of: variant)).firstIndex { graph.labelTexts[Int(graph.read($0).label)] == label }.map { $0 - graph.reads(of: graph.declaration(of: variant)).startIndex })
	}

	/// `Leaf` receives `theme: Theme?` only if available and builds itself again through `leafBuilder`; each of `places`,
	/// in `Root`'s declaration order, declares the `theme` it names, if any, then builds `leafBuilder`.
	private static func leafFixture(places: [(name: String, theme: String?)]) -> [String] {
		var types = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: places.map { "@Instantiated let \($0.name.prefix(1).lowercased() + $0.name.dropFirst()): \($0.name)" })]
		for place in places {
			types.append(seamFixtureType(named: place.name, isFinalClass: true, declarations: (place.theme.map { ["@Instantiated let theme: \($0)"] } ?? []) + ["@Instantiated let leafBuilder: Instantiator<Leaf>"]))
		}
		types.append(seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let theme: Theme?", "@Instantiated let leafBuilder: Instantiator<Leaf>"]))
		types.append(seamFixtureType(named: "Theme", isFinalClass: true, declarations: []))
		return types
	}
}
