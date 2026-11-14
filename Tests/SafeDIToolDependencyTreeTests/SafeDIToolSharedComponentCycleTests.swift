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

/// Siblings that require one another, where a loop of instantiators hides a cycle with a value on it from the search in
/// sibling order: the search marks the loop's members visited before it meets the value, so the value's receive of a
/// member reads as no back edge. The cycle is still found, by the search from each value through the siblings that
/// require one another in turn, and reported.
struct SafeDIToolSharedComponentCycleTests: ~Copyable {
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
	mutating func run_throwsDependencyCycleErrorThroughValue_whenLoopOfInstantiatorsIsSearchedBeforeValueThatClosesCycleThroughIt() async {
		// `sBuilder` leads the search into the loop `pBuilder` -> `qBuilder` -> `dBuilder`, all instantiators, and only then
		// to `v`, whose receive of `qBuilder` meets a visited sibling. The search from `v` passes `dBuilder`, which leads
		// nowhere new, and closes the cycle through `pBuilder`'s receive of `v`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["P.swift"]):9:5: error: Dependency cycle: @Instantiated `v: V` -> @Received `qBuilder: Instantiator<Q>` -> @Received `pBuilder: Instantiator<P>` -> @Received `v: V`. `v: V` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", isRoot: true, "@Instantiated let sBuilder: Instantiator<S>", "@Instantiated let dBuilder: Instantiator<D>", "@Instantiated let pBuilder: Instantiator<P>", "@Instantiated let qBuilder: Instantiator<Q>", "@Instantiated let v: V"),
				Self.type("S", "@Received let pBuilder: Instantiator<P>"),
				Self.type("D", "@Received let qBuilder: Instantiator<Q>"),
				Self.type("P", "@Received let qBuilder: Instantiator<Q>", "@Received let v: V"),
				Self.type("Q", "@Received let dBuilder: Instantiator<D>", "@Received let pBuilder: Instantiator<P>"),
				Self.type("V", "@Received let qBuilder: Instantiator<Q>"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsDependencyCycleErrorThroughErasingRename_whenLoopOfInstantiatorsIsSearchedBeforeRenameThatClosesCycleThroughIt() async {
		// Every sibling is an instantiator, and `wBuilder` receives `qBuilder` through `anyQ`, a rename that erases it, so
		// the cycle `qBuilder` -> `pBuilder` -> `wBuilder` -> `anyQ` -> `qBuilder` has a value on it. The search in sibling order meets
		// `anyQ` only once `qBuilder` is visited; the search from `qBuilder` passes `dBuilder`, whose receive of
		// `qBuilder` is no rename and closes nothing, and closes the cycle at `wBuilder`'s receive of `anyQ`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["W.swift"]):7:5: error: Dependency cycle: @Instantiated `qBuilder: Instantiator<Q>` -> @Received `pBuilder: Instantiator<P>` -> @Received `wBuilder: Instantiator<W>` -> @Received `anyQ: AnyQ` -> @Received `qBuilder: Instantiator<Q>`. `qBuilder: Instantiator<Q>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", isRoot: true, "@Instantiated let sBuilder: Instantiator<S>", "@Instantiated let dBuilder: Instantiator<D>", "@Instantiated let pBuilder: Instantiator<P>", "@Instantiated let qBuilder: Instantiator<Q>", "@Instantiated let wBuilder: Instantiator<W>", "@Received(fulfilledByDependencyNamed: \"qBuilder\", ofType: Instantiator<Q>.self, erasedToConcreteExistential: true) let anyQ: AnyQ"),
				Self.type("S", "@Received let pBuilder: Instantiator<P>"),
				Self.type("D", "@Received let qBuilder: Instantiator<Q>"),
				Self.type("P", "@Received let qBuilder: Instantiator<Q>", "@Received let wBuilder: Instantiator<W>"),
				Self.type("Q", "@Received let dBuilder: Instantiator<D>", "@Received let pBuilder: Instantiator<P>"),
				Self.type("W", "@Received let anyQ: AnyQ"),
				"""
				public struct AnyQ {
				    public init(_ builder: Instantiator<Q>) {}
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static func type(_ name: String, isRoot: Bool = false, _ declarations: String...) -> String {
		seamFixtureType(named: name, isRoot: isRoot, isFinalClass: true, declarations: declarations)
	}
}
