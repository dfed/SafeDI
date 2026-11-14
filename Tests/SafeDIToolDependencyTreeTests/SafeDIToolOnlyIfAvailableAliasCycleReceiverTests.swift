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

/// The receive a dependency cycle error is reported at, when the cycle closes through a type that declares several
/// `onlyIfAvailable` aliases of the property the cycle closes on: the error is at the receiver of the alias a type
/// beneath requires, whichever alias the type declares first.
struct SafeDIToolOnlyIfAvailableAliasCycleReceiverTests: ~Copyable {
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
	mutating func run_throwsErrorAtReceiverOfRequiredAlias_whenTypeDeclaresUnrequiredAliasOfSameOptionalFormFirst() async {
		// D requires `y`, which C can create only once Root's `x` is built, but X requires `b`, inside whose tree D is built.
		// C declares `w`, an alias of `x: X?` too, which nothing requires, before `y`: the search for the receiver passes
		// `w` and finds D's receive of `y`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["D.swift"]):4:5: error: Dependency cycle: @Instantiated `x: X` -> @Received `b: B` -> @Received `x: X?` -> @Received `x: X`. `x: X` is received while it is still being instantiated. `y: X?` renames `x: X?` only if available, so a type that receives `y` without `onlyIfAvailable` must be built after `x: X?`. Receive `y` with `@Received(onlyIfAvailable: true)` to be passed `nil` where `x: X?` cannot be built first.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(x: X, b: B) { self.x = x; self.b = b }
					    @Instantiated let x: X
					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable
					public final class X: Instantiable {
					    public init(b: B) { self.b = b }
					    @Received let b: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    public init(c: C) { self.c = c }
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    public init(w: X?, y: X?, d: D) { self.w = w; self.y = y; self.d = d }
					    @Received(fulfilledByDependencyNamed: "x", ofType: X?.self, onlyIfAvailable: true) let w: X?
					    @Received(fulfilledByDependencyNamed: "x", ofType: X?.self, onlyIfAvailable: true) let y: X?
					    @Instantiated let d: D
					}
					""",
					"""
					@Instantiable
					public final class D: Instantiable {
					    public init(y: X?) { self.y = y }
					    @Received let y: X?
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
