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

/// A module generates the `init()` of a root only when one of its own files declares the root. A module whose build
/// reads another module's files – the `SafeDIGenerator` package plugin reads those of every module a module depends on,
/// and `additionalDirectoriesToInclude` adds a directory's – writes the file `scan` plans for each root it finds there
/// without code, holding a comment that says where the root's `init()` is generated and what to do when it is not.
struct SafeDIToolRootOfOtherModuleTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A root a module the consumer depends on declares

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesRootOnlyInDeclaringModule_whenConsumerReadsRootWhoseTreeIsPublic(integration: MultiModuleIntegration) async throws {
		// Every declaration is `public` and no seam is declared, so `App` could build `FeatureRoot`'s tree; it leaves
		// the root to `Feature`, whose `init()` `App`'s hand-written code calls.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.featureModule(detailInitializerIsPublic: true)),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [Self.appRoot, Self.featureRootCall], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		switch integration {
		case .moduleInfo:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"Feature.swift": generatedFileHeader + Self.featureRootInitializer,
			])
			#expect(output.modules["App"]?.generatedFiles == [
				"App.swift": generatedFileHeader + Self.importBlock("Feature") + "\n\n",
			])
		case .swiftPackagePlugin:
			#expect(output.modules["Feature"]?.generatedFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + Self.featureRootInitializer,
			])
			#expect(output.modules["App"]?.generatedFiles == [
				"FeatureRoot+SafeDI.swift": generatedFileHeader + Self.importBlock("Feature") + "\n\n" + """
				// SafeDI generates FeatureRoot's init() only in Feature, the module that declares FeatureRoot. If FeatureRoot() does not compile, add the SafeDI plugin to the target that declares FeatureRoot.
				""",
				"Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Feature") + "\n\n",
			])
		}
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesPointerToDeclaringModule_whenConsumerReadsRootWhoseTreeConstructsInternalInitializer() async throws {
		// `Detail`'s initializer is `internal`, which `App` could not call; the file reads as for a public tree.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.featureModule(detailInitializerIsPublic: false)),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [Self.appRoot], dependencies: ["Feature"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["FeatureRoot+SafeDI.swift"] == generatedFileHeader + Self.importBlock("Feature") + "\n\n" + """
		// SafeDI generates FeatureRoot's init() only in Feature, the module that declares FeatureRoot. If FeatureRoot() does not compile, add the SafeDI plugin to the target that declares FeatureRoot.
		""")
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesPointerToDeclaringModule_whenConsumerReadsRootWhoseTreeCallsSeam() async throws {
		// `Screen` is a seam whose initializer `Feature` generates and `FeatureRoot`'s tree calls; the file reads as for a
		// tree that calls none.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.featureModule(detailInitializerIsPublic: true, screenIsSeam: true)),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [Self.appRoot, Self.featureRootCall], dependencies: ["Feature"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"FeatureRoot+SafeDI.swift": generatedFileHeader + Self.importBlock("Feature") + "\n\n" + """
			// SafeDI generates FeatureRoot's init() only in Feature, the module that declares FeatureRoot. If FeatureRoot() does not compile, add the SafeDI plugin to the target that declares FeatureRoot.
			""",
			"Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Feature") + "\n\n",
		])
		try expectEveryModuleCompiled(output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesFileWithoutComment_whenConsumerReadsRootWithoutDependencies() async throws {
		// `Feature` generates no `init()` for a root without dependencies, so `App`'s file for it says nothing either.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class FeatureRoot: Instantiable {
					    init() {}
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [Self.appRoot], dependencies: ["Feature"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == [
			"FeatureRoot+SafeDI.swift": generatedFileHeader,
		])
		#expect(output.modules["App"]?.generatedFiles == [
			"FeatureRoot+SafeDI.swift": generatedFileHeader + Self.importBlock("Feature") + "\n\n",
			"Root+SafeDI.swift": generatedFileHeader + Self.importBlock("Feature") + "\n\n",
		])
		try expectEveryModuleCompiled(output)
	}

	// MARK: A root of a module SafeDI does not know

	@Test(arguments: [[], ["--module-name", "App"]])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesPointerWithoutModuleName_whenRootIsReadFromAdditionalDirectory(moduleMembershipArguments: [String]) async throws {
		// `Feature`'s files are in a directory `App`'s configuration adds, which belongs to a module SafeDI does not
		// know, as under the Xcode project plugin, whether or not `App`'s own module is named.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				#SafeDIConfiguration(
				    additionalDirectoriesToInclude: ["$ADDITIONAL_DIRECTORY"]
				)
				""",
				Self.appRoot.replacingOccurrences(of: "import Feature\n\n", with: ""),
			],
			additionalDirectorySwiftFileContent: Self.featureModule(detailInitializerIsPublic: true),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: moduleMembershipArguments,
		)
		#expect(output.dependencyTreeFiles == [
			"FeatureRoot+SafeDI.swift": generatedFileHeader + """
			// SafeDI generates FeatureRoot's init() only in the module that declares FeatureRoot. If FeatureRoot() does not compile, add the SafeDI plugin to the target that declares FeatureRoot.
			""",
			"Root+SafeDI.swift": generatedFileHeader,
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `App`'s root, which instantiates nothing of `Feature`.
	private static let appRoot = """
	import Feature

	@Instantiable(isRoot: true)
	final class Root: Instantiable {
	    init() {}
	}
	"""

	/// `App`'s hand-written call of the `init()` SafeDI generates for `Feature`'s root.
	private static let featureRootCall = """
	import Feature

	func makeFeatureRoot() -> FeatureRoot {
	    FeatureRoot()
	}
	"""

	/// `Feature`'s public `Logger`; `Detail`, whose initializer is internal unless `detailInitializerIsPublic`, which
	/// receives `logger` only if available; `Screen`, a seam when `screenIsSeam`, which instantiates `Detail`; and the
	/// public root `FeatureRoot`, which instantiates `logger` and `Screen`.
	private static func featureModule(detailInitializerIsPublic: Bool, screenIsSeam: Bool = false) -> [String] {
		[
			seamFixtureType(named: "Logger", declarations: []),
			"""
			@Instantiable
			public struct Detail: Instantiable {
			    \(detailInitializerIsPublic ? "public " : "")init(logger: Logger?) {
			        self.logger = logger
			    }

			    @Received(onlyIfAvailable: true) let logger: Logger?
			}
			""",
			seamFixtureType(named: "Screen", isSeam: screenIsSeam, declarations: ["@Instantiated let detail: Detail"]),
			seamFixtureType(named: "FeatureRoot", isRoot: true, declarations: ["@Instantiated let logger: Logger", "@Instantiated let screen: Screen"]),
		]
	}

	/// The `init()` `Feature` generates for `FeatureRoot`, building the tree inline.
	private static let featureRootInitializer = """
	extension FeatureRoot {
	    public init() {
	        let logger = Logger()
	        func __safeDI_screen() -> Screen {
	            let detail = Detail(logger: logger)
	            return Screen(detail: detail)
	        }
	        let screen: Screen = __safeDI_screen()
	        self.init(logger: logger, screen: screen)
	    }
	}
	"""

	private static func importBlock(_ moduleName: String) -> String {
		"""
		#if canImport(\(moduleName))
		import \(moduleName)
		#endif
		"""
	}

	/// Expects every module to have compiled, when compile verification runs.
	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 }, sourceLocation: sourceLocation)
	}
}
