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

/// Stage D1's shadow: the lowering of each mock root, run beside the emitter, changes nothing generated and is tallied.
struct SafeDIToolMockLoweringShadowTests: ~Copyable {
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
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesSameFiles_whetherMockLoweringShadowRunsOrNot() async throws {
		let tally = MockLoweringShadowChecks.Tally()
		let withShadow = try await MockLoweringShadowChecks.$tally.withValue(tally) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.fixture,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		let withoutShadow = try await MockLoweringShadowChecks.$isDisabled.withValue(true) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.fixture,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}

		#expect(withShadow.mockFiles.count == 3)
		#expect(withShadow.generatedFiles == withoutShadow.generatedFiles)
		#expect(tally.reportLine == "mock-lowering: 1/3 roots identical (33.3%); 0 differ; unsupported: mock root with tree 2")
	}

	@Test
	func outcome_isIdentical_whenLoweredCodeEqualsEmittedCodeByteForByte() {
		#expect(MockLoweringShadow.outcome(comparing: .lowered("a\nb"), with: "a\nb") == .identical)
	}

	@Test
	func outcome_namesFirstDifferingLine_whenLoweredCodeDiffers() {
		#expect(MockLoweringShadow.outcome(comparing: .lowered("a\nc\nd"), with: "a\nb\nd") == .differs(line: 2, emitted: "b", lowered: "c"))
	}

	@Test
	func outcome_namesLineAfterShorterCode_whenOneCodeExtendsTheOther() {
		#expect(MockLoweringShadow.outcome(comparing: .lowered("a"), with: "a\nb") == .differs(line: 2, emitted: "b", lowered: nil))
		#expect(MockLoweringShadow.outcome(comparing: .lowered("a\nb"), with: "a") == .differs(line: 2, emitted: nil, lowered: "b"))
	}

	@Test
	func outcome_isUnsupported_whenLoweringMeetsUnportedRule() {
		#expect(MockLoweringShadow.outcome(comparing: .unsupported(.mockRootWithTree), with: "a") == .unsupported(.mockRootWithTree))
	}

	@Test
	func reportLine_listsDifferencesAndUnsupportedRoots_whenTallied() {
		let tally = MockLoweringShadowChecks.Tally()
		tally.record(MockLoweringShadow.Comparison(mockedType: "A", outcome: .identical))
		tally.record(MockLoweringShadow.Comparison(mockedType: "B", outcome: .differs(line: 4, emitted: "x", lowered: nil)))
		tally.record(MockLoweringShadow.Comparison(mockedType: "C", outcome: .unsupported(.mockRootWithTree)))
		tally.record(MockLoweringShadow.Comparison(mockedType: "D", outcome: .identical))

		#expect(tally.reportLine == """
		mock-lowering: 2/4 roots identical (50.0%); 1 differ; unsupported: mock root with tree 1
		  B line 4:
		    emitted: x
		    lowered: (end)
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Three mock roots: one with no dependency, one that instantiates a constant and an instantiator, and one that
	/// receives what the mock promotes.
	private static let fixture = [
		"""
		@Instantiable(generateMock: true)
		public struct Leaf: Instantiable {
		    public init() {}
		}
		""",
		"""
		@Instantiable(isRoot: true, generateMock: true)
		public struct Root: Instantiable {
		    public init(leaf: Leaf, screenBuilder: Instantiator<Screen>) {
		        self.leaf = leaf
		        self.screenBuilder = screenBuilder
		    }
		    @Instantiated let leaf: Leaf
		    @Instantiated let screenBuilder: Instantiator<Screen>
		}
		""",
		"""
		@Instantiable(generateMock: true)
		public struct Screen: Instantiable {
		    public init(leaf: Leaf) {
		        self.leaf = leaf
		    }
		    @Received let leaf: Leaf
		}
		""",
	]
}
