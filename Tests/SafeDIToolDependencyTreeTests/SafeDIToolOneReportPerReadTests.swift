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

/// A receive that one root's tree reaches by many chains of scopes is reported once per answer it is given: a receive
/// nothing fulfills once for each root, and a receive a closer declaration hides once for each nearest declaration that
/// hides it, each from the first chain a depth-first walk of the tree in declaration order reaches it by. Each test builds
/// twenty chains through twenty screens the root declares in an order that is not the order of their names, so a report
/// chosen by name, by message text or by the order of a set names another screen on nearly every run.
struct SafeDIToolOneReportPerReadTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – A receive nothing fulfills

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsUnfulfillableReceiveOnceFromFirstDeclaredChain_whenTwentyChainsOfOneRootReachIt() async {
		// Every screen builds the `Reader` that receives `user: User`, which nothing declares.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User` is not @Instantiated or @Forwarded in chain: Root -> ScreenD -> Reader. Declare `@Instantiated let user: User` on `Root` or on another type in the chain to fix.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: Self.screenDeclarations(inOrder: Self.firstOrder)),
			] + Self.screenNames.map { seamFixtureType(named: $0, declarations: ["@Instantiated let reader: Reader"]) } + [
				seamFixtureType(named: "Reader", declarations: ["@Received let user: User"]),
				seamFixtureType(named: "User", declarations: []),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsUnfulfillableReceiveOnceFromEachRootsFirstDeclaredChain_whenTwoRootsReachItByTwentyChainsEach() async {
		// `First` and `Second` declare the same twenty screens in two orders, so each root reports the chain through the
		// screen it declares first.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User` is not @Instantiated or @Forwarded in chain: First -> ScreenD -> Reader. Declare `@Instantiated let user: User` on `First` or on another type in the chain to fix.
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User` is not @Instantiated or @Forwarded in chain: Second -> ScreenL -> Reader. Declare `@Instantiated let user: User` on `Second` or on another type in the chain to fix.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "First", isRoot: true, declarations: Self.screenDeclarations(inOrder: Self.firstOrder)),
				seamFixtureType(named: "Second", isRoot: true, declarations: Self.screenDeclarations(inOrder: Self.secondOrder)),
			] + Self.screenNames.map { seamFixtureType(named: $0, declarations: ["@Instantiated let reader: Reader"]) } + [
				seamFixtureType(named: "Reader", declarations: ["@Received let user: User"]),
				seamFixtureType(named: "User", declarations: []),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – A receive a closer declaration hides

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsHiddenReceiveOnceFromFirstDeclaredChain_whenTwentyChainsShareItsNearestHidingDeclaration() async {
		// Every screen declares `user: Name` and builds `Middle`, whose `user: Draft` is the nearest declaration above the
		// `Reader` that receives `user: User`: one nearest hiding declaration, beneath twenty declarations that hide the
		// receive too. The report names the first chain's.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User` is hidden in chain: Root -> ScreenD -> Middle -> Reader. `Middle` declares `user: Draft` with the same label, so the types below `Middle` receive `user: Draft` instead, and above `Middle`, `ScreenD` declares `user: Name` with the same label too. Give `user: Draft` on `Middle` and `user: Name` on `ScreenD` each a different label to fix.
			\(fixtures["Middle.swift"]):8:5: note: `user: Draft` is declared here
			\(fixtures["ScreenD.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User"] + Self.screenDeclarations(inOrder: Self.firstOrder)),
			] + Self.screenNames.map { seamFixtureType(named: $0, declarations: ["@Instantiated let user: Name", "@Instantiated let middle: Middle"]) } + [
				seamFixtureType(named: "Middle", declarations: ["@Instantiated let user: Draft", "@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Reader", declarations: ["@Received let user: User"]),
				seamFixtureType(named: "User", declarations: []),
				seamFixtureType(named: "Name", declarations: []),
				seamFixtureType(named: "Draft", declarations: []),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsHiddenReceiveOnceForEachNearestHidingDeclaration_whenTwentyDeclarationsHideIt() async {
		// Every screen declares `user: Draft` itself, directly above the `Reader` that receives `user: User`: twenty nearest
		// hiding declarations, each of which is to be given another label, so each is reported.
		await assertThrowsError(diagnostics: { fixtures in
			Self.screenNames.map { screen in
				"""
				\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User` is hidden in chain: Root -> \(screen) -> Reader. `\(screen)` declares `user: Draft` with the same label, so the types below `\(screen)` receive `user: Draft` instead. Give `user: Draft` on `\(screen)` a different label to fix.
				\(fixtures["\(screen).swift"]):8:5: note: `user: Draft` is declared here
				"""
			}.joined(separator: "\n")
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User"] + Self.screenDeclarations(inOrder: Self.firstOrder)),
			] + Self.screenNames.map { seamFixtureType(named: $0, declarations: ["@Instantiated let user: Draft", "@Instantiated let reader: Reader"]) } + [
				seamFixtureType(named: "Reader", declarations: ["@Received let user: User"]),
				seamFixtureType(named: "User", declarations: []),
				seamFixtureType(named: "Draft", declarations: []),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	/// `ScreenA` to `ScreenT`.
	private static let screenNames = "ABCDEFGHIJKLMNOPQRST".map { "Screen\($0)" }

	/// An order of the twenty screens that starts with `ScreenD`.
	private static let firstOrder = (0..<20).map { ($0 * 7 + 3) % 20 }

	/// Another order of the twenty screens, which starts with `ScreenL`.
	private static let secondOrder = (0..<20).map { ($0 * 3 + 11) % 20 }

	/// The declarations of a type that instantiates every screen, in `order`.
	private static func screenDeclarations(inOrder order: [Int]) -> [String] {
		order.map { "@Instantiated let screen\($0): \(screenNames[$0])" }
	}

	private var filesToDelete: [URL]
}
