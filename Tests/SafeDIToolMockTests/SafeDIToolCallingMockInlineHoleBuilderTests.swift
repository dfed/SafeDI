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

	@Test(arguments: Self.inlineBuildingRootAttributes, Passed.allCases)
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

	/// The form of the place `F` and `G` hold, which only `App`'s `Live` fulfills, and how a probe reads and replaces it.
	enum WrappedPlace: String, CaseIterable, CustomTestStringConvertible {
		case erasedInstantiator
		case sendableErasedInstantiator
		case lazilyInstantiated

		var testDescription: String {
			rawValue
		}

		var declaration: String {
			switch self {
			case .erasedInstantiator:
				#"@Instantiated(fulfilledByType: "Live") public let api: ErasedInstantiator<Int, any Api>"#
			case .sendableErasedInstantiator:
				#"@Instantiated(fulfilledByType: "Live") public let api: SendableErasedInstantiator<Int, any Api>"#
			case .lazilyInstantiated:
				#"@Instantiated(fulfilledByType: "Live", erasedToConcreteExistential: false) public let api: LazilyInstantiated<any Api>"#
			}
		}

		var parameter: String {
			switch self {
			case .erasedInstantiator:
				"api: ErasedInstantiator<Int, any Api>"
			case .sendableErasedInstantiator:
				"api: SendableErasedInstantiator<Int, any Api>"
			case .lazilyInstantiated:
				"api: LazilyInstantiated<any Api>"
			}
		}

		/// The label of the builder `mock()` takes for the hole type, `Live` building `any Api`.
		var builderLabel: String {
			switch self {
			case .erasedInstantiator, .lazilyInstantiated:
				"live_ApiBuilder"
			case .sendableErasedInstantiator:
				"live_ApiSendableBuilder"
			}
		}

		/// The value the place holds, read from `G` or `F`.
		func read(from owner: String) -> String {
			switch self {
			case .erasedInstantiator, .sendableErasedInstantiator:
				"\(owner).api.instantiate(7)"
			case .lazilyInstantiated:
				"\(owner).api.instance"
			}
		}

		/// A closure that builds `type`, as the builder and the place's override take it.
		func closure(building type: String) -> String {
			switch self {
			case .erasedInstantiator, .sendableErasedInstantiator:
				"{ App.\(type)(id: $0) }"
			case .lazilyInstantiated:
				"{ App.\(type)(id: 7) }"
			}
		}

		/// `Live`, which forwards the instantiators' value.
		var live: String {
			switch self {
			case .erasedInstantiator, .sendableErasedInstantiator:
				"""
				@Instantiable
				public final class Live: Api, Instantiable, Sendable {
				    public init(id: Int) { self.id = id }
				    @Forwarded public let id: Int
				}
				"""
			case .lazilyInstantiated:
				"""
				@Instantiable
				public final class Live: Api, Instantiable, Sendable {
				    public init() {}
				}
				"""
			}
		}
	}

	@Test(arguments: Self.inlineBuildingRootAttributes, WrappedPlace.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsInlineBuiltPublicMocksWrappedPlaceWithBuilder_whenBuilderIsPassed(rootAttribute: String, place: WrappedPlace) async throws {
		let modules = Self.wrappedPlaceModules(rootAttribute: rootAttribute, place: place)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		let builder = "\(place.builderLabel): \(place.closure(building: "Fake"))"
		try await expectValues(of: output, modules: modules, pairs: [
			("\(place.read(from: "App.Root.mock().g")) is App.Live", "true"),
			("\(place.read(from: "App.Root.mock(\(builder)).g")) is App.Fake", "true"),
			("\(place.read(from: "App.Root.mock(\(builder)).f")) is App.Fake", "true"),
			("\(place.read(from: "App.Root.mock(\(builder), safeDIOverrides: .init(g: .init(api: \(place.closure(building: "Other"))))).g")) is App.Other", "true"),
		])
	}

	@Test(arguments: Self.inlineBuildingRootAttributes)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsPlaceOfPublicMockBuiltInlineInsideFillWithBuilder_whenBuilderIsPassed(rootAttribute: String) async throws {
		let modules = Self.insideFillModules(rootAttribute: rootAttribute)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		try await expectValues(of: output, modules: modules, pairs: [
			("(App.Root.mock().f.api as! App.Live).g.store is App.LiveStore", "true"),
			("(App.Root.mock(storeBuilder: { App.FakeStore() }).f.api as! App.Live).g.store is App.FakeStore", "true"),
			("App.Root.mock(storeBuilder: { App.FakeStore() }).h.store is App.FakeStore", "true"),
		])
	}

	@Test(arguments: Self.inlineBuildingRootAttributes, WrappedPlace.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWrappedPlaceOfPublicMockBuiltInlineInsideFillWithBuilder_whenBuilderIsPassed(rootAttribute: String, place: WrappedPlace) async throws {
		let modules = Self.wrappedPlaceInsideFillModules(rootAttribute: rootAttribute, place: place)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		let builder = "\(place.builderLabel): \(place.closure(building: "Fake"))"
		try await expectValues(of: output, modules: modules, pairs: [
			("\(place.read(from: "(App.Root.mock().f.shell as! App.Shell).g")) is App.Live", "true"),
			("\(place.read(from: "(App.Root.mock(\(builder)).f.shell as! App.Shell).g")) is App.Fake", "true"),
			("\(place.read(from: "App.Root.mock(\(builder)).h")) is App.Fake", "true"),
		])
	}

	// MARK: Tests – work

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_resolvesWhatPublicMocksModuleSeesOncePerWalk_whenInlineBuiltPublicMockHoldsManyPlaces() async throws {
		// `G`, built inline by `Root`'s mock, holds one place beside `api` or twenty: the walk of the places built inline
		// asked at each scope beneath `G` whether `Feat` sees its type, and resolved what `Feat` sees again each time.
		var resolutions = [Int]()
		for leafCount in [1, 20] {
			let modules = Self.modules(rootAttribute: "@Instantiable(generateMock: true)", leafCountOfG: leafCount)
			let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
			_ = try await GenerationWork.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) { [modules] in
				try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			}
			continuation.finish()
			var resolved = 0
			for await work in stream where work.step == .resolvingWhatAPublicMocksModuleSees {
				resolved += work.elementCount
			}
			resolutions.append(resolved)
		}
		#expect(resolutions == [1, 1])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The calling mock that builds `G` inline: an internal one. A `.public` mock calls `G`'s public mock instead, since it
	/// takes a required builder as a struct with no member for a place it would build inline
	/// (`DependencyTreeGenerator.publicMockCalls`), which the graph fuzzer's seed 763 checks.
	private static let inlineBuildingRootAttributes = ["@Instantiable(generateMock: true)"]

	/// Compares what each probe's first expression evaluates to in the generated mocks with its second.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValues(of output: MultiModuleTestOutput, modules: [ModuleFixture], pairs: [(String, String)]) async throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		#expect(compilation.failure == nil, "\(compilation.failure.map { "\($0)" } ?? "")")
		guard compilation.failure == nil else { return }
		let graph = DifferentialValueGraph(
			name: "",
			path: try DifferentialValuePath(output: output, modules: modules),
			probePairs: pairs.map { DifferentialValueProbePair(name: $0.0, featureExpression: $0.0, knownRightExpression: $0.1) },
		)
		let comparisons = try #require(try await DifferentialValueOracle.compare(graphs: [graph], filesToDelete: &filesToDelete))
		for comparison in comparisons {
			let result = try comparison.result.get()
			for difference in result.differences {
				Issue.record("The mock builds another value than expected for \(difference)\n\(result.report)")
			}
		}
	}

	/// `Root`, in module `App`, instantiates `F` and `G` of module `Feat`, each holding `api` in `place`'s form, which only
	/// `App`'s `Live` fulfills. `F`'s initializer is internal, so `Root`'s mock calls `F`'s mock and fills `api`, taking
	/// the builder of its hole type; `G`'s is public, so the mock builds `G` inline.
	private static func wrappedPlaceModules(rootAttribute: String, place: WrappedPlace) -> [ModuleFixture] {
		let types = [("F", ""), ("G", "public ")].map { name, access in
			"""
			@Instantiable(generateMock: .public)
			public final class \(name): Instantiable {
			    \(access)init(\(place.parameter)) {
			        self.api = api
			    }

			    \(place.declaration)
			}
			"""
		}
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: [
				"FeatTypes.swift": (["import SafeDI\n\npublic protocol Api {}"] + types).joined(separator: "\n\n"),
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import Feat
				import SafeDI

				\(place.live)

				public final class Fake: Api, Sendable {
				    public init(id: Int) {}
				}

				public final class Other: Api, Sendable {
				    public init(id: Int) {}
				}

				\(rootAttribute)
				public final class Root: Instantiable {
				    public init(f: F, g: G) {
				        self.f = f
				        self.g = g
				    }

				    @Instantiated public let f: F
				    @Instantiated public let g: G
				}
				""",
			], dependencies: ["Feat"]),
		]
	}

	/// `Root`, in module `App`, calls the public mocks of `F` and `H` of module `Feat`. `F`'s place of `any Api` is filled
	/// with `App`'s `Live`, which instantiates `G`, whose public initializer lets the fill build it inline, and `G` and
	/// `H` each hold a place of `any Store`, which only `App`'s `LiveStore` fulfills: `H`'s call fills it, so `mock()` takes
	/// `storeBuilder`, which `G`'s place inside the fill reads too.
	private static func insideFillModules(rootAttribute: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: [
				"FeatTypes.swift": """
				import SafeDI

				public protocol Api {}

				public protocol Store {}

				@Instantiable(generateMock: .public)
				public final class F: Instantiable {
				    init(api: any Api) {
				        self.api = api
				    }

				    @Instantiated public let api: any Api
				}

				@Instantiable(generateMock: .public)
				public final class G: Instantiable {
				    public init(store: any Store) {
				        self.store = store
				    }

				    @Instantiated public let store: any Store
				}

				@Instantiable(generateMock: .public)
				public final class H: Instantiable {
				    init(store: any Store) {
				        self.store = store
				    }

				    @Instantiated public let store: any Store
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import Feat
				import SafeDI

				@Instantiable(fulfillingAdditionalTypes: [Api.self])
				public final class Live: Api, Instantiable {
				    public init(g: G) {
				        self.g = g
				    }

				    @Instantiated public let g: G
				}

				@Instantiable(fulfillingAdditionalTypes: [Store.self])
				public final class LiveStore: Store, Instantiable {
				    public init() {}
				}

				public final class FakeStore: Store {
				    public init() {}
				}

				\(rootAttribute)
				public final class Root: Instantiable {
				    public init(f: F, h: H) {
				        self.f = f
				        self.h = h
				    }

				    @Instantiated public let f: F
				    @Instantiated public let h: H
				}
				""",
			], dependencies: ["Feat"]),
		]
	}

	/// `Root`, in module `App`, calls the public mocks of `F` and `H` of module `Feat`. `F`'s place of `any Container` is
	/// filled with `App`'s `Shell`, which instantiates `G`, whose public initializer lets the fill build it inline. `G` and
	/// `H` each hold `api` in `place`'s form, which only `App`'s `Live` fulfills: `H`'s call fills it, so `mock()` takes the
	/// builder of its hole type, which `G`'s place inside the fill reads too. `G` also holds a `Clock` its own module builds,
	/// so the fill asks twice what `Feat` sees.
	private static func wrappedPlaceInsideFillModules(rootAttribute: String, place: WrappedPlace) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: [
				"FeatTypes.swift": """
				import SafeDI

				public protocol Api {}

				public protocol Container {}

				@Instantiable
				public final class Clock: Instantiable {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public final class F: Instantiable {
				    init(shell: any Container) {
				        self.shell = shell
				    }

				    @Instantiated public let shell: any Container
				}

				@Instantiable(generateMock: .public)
				public final class G: Instantiable {
				    public init(clock: Clock, \(place.parameter)) {
				        self.clock = clock
				        self.api = api
				    }

				    @Instantiated public let clock: Clock
				    \(place.declaration)
				}

				@Instantiable(generateMock: .public)
				public final class H: Instantiable {
				    init(\(place.parameter)) {
				        self.api = api
				    }

				    \(place.declaration)
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import Feat
				import SafeDI

				\(place.live)

				public final class Fake: Api, Sendable {
				    public init(id: Int) {}
				}

				@Instantiable(fulfillingAdditionalTypes: [Container.self])
				public final class Shell: Container, Instantiable {
				    public init(g: G) {
				        self.g = g
				    }

				    @Instantiated public let g: G
				}

				\(rootAttribute)
				public final class Root: Instantiable {
				    public init(f: F, h: H) {
				        self.f = f
				        self.h = h
				    }

				    @Instantiated public let f: F
				    @Instantiated public let h: H
				}
				""",
			], dependencies: ["Feat"]),
		]
	}

	/// `Root`, in module `App`, instantiates `F` and `G`, whose public mocks module `Feat` generates, and each instantiates
	/// `api`, which only `App`'s `Live` fulfills. `F`'s initializer is internal, so `Root`'s mock calls `F`'s mock and
	/// fills `api`, taking `apiBuilder` for it; `G`'s is public, so the mock builds `G` inline.
	/// `G` holds `leafCountOfG` places of `Feat`'s own types beside `api`, which `Feat` sees.
	private static func modules(rootAttribute: String, leafCountOfG: Int = 0) -> [ModuleFixture] {
		let leaves = (0..<leafCountOfG).map { "\n\n@Instantiable\npublic struct Leaf\($0): Instantiable {\n    public init() {}\n}" }.joined()
		let leafProperties = (0..<leafCountOfG).map { "\n    @Instantiated public let leaf\($0): Leaf\($0)" }.joined()
		let leafParameters = (0..<leafCountOfG).map { ", leaf\($0): Leaf\($0)" }.joined()
		let leafAssignments = (0..<leafCountOfG).map { "\n        self.leaf\($0) = leaf\($0)" }.joined()
		return [
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
				    public init(api: any Api\(leafParameters)) {
				        self.api = api\(leafAssignments)
				    }

				    @Instantiated public let api: any Api\(leafProperties)
				}
				""" + leaves,
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
