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
/// `{ make() }` or a stored closure `make` of the family the builder struct names, must compile.
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

	// MARK: The compile

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
