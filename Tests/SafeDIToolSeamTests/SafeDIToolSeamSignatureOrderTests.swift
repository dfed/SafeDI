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

/// A module's seams are settled one strongly connected component at a time, and the components that reach none of one
/// another are computed at once, so they finish in any order. What the module generates never follows that order.
struct SafeDIToolSeamSignatureOrderTests: ~Copyable {
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

	@Test(arguments: CompletionOrder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesSameCode_whenComponentsOfSeamsFinishInAnotherOrder(completionOrder: CompletionOrder) async throws {
		let expectedFiles = try await executeSafeDIToolTest(
			swiftFileContent: Self.fixture,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		).dependencyTreeFiles
		let files = try await DependencyTreeGenerator.$seamComponentComputationWillStart.withValue({ componentIndex in
			try? await Task.sleep(nanoseconds: completionOrder.delayInMilliseconds(ofComponent: componentIndex, among: Self.seamCount) * 1_000_000)
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: Self.fixture,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: true,
			).dependencyTreeFiles
		}
		#expect(files == expectedFiles)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The order in which the delays make the components finish.
	enum CompletionOrder: CaseIterable, Sendable {
		/// The last component first.
		case reversed
		/// The first component first.
		case inOrder
		/// The components shuffled by a fixed stride.
		case strided

		func delayInMilliseconds(ofComponent componentIndex: Int, among componentCount: Int) -> UInt64 {
			switch self {
			case .reversed:
				UInt64(componentCount - componentIndex)
			case .inOrder:
				UInt64(componentIndex)
			case .strided:
				UInt64(componentIndex * 7 % componentCount)
			}
		}
	}

	/// Twenty-four seams, each its own component, each of which receives `token` from its caller through `Leaf<n>`;
	/// `Seam1`, `Seam4` and every third seam after them also instantiate the seam before it, so the seams settle in two
	/// waves. A stride of seven visits each of the twenty-four components once.
	private static let seamCount = 24

	private static var fixture: [String] {
		var files = [String]()
		var rootDependencies = [(label: String, type: String)]()
		rootDependencies.append((label: "token", type: "Token"))
		for index in 0..<seamCount {
			let callsPrevious = index % 3 == 1
			var dependencies = [(label: String, type: String)]()
			dependencies.append((label: "leaf", type: "Leaf\(index)"))
			if callsPrevious {
				dependencies.append((label: "previous", type: "Seam\(index - 1)"))
			}
			files.append(Self.type(named: "Seam\(index)", attributes: "@Instantiable(generateDependencyTree: true)", instantiating: dependencies))
			files.append("""
			@Instantiable
			public struct Leaf\(index): Instantiable {
			    public init(token: Token) {
			        self.token = token
			    }

			    @Received let token: Token
			}
			""")
			// A seam the next one instantiates is reached through it.
			if index % 3 != 0 {
				rootDependencies.append((label: "seam\(index)", type: "Seam\(index)"))
			}
		}
		files.append(Self.type(named: "Root", attributes: "@Instantiable(isRoot: true)", instantiating: rootDependencies))
		files.append("""
		@Instantiable
		public struct Token: Instantiable {
		    public init() {}
		}
		""")
		return files
	}

	private static func type(named name: String, attributes: String, instantiating dependencies: [(label: String, type: String)]) -> String {
		var lines = [String]()
		lines.append(attributes)
		lines.append("public struct \(name): Instantiable {")
		lines.append("    public init(\(dependencies.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {")
		for dependency in dependencies {
			lines.append("        self.\(dependency.label) = \(dependency.label)")
		}
		lines.append("    }")
		lines.append("")
		for dependency in dependencies {
			lines.append("    @Instantiated let \(dependency.label): \(dependency.type)")
		}
		lines.append("}")
		return lines.joined(separator: "\n")
	}
}
