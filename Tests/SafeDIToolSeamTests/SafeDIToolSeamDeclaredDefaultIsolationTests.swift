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

/// A seam's generated initializers in a module whose `#SafeDIConfiguration` declares `defaultIsolation: MainActor.self`,
/// called from a module that declares it too, each module compiled with and without `-default-isolation MainActor`.
struct SafeDIToolSeamDeclaredDefaultIsolationTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test(arguments: MultiModuleIntegration.allCases, [nil, "MainActor"] as [String?])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsMainActorOnSeamInitializersAndCallingRoot_whenBothModulesDeclareMainActor(integration: MultiModuleIntegration, buildSettingDefaultIsolation: String?) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(buildSettingDefaultIsolation: buildSettingDefaultIsolation),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(try #require(output.modules["Feature"]).generatedFiles == [
			integration == .moduleInfo ? "Feature.swift" : "Screen+SafeDI.swift": generatedFileHeader + """
			extension Screen {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    @MainActor public convenience init(__safeDI_user: @autoclosure @escaping () -> User) {
			        let user = LazilyInstantiated<User>(__safeDI_user)
			        @inline(never) func __safeDI_detailBuilder() -> Detail {
			            Detail(user: user.instance)
			        }
			        let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
			        self.init(detailBuilder: detailBuilder)
			    }
			}

			extension Screen {
			    public enum __safeDI_Screen_08AA1A656B91D4BA {}
			}
			""",
		])
		#expect(try #require(output.modules["App"]).generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    @MainActor public convenience init() {
			        let user = User()
			        func __safeDI_screen() -> Screen {
			            _ = Screen.__safeDI_Screen_08AA1A656B91D4BA.self\(integration.seamCallComment(type: "Screen", declaringModule: "Feature"))
			            return Screen(__safeDI_user: user)
			        }
			        let screen: Screen = __safeDI_screen()
			        self.init(user: user, screen: screen)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtRoot_whenRootStatesNoIsolationAndCallsSeamItsModuleGeneratesMainActor(integration: MultiModuleIntegration) async {
		// `App` declares no default isolation, so its root's generated `init()` is nonisolated, and cannot call the
		// `@MainActor` initializer `Feature` generated for its seam.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			let rootPath = switch integration {
			case .moduleInfo:
				fixtures["App"]!["Root.swift"]
			case .swiftPackagePlugin:
				NormalizedFilePath(fixtures["App"]!.compilerPath(of: "Root.swift")).path
			}
			return """
			\(rootPath):3:1: error: The initializer SafeDI generates for `Root` calls the initializer module `Feature` generates for `Screen`, which is `@MainActor` because `Feature` declares `defaultIsolation: MainActor.self` in its `#SafeDIConfiguration`, but the initializer SafeDI generates for `Root` states no isolation. Declare `defaultIsolation: MainActor.self` in this module’s `#SafeDIConfiguration`, or write `generatedAttributes: "@MainActor"` on `Root`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(buildSettingDefaultIsolation: nil, appConfiguration: [:]),
				integration: integration,
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesModuleInfoFileHoldingSuppliedAttributes_whenModuleDeclaresMainActor() async throws {
		// A module that reads `Feature`'s `.safedi` sees the attributes `Feature` resolved, and that SafeDI supplied them.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(buildSettingDefaultIsolation: nil),
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		let moduleInfoFile = try #require(output.modules["Feature"]?.moduleInfoFile)
		#expect(moduleInfoFile.configurations.map(\.defaultIsolation) == [.mainActor])
		#expect(moduleInfoFile.instantiables.map(\.concreteInstantiable.asSource) == ["Detail", "Screen", "User"])
		#expect(moduleInfoFile.instantiables.map(\.generatedInitializerAttributes) == ["@MainActor", "@MainActor", "@MainActor"])
		#expect(moduleInfoFile.instantiables.map(\.mockAttributes) == ["@MainActor", "@MainActor", "@MainActor"])
		#expect(moduleInfoFile.instantiables.map(\.usesModuleDefaultIsolation) == [true, true, true])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static let declaringMainActor = ["SafeDIConfiguration.swift": "#SafeDIConfiguration(defaultIsolation: MainActor.self)\n"]

	/// `Feature`, which declares the seam `Screen`, whose tree builds `Detail`, main-actor through `Feature`'s
	/// `Presentable`, and `App`, whose root builds `Screen`. `Feature` declares the main actor as its default isolation, and `App` declares
	/// `appConfiguration`.
	private static func modules(buildSettingDefaultIsolation: String?, appConfiguration: [String: String] = declaringMainActor) -> [ModuleFixture] {
		[
			ModuleFixture(
				name: "Feature",
				packageName: "Shop",
				swiftFileContent: [
					"""
					@MainActor
					public protocol Presentable: AnyObject {}
					""",
					"""
					@Instantiable(generateDependencyTree: true)
					public final class Screen: Instantiable {
					    public init(detailBuilder: Instantiator<Detail>) {
					        self.detailBuilder = detailBuilder
					    }

					    @Instantiated let detailBuilder: Instantiator<Detail>
					}
					""",
					"""
					@Instantiable
					public final class Detail: Instantiable, Presentable {
					    public init(user: User) {
					        self.user = user
					    }

					    @Received let user: User
					}
					""",
					"""
					@Instantiable
					public final class User: Instantiable, Sendable {
					    public init() {}
					}
					""",
				],
				swiftFileContentByFilePath: declaringMainActor,
				compilerSettings: VerificationCompilerSettings(defaultIsolation: buildSettingDefaultIsolation),
			),
			ModuleFixture(
				name: "App",
				packageName: "Shop",
				swiftFileContent: [
					"""
					import Feature

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(user: User, screen: Screen) {
					        self.user = user
					        self.screen = screen
					    }

					    @Instantiated let user: User
					    @Instantiated let screen: Screen
					}
					""",
				],
				swiftFileContentByFilePath: appConfiguration,
				dependencies: ["Feature"],
				compilerSettings: VerificationCompilerSettings(defaultIsolation: buildSettingDefaultIsolation),
			),
		]
	}
}
