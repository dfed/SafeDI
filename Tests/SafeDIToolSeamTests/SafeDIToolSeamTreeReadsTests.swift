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
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The oracle that compares what a seam's signature reads of its tree with what the per-type facts of that tree hold at
/// its root (`SeamTreeReadsObservation`, `SeamTreeReadsChecks`), which every test and fuzzer graph runs under. `Screen`'s
/// tree requires `config` and `onTap` of its caller, receives `theme` only if available, requires `token` only through
/// `Detail`'s `onlyIfAvailable` alias of it, and declares `OnTap` `@escaping`, so each field the facts produce is
/// non-empty: the oracle reports nothing, and reports each field emptied. Of its by-value pass-throughs, `config` is read
/// in plain code, `session` inside a `SendableInstantiator`'s builder, and `clock` by `Panel`, a nested seam that takes it
/// `@Sendable`; a pass-through no read reaches, whose label a fill binds from its struct, is
/// `generate_reportsNoDifference_whenFillOfSeamCallBindsLabelOfReceiveThatLeavesSeam`'s.
struct SafeDIToolSeamTreeReadsTests: ~Copyable {
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

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifference_whenFactsOfSeamsTreeHoldWhatTreeHolds(integration: MultiModuleIntegration) async throws {
		let comparisons = try await observedComparisons(under: integration)
		#expect(!comparisons.isEmpty)
		#expect(Set(comparisons.map(\.seam)) == ["Panel", "Screen"])
		let differences = comparisons.flatMap(\.differences)
		#expect(differences.isEmpty)
	}

