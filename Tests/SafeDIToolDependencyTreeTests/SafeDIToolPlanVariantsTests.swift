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

/// The bodies a plan's declarations are built as (`PlanVariants`), read from the trees `generate` builds.
struct SafeDIToolPlanVariantsTests: ~Copyable {
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
	mutating func generate_plansOneBodyPerDeclaration_whenEveryCallOfCycleDeclaresLabelWithOneType() async throws {
		// `Root` and `Mid` each declare `x: X` above a build of `A`, whose alias reads `x`: two declarations, one answer by
		// value, so `A` has one body. The fixture of `SafeDIToolOnlyIfAvailableRenameTests`'
		// `run_bindsErasedAliasOfCycleParameterByMappingIt_whenReceiverRequiresIt`, where the layout by type key gives up.
		let projections = try await projections(of: """
		@Instantiable public final class A: Instantiable {
		    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, erasedToConcreteExistential: true, onlyIfAvailable: true) let anyX: AnyX?
		    @Instantiated let grand: Grand
		    @Instantiated let midBuilder: Instantiator<Mid>
		    public init(anyX: AnyX?, grand: Grand, midBuilder: Instantiator<Mid>) { self.anyX = anyX; self.grand = grand; self.midBuilder = midBuilder }
		}

		@Instantiable public final class Grand: Instantiable {
		    @Received let anyX: AnyX?
		    public init(anyX: AnyX?) { self.anyX = anyX }
		}

		@Instantiable public final class Mid: Instantiable {
		    @Instantiated let x: X
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(x: X, aBuilder: Instantiator<A>) { self.x = x; self.aBuilder = aBuilder }
		}

		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let x: X
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(x: X, aBuilder: Instantiator<A>) { self.x = x; self.aBuilder = aBuilder }
		}

		public protocol XProtocol {}
		public struct AnyX { public init(_ x: XProtocol) { self.x = x }; let x: XProtocol }
		@Instantiable public final class X: Instantiable, XProtocol { public init() {} }
		""")

		#expect(projections == [
			"""
			0: Root -> 1 -> 2
			1: X as x: X
			2: A as aBuilder: Instantiator<A> [x = x: X] -> 3 -> 4
			3: Grand as grand: Grand [anyX = anyX: AnyX?]
			4: Mid as midBuilder: Instantiator<Mid> -> 1 -> 2
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_plansBodyPerAnswer_whenOneCallOfCycleDeclaresLabelAndAnotherDoesNot() async throws {
		// Nothing above `Root`'s `A` declares `x`, so `Root` reads it from above too, as `nil`, and `Mid` declares it above
		// the `A` it builds: two answers, two bodies.
		let projections = try await projections(of: """
		@Instantiable public final class A: Instantiable {
		    @Received(onlyIfAvailable: true) let x: X?
		    @Instantiated let midBuilder: Instantiator<Mid>
		    public init(x: X?, midBuilder: Instantiator<Mid>) { self.x = x; self.midBuilder = midBuilder }
		}

		@Instantiable public final class Mid: Instantiable {
		    @Instantiated let x: X
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(x: X, aBuilder: Instantiator<A>) { self.x = x; self.aBuilder = aBuilder }
		}

		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
		}

		@Instantiable public final class X: Instantiable { public init() {} }
		""")

		#expect(projections == [
			"""
			0: Root [x = nil] -> 1
			1: A as aBuilder: Instantiator<A> [x = nil] -> 2
			2: Mid as midBuilder: Instantiator<Mid> -> 3 -> 4
			3: X as x: X
			4: A as aBuilder: Instantiator<A> [x = x: X] -> 2
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_marksAnswerBeingBuilt_whenDeclarationReadsLabelItIsBuiltAs() async throws {
		// `B` is built as `b` and receives `b` only if available: the nearest declaration of the label is the one being
		// built around it.
		let projections = try await projections(of: """
		@Instantiable public final class A: Instantiable {
		    @Instantiated let b: B
		    public init(b: B) { self.b = b }
		}

		@Instantiable public final class B: Instantiable {
		    @Received(onlyIfAvailable: true) let b: B?
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(b: B?, aBuilder: Instantiator<A>) { self.b = b; self.aBuilder = aBuilder }
		}

		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
		}
		""")

		#expect(projections == [
			"""
			0: Root -> 1
			1: A as aBuilder: Instantiator<A> -> 2
			2: B as b: B [b = b: B being built] -> 1
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The bodies of each tree `generate` builds from `swiftFileContent` that reaches a cycle, as text, in the order first
	/// built. A run builds a root's tree more than once, and every build of one tree has one plan, so each distinct
	/// projection is listed once.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func projections(of swiftFileContent: String) async throws -> [String] {
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		try await PerTypePlanObservation.$variantsObserver.withValue(TaskLocalFunction { projection in
			continuation.yield(projection)
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var projections = [String]()
		for await projection in stream where !projections.contains(projection) {
			projections.append(projection)
		}
		return projections
	}
}
