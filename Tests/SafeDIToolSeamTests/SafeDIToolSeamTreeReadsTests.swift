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
/// non-empty: the oracle reports nothing, and reports each field emptied.
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
		#expect(Set(comparisons.map(\.seam)) == ["Screen"])
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
				try await self.observedComparisons(under: integration)
			}
		}
		let tree = switch field {
		case .requiredAliasFulfillingProperties:
			["token: Token"]
		case .typesDeclaredEscaping:
			["OnTap"]
		}
		#expect(!comparisons.isEmpty)
		for comparison in comparisons {
			#expect(comparison.seam == "Screen")
			#expect(comparison.differences.map(\.field) == [field.rawValue])
			#expect(comparison.differences.map(\.tree) == [tree])
			#expect(comparison.differences.map(\.facts) == [[]])
		}
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
			@Instantiable(generateDependencyTree: true)
			public final class Screen: Instantiable {
			    public init(reader: TapReader, badge: Badge, detail: Detail) { self.reader = reader; self.badge = badge; self.detail = detail }
			    @Instantiated let reader: TapReader
			    @Instantiated let badge: Badge
			    @Instantiated let detail: Detail
			}
			""",
		]),
		ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
			"""
			import Feature

			@Instantiable
			public final class Home: Instantiable {
			    public init(onTap: @escaping OnTap, config: Config, token: Token, screen: Screen) { self.onTap = onTap; self.config = config; self.token = token; self.screen = screen }
			    @Forwarded let onTap: OnTap
			    @Instantiated let config: Config
			    @Instantiated let token: Token
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
}
