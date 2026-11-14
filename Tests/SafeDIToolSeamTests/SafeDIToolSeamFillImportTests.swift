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

/// The file that fills another module's seam holds a fill for each place and a dispatcher for each scope enum it is
/// handed. A fill names the type it builds, which may be of a module no file of the filling module imports, and a
/// dispatcher names the enums of the seams a hole passes up through, which may be of modules the filling module reads
/// only from beneath it.
struct SafeDIToolSeamFillImportTests: ~Copyable {
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

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfTypeAFillBuilds_whenFileHoldsFillAndDispatchersAndNoFileReadImportsThatModule(integration: MultiModuleIntegration) async throws {
		// `App` lists `Impl` but none of its files imports it: the fill builds `TrackerImpl` for a property of type
		// `any Tracker`, so the generated file imports `Impl`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(appDependencies: ["Core", "Impl", "InnerSeamModule", "OuterSeamModule"]),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let generatedFiles = try #require(output.modules["App"]?.generatedFiles)
		let fileName = switch integration {
		case .moduleInfo: "App.swift"
		case .swiftPackagePlugin: "Root+SafeDI.swift"
		}
		#expect(generatedFiles == [fileName: Self.generatedFile(importing: ["Core", "Impl", "InnerSeamModule", "OuterSeamModule"], """
		extension Root {
		    public init() {
		        func __safeDI_outerSeam() -> OuterSeam {
		            _ = OuterSeam.__safeDI_OuterSeam_CF889EA9C7DEDD3E.self\(integration.seamCallComment(type: "OuterSeam", declaringModule: "OuterSeamModule"))
		            func __safeDI_trackerBuilder_OuterSeam(_ scope: OuterSeam.SafeDIScope_Tracker) -> any Tracker {
		                switch scope {
		                case let .innerSeam(_, scope): return __safeDI_trackerBuilder_InnerSeam(scope)
		                }
		            }
		            func __safeDI_trackerBuilder_InnerSeam(_ scope: InnerSeam.SafeDIScope_Tracker) -> any Tracker {
		                switch scope {
		                case .tracker:
		                    let tracker: any Tracker = TrackerImpl()
		                    return tracker
		                }
		            }
		            return OuterSeam(__safeDI_trackerBuilder: __safeDI_trackerBuilder_OuterSeam)
		        }
		        let outerSeam: OuterSeam = __safeDI_outerSeam()
		        self.init(outerSeam: outerSeam)
		    }
		}
		""")], "Unexpected output \(generatedFiles)")
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfTypeAFillBuilds_whenSeamsOwnFileFillsInnerSeamAndNoFileReadImportsThatModule(integration: MultiModuleIntegration) async throws {
		// `OuterSeam`'s module lists `Impl`, so `OuterSeam` fills `InnerSeam`'s place itself: its own file holds the fill and
		// the dispatcher, and imports `Impl`, which none of its files does.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: ["public protocol Tracker {}\n"]),
				ModuleFixture(name: "InnerSeamModule", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "InnerSeam", isSeam: true, declarations: ["@Instantiated let tracker: any Tracker"])], dependencies: ["Core"]),
				Self.impl,
				ModuleFixture(name: "OuterSeamModule", packageName: "Base", swiftFileContent: ["import Core\nimport InnerSeamModule\n\n" + seamFixtureType(named: "OuterSeam", isSeam: true, declarations: ["@Instantiated let innerSeam: InnerSeam"])], dependencies: ["Core", "Impl", "InnerSeamModule"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let generatedFiles = try #require(output.modules["OuterSeamModule"]?.generatedFiles)
		let fileName = switch integration {
		case .moduleInfo: "OuterSeamModule.swift"
		case .swiftPackagePlugin: "OuterSeam+SafeDI.swift"
		}
		#expect(generatedFiles == [fileName: Self.generatedFile(importing: ["Core", "Impl", "InnerSeamModule"], """
		extension OuterSeam {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        func __safeDI_innerSeam() -> InnerSeam {
		            _ = InnerSeam.__safeDI_InnerSeam_CF287AB62B83935B.self\(integration.seamCallComment(type: "InnerSeam", declaringModule: "InnerSeamModule"))
		            func __safeDI_trackerBuilder_InnerSeam(_ scope: InnerSeam.SafeDIScope_Tracker) -> any Tracker {
		                switch scope {
		                case .tracker:
		                    let tracker: any Tracker = TrackerImpl()
		                    return tracker
		                }
		            }
		            return InnerSeam(__safeDI_trackerBuilder: __safeDI_trackerBuilder_InnerSeam)
		        }
		        let innerSeam: InnerSeam = __safeDI_innerSeam()
		        self.init(innerSeam: innerSeam)
		    }
		}

