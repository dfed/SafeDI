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

/// A loop of builders the type key lays out moves its functions out of the nesting the walk wrote them in, so every line
/// of their text takes the function's new indentation, a rebinding wrapped in `#sourceLocation` directives included.
struct SafeDIToolMockTypeKeyLoopIndentationTests: ~Copyable {
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
	mutating func mock_indentsEveryLineOfRebindingAtItsFunction_whenTypeKeyLaysOutRenameWrappedInSourceLocation() async throws {
		// `Child`, built inside the `Node` the promoted `nodeBuilder` builds, aliases `nodeBuilder`, so its rebinding is
		// wrapped in `#sourceLocation` directives, three lines of one element of the loop's text.
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(nodeBuilder: Instantiator<Node>) { self.nodeBuilder = nodeBuilder }
			    @Received let nodeBuilder: Instantiator<Node>
			}
			""",
			"""
			@Instantiable
			public final class Node: Instantiable {
			    public init(child: Child) { self.child = child }
			    @Instantiated let child: Child
			}
			""",
			"""
			@Instantiable
			public final class Child: Instantiable {
			    public init(childBuilder: Instantiator<Node>) { self.childBuilder = childBuilder }
			    @Received(fulfilledByDependencyNamed: "nodeBuilder", ofType: Instantiator<Node>.self) let childBuilder: Instantiator<Node>
			}
			""",
		]
		let output = try await MockLowering.$laysOutWithTypeKey.withValue(true) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: Node.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                nodeBuilder: nodeBuilder
			            )
			        }

			        var nodeBuilder: Node.SafeDIMockConfiguration { __safeDI_storage.nodeBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                nodeBuilder: Node.SafeDIMockConfiguration
			            ) {
			                self.nodeBuilder = nodeBuilder
			            }

			            let nodeBuilder: Node.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_nodeBuilder(__safeDI_Node_configuration: Node.SafeDIMockConfiguration) -> Node {
			            let nodeBuilder = Instantiator<Node> {
			                __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
			            }
			            let child: Child = __safeDI_child(nodeBuilder: nodeBuilder, __safeDI_Child_configuration: __safeDI_Node_configuration.child)
			            return if let safeDIBuilder = __safeDI_Node_configuration.safeDIBuilder { safeDIBuilder(child) } else { Node(child: child) }
			        }
			        func __safeDI_child(nodeBuilder: Instantiator<Node>, __safeDI_Child_configuration: ((Instantiator<Node>) -> Child)?) -> Child {
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 4)
			            let childBuilder: Instantiator<Node> = nodeBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = __safeDI_Child_configuration { safeDIBuilder(childBuilder) } else { Child(childBuilder: childBuilder) }
			        }
			        let nodeBuilder = Instantiator<Node> {
			            __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
			        }
			        return Screen(nodeBuilder: nodeBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
