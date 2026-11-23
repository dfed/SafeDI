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

/// A calling mock takes an optional builder for each hole type and family whose places its calls of other modules' public
/// mocks fill: passed, it replaces every such fill, and an override of the called type is handed it, so that neither is
/// ignored.
struct SafeDIToolCallingMockHoleBuilderTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – values

	/// Each combination of the builder and an override of the called type `F`, as the calling mock builds it and as the
	/// inline mock of the same types in one module builds it with `F`'s `api` overridden alike.
	enum Combination: String, CaseIterable, CustomTestStringConvertible {
		case neither
		case builderOnly
		case overrideOnly
		case both

		var testDescription: String {
			rawValue
		}

		/// The expression the calling mock's path evaluates.
		var featureExpression: String {
			switch self {
			case .neither:
				"App.Root.mock()"
			case .builderOnly:
				"App.Root.mock(apiBuilder: { App.Fake() })"
			case .overrideOnly:
				"App.Root.mock(safeDIOverrides: .init(f: { _ in Feat.F.mock(apiBuilder: { App.Other() }) }))"
			case .both:
				"App.Root.mock(apiBuilder: { App.Fake() }, safeDIOverrides: .init(f: { apiBuilder in Feat.F.mock(apiBuilder: apiBuilder) }))"
			}
		}

		/// The expression the inline path evaluates, which builds the values the calling mock should.
		var knownRightExpression: String {
			switch self {
			case .neither:
				"App.Root.mock()"
			case .builderOnly, .both:
				"App.Root.mock(safeDIOverrides: .init(f: .init(api: { App.Fake() })))"
			case .overrideOnly:
				"App.Root.mock(safeDIOverrides: .init(f: .init(api: { App.Other() })))"
			}
		}
	}

	@Test(arguments: ["@Instantiable(generateMock: true)", "@Instantiable(generateMock: .public)"], Combination.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWhatInlineBuilds_whenCallingMockIsPassedBuilderOrOverrideOfFilledHole(rootAttribute: String, combination: Combination) async throws {
		let modules = Self.modules(rootAttribute: rootAttribute)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		#expect(compilation.failure == nil, "\(compilation.failure.map { "\($0)" } ?? "")")
		guard compilation.failure == nil else { return }
		let inline = Self.inlineModules
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inline, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let comparison = try #require(try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inline),
			probes: [DifferentialValueProbe(name: "App.Root", expression: combination.featureExpression, knownRightExpression: combination.knownRightExpression)],
			filesToDelete: &filesToDelete,
		))
		for difference in comparison.differences {
			Issue.record("The calling mock builds other values than inline for \(difference)\n\(comparison.report)")
		}
	}

	// MARK: Tests – generated code

	@Test
	mutating func mock_rebindsReceiveNamedApartUnderItsLabelInsideCallsBuilderFunction_whenCallFillsBuilderAndMockPromotesLabelInTwoForms() async throws {
		// `F` receives `user: User` and its sibling `G` receives `user: Draft`, so `Root.mock()` promotes both, named apart, and
		// the call of `F`’s public mock, which fills `api` and so is made in a builder function of its own, binds `user` again
		// there from `user_User`, as the leaf receives it.
		let modules = [
			ModuleFixture(name: "Base", packageName: "Base", swiftFileContentByFilePath: [
				"BaseTypes.swift": """
				import SafeDI

				public protocol Api {}

				@Instantiable
				public struct User: Instantiable {
				    public init() {}
				}
				""",
			]),
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: [
				"FeatTypes.swift": """
				import Base
				import SafeDI

				@Instantiable(generateMock: .public)
				public struct F: Instantiable {
				    init(user: User, api: any Api) {
				        self.user = user
				        self.api = api
				    }

				    @Received let user: User
				    @Instantiated let api: any Api
				}
				""",
			], dependencies: ["Base"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import Base
				import Feat
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct Live: Api, Instantiable {
				    public init() {}
				}

				@Instantiable
				public struct Draft: Instantiable {
				    public init() {}
				}

				@Instantiable
				public struct G: Instantiable {
				    public init(user: Draft) {
				        self.user = user
				    }

				    @Received let user: Draft
				}

				@Instantiable(generateMock: true)
				public struct Root: Instantiable {
				    public init(f: F, g: G) {
				        self.f = f
				        self.g = g
				    }

				    @Instantiated let f: F
				    @Instantiated let g: G
				}
				""",
			], dependencies: ["Base", "Feat"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Base)
		import Base
		#endif
		#if canImport(Feat)
		import Feat
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user_User: (() -> User)? = nil,
		            f: F.SafeDIOverrides = .init(),
		            user_Draft: (() -> Draft)? = nil,
		            g: ((Draft) -> G)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user_User: user_User,
		                f: f,
		                user_Draft: user_Draft,
		                g: g
		            )
		        }

		        var user_User: (() -> User)? { __safeDI_storage.user_User }
		        var f: F.SafeDIOverrides { __safeDI_storage.f }
		        var user_Draft: (() -> Draft)? { __safeDI_storage.user_Draft }
		        var g: ((Draft) -> G)? { __safeDI_storage.g }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user_User: (() -> User)?,
		                f: F.SafeDIOverrides,
		                user_Draft: (() -> Draft)?,
		                g: ((Draft) -> G)?
		            ) {
		                self.user_User = user_User
		                self.f = f
		                self.user_Draft = user_Draft
		                self.g = g
		            }

		            let user_User: (() -> User)?
		            let f: F.SafeDIOverrides
		            let user_Draft: (() -> Draft)?
		            let g: ((Draft) -> G)?
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let user_User = if let safeDIBuilder = safeDIOverrides.user_User { safeDIBuilder() } else { User() }
		        func __safeDI_f() -> F {
		            func __safeDI_apiBuilder_F() -> F.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { _ in
		                    let api: any Api = Live()
		                    return api
		                })
		            }
		            _ = F.__safeDI_F_mock_5CBE8C3D67CB9542.self // If this line does not compile, compile the code SafeDI generates for module Feat into Feat: under Bazel, add Feat’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            let user: User? = user_User
		            return F.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F(), user: user, safeDIOverrides: safeDIOverrides.f)
		        }
		        let f: F = __safeDI_f()
		        let user_Draft = if let safeDIBuilder = safeDIOverrides.user_Draft { safeDIBuilder() } else { Draft() }
		        func __safeDI_g() -> G {
		            let user: Draft = user_Draft
		            return if let safeDIBuilder = safeDIOverrides.g { safeDIBuilder(user) } else { G(user: user) }
		        }
		        let g: G = __safeDI_g()
		        return Root(f: f, g: g)
		    }
		}
		#endif
		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Root`, in module `App`, instantiates `F`, whose public mock module `Feat` generates, and `F` instantiates `api`,
	/// which only `App`'s `Live` fulfills: `Root`'s mock calls `F`'s and fills `api` with `Live`.
	private static func modules(rootAttribute: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Base", packageName: "Base", swiftFileContentByFilePath: [
				"BaseTypes.swift": """
				import SafeDI

				public protocol Api {}
				""",
			]),
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: [
				"FeatTypes.swift": """
				import Base
				import SafeDI

				@Instantiable(generateMock: .public)
				public struct F: Instantiable {
				    init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated let api: any Api
				}
				""",
			], dependencies: ["Base"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import Base
				import Feat
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public struct Live: Api, Instantiable {
				    public init() {}
				}

				public struct Fake: Api {
				    public init() {}
				}

				public struct Other: Api {
				    public init() {}
				}

				\(rootAttribute)
				public struct Root: Instantiable {
				    public init(f: F) {
				        self.f = f
				    }

				    @Instantiated let f: F
				}
				""",
			], dependencies: ["Base", "Feat"]),
		]
	}

	/// The same types in one module, whose mock builds `F` inline.
	private static let inlineModules = [
		ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
			"AppTypes.swift": """
			import SafeDI

			public protocol Api {}

			@Instantiable
			public struct F: Instantiable {
			    init(api: any Api) {
			        self.api = api
			    }

			    @Instantiated let api: any Api
			}

			@Instantiable(fulfillingAdditionalTypes: [Api.self])
			public struct Live: Api, Instantiable {
			    public init() {}
			}

			public struct Fake: Api {
			    public init() {}
			}

			public struct Other: Api {
			    public init() {}
			}

			@Instantiable(generateMock: true)
			public struct Root: Instantiable {
			    public init(f: F) {
			        self.f = f
			    }

			    @Instantiated let f: F
			}
			""",
		]),
	]
}