		extension OuterSeam {
		    public enum __safeDI_OuterSeam_CBF29CE484222325 {}
		}
		""")], "Unexpected output \(generatedFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsAndImportsEveryModuleTheDispatchersAndFillName_whenRootListsOnlyTheOuterSeamsModule() async throws {
		// Under Bazel `App` lists only what it imports. The hole is passed up through `OuterSeam`, so `App`'s dispatchers
		// name `InnerSeam`'s enum and its fill builds `TrackerImpl`: both modules are read from beneath and imported, and
		// `Sub`, which `App` lists but no file of it imports, is not.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: Self.modules(appDependencies: ["Core", "OuterSeamModule", "Sub"]),
			integration: .moduleInfo,
			modulesBeneath: { $0 },
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.moduleInfoFile?.dependencyModuleNames == ["Core", "Impl", "InnerSeamModule", "OuterSeamModule", "Sub"])
		let generatedFiles = try #require(output.modules["App"]?.generatedFiles)
		#expect(generatedFiles == ["App.swift": Self.generatedFile(importing: ["Core", "Impl", "InnerSeamModule", "OuterSeamModule"], """
		extension Root {
		    public init() {
		        func __safeDI_outerSeam() -> OuterSeam {
		            _ = OuterSeam.__safeDI_OuterSeam_CF889EA9C7DEDD3E.self\(MultiModuleIntegration.moduleInfo.seamCallComment(type: "OuterSeam", declaringModule: "OuterSeamModule"))
		            func __safeDI_trackerBuilder_OuterSeam(_ scope: OuterSeam.SafeDIScope_Tracker) -> any Tracker {
		                switch scope {
		                case let .innerSeam(_, scope): return __safeDI_trackerBuilder_InnerSeam(scope)
		                }
		            }
		            func __safeDI_trackerBuilder_InnerSeam(_ scope: InnerSeam.SafeDIScope_Tracker) -> any Tracker {
		                switch scope {
		                case .tracker:
		                    let tracker: any Tracker = TrackerImpl()
		                    return tracker
		                }
		            }
		            return OuterSeam(__safeDI_trackerBuilder: __safeDI_trackerBuilder_OuterSeam)
		        }
		        let outerSeam: OuterSeam = __safeDI_outerSeam()
		        self.init(outerSeam: outerSeam)
		    }
		}
		""")], "Unexpected output \(generatedFiles)")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `InnerSeam` holds a hole of `any Tracker`, which `OuterSeam` passes up to `App`'s root. `Impl` declares
	/// `TrackerImpl`, and `Sub` imports `Impl`; no file of `App` imports `Impl` or `InnerSeamModule`.
	private static func modules(appDependencies: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Base", swiftFileContent: ["public protocol Tracker {}\n"]),
			ModuleFixture(name: "InnerSeamModule", packageName: "Base", swiftFileContent: ["import Core\n\n" + seamFixtureType(named: "InnerSeam", isSeam: true, declarations: ["@Instantiated let tracker: any Tracker"])], dependencies: ["Core"]),
			ModuleFixture(name: "OuterSeamModule", packageName: "Base", swiftFileContent: ["import InnerSeamModule\n\n" + seamFixtureType(named: "OuterSeam", isSeam: true, declarations: ["@Instantiated let innerSeam: InnerSeam"])], dependencies: ["InnerSeamModule"]),
			impl,
			ModuleFixture(name: "Sub", packageName: "Base", swiftFileContent: ["import Impl\n\n" + seamFixtureType(named: "SubThing", declarations: [])], dependencies: ["Impl"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Core\nimport OuterSeamModule\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let outerSeam: OuterSeam"])], dependencies: appDependencies),
		]
	}

	/// `TrackerImpl`, which fulfills `Tracker`.
	private static let impl = ModuleFixture(name: "Impl", packageName: "Base", swiftFileContent: ["""
	import Core

	@Instantiable(fulfillingAdditionalTypes: [Tracker.self])
	public struct TrackerImpl: Instantiable, Tracker {
	    public init() {}
	}
	"""], dependencies: ["Core"])

	private static func generatedFile(importing moduleNames: [String], _ body: String) -> String {
		generatedFileHeader + moduleNames.map { "#if canImport(\($0))\nimport \($0)\n#endif" }.joined(separator: "\n") + "\n\n" + body
	}
}
