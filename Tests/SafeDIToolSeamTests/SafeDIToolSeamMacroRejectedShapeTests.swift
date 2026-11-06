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

/// Shapes of a seam the `@Instantiable` macro rejects, which `generate` – run before the compiler expands the macro –
/// reports with a plain error at the declaration rather than relying on the macro: a seam whose tree repeats a
/// dependency label, which the generated tier would repeat, and a `mockOnly` declaration that is also a seam, which
/// has no tree of its own. These fixtures are the one exception to fixtures the macro accepts.
struct SafeDIToolSeamMacroRejectedShapeTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A dependency declared in each clause of a platform condition

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtLaterDeclaration_whenSeamTreeDeclaresDependencyInEachClauseOfPlatformCondition() async {
		// `Panel`, a seam reached beneath `Screen`'s `onlyIfAvailable` alias, declares `x` in each clause: the plain error
		// is reported before any seam signature is computed, where the walk of `Screen`'s tree would otherwise key
		// `Panel`'s parameters by property and meet two.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Panel.swift"]):11:5: error: `Panel` declares the dependency `x` more than once. Declare it once: if each clause of an `#if` that only the compiler decides, such as `#if os(iOS)`, declares it, declare it outside the `#if`, since SafeDI reads every clause.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: Self.rootFixture(declarations: ["@Instantiated let token: Secret", "@Instantiated let x: X", "@Instantiated let screen: Screen"]) + [Self.screen] + Self.panelAndChild + Self.plainTypes, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtLaterDeclaration_whenSeamNoRootReachesDeclaresDependencyInEachClauseOfPlatformCondition() async {
		// A seam no root reaches is still a generated tree, so its repeated label is reported rather than generating an
		// initializer that takes `x` twice.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Panel.swift"]):11:5: error: `Panel` declares the dependency `x` more than once. Declare it once: if each clause of an `#if` that only the compiler decides, such as `#if os(iOS)`, declares it, declare it outside the `#if`, since SafeDI reads every clause.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: Self.rootFixture(declarations: ["@Instantiated let x: X"]) + Self.panelAndChild + Self.plainTypes, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: A mockOnly declaration that is a seam

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtDeclaration_whenMockOnlyDeclarationGeneratesDependencyTreeAndAnotherSeamFulfillsItsType() async {
		// `D`, a production seam, fulfills `K` additionally, so `K`'s `mockOnly` declaration loses the `K` slot to `D` but
		// keeps `Proto`'s: the seams would be `D` twice, which the plain error reports before any seam is resolved.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["K.swift"]):1:1: error: `K` is declared `mockOnly: true` and `generateDependencyTree: true`. The @Instantiable macro rejects that: a `mockOnly` declaration provides a hand-written mock and has no dependency tree. Remove `generateDependencyTree: true`.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: Self.rootFixture(declarations: ["@Instantiated let x: X", "@Instantiated let d: D"]) + [Self.mockOnlySeam, Self.seamFulfillingMockOnlyType, Self.x], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtDeclaration_whenMockOnlyDeclarationGeneratesDependencyTree() async {
		// The same declaration alone, which `generate` failed on with no message.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["K.swift"]):1:1: error: `K` is declared `mockOnly: true` and `generateDependencyTree: true`. The @Instantiable macro rejects that: a `mockOnly` declaration provides a hand-written mock and has no dependency tree. Remove `generateDependencyTree: true`.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: Self.rootFixture(declarations: ["@Instantiated let x: X"]) + [Self.mockOnlySeam, Self.x], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static func rootFixture(declarations: [String]) -> [String] {
		[seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: declarations)]
	}

	private static let screen = """
	@Instantiable(generateDependencyTree: true)
	public final class Screen: Instantiable {
	    public init(authToken: Secret?, panel: Panel) {
	        self.authToken = authToken
	        self.panel = panel
	    }

	    @Received(fulfilledByDependencyNamed: "token", ofType: Secret.self, onlyIfAvailable: true) let authToken: Secret?
	    @Instantiated let panel: Panel
	}
	"""

	private static let panelAndChild = [
		"""
		@Instantiable(generateDependencyTree: true)
		public final class Panel: Instantiable {
		    public init(x: X, child: Child) {
		        self.x = x
		        self.child = child
		    }

		    #if os(iOS)
		    @Received let x: X
		    #else
		    @Received let x: X
		    #endif
		    @Instantiated let child: Child
		}
		""",
		seamFixtureType(named: "Child", isFinalClass: true, declarations: []),
	]

	private static let plainTypes = [
		seamFixtureType(named: "X", isFinalClass: true, declarations: []),
		seamFixtureType(named: "Secret", isFinalClass: true, declarations: []),
	]

	private static let x = seamFixtureType(named: "X", isFinalClass: true, declarations: [])

	private static let mockOnlySeam = """
	@Instantiable(mockOnly: true, generateDependencyTree: true, fulfillingAdditionalTypes: [Proto.self])
	public class K: Instantiable, Proto {
	    public init() {}

	    public static func mock() -> K {
	        K()
	    }
	}

	public protocol Proto {}
	"""

	private static let seamFulfillingMockOnlyType = """
	@Instantiable(generateDependencyTree: true, fulfillingAdditionalTypes: [K.self])
	public final class D: K {
	    public init(x: X) {
	        self.x = x
	        super.init()
	    }

	    @Received let x: X
	}
	"""
}
