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

/// A hidden receive, or a receive of a declaration still being built, that one root's tree reaches by several chains of
/// scopes is reported once, from the chain a depth-first walk of the tree in declaration order reaches it by first: where two
/// chains part, the one through the scope declared first. Each test declares the two scopes where the chains part in both
/// orders, and names them so that one of the orders is not the order of their names.
struct SafeDIToolReportedChainTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Hidden receives

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsHiddenReceiveFromFirstDeclaredChainOnly_whenTwoChainsOfOneRootReachIt(screenFirst: Bool) async {
		// `Screen` and `Panel` each build `Left`, which declares `user: Name` above the `Reader` that receives `user: User`.
		let firstChild = screenFirst ? "Screen" : "Panel"
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User` is hidden in chain: Root -> \(firstChild) -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User"] + (screenFirst
						? ["@Instantiated let screen: Screen", "@Instantiated let panel: Panel"]
						: ["@Instantiated let panel: Panel", "@Instantiated let screen: Screen"])),
				seamFixtureType(named: "Screen", declarations: ["@Instantiated let left: Left"]),
				seamFixtureType(named: "Panel", declarations: ["@Instantiated let left: Left"]),
				seamFixtureType(named: "Left", declarations: ["@Instantiated let user: Name", "@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Reader", declarations: ["@Received let user: User"]),
				seamFixtureType(named: "User", declarations: []),
				seamFixtureType(named: "Name", declarations: []),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsHiddenReceiveFromFirstDeclaredChainOnly_whenChainsPartBeneathTheHidingDeclaration(screenFirst: Bool) async {
		// `Left` declares `user: Name` and builds `Reader` beneath both `Screen` and `Panel`: the chains part below the hiding
		// declaration rather than above it.
		let firstChild = screenFirst ? "Screen" : "Panel"
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User` is hidden in chain: Root -> Left -> \(firstChild) -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):9:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let left: Left"]),
				seamFixtureType(named: "Left", declarations: ["@Instantiated let user: Name"] + (screenFirst
						? ["@Instantiated let screen: Screen", "@Instantiated let panel: Panel"]
						: ["@Instantiated let panel: Panel", "@Instantiated let screen: Screen"])),
				seamFixtureType(named: "Screen", declarations: ["@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Panel", declarations: ["@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Reader", declarations: ["@Received let user: User"]),
				seamFixtureType(named: "User", declarations: []),
				seamFixtureType(named: "Name", declarations: []),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsHiddenReceiveFromFirstDeclaredChainOnly_whenOneChainRunsThroughTreeACycleBuildsAgain(directFirst: Bool) async {
		// `A` receives `x: X`. `B` declares `x: Y` and builds `A` again, closing a cycle on `Root`'s `aBuilder`, so the tree
		// built again there hides the receive; `Root` also reaches `B` beneath `C`, whose `B` builds an `A` it hides too. The
		// chains part at `Root`: through `aBuilder` and the tree built again, or through `c`.
		let throughA = "Root -> Instantiator<A> -> Instantiator<B> -> A"
		let throughC = "Root -> C -> Instantiator<B> -> A"
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["A.swift"]):8:5: error: @Received property `x: X` is hidden in chain: \(directFirst ? throughA : throughC). `B` declares `x: Y` with the same label, so the types below `B` receive `x: Y` instead. Give `x: Y` on `B` a different label to fix.
			\(fixtures["B.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X"] + (directFirst
						? ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let c: C"]
						: ["@Instantiated let c: C", "@Instantiated let aBuilder: Instantiator<A>"])),
				seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let x: X", "@Instantiated let bBuilder: Instantiator<B>"]),
				seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let aBuilder: Instantiator<A>"]),
				seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let bBuilder: Instantiator<B>"]),
				seamFixtureType(named: "X", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsHiddenReceiveFromFirstDeclaredChainOnly_whenTwoCycleClosingScopesBuildTheTreeAgain(dFirst: Bool) async {
		// `B` declares `x: Y` and closes a cycle on `Root`'s `aBuilder` twice, itself and beneath `D`, so each tree built again
		// hides `A`'s receive of `x: X`. The chains part at `B`, whose own cycle-closing scope's tree built again is walked in
		// its turn among `B`'s children.
		let throughD = "Root -> Instantiator<A> -> Instantiator<B> -> D -> A"
		let direct = "Root -> Instantiator<A> -> Instantiator<B> -> A"
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["A.swift"]):8:5: error: @Received property `x: X` is hidden in chain: \(dFirst ? throughD : direct). `B` declares `x: Y` with the same label, so the types below `B` receive `x: Y` instead. Give `x: Y` on `B` a different label to fix.
			\(fixtures["B.swift"]):9:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
				seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let x: X", "@Instantiated let bBuilder: Instantiator<B>"]),
				seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Y"] + (dFirst
						? ["@Instantiated let d: D", "@Instantiated let aBuilder: Instantiator<A>"]
						: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let d: D"])),
				seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
				seamFixtureType(named: "X", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsHiddenReceiveFromEachRootsOwnChain_whenTwoRootsReachIt() async {
		// Each root reports what its own tree reaches, so neither the names nor the files of the two roots decide which chain
		// is reported.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User` is hidden in chain: First -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User` is hidden in chain: Second -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "First", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let left: Left"]),
				seamFixtureType(named: "Second", isRoot: true, declarations: ["@Instantiated let user: User", "@Instantiated let left: Left"]),
				seamFixtureType(named: "Left", declarations: ["@Instantiated let user: Name", "@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Reader", declarations: ["@Received let user: User"]),
				seamFixtureType(named: "User", declarations: []),
				seamFixtureType(named: "Name", declarations: []),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_reportsHiddenReceiveFromFirstDeclaredChainOnly_whenTwoChainsOfMockedTypesTreeReachIt(screenFirst: Bool) async {
		// The mock of `Root`, which is no root of the dependency tree, reaches `Reader` through `Screen` and `Panel`.
		let firstChild = screenFirst ? "Screen" : "Panel"
		let children = screenFirst ? ["screen: Screen", "panel: Panel"] : ["panel: Panel", "screen: Screen"]
		let labels = children.map { $0.prefix { $0 != ":" } }
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `user: User` is hidden in chain: Root -> \(firstChild) -> Left -> Reader. `Left` declares `user: Name` with the same label, so the types below `Left` receive `user: Name` instead. Give `user: Name` on `Left` a different label to fix.
			\(fixtures["Left.swift"]):8:5: note: `user: Name` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Root: Instantiable {
				    public init(user: User, \(children[0]), \(children[1])) {
				        self.user = user
				        self.\(labels[0]) = \(labels[0])
				        self.\(labels[1]) = \(labels[1])
				    }

				    @Instantiated let user: User
				    @Instantiated let \(children[0])
				    @Instantiated let \(children[1])
				}
				""",
				seamFixtureType(named: "Screen", declarations: ["@Instantiated let left: Left"]),
				seamFixtureType(named: "Panel", declarations: ["@Instantiated let left: Left"]),
				seamFixtureType(named: "Left", declarations: ["@Instantiated let user: Name", "@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Reader", declarations: ["@Received let user: User"]),
				seamFixtureType(named: "User", declarations: []),
				seamFixtureType(named: "Name", declarations: []),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – Receives of a declaration still being built

	@Test(arguments: [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCycleErrorFromFirstDeclaredChain_whenTwoCycleClosingScopesBuildReceiverAgainBeneathDeclarationStillBeingBuilt(midFirst: Bool) async {
		// `T3` receives `t1: T1`, and the nearest declaration of `t1` above each `T3` built again is `T0`'s
		// `t1: LazilyInstantiated<T1>`, still being built. `T1` builds `T3` again itself and beneath `Mid`.
		let chain = midFirst ? "`T1` -> `Mid` -> `Instantiator<T3>` -> `T1`" : "`T1` -> `Instantiator<T3>` -> `T1`"
		await assertThrowsError(diagnostics: { fixtures in
			let midNote = midFirst ? "\n\(fixtures["Mid.swift"]):1:1: note: `Mid` is part of the cycle" : ""
			return """
			\(fixtures["T3.swift"]):9:5: error: Dependency cycle: \(chain). `T3` receives `t1: T1`, which is still being built when `T3` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
			\(fixtures["T1.swift"]):1:1: note: `T1` is part of the cycle\(midNote)
			\(fixtures["T3.swift"]):1:1: note: `T3` is part of the cycle
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let hostBuilder: Instantiator<Host>"]),
				seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Forwarded let t1: T1", "@Instantiated let t3Builder: Instantiator<T3>"]),
				seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Instantiated let t0Builder: Instantiator<T0>", "@Received let t1: T1"]),
				seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let t1: LazilyInstantiated<T1>"]),
				seamFixtureType(named: "T1", isFinalClass: true, declarations: midFirst
					? ["@Instantiated let mid: Mid", "@Instantiated let t3Builder: Instantiator<T3>"]
					: ["@Instantiated let t3Builder: Instantiator<T3>", "@Instantiated let mid: Mid"]),
				seamFixtureType(named: "Mid", isFinalClass: true, declarations: ["@Instantiated let t3Builder: Instantiator<T3>"]),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
