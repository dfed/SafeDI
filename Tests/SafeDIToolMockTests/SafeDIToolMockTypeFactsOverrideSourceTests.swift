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

/// The per-type facts' edge column of where a child's override comes from in a mock world (`TypeFactsOverrideSource`):
/// the parent's configuration has a field for the child, or the type edge is in the module's cycle edges and is left
/// out, as the mock writer decides (`ScopeGenerator.CycleEdge.leavesOut(_:beneath:in:)`). Each test compares the column
/// of every edge with what the writer answered (check 38 of `TypeFactsChecks`) and with the mock it wrote.
struct SafeDIToolMockTypeFactsOverrideSourceTests: ~Copyable {
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
	mutating func typeFacts_holdsParentConfiguration_whenParentsConfigurationHasFieldForChild() async throws {
		let (output, report, decisions) = try await mockWorld(of: "Home", types: [
			"""
			@Instantiable(generateMock: true)
			public struct Home: Instantiable {
			    public init(screen: Screen) { self.screen = screen }
			    @Instantiated let screen: Screen
			}
			""",
			"""
			@Instantiable
			public struct Screen: Instantiable {
			    public init(cache: Cache) { self.cache = cache }
			    @Instantiated let cache: Cache
			}
			""",
			"""
			@Instantiable
			public struct Cache: Instantiable {
			    public init() {}
			}
			""",
		])

		#expect(Self.overrideSources(in: report) == [
			"Home -> screen: parentConfiguration",
			"Screen as screen: Screen -> cache: parentConfiguration",
		])
		#expect(Self.check38(of: report, decisions: decisions) == Self.Check38(findings: [], compared: 2))
		#expect(output.mockConfigurationFile == generatedFileHeader + """
		#if DEBUG
		extension Screen {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            cache: (() -> Cache)? = nil,
		            _ safeDIBuilder: ((Cache) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                cache: cache,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var cache: (() -> Cache)? { __safeDI_storage.cache }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Cache) -> Screen)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                cache: (() -> Cache)?,
		                safeDIBuilder: ((Cache) -> Screen)?
		            ) {
		                self.cache = cache
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let cache: (() -> Cache)?
		            let safeDIBuilder: ((Cache) -> Screen)?
		        }
		    }
		}
		#endif

		""")
		#expect(output.mockFiles["Home+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: Screen.SafeDIMockConfiguration { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: Screen.SafeDIMockConfiguration
		            ) {
		                self.screen = screen
		            }

		            let screen: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_screen() -> Screen {
		            let cache = if let safeDIBuilder = safeDIOverrides.screen.cache { safeDIBuilder() } else { Cache() }
		            return if let safeDIBuilder = safeDIOverrides.screen.safeDIBuilder { safeDIBuilder(cache) } else { Screen(cache: cache) }
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}
		#endif
		""")
	}

	/// `Screen` and `Step` build each other, and the module's cycle edges leave out `Step`'s edge to `Screen`, the edge
	/// into the type the depth-first walk from the first type in name order entered first.
	@Test
	mutating func typeFacts_holdsLeftOut_whenTypeEdgeIsCycleEdge() async throws {
		let (output, report, decisions) = try await mockWorld(of: "Home", types: Self.cycleTypes)

		#expect(Self.overrideSources(in: report) == [
			"Home -> screen: parentConfiguration",
			"Screen as screen: Screen -> stepBuilder: parentConfiguration",
			"Step as stepBuilder: Instantiator<Step> -> screenBuilder: leftOut",
			"Screen as screenBuilder: Instantiator<Screen> -> stepBuilder: parentConfiguration",
		])
		#expect(Self.check38(of: report, decisions: decisions) == Self.Check38(findings: [], compared: 4))
		#expect(output.mockConfigurationFile == generatedFileHeader + """
		#if DEBUG
		extension Step {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            _ safeDIBuilder: ((Instantiator<Screen>) -> Step)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Instantiator<Screen>) -> Step)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                safeDIBuilder: ((Instantiator<Screen>) -> Step)?
		            ) {
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let safeDIBuilder: ((Instantiator<Screen>) -> Step)?
		        }
		    }
		}

		extension Screen {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            stepBuilder: Step.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((Instantiator<Step>) -> Screen)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                stepBuilder: stepBuilder,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var stepBuilder: Step.SafeDIMockConfiguration { __safeDI_storage.stepBuilder }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Instantiator<Step>) -> Screen)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                stepBuilder: Step.SafeDIMockConfiguration,
		                safeDIBuilder: ((Instantiator<Step>) -> Screen)?
		            ) {
		                self.stepBuilder = stepBuilder
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let stepBuilder: Step.SafeDIMockConfiguration
		            let safeDIBuilder: ((Instantiator<Step>) -> Screen)?
		        }
		    }
		}
		#endif

		""")
		#expect(output.mockFiles["Home+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Home {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            screen: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                screen: screen
		            )
		        }

		        var screen: Screen.SafeDIMockConfiguration { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                screen: Screen.SafeDIMockConfiguration
		            ) {
		                self.screen = screen
		            }

		            let screen: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Home {
		        func __safeDI_screen() -> Screen {
		            func __safeDI_stepBuilder() -> Step {
		                func __safeDI_screenBuilder() -> Screen {
		                    let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		                    return if let safeDIBuilder = safeDIOverrides.screen.safeDIBuilder { safeDIBuilder(stepBuilder) } else { Screen(stepBuilder: stepBuilder) }
		                }
		                let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
		                return if let safeDIBuilder = safeDIOverrides.screen.stepBuilder.safeDIBuilder { safeDIBuilder(screenBuilder) } else { Step(screenBuilder: screenBuilder) }
		            }
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            return if let safeDIBuilder = safeDIOverrides.screen.safeDIBuilder { safeDIBuilder(stepBuilder) } else { Screen(stepBuilder: stepBuilder) }
		        }
		        let screen: Screen = __safeDI_screen()
		        return Home(screen: screen)
		    }
		}
		#endif
		""")
	}

	/// `Root`'s mock builds `Alpha` with its hand-written mock, which builds no `Gamma`, and `Beta` builds `Alpha` again
	/// with `init` beneath the cycle edge, where no override reaches it; that `Alpha` builds `Gamma`, built nowhere else.
	/// The writer still asks of the type edge from `Alpha` to `Gamma` there, so the column is checked against its answer.
	@Test
	mutating func typeFacts_holdsParentConfiguration_whenTypeEdgeIsBuiltOnlyBeneathEdgeLeftOut() async throws {
		let (_, report, decisions) = try await mockWorld(of: "Root", types: [
			"""
			@Instantiable(generateMock: true)
			public struct Root: Instantiable {
			    public init(alpha: AlphaProtocol) { self.alpha = alpha }
			    @Instantiated let alpha: AlphaProtocol
			}
			""",
			"""
			public protocol AlphaProtocol {}

			@Instantiable(fulfillingAdditionalTypes: [AlphaProtocol.self])
			public struct Alpha: AlphaProtocol, Instantiable {
			    public init(beta: Instantiator<Beta>, gamma: Gamma) {
			        self.beta = beta
			        self.gamma = gamma
			    }
			    @Instantiated let beta: Instantiator<Beta>
			    @Instantiated let gamma: Gamma
			}

			@Instantiable(fulfillingAdditionalTypes: [AlphaProtocol.self], mockOnly: true)
			extension Alpha {
			    public static func mock(beta: Instantiator<Beta> = Instantiator { .unused() }) -> AlphaProtocol {
			        Alpha(beta: beta, gamma: Gamma())
			    }
			}
			""",
			"""
			extension Beta {
			    public static func unused() -> Beta {
			        Beta(alphaBuilder: Instantiator { Alpha(beta: Instantiator { unused() }, gamma: Gamma()) })
			    }
			}

			@Instantiable
			public struct Beta: Instantiable {
			    public init(alphaBuilder: Instantiator<Alpha>) { self.alphaBuilder = alphaBuilder }
			    @Instantiated let alphaBuilder: Instantiator<Alpha>
			}
			""",
			"""
			public protocol GammaProtocol {}

			@Instantiable(fulfillingAdditionalTypes: [GammaProtocol.self])
			public struct Gamma: GammaProtocol, Instantiable {
			    public init(flag: Bool = true) {}
			}

			@Instantiable(fulfillingAdditionalTypes: [GammaProtocol.self], mockOnly: true)
			extension Gamma {
			    public static func mock(flag: Bool = true) -> GammaProtocol { Gamma(flag: flag) }
			}
			""",
		])

		#expect(Self.overrideSources(in: report) == [
			"Root -> alpha: parentConfiguration",
			"Alpha as alpha: AlphaProtocol -> beta: parentConfiguration",
			"Beta as beta: Instantiator<Beta> -> alphaBuilder: leftOut",
			"Alpha as alphaBuilder: Instantiator<Alpha> -> beta: parentConfiguration",
			"Alpha as alphaBuilder: Instantiator<Alpha> -> gamma: parentConfiguration",
		])
		#expect(Self.check38(of: report, decisions: decisions) == Check38(findings: [], compared: 5))
	}

	/// `Child` instantiates `analytics` only if available and nothing fulfills it, so the mock builds no node for it: it binds
	/// the override of what its tree receives only if available, and the writer asks nothing of the edge.
	@Test
	mutating func typeFacts_holdsNoOverrideSource_whenChildIsInstantiatedOnlyIfAvailableAndNothingFulfillsIt() async throws {
		let (_, report, decisions) = try await mockWorld(of: "Screen", types: [
			"""
			public protocol Analytics {}
			""",
			"""
			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(child: Child) {
			        self.child = child
			    }
			    @Instantiated let child: Child
			}
			""",
			"""
			@Instantiable
			public final class Child: Instantiable {
			    public init(analytics: (any Analytics)?) {
			        self.analytics = analytics
			    }
			    @Instantiated(onlyIfAvailable: true) let analytics: (any Analytics)?
			}
			""",
		])

		#expect(Self.overrideSources(in: report) == [
			"Screen -> child: parentConfiguration",
			"Child as child: Child -> analytics: none",
		])
		#expect(Self.check38(of: report, decisions: decisions) == Check38(findings: [], compared: 1))
	}

	/// `Step`'s `screenBuilder` builds `Screen` again, whose `stepBuilder` closes the cycle on the `Step` above it; the
	/// edge from `Screen` to `Step` is no cycle edge, so `Screen`'s configuration has a field for the closing child.
	@Test
	mutating func typeFacts_holdsParentConfiguration_whenCycleClosingEdgeIsNoCycleEdge() async throws {
		let (_, report, decisions) = try await mockWorld(of: "Home", types: Self.cycleTypes)

		let closingEdges = report.places.compactMap { place -> String? in
			guard place.closesCycle, let parent = place.parent, let parentNode = report.places[parent].node, let node = place.node, let edge = report.nodes[parentNode].edges.firstIndex(of: node) else { return nil }
			return "\(report.places[parent].declaration) -> \(place.declaration): \(report.nodes[parentNode].edgeFacts[edge].overrideSource ?? "none")"
		}
		#expect(closingEdges == [
			"Screen as screenBuilder: Instantiator<Screen> -> Step as stepBuilder: Instantiator<Step>: parentConfiguration",
		])
		#expect(Self.check38(of: report, decisions: decisions).findings == [])
	}

	/// A production world has no configuration, so no edge of it has an override source.
	@Test
	mutating func typeFacts_holdsNoOverrideSource_whenWorldIsProduction() async throws {
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		var filesToDelete = filesToDelete
		_ = try await ConstructionMemoOracle.$observer.withValue({ _, _, report in continuation.yield(report) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(screen: Screen) { self.screen = screen }
					    @Instantiated let screen: Screen
					}
					""",
				] + Array(Self.cycleTypes.dropFirst()),
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		self.filesToDelete = filesToDelete
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == "Root" && !report.forMockGeneration {
			reports.append(report)
		}
		let report = try #require(reports.last)

		#expect(Self.overrideSources(in: report) == [
			"Root -> screen: none",
			"Screen as screen: Screen -> stepBuilder: none",
			"Step as stepBuilder: Instantiator<Step> -> screenBuilder: none",
			"Screen as screenBuilder: Instantiator<Screen> -> stepBuilder: none",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Home` builds `Screen`, and `Screen` and `Step` build each other through instantiators.
	private static let cycleTypes = [
		"""
		@Instantiable(generateMock: true)
		public struct Home: Instantiable {
		    public init(screen: Screen) { self.screen = screen }
		    @Instantiated let screen: Screen
		}
		""",
		"""
		@Instantiable
		public struct Screen: Instantiable {
		    public init(stepBuilder: Instantiator<Step>) { self.stepBuilder = stepBuilder }
		    @Instantiated let stepBuilder: Instantiator<Step>
		}
		""",
		"""
		@Instantiable
		public struct Step: Instantiable {
		    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
		    @Instantiated let screenBuilder: Instantiator<Screen>
		}
		""",
	]

	/// What check 38 found of a world, and how many places it compared.
	private struct Check38: Equatable {
		let findings: [String]
		let compared: Int
	}

	/// The mock world of `mockRoot`, the last one the run built, with the run's output and what the writer answered of the
	/// cycle edges as it lowered that root.
	private mutating func mockWorld(of mockRoot: String, types: [String]) async throws -> (output: TestOutput, report: TypeFactsReport, decisions: [MockOverrideSourceDecision]) {
		let (reports, reportContinuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		let (decisions, decisionContinuation) = AsyncStream.makeStream(of: MockOverrideSourceDecision.self)
		var filesToDelete = filesToDelete
		let output = try await MockOverrideSourceObservation.$observer.withValue({ root, decision in
			if root == mockRoot {
				decisionContinuation.yield(decision)
			}
		}) {
			try await ConstructionMemoOracle.$observer.withValue({ _, _, report in reportContinuation.yield(report) }) {
				try await executeSafeDIToolTest(swiftFileContent: types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
		}
		self.filesToDelete = filesToDelete
		reportContinuation.finish()
		decisionContinuation.finish()
		var mockWorlds = [TypeFactsReport]()
		for await report in reports where report.root == mockRoot && report.forMockGeneration {
			mockWorlds.append(report)
		}
		var writerDecisions = [MockOverrideSourceDecision]()
		for await decision in decisions {
			writerDecisions.append(decision)
		}
		return (output, try #require(mockWorlds.last), writerDecisions)
	}

	/// Each edge's override source, a line per edge in node and edge order: the parent's type, the child's label, the
	/// column.
	private static func overrideSources(in report: TypeFactsReport) -> [String] {
		report.nodes.flatMap { node in
			zip(node.edges, node.edgeFacts).map { target, edge in
				"\(node.description) -> \(report.nodes[target].label): \(edge.overrideSource ?? "none")"
			}
		}
	}

	private static func check38(of report: TypeFactsReport, decisions: [MockOverrideSourceDecision]) -> Check38 {
		let result = TypeFactsChecks.findings(of: report, writerOverrideSources: decisions)
		return Check38(findings: result.findingsByCheck[38, default: []], compared: result.comparedByCheck[38, default: 0])
	}
}
