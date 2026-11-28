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

/// A seam's tree that builds a place inside a `@Sendable` builder function binds the member of its builder struct for the
/// place at the top of that function. Each such binding is a place of its own, as a payload binding is, so the type key
/// lays the tree out and a type built on two paths beneath the function is built by one function.
struct SafeDIToolSeamSendableMemberCallTests: ~Copyable {
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
	mutating func generate_declaresBuilderFunctionOnce_whenTypeBuiltOnTwoPathsInsideSendableFunctionHoldsPlace() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Host {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_GadgetCarrier_Screen<__safeDI_Built> {
			        public let rowA: __safeDI_GadgetCarrier_RowA<__safeDI_Built>
			        public let rowB: (RowA) -> __safeDI_GadgetCarrier_RowB<__safeDI_Built>

			        public init(rowA: __safeDI_GadgetCarrier_RowA<__safeDI_Built>, rowB: @escaping (RowA) -> __safeDI_GadgetCarrier_RowB<__safeDI_Built>) {
			            self.rowA = rowA
			            self.rowB = rowB
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(rowA: .init(__safeDI_noScope: __safeDI_builder), rowB: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_GadgetCarrier_RowA<__safeDI_Built> {
			        public let cell: __safeDI_GadgetCarrier_Cell<__safeDI_Built>

			        public init(cell: __safeDI_GadgetCarrier_Cell<__safeDI_Built>) {
			            self.cell = cell
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(cell: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_GadgetCarrier_RowB<__safeDI_Built> {
			        public let cell: __safeDI_GadgetCarrier_Cell<__safeDI_Built>

			        public init(cell: __safeDI_GadgetCarrier_Cell<__safeDI_Built>) {
			            self.cell = cell
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(cell: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_GadgetCarrier_Cell<__safeDI_Built> {
			        public let gadget: () -> __safeDI_Built

			        public init(gadget: @escaping () -> __safeDI_Built) {
			            self.gadget = gadget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(gadget: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_GadgetSendableCarrier<__safeDI_Built>: Sendable {
			        public let screenBuilder: @Sendable () -> __safeDI_GadgetCarrier_Screen<__safeDI_Built>

			        public init(screenBuilder: @escaping @Sendable () -> __safeDI_GadgetCarrier_Screen<__safeDI_Built>) {
			            self.screenBuilder = screenBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(screenBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_gadgetSendableBuilder: __safeDI_GadgetSendableCarrier<any Gadget>) {
			        @inline(never) @Sendable nonisolated func __safeDI_rowA(__safeDI_gadgetSendableBuilder_rowA: __safeDI_GadgetCarrier_RowA<any Gadget>) -> RowA {
			            let __safeDI_gadgetSendableBuilder_cell = __safeDI_gadgetSendableBuilder_rowA.cell
			            let cell: Cell = __safeDI_cell(__safeDI_gadgetSendableBuilder_cell: __safeDI_gadgetSendableBuilder_cell)
			            return RowA(cell: cell)
			        }
			        @inline(never) @Sendable nonisolated func __safeDI_cell(__safeDI_gadgetSendableBuilder_cell: __safeDI_GadgetCarrier_Cell<any Gadget>) -> Cell {
			            let gadget: any Gadget = __safeDI_gadgetSendableBuilder_cell.gadget()
			            return Cell(gadget: gadget)
			        }
			        @inline(never) @Sendable nonisolated func __safeDI_rowB(__safeDI_gadgetSendableBuilder_rowB: __safeDI_GadgetCarrier_RowB<any Gadget>) -> RowB {
			            let __safeDI_gadgetSendableBuilder_cell = __safeDI_gadgetSendableBuilder_rowB.cell
			            let cell: Cell = __safeDI_cell(__safeDI_gadgetSendableBuilder_cell: __safeDI_gadgetSendableBuilder_cell)
			            return RowB(cell: cell)
			        }
			        @inline(never) @Sendable nonisolated func __safeDI_screenBuilder() -> Screen {
			            let __safeDI_gadgetSendableBuilder_screenBuilder = __safeDI_gadgetSendableBuilder.screenBuilder()
			            let __safeDI_gadgetSendableBuilder_rowA = __safeDI_gadgetSendableBuilder_screenBuilder.rowA
			            let rowA: RowA = __safeDI_rowA(__safeDI_gadgetSendableBuilder_rowA: __safeDI_gadgetSendableBuilder_rowA)
			            let __safeDI_gadgetSendableBuilder_rowB = __safeDI_gadgetSendableBuilder_screenBuilder.rowB(rowA)
			            let rowB: RowB = __safeDI_rowB(__safeDI_gadgetSendableBuilder_rowB: __safeDI_gadgetSendableBuilder_rowB)
			            return Screen(rowA: rowA, rowB: rowB)
			        }
			        let screenBuilder = SendableInstantiator<Screen>(__safeDI_screenBuilder)
			        self.init(screenBuilder: screenBuilder)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_3338D9797C4C6CD3 {}
			}
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Expects `generatedFiles` to equal `expected`, recording the files generated when they do not, so a failure shows
	/// the output in full.
	private func expectGeneratedFiles(_ generatedFiles: [String: String]?, _ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}

	/// `Host`, a seam that opens `Screen` through a `SendableInstantiator`, whose rows each build `Cell`, which holds the
	/// hole `gadget`, which `App` fills.
	private static let modules = SafeDIToolSeamBuilderParameterTests.modules(
		feature: [
			"public protocol Gadget: Sendable {}",
			seamFixtureType(named: "Cell", declarations: ["@Instantiated let gadget: any Gadget"], conformances: ", Sendable"),
			seamFixtureType(named: "RowA", declarations: ["@Instantiated let cell: Cell"], conformances: ", Sendable"),
			seamFixtureType(named: "RowB", declarations: ["@Instantiated let cell: Cell"], conformances: ", Sendable"),
			seamFixtureType(named: "Screen", declarations: ["@Instantiated let rowA: RowA", "@Instantiated let rowB: RowB"], conformances: ", Sendable"),
			seamFixtureType(named: "Host", isSeam: true, declarations: ["@Instantiated let screenBuilder: SendableInstantiator<Screen>"]),
		],
		app: [
			SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "DefaultGadget", fulfilling: "Gadget", declarations: []),
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let host: Host"]),
		],
	)
}
