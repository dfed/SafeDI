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

/// Rule 3's second stage laid out from node records: where `nil` keys with a lazy wrapper, one function of a cycle takes
/// the wrapper, optional where some call passes `nil`, and each call passes what it has. Each expectation is 2.4.x's text.
struct SafeDIToolNodeRecordsWrapperOrNilTests: ~Copyable {
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
	mutating func generate_laysOutOneFunctionTakingTheOptionalWrapper_whenOneParentPassesTheWrapperAndAnotherNothing() async throws {
		// `Second` passes `Leaf` a lazy wrapper of `theme` and `Third` nothing: one function takes the wrapper as optional,
		// reads its instance through optional chaining, and `Third`'s call passes `nil` (cell s1).
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    public init(second: Second, third: Third) { self.second = second; self.third = third }
					    @Instantiated let second: Second
					    @Instantiated let third: Third
					}
					@Instantiable public final class First: Instantiable {
					    public init(theme: Theme, leafBuilder: Instantiator<Leaf>) { self.theme = theme; self.leafBuilder = leafBuilder }
					    @Instantiated let theme: Theme
					    @Instantiated let leafBuilder: Instantiator<Leaf>
					}
					@Instantiable public final class Second: Instantiable {
					    public init(theme: LazilyInstantiated<Theme>, leafBuilder: Instantiator<Leaf>) { self.theme = theme; self.leafBuilder = leafBuilder }
					    @Instantiated let theme: LazilyInstantiated<Theme>
					    @Instantiated let leafBuilder: Instantiator<Leaf>
					}
					@Instantiable public final class Leaf: Instantiable {
					    public init(theme: Theme?, leafBuilder: Instantiator<Leaf>) { self.theme = theme; self.leafBuilder = leafBuilder }
					    @Received(onlyIfAvailable: true) let theme: Theme?
					    @Instantiated let leafBuilder: Instantiator<Leaf>
					}
					@Instantiable public final class Theme: Instantiable {
					    public init() {}
					}
					@Instantiable public final class Third: Instantiable {
					    public init(leafBuilder: Instantiator<Leaf>) { self.leafBuilder = leafBuilder }
					    @Instantiated let leafBuilder: Instantiator<Leaf>
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_theme() -> Theme {
			            Theme()
			        }
			        func __safeDI_leafBuilder(theme: LazilyInstantiated<Theme>?) -> Leaf {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(theme: theme)
			            }
			            return Leaf(theme: theme?.instance, leafBuilder: leafBuilder)
			        }
			        func __safeDI_second() -> Second {
			            let theme = LazilyInstantiated<Theme>(__safeDI_theme)
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(theme: theme)
			            }
			            return Second(theme: theme, leafBuilder: leafBuilder)
			        }
			        let second: Second = __safeDI_second()
			        func __safeDI_third() -> Third {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(theme: nil)
			            }
			            return Third(leafBuilder: leafBuilder)
			        }
			        let third: Third = __safeDI_third()
			        self.init(second: second, third: third)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true], "\(reports.map(\.refusal))")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutTheLazyWrappersFunctionTakingNil_whenASendableWrapperALazyWrapperAndNothingReachTheReceive() async throws {
		// `First` passes a Sendable lazy wrapper, `Second` a lazy one and `Third` nothing: `nil` goes to the lazy wrapper's
		// function, which takes it as optional, and the Sendable one's takes its wrapper as declared (cell s3).
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    public init(second: Second, first: First, third: Third) { self.second = second; self.first = first; self.third = third }
					    @Instantiated let second: Second
					    @Instantiated let first: First
					    @Instantiated let third: Third
					}
					@Instantiable public final class First: Instantiable {
					    public init(theme: SendableLazilyInstantiated<Theme>, leafBuilder: Instantiator<Leaf>) { self.theme = theme; self.leafBuilder = leafBuilder }
					    @Instantiated let theme: SendableLazilyInstantiated<Theme>
					    @Instantiated let leafBuilder: Instantiator<Leaf>
					}
					@Instantiable public final class Second: Instantiable {
					    public init(theme: LazilyInstantiated<Theme>, leafBuilder: Instantiator<Leaf>) { self.theme = theme; self.leafBuilder = leafBuilder }
					    @Instantiated let theme: LazilyInstantiated<Theme>
					    @Instantiated let leafBuilder: Instantiator<Leaf>
					}
					@Instantiable public final class Leaf: Instantiable {
					    public init(theme: Theme?, leafBuilder: Instantiator<Leaf>) { self.theme = theme; self.leafBuilder = leafBuilder }
					    @Received(onlyIfAvailable: true) let theme: Theme?
					    @Instantiated let leafBuilder: Instantiator<Leaf>
					}
					@Instantiable public final class Theme: Instantiable, Sendable {
					    public init() {}
					}
					@Instantiable public final class Third: Instantiable {
					    public init(leafBuilder: Instantiator<Leaf>) { self.leafBuilder = leafBuilder }
					    @Instantiated let leafBuilder: Instantiator<Leaf>
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_theme() -> Theme {
			            Theme()
			        }
			        func __safeDI_leafBuilder(theme: LazilyInstantiated<Theme>?) -> Leaf {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(theme: theme)
			            }
			            return Leaf(theme: theme?.instance, leafBuilder: leafBuilder)
			        }
			        func __safeDI_second() -> Second {
			            let theme = LazilyInstantiated<Theme>(__safeDI_theme)
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(theme: theme)
			            }
			            return Second(theme: theme, leafBuilder: leafBuilder)
			        }
			        let second: Second = __safeDI_second()
			        @Sendable nonisolated func __safeDI_theme_() -> Theme {
			            Theme()
			        }
			        func __safeDI_leafBuilder_(theme: SendableLazilyInstantiated<Theme>) -> Leaf {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder_(theme: theme)
			            }
			            return Leaf(theme: theme.instance, leafBuilder: leafBuilder)
			        }
			        func __safeDI_first() -> First {
			            let theme = SendableLazilyInstantiated<Theme>(__safeDI_theme_)
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder_(theme: theme)
			            }
			            return First(theme: theme, leafBuilder: leafBuilder)
			        }
			        let first: First = __safeDI_first()
			        func __safeDI_third() -> Third {
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(theme: nil)
			            }
			            return Third(leafBuilder: leafBuilder)
			        }
			        let third: Third = __safeDI_third()
			        self.init(second: second, first: first, third: third)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true], "\(reports.map(\.refusal))")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static func layingOutRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
				try await body(&filesMade)
			}
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream {
			reports.append(report)
		}
		return (output, reports)
	}
}
