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

/// A mock root's parameter tree builds the items beneath a generator once for each context it reaches the generator in,
/// and every place that reaches it in that context shares them.
struct SafeDIToolMockTreeSharingTests: ~Copyable {
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
	mutating func mock_buildsItemsBeneathEachGeneratorOncePerContext_whenOneGeneratorIsReachedInsideAndOutsideASendableScope() async throws {
		let (builds, continuation) = AsyncStream.makeStream(of: MockTreeBuildKey.self)
		let output = try await MockTreeBuildObservation.$observer.withValue({ generator, insideSendableScope, propertiesGeneratedLater in
			continuation.yield(MockTreeBuildKey(generator: generator, insideSendableScope: insideSendableScope, propertiesGeneratedLater: propertiesGeneratedLater))
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Root: Instantiable, Sendable {
					    public init(a: A, bBuilder: SendableInstantiator<B>, c: C) {
					        self.a = a
					        self.bBuilder = bBuilder
					        self.c = c
					    }
					    @Instantiated let a: A
					    @Instantiated let bBuilder: SendableInstantiator<B>
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable, Sendable {
					    public init(g: G) { self.g = g }
					    @Instantiated let g: G
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable, Sendable {
					    public init(g: G) { self.g = g }
					    @Instantiated let g: G
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable, Sendable {
					    public init(g: G) { self.g = g }
					    @Instantiated let g: G
					}
					""",
					"""
					@Instantiable
					public struct G: Instantiable, Sendable {
					    public init(leaf: Leaf) { self.leaf = leaf }
					    @Instantiated let leaf: Leaf
					}
					""",
					"""
					@Instantiable
					public struct Leaf: Instantiable, Sendable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var buildCountByKey = [MockTreeBuildKey: Int]()
		for await build in builds {
			buildCountByKey[build, default: 0] += 1
		}

		// Root, A, C, G and Leaf outside the `@Sendable` builder, and B, G and Leaf inside it: G and Leaf are reached twice
		// outside it, beneath A and beneath C, and built once.
		#expect(buildCountByKey.count == 8)
		#expect(buildCountByKey.values.allSatisfy { $0 == 1 }, "\(buildCountByKey.values.sorted())")
		let contextCountByGenerator = Dictionary(grouping: buildCountByKey.keys, by: \.generator).mapValues(\.count)
		#expect(contextCountByGenerator.values.sorted() == [1, 1, 1, 1, 2, 2])
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == """
		PLACEHOLDER
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private struct MockTreeBuildKey: Hashable, Sendable {
		let generator: ObjectIdentifier
		let insideSendableScope: Bool
		let propertiesGeneratedLater: Set<Property>
	}
}
