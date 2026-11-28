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
import Testing
@testable import SafeDICore
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The per-type facts' key of a fill (`TypeFactsDeclaration`), which carries its hole's erasure as a built place's key
/// carries its property's: a fill of an erased place builds the erased value.
struct SafeDIToolSeamFillErasureFactsTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func typeFacts_keysFillByItsHolesErasure_whenOneFulfillerFillsAnErasedAndAPlainPlace() async throws {
		// `LiveGadget` fills both of `Home`'s places: `gadget`, an `any Gadget`, and `erasedGadget`, an `AnyGadget` it is
		// erased to. The two fills are two nodes, and only the erased place's is erased; the place of each fill finds its node.
		let modules = SafeDIToolSeamBuilderParameterTests.modules(
			feature: [
				"public protocol Gadget {}",
				"""
				public struct AnyGadget: Gadget {
				    public init(_ base: any Gadget) {
				        self.base = base
				    }

				    let base: any Gadget
				}
				""",
				seamFixtureType(named: "Home", isSeam: true, declarations: [
					"@Instantiated let gadget: any Gadget",
					#"@Instantiated(fulfilledByType: "LiveGadget", erasedToConcreteExistential: true) let erasedGadget: AnyGadget"#,
				]),
			],
			app: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveGadget", fulfilling: "Gadget", declarations: []),
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let home: Home"]),
			],
		)
		let (stream, continuation) = AsyncStream.makeStream(of: TypeFactsReport.self)
		_ = try await ConstructionMemoOracle.$observer.withValue(TaskLocalFunction { _, _, report in continuation.yield(report) }) {
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var reports = [TypeFactsReport]()
		for await report in stream where report.root == "Root" && !report.forMockGeneration {
			reports.append(report)
		}
		let report = try #require(reports.last)

		let fills = report.graph.graph.nodes.filter(\.key.isFill).map { "\($0.property?.label ?? "") erased \($0.key.erasedToConcreteExistential)" }
		#expect(fills.sorted() == ["erasedGadget erased true", "gadget erased false"])
		#expect(report.places.filter(\.isFill).map { $0.node != nil } == [true, true])
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
