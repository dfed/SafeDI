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

/// Output jobs of production output that throw: every failing root reports its error, in source order, whatever order the jobs
/// complete in. The failures come from `outputJobObserver`: the one known output failure of valid input, a deliberate
/// gap, has no location and one message, so it could not show the order.
struct SafeDIToolOutputFailureTests: ~Copyable {
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
	mutating func generate_reportsBothFailuresInSourceOrder_whenTwoRootsThrowDuringProductionOutput() async throws {
		// `Beta` is declared before `Alpha`, which comes first in type order.
		let fixture = """
		@Instantiable(isRoot: true)
		public struct Beta: Instantiable {
		    public init() {}
		}

		@Instantiable(isRoot: true)
		public struct Alpha: Instantiable {
		    public init() {}
		}
		"""
		for (orderName, releaseOrder) in [(name: "index order", releaseOrder: [0, 1]), (name: "reverse order", releaseOrder: [1, 0])] {
			let description = try await thrownDescription(
				fixture: fixture,
				jobCount: 2,
				releaseOrder: releaseOrder,
				failure: { rootType in
					OutputFailure(rootType: rootType, location: .init(filePath: "Roots.swift", line: rootType == "Beta" ? 1 : 6, column: 1))
				},
			)
			#expect(description == """
			Roots.swift:1:1: error: Generating `Beta` failed.
			Roots.swift:6:1: error: Generating `Alpha` failed.
			""", "\(orderName)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsEveryLocatedFailureInSourceOrder_whenTwentyRootsThrowDuringProductionOutputInAnyCompletionOrder() async throws {
		// The roots are declared in an order that is not their type order. Each root first in type order at an even index
		// throws an error SafeDI declares, and each other root another error located in source, which is wrapped.
		for (orderName, releaseOrder) in ForcedCompletionOrder.orders(ofJobCount: 20) {
			let description = try await thrownDescription(
				fixture: Self.twentyRootsFixture,
				jobCount: 20,
				releaseOrder: releaseOrder,
				failure: Self.locatedFailure(of:),
			)
			#expect(description == """
			Roots.swift:1:1: error: Generating `Root03` failed.
			Roots.swift:6:1: error: `Root10` cannot have a hand-written `mock()` method because it is decorated with `@Instantiable(generateMock: true)`, and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@Instantiable` that declares it.
			Roots.swift:11:1: error: Generating `Root17` failed.
			Roots.swift:16:1: error: `Root04` cannot have a hand-written `mock()` method because it is decorated with `@Instantiable(generateMock: true)`, and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@Instantiable` that declares it.
			Roots.swift:21:1: error: Generating `Root11` failed.
			Roots.swift:26:1: error: `Root18` cannot have a hand-written `mock()` method because it is decorated with `@Instantiable(generateMock: true)`, and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@Instantiable` that declares it.
			Roots.swift:31:1: error: Generating `Root05` failed.
			Roots.swift:36:1: error: `Root12` cannot have a hand-written `mock()` method because it is decorated with `@Instantiable(generateMock: true)`, and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@Instantiable` that declares it.
			Roots.swift:41:1: error: Generating `Root19` failed.
			Roots.swift:46:1: error: `Root06` cannot have a hand-written `mock()` method because it is decorated with `@Instantiable(generateMock: true)`, and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@Instantiable` that declares it.
			Roots.swift:51:1: error: Generating `Root13` failed.
			Roots.swift:56:1: error: `Root00` cannot have a hand-written `mock()` method because it is decorated with `@Instantiable(generateMock: true)`, and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@Instantiable` that declares it.
			Roots.swift:61:1: error: Generating `Root07` failed.
			Roots.swift:66:1: error: `Root14` cannot have a hand-written `mock()` method because it is decorated with `@Instantiable(generateMock: true)`, and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@Instantiable` that declares it.
			Roots.swift:71:1: error: Generating `Root01` failed.
			Roots.swift:76:1: error: `Root08` cannot have a hand-written `mock()` method because it is decorated with `@Instantiable(generateMock: true)`, and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@Instantiable` that declares it.
			Roots.swift:81:1: error: Generating `Root15` failed.
			Roots.swift:86:1: error: `Root02` cannot have a hand-written `mock()` method because it is decorated with `@Instantiable(generateMock: true)`, and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@Instantiable` that declares it.
			Roots.swift:91:1: error: Generating `Root09` failed.
			Roots.swift:96:1: error: `Root16` cannot have a hand-written `mock()` method because it is decorated with `@Instantiable(generateMock: true)`, and the generated and hand-written methods would have ambiguous signatures. Give the hand-written method a different name and pass that name as `customMockName` on the `@Instantiable` that declares it.
			""", "\(orderName)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsOnlyTheUnlocatedFailureOfTheRootFirstInTypeOrder_whenTwentyRootsThrowDuringProductionOutputInAnyCompletionOrder() async throws {
		// Three roots throw an error with no location; the others throw located errors, which are not reported.
		for (orderName, releaseOrder) in ForcedCompletionOrder.orders(ofJobCount: 20) {
			let description = try await thrownDescription(
				fixture: Self.twentyRootsFixture,
				jobCount: 20,
				releaseOrder: releaseOrder,
				failure: { rootType in
					["Root05", "Root09", "Root14"].contains(rootType) ? UnlocatedOutputFailure(rootType: rootType) : Self.locatedFailure(of: rootType)
				},
			)
			#expect(description == "Generating Root05 failed without a location.", "\(orderName)")
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Twenty roots in one file, declared in an order that is not their type order.
	private static let twentyRootsFixture = """
	@Instantiable(isRoot: true)
	public struct Root03: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root10: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root17: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root04: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root11: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root18: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root05: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root12: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root19: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root06: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root13: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root00: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root07: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root14: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root01: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root08: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root15: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root02: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root09: Instantiable {
	    public init() {}
	}

	@Instantiable(isRoot: true)
	public struct Root16: Instantiable {
	    public init() {}
	}
	"""

	/// The located failure the root of type `rootType` throws in `twentyRootsFixture`: an error SafeDI declares for a
	/// root at an even index in type order, and another error located in source for the others, each at the root's
	/// declaration.
	private static func locatedFailure(of rootType: String) -> any Error {
		let declarationLine = twentyRootsFixture.split(separator: "\n", omittingEmptySubsequences: false)
			.firstIndex { $0.hasPrefix("public struct \(rootType):") } ?? 0
		let location = Dependency.DeclarationLocation(filePath: "Roots.swift", line: declarationLine, column: 1)
		return (Int(rootType.suffix(2)) ?? 0).isMultiple(of: 2)
			? DependencyTreeGenerator.DependencyTreeGeneratorError.handWrittenMockSharesGeneratedMockName(
				TypeDescription.simple(name: rootType),
				declaredAt: [location],
				isGeneratedForAdditionalMocksToGenerate: false,
			)
			: OutputFailure(rootType: rootType, location: location)
	}

	/// What `generate` throws for `fixture` when each output job throws `failure` of its root's type, at a width that
	/// admits every job at once, with the jobs of each helper call completing in `releaseOrder`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func thrownDescription(
		fixture: String,
		jobCount: Int,
		releaseOrder: [Int],
		failure: @escaping @Sendable (_ rootType: String) -> any Error,
	) async throws -> String? {
		let forcedOrder = ForcedCompletionOrder(jobCount: jobCount, releaseOrder: releaseOrder)
		do {
			_ = try await GenerationJobs.$width.withValue(32) {
				try await GenerationJobs.$completionObserver.withValue(forcedOrder.arrive) {
					try await DependencyTreeGenerator.$outputJobObserver.withValue({ rootType in throw failure(rootType.asSource) }) {
						try await executeSafeDIToolTest(
							swiftFileContent: [fixture],
							buildSwiftOutputDirectory: true,
							filesToDelete: &filesToDelete,
						)
					}
				}
			}
			Issue.record("Did not throw error!")
			return nil
		} catch let error as SafeDIToolTestError {
			return "\(error)"
		}
	}
}

/// A failure of an output job, located in source, that SafeDI does not declare.
private struct OutputFailure: SourceLocatedError {
	let rootType: String
	let location: Dependency.DeclarationLocation

	var sourceDiagnostics: [SourceDiagnostic] {
		[SourceDiagnostic(severity: .error, location: location, message: "Generating `\(rootType)` failed.")]
	}
}

/// A failure of an output job with no location in source.
private struct UnlocatedOutputFailure: Error, CustomStringConvertible {
	let rootType: String

	var description: String {
		"Generating \(rootType) failed without a location."
	}
}
