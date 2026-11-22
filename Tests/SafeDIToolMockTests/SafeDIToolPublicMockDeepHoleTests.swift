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

/// A mock that calls another module's public mock whose hole is far beneath its root. The calling mock declares a level
/// function for each level between the root and the hole, which a walk that recursed per level would overflow a thread
/// of half a megabyte building, so the run is on one (`withHalfMegabyteStack(_:)`), as on Apple platforms.
struct SafeDIToolPublicMockDeepHoleTests: ~Copyable {
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

	@Test
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
	mutating func generate_declaresLevelFunctionForEachLevel_whenCalledPublicMocksHoleIsThreeHundredLevelsBeneathItsRoot() async throws {
		let output = try await withHalfMegabyteStack {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(depth: 300),
				integration: .moduleInfo,
				// The code of `Panel`'s public mock grows with the square of its depth, so the chain of five below is compiled instead.
				compileVerification: .skipped,
				filesToDelete: &filesToDelete,
			)
		}

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == Self.screenMock(depth: 300, guardHash: "45556951E140F1D8"))
	}

	@Test
	@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
	mutating func generate_declaresLevelFunctionThatCompiles_whenCalledPublicMocksHoleIsFiveLevelsBeneathItsRoot() async throws {
		let output = try await withHalfMegabyteStack {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(depth: 5),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == Self.screenMock(depth: 5, guardHash: "67623582F91ED32F"))
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Module `Core`, whose `Panel` has a public mock and instantiates a chain of `depth` features, the last of which
	/// instantiates `any Widget`, which `Core` cannot build; and module `App`, whose `Screen` has a mock that instantiates
	/// `Panel`, and whose `WidgetImpl` fills the hole.
	private static func modules(depth: Int) -> [ModuleFixture] {
		var coreFiles = [
			"public protocol Widget {}",
			"""
			@Instantiable(generateMock: .public)
			public struct Panel: Instantiable {
			    init(feature0: Feature0) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let feature0: Feature0
			}
			""",
		]
		for index in 0..<depth {
			let property = index + 1 < depth ? "feature\(index + 1): Feature\(index + 1)" : "widget: any Widget"
			coreFiles.append("""
			@Instantiable
			public struct Feature\(index): Instantiable {
			    init(\(property)) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let \(property)
			}
			""")
		}
		return [
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContent: coreFiles, activeCompilationConditions: ["DEBUG"]),
			ModuleFixture(
				name: "App",
				packageName: "App",
				swiftFileContent: [
					"""
					import Core

					@Instantiable(fulfillingAdditionalTypes: [Widget.self])
					public struct WidgetImpl: Widget, Instantiable {
					    public init() {}
					}
					""",
					"""
					import Core

					@Instantiable(generateMock: true)
					public struct Screen: Instantiable {
					    public init(panel: Panel) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let panel: Panel
					}
					""",
				],
				dependencies: ["Core"],
				activeCompilationConditions: ["DEBUG"],
			),
		]
	}

	/// The code generated for `App`: the mock of `Screen`, which calls `Panel`'s public mock with a level function for each
	/// of the `depth` features, the last of which fills the hole with `WidgetImpl`.
	private static func screenMock(depth: Int, guardHash: String) -> String {
		var lines = [
			"""
			// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
			// Any modifications made to this file will be overwritten on subsequent builds.
			// Please refrain from editing this file directly.

			#if canImport(Core)
			import Core
			#endif

			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            panel: Panel.SafeDIOverrides = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                panel: panel
			            )
			        }

			        var panel: Panel.SafeDIOverrides { __safeDI_storage.panel }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                panel: Panel.SafeDIOverrides
			            ) {
			                self.panel = panel
			            }

			            let panel: Panel.SafeDIOverrides
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_panel() -> Panel {
			            func __safeDI_widgetBuilder_Panel() -> Panel.SafeDIMockScope_Widget.__safeDI_Builder<any Widget> {
			                .init(feature0: { _ in __safeDI_widgetBuilder_Panel_Feature0_Scope() })
			            }
			""",
		]
		for index in 0..<depth - 1 {
			lines.append("""
			            func __safeDI_widgetBuilder_Panel_Feature\(index)_Scope() -> Panel.SafeDIMockScope_Widget.Feature\(index)_Scope.__safeDI_Builder<any Widget> {
			                .init(feature\(index + 1): { _ in __safeDI_widgetBuilder_Panel_Feature\(index + 1)_Scope() })
			            }
			""")
		}
		lines.append("""
		            func __safeDI_widgetBuilder_Panel_Feature\(depth - 1)_Scope() -> Panel.SafeDIMockScope_Widget.Feature\(depth - 1)_Scope.__safeDI_Builder<any Widget> {
		                .init(widget: { _ in
		                    let widget: any Widget = WidgetImpl()
		                    return widget
		                })
		            }
		            _ = Panel.__safeDI_Panel_mock_\(guardHash).self // If this line does not compile, compile the code SafeDI generates for module Core into Core: under Bazel, add Core’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Panel.__safeDI_mock(widgetBuilder: __safeDI_widgetBuilder_Panel(), safeDIOverrides: safeDIOverrides.panel)
		        }
		        let panel: Panel = __safeDI_panel()
		        return Screen(panel: panel)
		    }
		}
		#endif
		""")
		return lines.joined(separator: "\n")
	}
}
