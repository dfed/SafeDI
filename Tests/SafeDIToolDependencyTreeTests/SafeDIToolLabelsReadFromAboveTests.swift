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

/// The labels a scope's subtree reads from above it, as the least sets of the rule (`LabelsReadFromAbove`), over the
/// scopes the validation walk asks the same question of.
struct SafeDIToolLabelsReadFromAboveTests: ~Copyable {
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
	mutating func generate_findsLabelReadAroundCycle_whenWalkEntersCycleAtTheScopeThatReadsIt() async {
		// `A` and `B` open each other and `B` receives `y`, so `A`'s tree reads `y` through `B`. `Third`, which declares
		// `y`, enters the cycle at `B`: a walk from there finishes `A` while `B` is still in progress. `One` declares `y`
		// above `A` and `Two` does not, so `Two`'s tree reads `y` from above it, where nothing declares it.
		let (stream, continuation) = AsyncStream.makeStream(of: Answer.self)
		await LabelsReadFromAboveObservation.$observer.withValue(TaskLocalFunction { type, _, byComponent, byPasses in
			continuation.yield(Answer(type: type, byComponent: byComponent, byPasses: byPasses))
		}) {
			// Whether the tree is rejected is the validation walk's subject, not this test's: it reads what the walk asked.
			do {
				_ = try await executeSafeDIToolTest(
					swiftFileContent: [
						"""
						@Instantiable(isRoot: true)
						public struct Root: Instantiable {
							public init(one: Instantiator<One>, two: Instantiator<Two>, third: Instantiator<Third>) {
								self.one = one
								self.two = two
								self.third = third
							}

							@Instantiated let one: Instantiator<One>
							@Instantiated let two: Instantiator<Two>
							@Instantiated let third: Instantiator<Third>
						}

						@Instantiable
						public struct One: Instantiable {
							public init(y: Y, aBuilder: Instantiator<A>) {
								self.y = y
								self.aBuilder = aBuilder
							}

							@Instantiated let y: Y
							@Instantiated let aBuilder: Instantiator<A>
						}

						@Instantiable
						public struct Two: Instantiable {
							public init(aBuilder: Instantiator<A>) {
								self.aBuilder = aBuilder
							}

							@Instantiated let aBuilder: Instantiator<A>
						}

						@Instantiable
						public struct Third: Instantiable {
							public init(y: Y, bBuilder: Instantiator<B>) {
								self.y = y
								self.bBuilder = bBuilder
							}

							@Instantiated let y: Y
							@Instantiated let bBuilder: Instantiator<B>
						}

						@Instantiable
						public struct A: Instantiable {
							public init(bBuilder: Instantiator<B>) {
								self.bBuilder = bBuilder
							}

							@Instantiated let bBuilder: Instantiator<B>
						}

						@Instantiable
						public struct B: Instantiable {
							public init(y: Y, aBuilder: Instantiator<A>) {
								self.y = y
								self.aBuilder = aBuilder
							}

							@Received let y: Y
							@Instantiated let aBuilder: Instantiator<A>
						}

						@Instantiable
						public struct Y: Instantiable {
							public init() {}
						}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
					skipCompileVerification: true,
				)
			} catch {}
		}
		continuation.finish()
		var labelsByType = [String: [String]]()
		for await answer in stream {
			#expect(answer.byComponent == answer.byPasses, "\(answer.type)")
			labelsByType[answer.type] = answer.byComponent
		}

		#expect(labelsByType["A"] == ["y"])
		#expect(labelsByType["B"] == ["y"])
		#expect(labelsByType["Two"] == ["y"])
		#expect(labelsByType["One"] == [])
		#expect(labelsByType["Third"] == [])
	}

	// MARK: Private

	private struct Answer: Sendable {
		let type: String
		let byComponent: [String]
		let byPasses: [String]
	}

	private var filesToDelete: [URL]
}
