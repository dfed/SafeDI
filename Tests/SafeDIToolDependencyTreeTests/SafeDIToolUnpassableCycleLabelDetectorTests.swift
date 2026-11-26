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

/// Which production roots the plan's detector of labels no one parameter can pass keeps on today's tree
/// (`UnpassableCycleLabelObservation`). Every test that reports such a label checks that the detector fires for its root
/// (`UnpassableCycleLabelChecks`); these check where it fires though today reports nothing, and where it does not fire.
struct SafeDIToolUnpassableCycleLabelDetectorTests: ~Copyable {
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
	mutating func generate_keepsRootOnTodaysTree_whenCycleRedeclaresLabelItsTreeReceivesInTwoPassableForms() async throws {
		// `A` requires `x: X` and `B` beneath it receives `x: X?` only if available: one parameter `x: X` carries both, so
		// today reports nothing, but `S` declares `x` again on the cycle and `A`'s tree receives two forms of it, so the
		// detector keeps the root on today's tree, whose code is today's.
		let (output, detections) = try await detections(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let x: X
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(x: X, aBuilder: Instantiator<A>) { self.x = x; self.aBuilder = aBuilder }
		}

		@Instantiable public final class X: Instantiable { public init() {} }

		@Instantiable public final class A: Instantiable {
		    @Received let x: X
		    @Instantiated let b: B
		    @Instantiated let sBuilder: Instantiator<S>
		    public init(x: X, b: B, sBuilder: Instantiator<S>) { self.x = x; self.b = b; self.sBuilder = sBuilder }
		}

		@Instantiable public final class B: Instantiable {
		    @Received(onlyIfAvailable: true) let x: X?
		    public init(x: X?) { self.x = x }
		}

		@Instantiable public final class S: Instantiable {
		    @Instantiated let x: X
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(x: X, aBuilder: Instantiator<A>) { self.x = x; self.aBuilder = aBuilder }
		}
		""")

		#expect(detections == ["Root": Detection(detectorFires: true, todaysTreeReports: false)])
		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": generatedFileHeader + """
		extension Root {
		    public convenience init() {
		        let x = X()
		        func __safeDI_aBuilder(x: X) -> A {
		            let b = B(x: x)
		            let sBuilder = Instantiator<S>(__safeDI_sBuilder)
		            return A(x: x, b: b, sBuilder: sBuilder)
		        }
		        func __safeDI_sBuilder() -> S {
		            let x = X()
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(x: x)
		            }
		            return S(x: x, aBuilder: aBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(x: x)
		        }
		        self.init(x: x, aBuilder: aBuilder)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_leavesRootToPlan_whenNoTypeOnCycleReceivesLabel() async throws {
		// Screens open each other through builders whose labels each screen declares again, and no screen receives
		// anything: no label is passed around the cycle, so the detector leaves the root to its plan.
		let (_, detections) = try await detections(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let home: S0
		    public init(home: S0) { self.home = home }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    @Instantiated let s2Builder: Instantiator<S2>
		    public init(s1Builder: Instantiator<S1>, s2Builder: Instantiator<S2>) { self.s1Builder = s1Builder; self.s2Builder = s2Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let s2Builder: Instantiator<S2>
		    public init(s2Builder: Instantiator<S2>) { self.s2Builder = s2Builder }
		}

		@Instantiable public final class S2: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}
		""")

		#expect(detections == ["Root": Detection(detectorFires: false, todaysTreeReports: false)])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private struct Detection: Equatable, Sendable {
		let detectorFires: Bool
		let todaysTreeReports: Bool
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func detections(of swiftFileContent: String) async throws -> (TestOutput, [String: Detection]) {
		let (stream, continuation) = AsyncStream.makeStream(of: (String, Detection).self)
		let output = try await UnpassableCycleLabelObservation.$observer.withValue({ root, detectorFires, todaysTreeReports in
			continuation.yield((root, Detection(detectorFires: detectorFires, todaysTreeReports: todaysTreeReports)))
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var detections = [String: Detection]()
		for await (root, detection) in stream {
			detections[root] = detection
		}
		return (output, detections)
	}
}
