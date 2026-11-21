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

/// The oracle that no initializer only generated code calls gives a parameter a default
/// (`GraphFuzzerGeneratedOnlyInitializerDefaults.parametersWithDefaults(in:)`).
struct SafeDIToolGraphFuzzerGeneratedOnlyInitializerDefaultTests {
	@Test
	func parametersWithDefaults_reportsParameter_whenSeamGeneratedOnlyInitializerGivesDefault() {
		let findings = GraphFuzzerGeneratedOnlyInitializerDefaults.parametersWithDefaults(in: [
			"Feed/Feature+SafeDI.swift": Self.featureSeam(themeParameter: "__safeDI_theme theme: Theme? = nil"),
		])

		#expect(findings == [
			"`Feed/Feature+SafeDI.swift` line 6: `Feature`’s initializer only generated code calls gives `__safeDI_theme` a default: __safeDI_theme theme: Theme? = nil",
		])
	}

	@Test
	func parametersWithDefaults_isEmpty_whenSeamGeneratedOnlyInitializerGivesNoDefault() {
		let files = ["Feed/Feature+SafeDI.swift": Self.featureSeam(themeParameter: "__safeDI_theme theme: Theme?")]

		#expect(GraphFuzzerGeneratedOnlyInitializerDefaults.parametersWithDefaults(in: files) == [])
		#expect(GraphFuzzerGeneratedOnlyInitializerDefaults.initializerCount(in: files) == 1)
	}

	@Test
	func parametersWithDefaults_reportsParameter_whenBuilderStructNoScopeInitializerGivesDefault() {
		let findings = GraphFuzzerGeneratedOnlyInitializerDefaults.parametersWithDefaults(in: [
			"Feed/Home+SafeDI.swift": """
			extension Home {
			    public enum SafeDIScope_Api {
			        public struct __safeDI_Builder<__safeDI_Built> {
			            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built = { fatalError() }) {
			                self.place = { _ in __safeDI_builder() }
			            }

			            public let place: (Int) -> __safeDI_Built
			        }
			    }
			}
			""",
		])

		#expect(findings == [
			"`Feed/Home+SafeDI.swift` line 4: `Home.SafeDIScope_Api.__safeDI_Builder`’s initializer only generated code calls gives `__safeDI_noScope` a default: __safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built = { fatalError() }",
		])
	}

	@Test
	func parametersWithDefaults_isEmpty_whenInitializerMeantForPeopleGivesDefault() {
		// A plain initializer and a configuration's are called by code people write, whose defaults are their API.
		let files = ["Feed/Feature+SafeDIMock.swift": """
		extension Feature {
		    public struct SafeDIOverrides {
		        public init(theme: (() -> Theme)? = nil) {
		            self.theme = theme
		        }

		        public let theme: (() -> Theme)?
		    }
		}
		"""]

		#expect(GraphFuzzerGeneratedOnlyInitializerDefaults.parametersWithDefaults(in: files) == [])
		#expect(GraphFuzzerGeneratedOnlyInitializerDefaults.initializerCount(in: files) == 0)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generatedOnlyInitializerTakesDefaultFailure_reportsFailure_whenAcceptedGraphGivesDefault() {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [])
		let outcome = GraphFuzzerToolOutcome.accepted(generatedFiles: [
			"Feed/Feature+SafeDI.swift": Self.featureSeam(themeParameter: "__safeDI_theme theme: Theme? = nil"),
		], warnings: [])
		let runs = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)

		#expect(runs.generatedOnlyInitializerTakesDefaultFailure?.kind == .generatedOnlyInitializerTakesDefault)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generatedOnlyInitializerTakesDefaultFailure_isNil_whenToolGeneratesSeamWithOnlyIfAvailableParameter() async throws {
		let fixture = GraphFuzzerFixture(seed: 1, swiftFileContent: [
			"""
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(feature: Feature) {
			        self.feature = feature
			    }

			    @Instantiated let feature: Feature
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public final class Feature: Instantiable {
			    public init(theme: Theme?, panel: Panel) {
			        self.theme = theme
			        self.panel = panel
			    }

			    @Received(onlyIfAvailable: true) let theme: Theme?
			    @Instantiated let panel: Panel
			}
			""",
			"""
			@Instantiable
			public final class Panel: Instantiable {
			    public init(theme: Theme?) {
			        self.theme = theme
			    }

			    @Received(onlyIfAvailable: true) let theme: Theme?
			}
			""",
			"""
			@Instantiable
			public final class Theme: Instantiable {
			    public init() {}
			}
			""",
		])
		let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixture)
		let runs = GraphFuzzerToolRuns(fixture: fixture, firstOutcome: outcome, secondOutcome: outcome)

		#expect(runs.generatedOnlyInitializerCount > 0)
		#expect(runs.generatedOnlyInitializerTakesDefaultFailure == nil)
	}

	/// A seam's initializer only generated code calls, taking `theme` as `themeParameter` spells it.
	private static func featureSeam(themeParameter: String) -> String {
		"""
		extension Feature {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    public convenience init(
		        __safeDI_panel panel: Panel,
		        __safeDI_analytics analytics: LazilyInstantiated<Analytics>,
		        \(themeParameter)
		    ) {
		        self.init(panel: panel, analytics: analytics.instance, theme: theme)
		    }
		}

		extension Feature {
		    public enum __safeDI_Feature_8A1B {}
		}
		"""
	}
}
