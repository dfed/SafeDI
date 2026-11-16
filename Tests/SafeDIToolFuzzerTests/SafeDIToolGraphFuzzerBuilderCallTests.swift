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
@testable import SafeDIToolTestSupport

/// The compile of the hand-written call `C` (`GraphFuzzerBuilderSurface.addingBuilderCalls(to:seamTypeAccess:modules:)`):
/// a call a person writes of a seam's readable initializer, passing each builder that takes a builder struct a closure
/// `{ make() }` or a stored closure `make` of the family the builder struct names, or, where the builder's places are held
/// in instantiators, a closure over the value they forward, must compile.
struct SafeDIToolGraphFuzzerBuilderCallTests {
	// MARK: The calls written

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingBuilderCalls_writesClosureAndStoredClosureCalls_whenSeamTakesBuilderStructOfEachFamily() {
		let generatedFiles = ["S1_Home+SafeDI.swift": Self.generatedSeamFile(prefix: "S1_", readablePlainBuilderType: "@escaping () -> any S1_Api")]

		let withCalls = GraphFuzzerBuilderSurface.addingBuilderCalls(to: generatedFiles)

		#expect(withCalls.keys.sorted() == ["S1_Home+SafeDI.swift", "S1_Home+SafeDIBuilderCall.swift"])
		#expect(withCalls["S1_Home+SafeDIBuilderCall.swift"] == """
		public enum S1_HomeBuilderCall {
		    public static func callTier0WritingClosures(_ parameter0: Int, _ parameter1: @escaping () -> any S1_Api, _ parameter2: @escaping @Sendable () -> any S1_Api) -> S1_Home {
		        S1_Home(count: parameter0, apiBuilder: { parameter1() }, apiSendableBuilder: { parameter2() })
		    }
		    public static func callTier0PassingStoredClosures(_ parameter0: Int, _ parameter1: @escaping () -> any S1_Api, _ parameter2: @escaping @Sendable () -> any S1_Api) -> S1_Home {
		        S1_Home(count: parameter0, apiBuilder: parameter1, apiSendableBuilder: parameter2)
		    }
		}

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingBuilderCalls_readsFamilyFromBuilderStruct_whenReadableParameterSpellsAnotherFamily() {
		// The plain family's readable parameter spelled `@Sendable`: `C` still passes a plain closure, the drawn graph's.
		let generatedFiles = ["S1_Home+SafeDI.swift": Self.generatedSeamFile(prefix: "S1_", readablePlainBuilderType: "@escaping @Sendable () -> any S1_Api")]

		let withCalls = GraphFuzzerBuilderSurface.addingBuilderCalls(to: generatedFiles)

		#expect(withCalls["S1_Home+SafeDIBuilderCall.swift"]?.contains("public static func callTier0PassingStoredClosures(_ parameter0: Int, _ parameter1: @escaping () -> any S1_Api, _ parameter2: @escaping @Sendable () -> any S1_Api) -> S1_Home {") == true)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingBuilderCalls_writesNoCall_whenEveryBuilderKeepsItsScopeForm() {
		// A kept builder, whose readable initializer takes a closure over the scope enum, is the base check's to judge: no
		// form of `C` compiles against it.
		let generatedFiles = ["S1_Home+SafeDI.swift": """
		extension S1_Home {
		    public convenience init(panelBuilder: @escaping (SafeDIScope_Panel) -> any S1_Panel) {
		        self.init(__safeDI_panelBuilder: panelBuilder)
		    }

		    public convenience init(__safeDI_panelBuilder: @escaping (SafeDIScope_Panel) -> any S1_Panel) {
		        self.init(panel: __safeDI_panelBuilder(.panel(SafeDIScope_Panel.panel_Values())))
		    }
		}

		extension S1_Home {
		    public enum __safeDI_Home_0 {}
		}

		"""]

		#expect(GraphFuzzerBuilderSurface.addingBuilderCalls(to: generatedFiles) == generatedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingBuilderCalls_writesCallOfNarrowestReachableTier_whenGraphIsSplitAcrossModules() {
		let generatedFiles = ["FuzzFeature/S1_Home+SafeDI.swift": "import FuzzSession\n\n" + Self.generatedSeamFile(prefix: "S1_", readablePlainBuilderType: "@escaping () -> any S1_Api")]

		let withCalls = GraphFuzzerBuilderSurface.addingBuilderCalls(to: generatedFiles, modules: [.seamModule, .samePackageCaller])

		#expect(withCalls.keys.sorted() == ["FuzzApp/S1_Home+SafeDIBuilderCall.swift", "FuzzFeature/S1_Home+SafeDI.swift", "FuzzFeature/S1_Home+SafeDIBuilderCall.swift"])
		#expect(withCalls["FuzzApp/S1_Home+SafeDIBuilderCall.swift"] == """
		import FuzzFeature
		import FuzzSession

		public enum S1_HomeSamePackageBuilderCall {
		    public static func callTier0WritingClosures(_ parameter0: Int, _ parameter1: @escaping () -> any S1_Api, _ parameter2: @escaping @Sendable () -> any S1_Api) -> S1_Home {
		        S1_Home(count: parameter0, apiBuilder: { parameter1() }, apiSendableBuilder: { parameter2() })
		    }
		    public static func callTier0PassingStoredClosures(_ parameter0: Int, _ parameter1: @escaping () -> any S1_Api, _ parameter2: @escaping @Sendable () -> any S1_Api) -> S1_Home {
		        S1_Home(count: parameter0, apiBuilder: parameter1, apiSendableBuilder: parameter2)
		    }
		}

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func addingBuilderCalls_writesEachFormOfForwardedValue_whenBuildersPlacesAreHeldInInstantiators() {
		// `liveApi_ApiBuilder` reaches a plain place beside one that forwards nothing, and takes nothing; the others take what
		// their places forward, read from the builder struct's members and, for `livePanel_PanelBuilder`, its level's: `()`,
		// a labeled pair, which two more functions destructure and read by label, a `String`, and a `@Sendable` builder's `Int`.
		let generatedFiles = ["FuzzFeature/Home+SafeDI.swift": Self.forwardingSeamFile]

		let withCalls = GraphFuzzerBuilderSurface.addingBuilderCalls(to: generatedFiles)

		#expect(withCalls.keys.sorted() == ["FuzzFeature/Home+SafeDI.swift", "FuzzFeature/Home+SafeDIBuilderCall.swift"])
		#expect(withCalls["FuzzFeature/Home+SafeDIBuilderCall.swift"] == """
		public enum HomeBuilderCall {
		    public static func callTier0WritingClosures(_ parameter0: @escaping () -> any Api, _ parameter1: @escaping (()) -> any Later, _ parameter2: @escaping ((id: Int, name: String)) -> any Pair, _ parameter3: @escaping (String) -> any Panel, _ parameter4: @escaping @Sendable (Int) -> any Ticket) -> Home {
		        Home(liveApi_ApiBuilder: { parameter0() }, liveLater_LaterBuilder: { parameter1(()) }, livePair_PairBuilder: { value in parameter2(value) }, livePanel_PanelBuilder: { value in parameter3(value) }, liveTicket_TicketSendableBuilder: { value in parameter4(value) })
		    }
		    public static func callTier0PassingStoredClosures(_ parameter0: @escaping () -> any Api, _ parameter1: @escaping (()) -> any Later, _ parameter2: @escaping ((id: Int, name: String)) -> any Pair, _ parameter3: @escaping (String) -> any Panel, _ parameter4: @escaping @Sendable (Int) -> any Ticket) -> Home {
		        Home(liveApi_ApiBuilder: parameter0, liveLater_LaterBuilder: parameter1, livePair_PairBuilder: parameter2, livePanel_PanelBuilder: parameter3, liveTicket_TicketSendableBuilder: parameter4)
		    }
		    public static func callTier0DestructuringTuples(_ parameter0: @escaping () -> any Api, _ parameter1: @escaping (()) -> any Later, _ parameter2: @escaping ((id: Int, name: String)) -> any Pair, _ parameter3: @escaping (String) -> any Panel, _ parameter4: @escaping @Sendable (Int) -> any Ticket) -> Home {
		        Home(liveApi_ApiBuilder: { parameter0() }, liveLater_LaterBuilder: { parameter1(()) }, livePair_PairBuilder: { id, name in parameter2((id: id, name: name)) }, livePanel_PanelBuilder: { value in parameter3(value) }, liveTicket_TicketSendableBuilder: { value in parameter4(value) })
		    }
		    public static func callTier0ReadingTupleLabels(_ parameter0: @escaping () -> any Api, _ parameter1: @escaping (()) -> any Later, _ parameter2: @escaping ((id: Int, name: String)) -> any Pair, _ parameter3: @escaping (String) -> any Panel, _ parameter4: @escaping @Sendable (Int) -> any Ticket) -> Home {
		        Home(liveApi_ApiBuilder: { parameter0() }, liveLater_LaterBuilder: { parameter1(()) }, livePair_PairBuilder: { parameter2((id: $0.id, name: $0.name)) }, livePanel_PanelBuilder: { value in parameter3(value) }, liveTicket_TicketSendableBuilder: { value in parameter4(value) })
		    }
		}

		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callsWrapperBuilder_findsBuilderTakingForwardedValue_whenAPlaceIsHeldInAnInstantiator() {
		#expect(GraphFuzzerBuilderSurface.callsWrapperBuilder(in: ["FuzzFeature/Home+SafeDI.swift": Self.forwardingSeamFile]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func callsWrapperBuilder_findsNone_whenEveryBuilderTakesNothing() {
		#expect(!GraphFuzzerBuilderSurface.callsWrapperBuilder(in: ["S1_Home+SafeDI.swift": Self.generatedSeamFile(prefix: "S1_", readablePlainBuilderType: "@escaping () -> any S1_Api")]))
	}

	// MARK: The compile

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compilationFailures_reportNothing_whenReadableParametersTakeWrappersBuilders() async throws {
		let toolRuns = [Self.forwardingSeamGraph(seed: 1_000_000_106, generatedFile: Self.forwardingSeamFile)]

		let failures = try await GraphFuzzerOracle.compilationFailures(of: toolRuns)

		#expect(failures.isEmpty, "\(failures.values.map(\.details))")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compilationFailures_reportBuilderCallFailure_whenPlainFamilysWrapperBuilderIsSpelledWithSendableTwin() async throws {
		// The seam's module compiles: a `@Sendable` function converts to the builder struct's plain member. A person's stored
		// `((id: Int, name: String)) -> any Pair` does not convert to the `Sendable` twin's `Builder`.
		let seed: UInt64 = 1_000_000_107
		let readable = "livePair_PairBuilder: @escaping ErasedInstantiator<(id: Int, name: String), any Pair>.Builder"
		#expect(Self.forwardingSeamFile.components(separatedBy: readable).count == 2)
		let toolRuns = [Self.forwardingSeamGraph(seed: seed, generatedFile: Self.forwardingSeamFile.replacingOccurrences(of: readable, with: "livePair_PairBuilder: @escaping SendableErasedInstantiator<(id: Int, name: String), any Pair>.Builder"))]

		let failures = try await GraphFuzzerOracle.compilationFailures(of: toolRuns)

		#expect(failures.keys.sorted() == [seed])
		#expect(failures[seed]?.kind == .builderCallDoesNotCompile)
		#expect(failures[seed]?.details.contains("Home+SafeDIBuilderCall.swift:") == true)
		#expect(failures[seed]?.details.contains("+SafeDI.swift:") == false)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compilationFailures_reportNothing_whenReadableParametersTakeTheirBuilderStructsFamilies() async throws {
		let toolRuns = [Self.seamGraph(seed: 1_000_000_101, readablePlainBuilderType: "@escaping () -> any S1000000101_Api")]

		let failures = try await GraphFuzzerOracle.compilationFailures(of: toolRuns)

		#expect(failures.isEmpty, "\(failures.values.map(\.details))")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compilationFailures_reportBuilderCallFailure_whenPlainFamilysReadableParameterIsSendable() async throws {
		// The seam's module compiles: a `@Sendable` closure converts to the builder struct's plain one. A person's stored
		// `() -> X` does not convert to it.
		let seed: UInt64 = 1_000_000_102
		let toolRuns = [Self.seamGraph(seed: seed, readablePlainBuilderType: "@escaping @Sendable () -> any S1000000102_Api")]

		let failures = try await GraphFuzzerOracle.compilationFailures(of: toolRuns)

		#expect(failures.keys.sorted() == [seed])
		#expect(failures[seed]?.kind == .builderCallDoesNotCompile)
		#expect(failures[seed]?.details.contains("S1000000102_Home+SafeDIBuilderCall.swift:") == true)
		#expect(failures[seed]?.details.contains("+SafeDI.swift:") == false)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compilationFailures_reportBuilderCallFailure_whenReadableParameterIsAutoclosure() async throws {
		// The seam's module compiles: an `@autoclosure @escaping` parameter is a closure inside the initializer. A person's
		// closure is not the value the autoclosure wraps.
		let seed: UInt64 = 1_000_000_103
		let toolRuns = [Self.seamGraph(seed: seed, readablePlainBuilderType: "@autoclosure @escaping () -> any S1000000103_Api")]

		let failures = try await GraphFuzzerOracle.compilationFailures(of: toolRuns)

		#expect(failures.keys.sorted() == [seed])
		#expect(failures[seed]?.kind == .builderCallDoesNotCompile)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compilationFailures_reportGeneratedCodeFailure_whenGeneratedCodeFailsBesideBuilderCall() async throws {
		// The builder call fails too, but the graph's own code failing is the finding: compiled without the call, it still fails.
		let seed: UInt64 = 1_000_000_104
		let toolRuns = [Self.seamGraph(seed: seed, readablePlainBuilderType: "@escaping @Sendable () -> any S1000000104_Api", extraGeneratedCode: "func brokenWhenLowered() -> Int {\n    func read() -> Int { value }\n    let value = read()\n    return value\n}\n")]

		let failures = try await GraphFuzzerOracle.compilationFailures(of: toolRuns)

		#expect(failures.keys.sorted() == [seed])
		#expect(failures[seed]?.kind == .generatedCodeDoesNotCompile)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, "The oracle compiles generated code only when compile verification is enabled"))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func compilationFailures_reportGeneratedCodeWarning_whenGeneratedCodeDrawsWarningBesideBuilderCall() async throws {
		// The graph's own code compiles without the failing builder call, but draws a warning: that is the finding.
		let seed: UInt64 = 1_000_000_105
		let toolRuns = [Self.seamGraph(seed: seed, readablePlainBuilderType: "@escaping @Sendable () -> any S1000000105_Api", extraGeneratedCode: "func drawsWarning() {\n    let unused = 1\n}\n")]

		let failures = try await GraphFuzzerOracle.compilationFailures(of: toolRuns)

		#expect(failures.keys.sorted() == [seed])
		#expect(failures[seed]?.kind == .generatedCodeDrawsWarning)
	}

	// MARK: Findings

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func findings_reportBuilderCallFailure_whenItFollowsKnownCompilerError() {
		// No known failure masks the compile of `C`: it judges only what a person writes against the readable initializer.
		let knownIssue = GraphFuzzerKnownIssue(reason: "Redeclared", signatures: [.compilerError(containing: "invalid redeclaration")], seeds: [7])
		let compilerError = GraphFuzzerFailure(seed: 7, kind: .generatedCodeDoesNotCompile, details: "Root+SafeDI.swift:3:5: error: invalid redeclaration of 'value'")
		let builderCall = GraphFuzzerFailure(seed: 7, kind: .builderCallDoesNotCompile, details: "S7_Home+SafeDIBuilderCall.swift:3:42: error: converting non-Sendable function value")

		#expect(GraphFuzzerFinding.findings(failure: compilerError, laterFailures: [builderCall], knownIssue: knownIssue) == [.failure(builderCall)])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func findings_reportBuilderCallFailure_whenItFollowsKnownBuilderSurfaceFailure() {
		let knownIssue = GraphFuzzerKnownIssue(reason: "Surface", signatures: [.builderSurface(.builderSurfaceNamesGeneratedType)], seeds: [7])
		let surface = GraphFuzzerFailure(seed: 7, kind: .builderSurfaceNamesGeneratedType, details: "surface")
		let builderCall = GraphFuzzerFailure(seed: 7, kind: .builderCallDoesNotCompile, details: "S7_Home+SafeDIBuilderCall.swift:3:42: error: converting non-Sendable function value")

		#expect(GraphFuzzerFinding.findings(failure: surface, laterFailures: [builderCall], knownIssue: knownIssue) == [.failure(builderCall)])
	}

	// MARK: Fixtures

	/// The file SafeDI generates for `<prefix>Home`, a seam with a value `count` and a place of `any <prefix>Api` in each
	/// family, each of whose builders takes a builder struct; the plain family's readable parameter spelled
	/// `readablePlainBuilderType`, which a hand mutation of the generator changes.
	private static func generatedSeamFile(prefix: String, readablePlainBuilderType: String) -> String {
		"""
		extension \(prefix)Home {
		    @frozen nonisolated public enum SafeDIScope_Api {
		        case api(api_Values)

		        nonisolated public struct api_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let api: (api_Values) -> __safeDI_Built

		            public init(api: @escaping (api_Values) -> __safeDI_Built) {
		                self.api = api
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.api = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    @frozen nonisolated public enum SafeDISendableScope_Api {
		        case api_Sendable(api_Sendable_Values)

		        nonisolated public struct api_Sendable_Values: Sendable {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
		            public let api_Sendable: @Sendable (api_Sendable_Values) -> __safeDI_Built

		            public init(api_Sendable: @escaping @Sendable (api_Sendable_Values) -> __safeDI_Built) {
		                self.api_Sendable = api_Sendable
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
		                self.api_Sendable = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
		    public convenience init(count: Int, apiBuilder: \(readablePlainBuilderType), apiSendableBuilder: @escaping @Sendable () -> any \(prefix)Api) {
		        self.init(__safeDI_count: count, __safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder), __safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// From code you write, call the initializer above instead.
		    public convenience init(__safeDI_count count: Int, __safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any \(prefix)Api>, __safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any \(prefix)Api>) {
		        let api: any \(prefix)Api = __safeDI_apiBuilder.api(SafeDIScope_Api.api_Values())
		        let sendableApi: any \(prefix)Api = __safeDI_apiSendableBuilder.api_Sendable(SafeDISendableScope_Api.api_Sendable_Values())
		        self.init(count: count, api: api, sendableApi: sendableApi)
		    }
		}

		extension \(prefix)Home {
		    public enum __safeDI_Home_0 {}
		}

		"""
	}

	/// The file SafeDI generates for `Home` (`forwardingSeamSource`), a seam whose builders reach a plain place beside an
	/// erased instantiator that forwards nothing, an erased instantiator that forwards nothing, one that forwards a labeled
	/// pair, one beneath `Worker`'s level that forwards a `String`, and a `SendableErasedInstantiator` that forwards an `Int`.
	private static let forwardingSeamFile = """
	extension Home {
	    @frozen nonisolated public enum SafeDIScope_LiveApi_Api {
	        case api(api_Values)
	        case apiLater(apiLater_Values)

	        nonisolated public struct api_Values {}

	        nonisolated public struct apiLater_Values {
	            public let api: any Api
	        }

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let api: (api_Values) -> __safeDI_Built
	            public let apiLater: (apiLater_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

	            public init(api: @escaping (api_Values) -> __safeDI_Built, apiLater: @escaping (apiLater_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
	                self.api = api
	                self.apiLater = apiLater
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
	                self.api = { _ in __safeDI_builder() }
	                self.apiLater = { _ in { _ in __safeDI_builder() } }
	            }
	        }
	    }

	    @frozen nonisolated public enum SafeDIScope_LiveLater_Later {
	        case laterBuilder(laterBuilder_Values)

	        nonisolated public struct laterBuilder_Values {
	            public let api: any Api
	            public let apiLater: ErasedInstantiator<(), any Api>
	            public let pairBuilder: ErasedInstantiator<(id: Int, name: String), any Pair>
	            public let ticketBuilder: SendableErasedInstantiator<Int, any Ticket>
	        }

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let laterBuilder: (laterBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder

	            public init(laterBuilder: @escaping (laterBuilder_Values) -> ErasedInstantiator<(), __safeDI_Built>.Builder) {
	                self.laterBuilder = laterBuilder
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(), __safeDI_Built>.Builder) {
	                self.laterBuilder = { _ in __safeDI_builder }
	            }
	        }
	    }

	    @frozen nonisolated public enum SafeDIScope_LivePair_Pair {
	        case pairBuilder(pairBuilder_Values, (id: Int, name: String))

	        nonisolated public struct pairBuilder_Values {
	            public let api: any Api
	            public let apiLater: ErasedInstantiator<(), any Api>
	        }

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let pairBuilder: (pairBuilder_Values) -> ErasedInstantiator<(id: Int, name: String), __safeDI_Built>.Builder

	            public init(pairBuilder: @escaping (pairBuilder_Values) -> ErasedInstantiator<(id: Int, name: String), __safeDI_Built>.Builder) {
	                self.pairBuilder = pairBuilder
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<(id: Int, name: String), __safeDI_Built>.Builder) {
	                self.pairBuilder = { _ in __safeDI_builder }
	            }
	        }
	    }

	    @frozen nonisolated public enum SafeDIScope_LivePanel_Panel {
	        case worker(worker_Values, SafeDIScope_LivePanel_Panel.Worker_Scope)

	        nonisolated public struct worker_Values {
	            public let api: any Api
	            public let apiLater: ErasedInstantiator<(), any Api>
	            public let pairBuilder: ErasedInstantiator<(id: Int, name: String), any Pair>
	            public let ticketBuilder: SendableErasedInstantiator<Int, any Ticket>
	            public let laterBuilder: ErasedInstantiator<(), any Later>
	        }

	        @frozen nonisolated public enum Worker_Scope {
	            case panelBuilder(panelBuilder_Values, String)

	            nonisolated public struct panelBuilder_Values {}

	            /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	            nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	                public let panelBuilder: (panelBuilder_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder

	                public init(panelBuilder: @escaping (panelBuilder_Values) -> ErasedInstantiator<String, __safeDI_Built>.Builder) {
	                    self.panelBuilder = panelBuilder
	                }

	                public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
	                    self.panelBuilder = { _ in __safeDI_builder }
	                }
	            }
	        }

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
	            public let worker: (worker_Values) -> SafeDIScope_LivePanel_Panel.Worker_Scope.__safeDI_Builder<__safeDI_Built>

	            public init(worker: @escaping (worker_Values) -> SafeDIScope_LivePanel_Panel.Worker_Scope.__safeDI_Builder<__safeDI_Built>) {
	                self.worker = worker
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<String, __safeDI_Built>.Builder) {
	                self.worker = { _ in .init(__safeDI_noScope: __safeDI_builder) }
	            }
	        }
	    }

	    @frozen nonisolated public enum SafeDISendableScope_LiveTicket_Ticket {
	        case ticketBuilder(Int)

	        nonisolated public struct ticketBuilder_Values: Sendable {}

	        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
	        nonisolated public struct __safeDI_Builder<__safeDI_Built>: Sendable {
	            public let ticketBuilder: @Sendable (ticketBuilder_Values) -> SendableErasedInstantiator<Int, __safeDI_Built>.Builder

	            public init(ticketBuilder: @escaping @Sendable (ticketBuilder_Values) -> SendableErasedInstantiator<Int, __safeDI_Built>.Builder) {
	                self.ticketBuilder = ticketBuilder
	            }

	            public init(__safeDI_noScope __safeDI_builder: @escaping SendableErasedInstantiator<Int, __safeDI_Built>.Builder) {
	                self.ticketBuilder = { _ in __safeDI_builder }
	            }
	        }
	    }

	    /// For code you write: each argument is evaluated at the call, and nothing of the calling code is retained but the builders, which can be called after this initializer returns.
	    public init(liveApi_ApiBuilder: @escaping () -> any Api, liveLater_LaterBuilder: @escaping ErasedInstantiator<(), any Later>.Builder, livePair_PairBuilder: @escaping ErasedInstantiator<(id: Int, name: String), any Pair>.Builder, livePanel_PanelBuilder: @escaping ErasedInstantiator<String, any Panel>.Builder, liveTicket_TicketSendableBuilder: @escaping SendableErasedInstantiator<Int, any Ticket>.Builder) {
	        self.init(__safeDI_liveApi_ApiBuilder: .init(__safeDI_noScope: liveApi_ApiBuilder), __safeDI_liveLater_LaterBuilder: .init(__safeDI_noScope: liveLater_LaterBuilder), __safeDI_livePair_PairBuilder: .init(__safeDI_noScope: livePair_PairBuilder), __safeDI_livePanel_PanelBuilder: .init(__safeDI_noScope: livePanel_PanelBuilder), __safeDI_liveTicket_TicketSendableBuilder: .init(__safeDI_noScope: liveTicket_TicketSendableBuilder))
	    }

	    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
	    /// From code you write, call the initializer above instead.
	    public init(__safeDI_liveApi_ApiBuilder: SafeDIScope_LiveApi_Api.__safeDI_Builder<any Api>, __safeDI_liveLater_LaterBuilder: SafeDIScope_LiveLater_Later.__safeDI_Builder<any Later>, __safeDI_livePair_PairBuilder: SafeDIScope_LivePair_Pair.__safeDI_Builder<any Pair>, __safeDI_livePanel_PanelBuilder: SafeDIScope_LivePanel_Panel.__safeDI_Builder<any Panel>, __safeDI_liveTicket_TicketSendableBuilder: SafeDISendableScope_LiveTicket_Ticket.__safeDI_Builder<any Ticket>) {
	        let api: any Api = __safeDI_liveApi_ApiBuilder.api(SafeDIScope_LiveApi_Api.api_Values())
	        let apiLater = ErasedInstantiator<(), any Api>(__safeDI_liveApi_ApiBuilder.apiLater(SafeDIScope_LiveApi_Api.apiLater_Values(api: api)))
	        let pairBuilder = ErasedInstantiator<(id: Int, name: String), any Pair>(__safeDI_livePair_PairBuilder.pairBuilder(SafeDIScope_LivePair_Pair.pairBuilder_Values(api: api, apiLater: apiLater)))
	        let ticketBuilder = SendableErasedInstantiator<Int, any Ticket>(__safeDI_liveTicket_TicketSendableBuilder.ticketBuilder(SafeDISendableScope_LiveTicket_Ticket.ticketBuilder_Values()))
	        let laterBuilder = ErasedInstantiator<(), any Later>(__safeDI_liveLater_LaterBuilder.laterBuilder(SafeDIScope_LiveLater_Later.laterBuilder_Values(api: api, apiLater: apiLater, pairBuilder: pairBuilder, ticketBuilder: ticketBuilder)))
	        let __safeDI_livePanel_PanelBuilder_worker = __safeDI_livePanel_PanelBuilder.worker(SafeDIScope_LivePanel_Panel.worker_Values(api: api, apiLater: apiLater, pairBuilder: pairBuilder, ticketBuilder: ticketBuilder, laterBuilder: laterBuilder))
	        func __safeDI_worker() -> Worker {
	            let panelBuilder = ErasedInstantiator<String, any Panel>(__safeDI_livePanel_PanelBuilder_worker.panelBuilder(SafeDIScope_LivePanel_Panel.Worker_Scope.panelBuilder_Values()))
	            return Worker(panelBuilder: panelBuilder)
	        }
	        let worker: Worker = __safeDI_worker()
	        self.init(api: api, apiLater: apiLater, pairBuilder: pairBuilder, ticketBuilder: ticketBuilder, laterBuilder: laterBuilder, worker: worker)
	    }
	}

	extension Home {
	    public enum __safeDI_Home_17349AE452A99B7C {}
	}

	"""

	/// The source the tool generated `forwardingSeamFile` from.
	private static let forwardingSeamSource = """
	import SafeDI

	public protocol Api {}
	public protocol Pair {}
	public protocol Ticket: Sendable {}
	public protocol Later {}
	public protocol Panel {}

	@Instantiable
	public struct Worker: Instantiable {
	    public init(panelBuilder: ErasedInstantiator<String, any Panel>) {
	        self.panelBuilder = panelBuilder
	    }

	    @Instantiated(fulfilledByType: "LivePanel") let panelBuilder: ErasedInstantiator<String, any Panel>
	}

	@Instantiable(generateDependencyTree: true)
	public struct Home: Instantiable {
	    public init(api: any Api, apiLater: ErasedInstantiator<(), any Api>, pairBuilder: ErasedInstantiator<(id: Int, name: String), any Pair>, ticketBuilder: SendableErasedInstantiator<Int, any Ticket>, laterBuilder: ErasedInstantiator<(), any Later>, worker: Worker) {
	        self.api = api
	        self.apiLater = apiLater
	        self.pairBuilder = pairBuilder
	        self.ticketBuilder = ticketBuilder
	        self.laterBuilder = laterBuilder
	        self.worker = worker
	    }

	    @Instantiated(fulfilledByType: "LiveApi") let api: any Api
	    @Instantiated(fulfilledByType: "LiveApi") let apiLater: ErasedInstantiator<(), any Api>
	    @Instantiated(fulfilledByType: "LivePair") let pairBuilder: ErasedInstantiator<(id: Int, name: String), any Pair>
	    @Instantiated(fulfilledByType: "LiveTicket") let ticketBuilder: SendableErasedInstantiator<Int, any Ticket>
	    @Instantiated(fulfilledByType: "LiveLater") let laterBuilder: ErasedInstantiator<(), any Later>
	    @Instantiated let worker: Worker
	}

	#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)

	"""

	/// A graph whose fixture is `forwardingSeamSource`, which the tool accepted with `generatedFile` as `Home`'s generated
	/// file.
	private static func forwardingSeamGraph(seed: UInt64, generatedFile: String) -> GraphFuzzerToolRuns {
		let fixture = GraphFuzzerFixture(seed: seed, swiftFileContent: ["\(GraphFuzzerFixture.fileNameMarker)Home.swift\n" + forwardingSeamSource])
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: ["Home+SafeDI.swift": generatedFile], warnings: [])
		return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)
	}

	/// A graph whose fixture declares `<prefix>Home` and `<prefix>Api`, which the tool accepted with `generatedSeamFile` as
	/// `<prefix>Home`'s generated file, and `extraGeneratedCode` in a generated file of its own.
	private static func seamGraph(seed: UInt64, readablePlainBuilderType: String, extraGeneratedCode: String? = nil) -> GraphFuzzerToolRuns {
		let prefix = GraphFuzzerFixture.typeNamePrefix(forSeed: seed)
		let fixture = GraphFuzzerFixture(seed: seed, swiftFileContent: ["""
		\(GraphFuzzerFixture.fileNameMarker)\(prefix)Home.swift
		public protocol \(prefix)Api {}

		public final class \(prefix)Home {
			public init(count: Int, api: any \(prefix)Api, sendableApi: any \(prefix)Api) {
				self.count = count
				self.api = api
				self.sendableApi = sendableApi
			}

			public let count: Int
			public let api: any \(prefix)Api
			public let sendableApi: any \(prefix)Api
		}

		"""])
		var generatedFiles = ["\(prefix)Home+SafeDI.swift": generatedSeamFile(prefix: prefix, readablePlainBuilderType: readablePlainBuilderType)]
		if let extraGeneratedCode {
			generatedFiles["\(prefix)Broken.swift"] = extraGeneratedCode
		}
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: generatedFiles, warnings: [])
		return GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)
	}
}
