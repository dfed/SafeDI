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

/// The parameters a variant's function takes for what its subtree reads from above, read from the facts alone
/// (`TypeFactsWorld.parameters(of:)`, `TypeFactsWorld.parameterType(of:_:)`).
struct SafeDIToolTypeFactsParameterTests: ~Copyable {
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
	mutating func generate_typesParameterAsDeclared_whenEveryCallAnswersRequiredReceiveWithAValue() async throws {
		// `Toolbar`, inside `A`, receives `theme`, which `Root` declares and `B` declares again before it closes the cycle
		// on `A`: the function is `__safeDI_aBuilder(theme: Theme)`.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let toolbar: Toolbar", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Toolbar", isFinalClass: true, declarations: ["@Received let theme: Theme"]),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
		])

		#expect(try parameters(ofVariantsOf: "A ", in: report) == [["theme: Theme"]], "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_typesParametersOptionalInBodysOrder_whenReceivesAreOnlyIfAvailable() async throws {
		// `Ring0` receives `zeta` only if available before its `leaf` receives `alpha` so, and the cycle `Ring1` closes
		// reads its own label, which is no parameter: the function is `__safeDI_ring0Builder(zeta: Zeta?, alpha: Alpha?)`.
		let report = try await rootReport(of: [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let entry0: Entry0"]),
			seamFixtureType(named: "Entry0", isFinalClass: true, declarations: ["@Instantiated let alpha: Alpha", "@Instantiated let zeta: Zeta", "@Instantiated let ring0Builder: Instantiator<Ring0>"]),
			seamFixtureType(named: "Ring0", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let zeta: Zeta?", "@Instantiated let leaf: Leaf", "@Instantiated let ring1Builder: Instantiator<Ring1>"]),
			seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let alpha: Alpha?"]),
			seamFixtureType(named: "Ring1", isFinalClass: true, declarations: ["@Instantiated let ring0Builder: Instantiator<Ring0>"]),
			seamFixtureType(named: "Alpha", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Zeta", isFinalClass: true, declarations: []),
		])

		#expect(try parameters(ofVariantsOf: "Ring0 ", in: report) == [["zeta: Zeta?", "alpha: Alpha?"]], "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNoParameter_whenEveryCallPassesNilForReceiveOnlyIfAvailable() async throws {
		// `Root` and `T0` each build their `logger` after their `t3Builder`, and `T4` and `T5` declare none, so no call of
		// `T3`'s function has a logger to pass: the label is no parameter, and the body is passed `nil` for it.
		let report = try await rootReport(of: Self.loggerFixture(t4Declares: []))

		#expect(try parameters(ofVariantsOf: "T3 ", in: report) == [["session: Session?"]], "\(report.world)")
	}

	@Test(arguments: [
		["@Instantiated let logger: Logger", "@Instantiated let t5: T5"],
		["@Instantiated let t5: T5", "@Instantiated let logger: Logger"],
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsParameter_whenOneCallBindsLabelEveryOtherCallPassesNilFor(t4Declares: [String]) async throws {
		// As above, but `T4` declares a `logger` of its own, in either order with the `T5` that closes the cycle, whose
		// call passes that logger. Every other call still passes `nil`, which the optional parameter carries.
		let report = try await rootReport(of: Self.loggerFixture(t4Declares: t4Declares))

		#expect(try parameters(ofVariantsOf: "T3 ", in: report) == [["session: Session?", "logger: Logger?"]], "\(report.world)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_typesNoParameter_whenReadIsNotOneOfTheVariantsDeclaration() async throws {
		let report = try await rootReport(of: Self.loggerFixture(t4Declares: []))
		let graph = report.graph
		let t3 = try #require(report.variantNodes.firstIndex { report.nodes[$0].description.hasPrefix("T3 ") })
		let logger = try #require(report.variantNodes.firstIndex { report.nodes[$0].description.hasPrefix("Logger ") })
		let loggerReads = graph.reads(of: graph.declaration(of: VariantID(logger)))
		let t3Reads = graph.reads(of: graph.declaration(of: VariantID(t3)))

		// A read of another declaration is no read of the variant.
		#expect(loggerReads.filter { !t3Reads.contains($0) }.allSatisfy { graph.parameterType(of: VariantID(t3), $0) == nil })
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_typesNoParameter_whenReadAsksWhatAMockRootPins() async throws {
		// A mock root's world reads what the root pins for a label, which is no value a function is handed.
		let fixture = Self.loggerFixture(t4Declares: []).map { $0.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)") }
		let graph = try await rootReport(of: fixture, forMockGeneration: true).graph
		var pinnedReadCount = 0
		for variant in 0..<graph.variantCount {
			for read in graph.reads(of: graph.declaration(of: VariantID(variant))) where graph.readTable[Int(read)].channel == .mock {
				pinnedReadCount += 1
				#expect(graph.parameterType(of: VariantID(variant), read) == nil)
			}
		}
		#expect(pinnedReadCount > 0)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A logger's tree receives `t3Builder` only if available, and `T3` receives `session` and `logger` only if available.
	/// `Root` and `T0` declare a session, a logger and `t3Builder`, and build the logger after the builder it receives; `T5`, inside `T4` inside `T3`, closes the cycle on it.
	private static func loggerFixture(t4Declares: [String]) -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let logger: Logger", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: [
				"@Received(onlyIfAvailable: true) let session: Session?",
				#"@Received(fulfilledByDependencyNamed: "session", ofType: Session.self, onlyIfAvailable: true) let aliasedSession: Session?"#,
				"@Received(onlyIfAvailable: true) let logger: Logger?",
				"@Instantiated let t0Builder: Instantiator<T0>",
				"@Instantiated let t4Builder: Instantiator<T4>",
			]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let session: Session", "@Instantiated let logger: Logger", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T4", isFinalClass: true, declarations: t4Declares.isEmpty ? ["@Instantiated let t5: T5"] : t4Declares),
			seamFixtureType(named: "T5", isFinalClass: true, declarations: ["@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "Session", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Logger", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let t3Builder: Instantiator<T3>?"]),
		]
	}

	/// The parameters of each variant of the nodes whose description starts with `prefix`.
	private func parameters(ofVariantsOf prefix: String, in report: TypeFactsReport) throws -> Set<[String]> {
		let variants = report.variantNodes.indices.filter { report.nodes[report.variantNodes[$0]].description.hasPrefix(prefix) }
		try #require(!variants.isEmpty)
		return Set(variants.map { report.variantParameters[$0] })
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func rootReport(of types: [String], forMockGeneration: Bool = false) async throws -> TypeFactsReport {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		_ = try await ConstructionMemoOracle.$observer.withValue(TaskLocalFunction { _, _, report in continuation.yield(report) }) {
			try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == "Root" && report.forMockGeneration == forMockGeneration {
			reports.append(report)
		}
		// Where a root's cycles are planned per type, the tree is built in pieces, each observed as a world of its own: the
		// piece with the most places holds the function the test reads.
		var largest = try #require(reports.first)
		for report in reports.dropFirst() where report.places.count > largest.places.count {
			largest = report
		}
		return largest
	}
}
