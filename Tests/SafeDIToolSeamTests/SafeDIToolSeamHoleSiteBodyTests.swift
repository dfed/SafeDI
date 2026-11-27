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

/// A hole is the one scope that can write nothing, and only in a tree built to compute a seam's signature, which
/// generates no code. In a seam's generated tree every hole writes its site, so a builder function whose only child is a
/// hole has a statement (`.claude/rules/emission-decisions.md`, "Empty chunks").
struct SafeDIToolSeamHoleSiteBodyTests: ~Copyable {
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
	mutating func generate_declaresBuilderFunctionForEachForm_whenItsOnlyChildIsHole() async throws {
		// `Panel`'s only child is the hole `api`, which `Feature` cannot fill. `Office` holds `Panel` as a constant, an
		// instantiator and a lazy wrapper, and each declares a builder function whose body is the hole's site.
		let modules = SafeDIToolSeamBuilderParameterTests.modules(
			feature: [
				"public protocol Api {}",
				seamFixtureType(named: "Panel", declarations: ["@Instantiated let api: any Api"]),
				seamFixtureType(named: "Office", isSeam: true, declarations: ["@Instantiated let panel: Panel", "@Instantiated let panelBuilder: Instantiator<Panel>", "@Instantiated let lazyPanel: LazilyInstantiated<Panel>"]),
			],
			app: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultApi", fulfilling: "Api", declarations: []),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let office: Office"]),
			],
		)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let generated: String? = output.modules["Feature"]?.generatedFiles["Feature.swift"]
		let expected: String = generatedFileHeader + """
		extension Office {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier<__safeDI_Built> {
		        public let panel: __safeDI_ApiCarrier_Panel<__safeDI_Built>
		        public let panelBuilder: (Panel) -> __safeDI_ApiCarrier_Panel<__safeDI_Built>
		        public let lazyPanel: (Panel, Instantiator<Panel>) -> __safeDI_ApiCarrier_Panel<__safeDI_Built>

		        public init(panel: __safeDI_ApiCarrier_Panel<__safeDI_Built>, panelBuilder: @escaping (Panel) -> __safeDI_ApiCarrier_Panel<__safeDI_Built>, lazyPanel: @escaping (Panel, Instantiator<Panel>) -> __safeDI_ApiCarrier_Panel<__safeDI_Built>) {
		            self.panel = panel
		            self.panelBuilder = panelBuilder
		            self.lazyPanel = lazyPanel
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(panel: .init(__safeDI_noScope: __safeDI_builder), panelBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) }, lazyPanel: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
		        }
		    }

		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ApiCarrier_Panel<__safeDI_Built> {
		        public let api: () -> __safeDI_Built

		        public init(api: @escaping () -> __safeDI_Built) {
		            self.api = api
		        }

		        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		            self.init(api: { __safeDI_builder() })
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_apiBuilder: __safeDI_ApiCarrier<any Api>) {
		        let __safeDI_apiBuilder_panel = __safeDI_apiBuilder.panel
		        @inline(never) func __safeDI_panel() -> Panel {
		            let api: any Api = __safeDI_apiBuilder_panel.api()
		            return Panel(api: api)
		        }
		        let panel: Panel = __safeDI_panel()
		        let __safeDI_apiBuilder_panelBuilder = __safeDI_apiBuilder.panelBuilder(panel)
		        @inline(never) func __safeDI_panelBuilder() -> Panel {
		            let api: any Api = __safeDI_apiBuilder_panelBuilder.api()
		            return Panel(api: api)
		        }
		        let panelBuilder = Instantiator<Panel>(__safeDI_panelBuilder)
		        let __safeDI_apiBuilder_lazyPanel = __safeDI_apiBuilder.lazyPanel(panel, panelBuilder)
		        @inline(never) func __safeDI_lazyPanel() -> Panel {
		            let api: any Api = __safeDI_apiBuilder_lazyPanel.api()
		            return Panel(api: api)
		        }
		        let lazyPanel = LazilyInstantiated<Panel>(__safeDI_lazyPanel)
		        self.init(panel: panel, panelBuilder: panelBuilder, lazyPanel: lazyPanel)
		    }
		}

		extension Office {
		    public enum __safeDI_Office_2A9E2C96B2DC0CA1 {}
		}
		"""
		#expect(generated == expected)
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