	@Test(arguments: SeamTreeReadsObservation.FactsField.allCases, MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDifference_whenFactsFieldIsPerturbed(field: SeamTreeReadsObservation.FactsField, integration: MultiModuleIntegration) async throws {
		// The harness records an issue for each comparison that differs, which is what this test makes happen.
		var comparisons = [SeamTreeReadsComparison]()
		try await withKnownIssue {
			comparisons = try await SeamTreeReadsObservation.$perturbsFactsField.withValue(field) {
				try await observedComparisons(under: integration)
			}
		}
		let tree = switch field {
		case .requiredReceivedProperties:
			["clock: Clock", "config: Config", "onTap: OnTap", "session: Session"]
		case .requiredAliasFulfillingProperties:
			["token: Token"]
		case .typesDeclaredEscaping:
			["OnTap"]
		}
		// `Panel`'s tree holds no alias and no escaping type.
		let screenComparisons = comparisons.filter { $0.seam == "Screen" }
		#expect(!screenComparisons.isEmpty)
		for comparison in screenComparisons {
			#expect(comparison.differences.map(\.field) == [field.rawValue])
			#expect(comparison.differences.map(\.tree) == [tree])
			#expect(comparison.differences.map(\.facts) == [[]])
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifference_whenFillOfSeamCallBindsLabelOfReceiveThatLeavesSeam() async throws {
		// `Top`'s fill of `Inner`'s place, which `Outer` passes up, binds `token` from its struct, so `WrapperReader`'s
		// receive of `token` reaches no parameter of `Top`: the graph is rejected (`declarationHiddenByField`), and the
		// signature pass before the error compares `Top`.
		let (stream, continuation) = AsyncStream.makeStream(of: SeamTreeReadsComparison.self)
		await #expect(throws: (any Error).self) {
			try await SeamTreeReadsObservation.$comparesFacts.withValue({ continuation.yield($0) }) {
				_ = try await executeSafeDIToolMultiModuleTest(
					modules: Self.fillBindingLabelModules,
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			}
		}
		continuation.finish()
		var comparisons = [SeamTreeReadsComparison]()
		for await comparison in stream where comparison.seam == "Top" {
			comparisons.append(comparison)
		}
		#expect(!comparisons.isEmpty)
		#expect(comparisons.flatMap(\.differences).isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsNoDifference_whenFillOfSeamCallRequiresValueOfSeamsCaller() async throws {
		// `Desk`'s fill of `Drawer`'s place builds `PenImpl`, which requires `clock` of `Desk`'s caller: the tree's
		// required receives count it, as the facts' must.
		let (stream, continuation) = AsyncStream.makeStream(of: SeamTreeReadsComparison.self)
		try await SeamTreeReadsObservation.$comparesFacts.withValue({ continuation.yield($0) }) {
			_ = try await executeSafeDIToolMultiModuleTest(
				modules: Self.fillRequiringCallersValueModules,
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var comparisons = [SeamTreeReadsComparison]()
		for await comparison in stream where comparison.seam == "Desk" {
			comparisons.append(comparison)
		}
		#expect(!comparisons.isEmpty)
		#expect(comparisons.flatMap(\.differences).isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesSameSignaturesAndCode_whenSignaturePassesProceedWithFactsReads() async throws {
		let fromTree = try await signaturesAndCode(proceedingWith: .tree)
		let fromFacts = try await signaturesAndCode(proceedingWith: .facts)
		#expect(fromTree.signatures.contains("Screen"))
		#expect(fromTree.code.values.contains { $0.contains("__safeDI_onTap") })
		#expect(fromFacts.signatures == fromTree.signatures)
		#expect(fromFacts.code == fromTree.code)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Feature`'s stored seam signatures, as JSON, and every module's generated code, each with the fixture root spelled
	/// `$FIXTURE_ROOT`, when every signature pass proceeds with `producer`'s reads.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func signaturesAndCode(proceedingWith producer: SeamTreeReadsObservation.Producer) async throws -> (signatures: String, code: [String: String]) {
		let output = try await SeamTreeReadsObservation.$producer.withValue(producer) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules,
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
		let fixtureRoot = output.fixtureRoot.path
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
		let moduleInfoFile = try #require(output.modules["Feature"]?.moduleInfoFile)
		let storedSignatures = try moduleInfoFile.seamSignatures.decoded
		let signatures = try String(decoding: encoder.encode(storedSignatures), as: UTF8.self)
			.replacingOccurrences(of: fixtureRoot, with: "$FIXTURE_ROOT")
		var code = [String: String]()
		for (moduleName, module) in output.modules {
			for (fileName, content) in module.generatedFiles {
				code["\(moduleName)/\(fileName)"] = content.replacingOccurrences(of: fixtureRoot, with: "$FIXTURE_ROOT")
			}
		}
		return (signatures, code)
	}

	/// Every comparison the oracle makes while `App` and `Feature` generate.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func observedComparisons(under integration: MultiModuleIntegration) async throws -> [SeamTreeReadsComparison] {
		let (stream, continuation) = AsyncStream.makeStream(of: SeamTreeReadsComparison.self)
		try await SeamTreeReadsObservation.$comparesFacts.withValue({ continuation.yield($0) }) {
			_ = try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules,
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var comparisons = [SeamTreeReadsComparison]()
		for await comparison in stream {
			comparisons.append(comparison)
		}
		return comparisons
	}

	private static let modules = [
		ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
			"""
			public typealias OnTap = (Int) -> Void
			""",
			"""
			@Instantiable
			public final class Config: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Theme: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Token: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class TapReader: Instantiable {
			    public init(onTap: @escaping OnTap, config: Config) { self.onTap = onTap; self.config = config }
			    @Received let onTap: OnTap
			    @Received let config: Config
			}
			""",
			"""
			@Instantiable
			public final class Badge: Instantiable {
			    public init(theme: Theme?) { self.theme = theme }
			    @Received(onlyIfAvailable: true) let theme: Theme?
			}
			""",
			"""
			@Instantiable
			public final class Child: Instantiable {
			    public init(authToken: Token?) { self.authToken = authToken }
			    @Received let authToken: Token?
			}
			""",
			"""
			@Instantiable
			public final class Detail: Instantiable {
			    public init(authToken: Token?, child: Child) { self.authToken = authToken; self.child = child }
			    @Received(fulfilledByDependencyNamed: "token", ofType: Token.self, onlyIfAvailable: true) let authToken: Token?
			    @Instantiated let child: Child
			}
			""",
			"""
			@Instantiable
			public final class Session: Instantiable, Sendable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Poller: Instantiable, Sendable {
			    public init(session: Session) { self.session = session }
			    @Received let session: Session
			}
			""",
			"""
			@Instantiable
			public final class Clock: Instantiable, Sendable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Ticker: Instantiable, Sendable {
			    public init(clock: Clock) { self.clock = clock }
			    @Received let clock: Clock
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class Panel: Instantiable {
			    public init(tickerBuilder: SendableInstantiator<Ticker>) { self.tickerBuilder = tickerBuilder }
			    @Instantiated let tickerBuilder: SendableInstantiator<Ticker>
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class Screen: Instantiable {
			    public init(reader: TapReader, badge: Badge, detail: Detail, pollerBuilder: SendableInstantiator<Poller>, panel: Panel) { self.reader = reader; self.badge = badge; self.detail = detail; self.pollerBuilder = pollerBuilder; self.panel = panel }
			    @Instantiated let reader: TapReader
			    @Instantiated let badge: Badge
			    @Instantiated let detail: Detail
			    @Instantiated let pollerBuilder: SendableInstantiator<Poller>
			    @Instantiated let panel: Panel
			}
			""",
		]),
		ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
			"""
			import Feature

			@Instantiable
			public final class Home: Instantiable {
			    public init(onTap: @escaping OnTap, config: Config, token: Token, session: Session, clock: Clock, screen: Screen) { self.onTap = onTap; self.config = config; self.token = token; self.session = session; self.clock = clock; self.screen = screen }
			    @Forwarded let onTap: OnTap
			    @Instantiated let config: Config
			    @Instantiated let token: Token
			    @Instantiated let session: Session
			    @Instantiated let clock: Clock
			    @Instantiated let screen: Screen
			}
			""",
			"""
			import Feature

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(homeBuilder: Instantiator<Home>) { self.homeBuilder = homeBuilder }
			    @Instantiated let homeBuilder: Instantiator<Home>
			}
			""",
		], dependencies: ["Feature"]),
	]

	/// `Inner`, a seam of `Core`, takes a builder for `service`; `Outer`, a seam of `Session`, declares `token` and calls
	/// `Inner`, passing the place up; `Top`, a seam of `Feature`, calls `Outer` and fills the place with `ServiceImpl`, whose
	/// `WrapperReader` receives `token` as a wrapper, a form the place's field does not provide.
	private static let fillBindingLabelModules = [
		ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: ["""
		import SafeDI

		public protocol Service: Sendable {}

		@Instantiable
		public final class Token: Instantiable, Sendable {
		    public init() {}
		}

		@Instantiable
		public final class Leaf: Instantiable, Sendable {
		    public init(token: Token) { self.token = token }
		    @Received public let token: Token
		}

		@Instantiable(generateDependencyTree: true)
		public final class Inner: Instantiable, Sendable {
		    public init(leafBuilder: SendableInstantiator<Leaf>, service: any Service) { self.leafBuilder = leafBuilder; self.service = service }
		    @Instantiated public let leafBuilder: SendableInstantiator<Leaf>
		    @Instantiated public let service: any Service
		}
		"""]),
		ModuleFixture(name: "Session", packageName: "Min", swiftFileContent: ["""
		import Core
		import SafeDI

		@Instantiable(generateDependencyTree: true)
		public final class Outer: Instantiable, Sendable {
		    public init(token: SendableLazilyInstantiated<Token>, inner: Inner) { self.token = token; self.inner = inner }
		    @Instantiated public let token: SendableLazilyInstantiated<Token>
		    @Instantiated public let inner: Inner
		}
		"""], dependencies: ["Core"]),
		ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: ["""
		import Core
		import Session
		import SafeDI

		@Instantiable
		public final class WrapperReader: Instantiable, Sendable {
		    public init(token: SendableLazilyInstantiated<Token>) { self.token = token }
		    @Received public let token: SendableLazilyInstantiated<Token>
		}

		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public final class ServiceImpl: Instantiable, Service, Sendable {
		    public init(wrapperReader: WrapperReader) { self.wrapperReader = wrapperReader }
		    @Instantiated public let wrapperReader: WrapperReader
		}

		@Instantiable(generateDependencyTree: true)
		public final class Top: Instantiable, Sendable {
		    public init(outer: Outer) { self.outer = outer }
		    @Instantiated public let outer: Outer
		}
		"""], dependencies: ["Core", "Session"]),
	]

	/// `Drawer`, a seam of `Supplies`, takes a builder for `pen`; `Desk`, a seam of `Office`, calls `Drawer` and fills the
	/// place with `PenImpl`, which requires `clock`, a value no type of `Desk`'s tree declares.
	private static let fillRequiringCallersValueModules = [
		ModuleFixture(name: "Supplies", packageName: "Stationery", swiftFileContent: ["""
		import SafeDI

		public protocol Pen {}

		@Instantiable
		public final class Clock: Instantiable {
		    public init() {}
		}

		@Instantiable(generateDependencyTree: true)
		public final class Drawer: Instantiable {
		    public init(pen: any Pen) { self.pen = pen }
		    @Instantiated public let pen: any Pen
		}
		"""]),
		ModuleFixture(name: "Office", packageName: "Stationery", swiftFileContent: ["""
		import Supplies
		import SafeDI

		@Instantiable(fulfillingAdditionalTypes: [Pen.self])
		public final class PenImpl: Instantiable, Pen {
		    public init(clock: Clock) { self.clock = clock }
		    @Received public let clock: Clock
		}

		@Instantiable(generateDependencyTree: true)
		public final class Desk: Instantiable {
		    public init(drawer: Drawer) { self.drawer = drawer }
		    @Instantiated public let drawer: Drawer
		}
		"""], dependencies: ["Supplies"]),
	]
}
