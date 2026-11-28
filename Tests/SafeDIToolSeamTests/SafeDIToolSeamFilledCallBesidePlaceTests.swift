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

/// A seam whose tree holds a place of its own beside a call of an inner seam whose every hole it fills: the call passes
/// nothing up, so the seam's enums read it as any other declaration, and the fill it makes leads to no place. The graph
/// of the seam's declarations walks into the call and meets the fill, a generator with no property, which it leaves out
/// before asking what edge the fill gives the call.
struct SafeDIToolSeamFilledCallBesidePlaceTests: ~Copyable {
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
	mutating func generate_givesFilledCallNoCase_whenSeamBuildsPlaceBesideCallWhoseEveryHoleItFills() async throws {
		// `Outer` fills `Inner`'s `widget` with `DefaultWidget`, whose tree holds no place, and builds `service`, a place only
		// `App` can fill, after the call: `Outer`'s enum has a case for `service` alone, which carries `inner`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"public protocol Widget {}",
					seamFixtureType(named: "Inner", isSeam: true, declarations: ["@Instantiated public let widget: any Widget"]),
				]),
				ModuleFixture(name: "Middle", packageName: "Other", swiftFileContent: [
					"public protocol Service {}",
					SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: []),
					seamFixtureType(named: "Outer", isSeam: true, declarations: ["@Instantiated public let inner: Inner", "@Instantiated public let service: any Service"]),
				].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
					SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveService", fulfilling: "Service", declarations: []),
					seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let outer: Outer"]),
				].map { "import Feature\nimport Middle\n\n" + $0 }, dependencies: ["Feature", "Middle"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Middle"]?.generatedFiles["Middle.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Outer {
		    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		    nonisolated public final class __safeDI_ServiceCarrier<__safeDI_Built> {
		        public let service: (Inner) -> __safeDI_Built

		        public init(service: @escaping (Inner) -> __safeDI_Built) {
		            self.service = service
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_serviceBuilder: __safeDI_ServiceCarrier<any Service>) {
		        @inline(never) func __safeDI_widgetBuilder_Inner() -> Inner.__safeDI_WidgetCarrier<any Widget> {
		            .init(widget: {
		                let widget: any Widget = DefaultWidget()
		                return widget
		            })
		        }
		        @inline(never) func __safeDI_inner() -> Inner {
		            _ = Inner.__safeDI_Inner_DF0C971D70DD0421.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Inner(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Inner())
		        }
		        let inner: Inner = __safeDI_inner()
		        let service: any Service = __safeDI_serviceBuilder.service(inner)
		        self.init(inner: inner, service: service)
		    }
		}

		extension Outer {
		    public enum __safeDI_Outer_655C7EE201FC4037 {}
		}
		""")
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Middle)
		import Middle
		#endif

		extension Root {
		    public init() {
		        func __safeDI_serviceBuilder_Outer() -> Outer.__safeDI_ServiceCarrier<any Service> {
		            .init(service: { scope_inner in
		                let service: any Service = LiveService()
		                return service
		            })
		        }
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_655C7EE201FC4037.self // If this line does not compile, compile the code SafeDI generates for module Middle into Middle: under Bazel, add Middle’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer(__safeDI_serviceBuilder: __safeDI_serviceBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
