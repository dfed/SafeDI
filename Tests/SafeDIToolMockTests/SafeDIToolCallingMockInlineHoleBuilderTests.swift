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

/// A calling mock builds inline a public mock of another module whose tree the calling module can construct, rather
/// than calling it: the places of that tree that are holes of the public mock's module read the builder `mock()` takes
/// for their hole type and family, as they do where the mock calls that public mock, unless the place's own override is
/// set.
struct SafeDIToolCallingMockInlineHoleBuilderTests: ~Copyable {
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

	/// What a test passes the calling mock of `Root`, which calls `F`'s public mock and builds `G` inline, and what the
	/// inline mock of the same types in one module is passed to build the same values.
	enum Passed: String, CaseIterable, CustomTestStringConvertible {
		case nothing
		case builder
		case builderAndPlaceOverride

		var testDescription: String {
			rawValue
		}

		/// The expression the calling mock's path evaluates.
		var featureExpression: String {
			switch self {
			case .nothing:
				"App.Root.mock()"
			case .builder:
				"App.Root.mock(apiBuilder: { App.Fake() })"
			case .builderAndPlaceOverride:
				"App.Root.mock(apiBuilder: { App.Fake() }, safeDIOverrides: .init(g: .init(api: { App.Other() })))"
			}
		}

		/// The expression the inline path evaluates, which builds the values the calling mock should: `G`'s place is
		/// built as `F`'s is, by the builder, unless its own override is set.
		var knownRightExpression: String {
			switch self {
			case .nothing:
				"App.Root.mock()"
			case .builder:
				"App.Root.mock(safeDIOverrides: .init(f: .init(api: { App.Fake() }), g: .init(api: { App.Fake() })))"
			case .builderAndPlaceOverride:
				"App.Root.mock(safeDIOverrides: .init(f: .init(api: { App.Fake() }), g: .init(api: { App.Other() })))"
			}
		}
	}

	@Test(arguments: ["@Instantiable(generateMock: true)", "@Instantiable(generateMock: .public)"], Passed.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsInlineBuiltPublicMocksPlaceWithBuilder_whenBuilderIsPassed(rootAttribute: String, passed: Passed) async throws {
		let modules = Self.modules(rootAttribute: rootAttribute)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		#expect(compilation.failure == nil, "\(compilation.failure.map { "\($0)" } ?? "")")
		guard compilation.failure == nil else { return }
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: Self.inlineModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let comparison = try #require(try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: Self.inlineModules),
			probes: [DifferentialValueProbe(name: "App.Root", expression: passed.featureExpression, knownRightExpression: passed.knownRightExpression)],
			filesToDelete: &filesToDelete,
		))
		for difference in comparison.differences {
			Issue.record("The calling mock builds other values than inline for \(difference)\n\(comparison.report)")
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Root`, in module `App`, instantiates `F` and `G`, whose public mocks module `Feat` generates, and each instantiates
	/// `api`, which only `App`'s `Live` fulfills. `F`'s initializer is internal, so `Root`'s mock calls `F`'s mock and
	/// fills `api`, taking `apiBuilder` for it; `G`'s is public, so the mock builds `G` inline.
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

				    @Instantiated public let api: any Api
				}

				@Instantiable(generateMock: .public)
				public struct G: Instantiable {
				    public init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated public let api: any Api
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
	}

	/// The same types in one module, whose mock builds `F` and `G` inline.
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

			    @Instantiated public let api: any Api
			}

			@Instantiable
			public struct G: Instantiable {
			    public init(api: any Api) {
			        self.api = api
			    }

			    @Instantiated public let api: any Api
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
			    public init(f: F, g: G) {
			        self.f = f
			        self.g = g
			    }

			    @Instantiated let f: F
			    @Instantiated let g: G
			}
			""",
		]),
	]
}
