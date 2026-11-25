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

/// A public mock takes its type's own optional-typed default-valued parameter as a parameter of `mock()` that defaults to
/// the declaration's default, as an internal mock does, whatever the type's isolation and whether it builds anything, so
/// that `Banner.mock(title: "Sale", note: "Ends Friday")` is one call for every type a test in another module mocks.
struct SafeDIToolPublicMockOwnDefaultTests: ~Copyable {
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
	mutating func generate_takesOwnOptionalDefaultAsMockParameter_whetherTypeIsNonisolatedOnMainActorOrBuildsNothing() async throws {
		// `Banner` is not bound to an actor and builds a `Logger`, `BannerView` is the same type on the main actor, and
		// `BannerModel` builds nothing: each takes `note` on `mock()`, defaulting to its provider, so a test in another
		// package makes the same call on all three.
		let modules = Self.modules(appFiles: ["Calls.swift": Self.sameCallOnEveryBanner])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == [
			"Feed.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Banner {
			    @usableFromInline static func __safeDI_publicMockDefault_note() -> String? { "x" }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            logger: (() -> Logger)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                logger: logger
			            )
			        }

			        public var logger: (() -> Logger)? { __safeDI_storage.logger }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                logger: (() -> Logger)?
			            ) {
			                self.logger = logger
			            }

			            let logger: (() -> Logger)?
			        }
			    }

			    public static func mock(
			        title: String? = nil,
			        note: String? = Banner.__safeDI_publicMockDefault_note(),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Banner {
			        Banner.__safeDI_mock(title: title, note: note, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        title: String? = nil,
			        note: String? = Banner.__safeDI_publicMockDefault_note(),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Banner {
			        let title = title ?? ("Hello")
			        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
			        return Banner(logger: logger, title: title, note: note)
			    }
			}

			extension Banner {
			    public enum __safeDI_Banner_mock_0B93BE1CE3B20378 {}
			}
			#endif

			#if DEBUG
			extension BannerModel {
			    @usableFromInline static func __safeDI_publicMockDefault_note() -> String? { "x" }

			    public static func mock(
			        title: String? = nil,
			        note: String? = BannerModel.__safeDI_publicMockDefault_note()
			    ) -> BannerModel {
			        BannerModel.__safeDI_mock(title: title, note: note)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        title: String? = nil,
			        note: String? = BannerModel.__safeDI_publicMockDefault_note()
			    ) -> BannerModel {
			        let title = title ?? ("Hello")
			        return BannerModel(title: title, note: note)
			    }
			}

			extension BannerModel {
			    public enum __safeDI_BannerModel_mock_4BBE6BDEBF1855D9 {}
			}
			#endif

			#if DEBUG
			extension BannerView {
			    @usableFromInline static func __safeDI_publicMockDefault_note() -> String? { "x" }

			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            logger: (() -> Logger)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                logger: logger
			            )
			        }

			        public var logger: (() -> Logger)? { __safeDI_storage.logger }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                logger: (() -> Logger)?
			            ) {
			                self.logger = logger
			            }

			            let logger: (() -> Logger)?
			        }
			    }

			    public static func mock(
			        title: String? = nil,
			        note: String? = BannerView.__safeDI_publicMockDefault_note(),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> BannerView {
			        BannerView.__safeDI_mock(title: title, note: note, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        title: String? = nil,
			        note: String? = BannerView.__safeDI_publicMockDefault_note(),
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> BannerView {
			        let title = title ?? ("Hello")
			        let logger = if let safeDIBuilder = safeDIOverrides.logger { safeDIBuilder() } else { Logger() }
			        return BannerView(logger: logger, title: title, note: note)
			    }
			}

			extension BannerView {
			    public enum __safeDI_BannerView_mock_0B93BE1CE3B20378 {}
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsInternalMocksValues_whenTestInAnotherPackagePassesOwnOptionalDefaultAndCallingMockLeavesIt() async throws {
		// A test in another package passes `note` to `Banner.mock()`, and `Shelf`'s mock there calls `Banner.mock()`, which
		// it passes no `note`: both build what the internal mocks build when every declaration is in one module.
		let modules = Self.modules(appFiles: ["Shelf.swift": Self.shelf])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Feed)
			import Feed
			#endif
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Shelf {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            banner: Banner.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                banner: banner
			            )
			        }

			        var banner: Banner.SafeDIOverrides { __safeDI_storage.banner }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                banner: Banner.SafeDIOverrides
			            ) {
			                self.banner = banner
			            }

			            let banner: Banner.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Shelf {
			        _ = Banner.__safeDI_Banner_mock_0B93BE1CE3B20378.self // If this line does not compile, compile the code SafeDI generates for module Feed into Feed: under Bazel, add Feed’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			        let banner = Banner.__safeDI_mock(safeDIOverrides: safeDIOverrides.banner)
			        return Shelf(banner: banner)
			    }
			}
			#endif
			""",
		])
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe("Banner.mock(title: \"Sale\", note: \"Ends Friday\")"),
			DifferentialValueProbe("Banner.mock(note: nil)"),
			DifferentialValueProbe("BannerModel.mock(title: \"Sale\", note: \"Ends Friday\")"),
			DifferentialValueProbe("Shelf.mock()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_evaluatesOwnOptionalDefaultInMocksIsolation_whenTypeTakesItFromConformanceOrFromGlobalActorNotNamedActor() async throws {
		// `Poster` is on the main actor only through `Screen`, and `Crate` is bound to `Storage`, a global actor whose name
		// does not end in `Actor`. Each default reads its actor's state, so it compiles only in that actor's isolation,
		// which each provider takes from the extension it shares with `mock()`: SafeDI reads no isolation.
		let modules = [
			ModuleFixture(name: "Store", packageName: "store", swiftFileContentByFilePath: ["Store.swift": """
			import SafeDI

			@MainActor
			public protocol Screen {}

			@MainActor
			public enum Theme {
			    public static var accent: String? = "blue"
			}

			@Instantiable(generateMock: .public)
			public final class Poster: Screen, Instantiable {
			    public init(accent: String? = Theme.accent) {
			        self.accent = accent
			    }

			    public let accent: String?
			}

			@globalActor
			public actor Storage {
			    public static let shared = Storage()
			}

			@Storage
			public enum Shelf {
			    public static var label: String? = "top"
			}

			@Storage
			@Instantiable(generateMock: .public)
			public final class Crate: Instantiable {
			    public init(label: String? = Shelf.label) {
			        self.label = label
			    }

			    public let label: String?
			}
			"""]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Store"]?.generatedFiles == [
			"Store.swift": generatedFileHeader + """
			#if canImport(SafeDI)
			import SafeDI
			#endif

			#if DEBUG
			extension Crate {
			    @usableFromInline static func __safeDI_publicMockDefault_label() -> String? { Shelf.label }

			    public static func mock(
			        label: String? = Crate.__safeDI_publicMockDefault_label()
			    ) -> Crate {
			        Crate.__safeDI_mock(label: label)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        label: String? = Crate.__safeDI_publicMockDefault_label()
			    ) -> Crate {
			        return Crate(label: label)
			    }
			}

			extension Crate {
			    public enum __safeDI_Crate_mock_60427B5233F1F2E1 {}
			}
			#endif

			#if DEBUG
			extension Poster {
			    @usableFromInline static func __safeDI_publicMockDefault_accent() -> String? { Theme.accent }

			    public static func mock(
			        accent: String? = Poster.__safeDI_publicMockDefault_accent()
			    ) -> Poster {
			        Poster.__safeDI_mock(accent: accent)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        accent: String? = Poster.__safeDI_publicMockDefault_accent()
			    ) -> Poster {
			        return Poster(accent: accent)
			    }
			}

			extension Poster {
			    public enum __safeDI_Poster_mock_E4DF61718BCCF443 {}
			}
			#endif
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Feed`, which declares the three banners, in package `feed`, and `App`, which holds `appFiles`, in package `app`,
	/// which cannot build a `Logger`.
	private static func modules(appFiles: [String: String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feed", packageName: "feed", swiftFileContentByFilePath: ["Banner.swift": banners]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: appFiles, dependencies: ["Feed"]),
		]
	}

	private static let banners = """
	import SafeDI

	/// Only `Feed`'s package can build a `Logger`, so a mock in `App` that builds a `Banner` calls `Banner`'s public mock.
	@Instantiable
	public final class Logger: Instantiable {
	    package init() {}
	}

	/// Not bound to an actor, builds a `Logger`.
	@Instantiable(generateMock: .public)
	public final class Banner: Instantiable {
	    public init(logger: Logger, title: String = "Hello", note: String? = "x") {
	        self.logger = logger
	        self.title = title
	        self.note = note
	    }

	    @Instantiated private let logger: Logger
	    public let title: String
	    public let note: String?
	}

	/// The same type on the main actor.
	@MainActor
	@Instantiable(generateMock: .public)
	public final class BannerView: Instantiable {
	    public init(logger: Logger, title: String = "Hello", note: String? = "x") {
	        self.logger = logger
	        self.title = title
	        self.note = note
	    }

	    @Instantiated private let logger: Logger
	    public let title: String
	    public let note: String?
	}

	/// Not bound to an actor, builds nothing.
	@Instantiable(generateMock: .public)
	public final class BannerModel: Instantiable {
	    public init(title: String = "Hello", note: String? = "x") {
	        self.title = title
	        self.note = note
	    }

	    public let title: String
	    public let note: String?
	}
	"""

	/// The call a test of each banner makes, which an internal mock takes too.
	private static let sameCallOnEveryBanner = """
	import Feed

	#if DEBUG
	@MainActor
	func bannerTests() {
	    let banner = Banner.mock(title: "Sale", note: "Ends Friday")
	    let bannerView = BannerView.mock(title: "Sale", note: "Ends Friday")
	    let bannerModel = BannerModel.mock(title: "Sale", note: "Ends Friday")
	    let bannerWithoutNote = Banner.mock(note: nil, safeDIOverrides: .init(logger: nil))
	    _ = (banner, bannerView, bannerModel, bannerWithoutNote)
	}
	#endif
	"""

	/// A mocked type of `App` that builds a `Banner`, whose mock calls `Banner`'s public mock.
	private static let shelf = """
	import Feed
	import SafeDI

	@Instantiable(generateMock: true)
	public final class Shelf: Instantiable {
	    public init(banner: Banner) {
	        self.banner = banner
	    }

	    @Instantiated public let banner: Banner
	}
	"""

	/// Compares the values the mocks of `modules`, as `output` generated them, build for `probes` with what internal
	/// mocks build inline when every declaration of `modules` is in one module and every public mock is internal.
	private mutating func expectValuesAgreeWithInlineMocks(
		of modules: [ModuleFixture],
		output: MultiModuleTestOutput,
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let moduleNames = Set(modules.map(\.name))
		func inline(_ source: String) -> String {
			source
				.split(separator: "\n", omittingEmptySubsequences: false)
				.filter { line in !moduleNames.contains { line == "import \($0)" } }
				.joined(separator: "\n")
				.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")
		}
		var inlineFiles = [String: String]()
		for module in modules {
			for (fileName, content) in module.swiftFileContentByFilePath {
				inlineFiles["\(module.name)_\(fileName)"] = inline(content)
			}
		}
		let inlineModules = [ModuleFixture(name: modules[0].name, packageName: modules[0].packageName, swiftFileContentByFilePath: inlineFiles)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		func path(of modules: [ModuleFixture], output: MultiModuleTestOutput) throws -> DifferentialValuePath {
			try DifferentialValuePath(modules: modules.map { module in
				try DifferentialValueModule(
					name: module.name,
					packageName: module.packageName,
					dependencyModuleNames: module.dependencies,
					fixtureFiles: module.swiftFileContentByFilePath,
					generatedFiles: #require(output.modules[module.name], sourceLocation: sourceLocation).generatedFiles,
				)
			})
		}
		try await expectDifferentialValuesAgree(
			feature: path(of: modules, output: output),
			knownRight: path(of: inlineModules, output: inlineOutput),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
