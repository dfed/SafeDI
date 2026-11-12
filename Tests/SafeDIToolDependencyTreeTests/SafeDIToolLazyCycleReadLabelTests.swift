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

/// The walk of a tree a lazy cycle builds again is skipped where nothing the tree reads is new to it. Each test but the
/// last gives the walk one diagnostic to find, read in one way a set of the labels a tree reads could leave out: leaving
/// the label out skips the walk that reports it. The last gives the walk nothing to find, on a shape it cannot finish.
struct SafeDIToolLazyCycleReadLabelTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Labels a tree reads

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenOnlyReceiveOfLabelIsReachedThroughCycleClosingScope() async {
		// `M` declares `x: Y` between `C` and the cycle-closing scope that builds `C` again. Nothing in `C`'s own tree receives
		// `x`: only `R` does, and `C` reaches it through the cycle-closing scope that builds `P` again.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let pBuilder: Instantiator<P>"]),
			seamFixtureType(named: "P", isFinalClass: true, declarations: ["@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let rBuilder: Instantiator<R>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let mBuilder: Instantiator<M>", "@Instantiated let pBuilder: Instantiator<P>"]),
			seamFixtureType(named: "M", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "R", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["R.swift"]):7:5: error: @Received property `x: X` is hidden in chain: Root -> Instantiator<P> -> Instantiator<C> -> Instantiator<M> -> Instantiator<C> -> Instantiator<P> -> R. `M` declares `x: Y` with the same label, so the types below `M` receive `x: Y` instead. Give `x: Y` on `M` a different label to fix.
			\(fixtures["M.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenOnlyReadOfLabelIsAnAliasFulfilledByIt() async {
		// `A`'s alias reads `x`, the label of the property that fulfills it, and declares `renamed`, which `B` does not.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: [#"@Received(fulfilledByDependencyNamed: "x", ofType: X.self) let renamed: X"#, "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["A.swift"]):8:5: error: @Received property `x: X` is hidden in chain: Root -> Instantiator<A> -> Instantiator<B> -> A. `B` declares `x: Y` with the same label, so the types below `B` receive `x: Y` instead. Give `x: Y` on `B` a different label to fix.
			\(fixtures["B.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenOnlyReceiveOfLabelIsInTreeOfLazilyInstantiatedChild() async {
		// `B` declares `x: Y` between `A` and the cycle-closing scope that builds `A` again. Nothing `A` builds directly
		// receives `x`: only `D` does, which `A` instantiates lazily, so the walk goes on into the tree `d` creates.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let d: LazilyInstantiated<D>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "D", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["D.swift"]):7:5: error: @Received property `x: X` is hidden in chain: Root -> Instantiator<A> -> Instantiator<B> -> Instantiator<A> -> D. `B` declares `x: Y` with the same label, so the types below `B` receive `x: Y` instead. Give `x: Y` on `B` a different label to fix.
			\(fixtures["B.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCycleError_whenByValueReceiveOfLazilyInstantiatedDeclarationStillBeingBuiltIsReadThroughItsLabel() async {
		// `T3` receives `t1: T1` by value, and the nearest declaration of `t1` above the `T3` built again is `T0`'s
		// `t1: LazilyInstantiated<T1>`, another property of the label, still being built. `Host` is handed its `t1`, so nothing
		// else builds `T1` where the first `T3` receives it.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let hostBuilder: Instantiator<Host>"]),
			seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Forwarded let t1: T1", "@Instantiated let t3Builder: Instantiator<T3>"]),
			seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Instantiated let t0Builder: Instantiator<T0>", "@Received let t1: T1"]),
			seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let t1: LazilyInstantiated<T1>"]),
			seamFixtureType(named: "T1", isFinalClass: true, declarations: ["@Instantiated let t3Builder: Instantiator<T3>"]),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["T3.swift"]):9:5: error: Dependency cycle: `T1` -> `Instantiator<T3>` -> `T1`. `T3` receives `t1: T1`, which is still being built when `T3` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
			\(fixtures["T1.swift"]):1:1: note: `T1` is part of the cycle
			\(fixtures["T3.swift"]):1:1: note: `T3` is part of the cycle
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenOnlyReadOfLabelIsReceivedOnlyIfAvailable() async {
		// The walk's cycle check reads required receives alone, but its hidden-label check reads this one too.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["A.swift"]):8:5: error: @Received property `x: X?` is hidden in chain: Root -> Instantiator<A> -> Instantiator<B> -> A. `B` declares `x: Y` with the same label, so the types below `B` receive `x: Y` instead. Give `x: Y` on `B` a different label to fix.
			\(fixtures["B.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenScopeWasReachedInsideCycleBeforeItsOwnTreeIsAskedWhatItReads() async {
		// The first walk asks what `A`'s tree reads, which reaches `B` and, through `B`'s cycle-closing scope, `A` again. A set
		// that stopped at `A` there, as a scope still being answered, would record that `B`'s tree reads nothing. The second
		// walk asks about `B`, whose tree reads `x` through that same cycle-closing scope, and `C` declares `x: Y`.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let x: X", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["A.swift"]):8:5: error: @Received property `x: X` is hidden in chain: Root -> Instantiator<A> -> Instantiator<B> -> Instantiator<C> -> Instantiator<B> -> A. `C` declares `x: Y` with the same label, so the types below `C` receive `x: Y` instead. Give `x: Y` on `C` a different label to fix.
			\(fixtures["C.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenTreeBuiltAgainHoldsAChainTooDeepToWalkRecursively() async {
		// `C` reads `x` and `S` declares `x: Y`, so the walk starts; asking what `C`'s tree reads visits every link of the chain.
		var fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Received let x: X", "@Instantiated let sBuilder: Instantiator<S>", "@Instantiated let link0: Link0"]),
			seamFixtureType(named: "S", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		let linkCount = 3_000
		for index in 0..<linkCount {
			let nextLink = index + 1 < linkCount ? ["@Instantiated let link\(index + 1): Link\(index + 1)"] : []
			fixture.append(seamFixtureType(named: "Link\(index)", isFinalClass: true, declarations: nextLink))
		}
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["C.swift"]):9:5: error: @Received property `x: X` is hidden in chain: Root -> Instantiator<C> -> Instantiator<S> -> C. `S` declares `x: Y` with the same label, so the types below `S` receive `x: Y` instead. Give `x: Y` on `S` a different label to fix.
			\(fixtures["S.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – A tree that reads nothing new

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesDependencyTreeWithoutWalkingCycles_whenNothingReadsLabelsDeclaredBetween() async throws {
		// Without the skip this shape takes minutes and gigabytes: the walk's work grows with the number of subsets of the
		// hub's labels it can reach, and it visits none of them usefully, since nothing here receives anything. The tree
		// itself is small, as this expectation shows, so with the skip the test finishes in well under a second. A count
		// of the scopes walked would need a test seam in shipped code; the size is the assertion instead.
		let screenCount = 20
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.screensAndHubFixture(screenCount: screenCount),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == ["Root+SafeDI.swift": generatedFileHeader + Self.screensAndHubDependencyTree(screenCount: screenCount)])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static func screenName(_ index: Int) -> String {
		index < 10 ? "Screen0\(index)" : "Screen\(index)"
	}

	private static func screenLabel(_ index: Int) -> String {
		index < 10 ? "screen0\(index)" : "screen\(index)"
	}

	private static func serviceLabel(_ index: Int) -> String {
		index < 10 ? "service0\(index)" : "service\(index)"
	}

	/// The screens each screen opens above it: as many as four, the nearest last.
	private static func screenIndicesOpenedAbove(_ index: Int) -> [Int] {
		Array(max(0, index - 4)..<index)
	}

	/// `Root` opens `Screen00`. Each of `screenCount` screens declares a `Service` of its own, opens the four screens above it
	/// and opens the next screen, the last of which opens `Hub`. `Hub` declares every screen's `Service` again and opens
	/// the last screen, so the cycle it closes has one new label per screen.
	private static func screensAndHubFixture(screenCount: Int) -> [String] {
		var fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let \(screenLabel(0)): Instantiator<\(screenName(0))>"]),
			seamFixtureType(named: "Service", isFinalClass: true, declarations: []),
			seamFixtureType(
				named: "Hub",
				isFinalClass: true,
				declarations: (0..<screenCount).map { "@Instantiated let \(serviceLabel($0)): Service" } + ["@Instantiated let \(screenLabel(screenCount - 1)): Instantiator<\(screenName(screenCount - 1))>"],
			),
		]
		for index in 0..<screenCount {
			var declarations = ["@Instantiated let \(serviceLabel(index)): Service"]
			declarations += screenIndicesOpenedAbove(index).map { "@Instantiated let \(screenLabel($0)): Instantiator<\(screenName($0))>" }
			declarations.append(index + 1 < screenCount ? "@Instantiated let \(screenLabel(index + 1)): Instantiator<\(screenName(index + 1))>" : "@Instantiated let hub: Instantiator<Hub>")
			fixture.append(seamFixtureType(named: screenName(index), isFinalClass: true, declarations: declarations))
		}
		return fixture
	}

	/// The dependency tree of `screensAndHubFixture`: the screens' builder functions nest, each screen's reference to a screen
	/// above it calls that screen's enclosing function, and `Hub`'s builder function is the innermost.
	private static func screensAndHubDependencyTree(screenCount: Int) -> String {
		func indentation(_ level: Int) -> String {
			String(repeating: "    ", count: level)
		}
		var lines = ["extension Root {", "    public convenience init() {"]
		for index in 0..<screenCount {
			lines.append("\(indentation(2 + index))func __safeDI_\(screenLabel(index))() -> \(screenName(index)) {")
			lines.append("\(indentation(3 + index))let \(serviceLabel(index)) = Service()")
			lines += screenIndicesOpenedAbove(index).map {
				"\(indentation(3 + index))let \(screenLabel($0)) = Instantiator<\(screenName($0))>(__safeDI_\(screenLabel($0)))"
			}
		}
		let hubIndentation = indentation(2 + screenCount)
		let hubBodyIndentation = indentation(3 + screenCount)
		lines.append("\(hubIndentation)func __safeDI_hub() -> Hub {")
		lines += (0..<screenCount).map { "\(hubBodyIndentation)let \(serviceLabel($0)) = Service()" }
		let lastScreen = screenCount - 1
		lines.append("\(hubBodyIndentation)let \(screenLabel(lastScreen)) = Instantiator<\(screenName(lastScreen))>(__safeDI_\(screenLabel(lastScreen)))")
		let hubArguments = (0..<screenCount).map { "\(serviceLabel($0)): \(serviceLabel($0))" } + ["\(screenLabel(lastScreen)): \(screenLabel(lastScreen))"]
		lines.append("\(hubBodyIndentation)return Hub(\(hubArguments.joined(separator: ", ")))")
		lines.append("\(hubIndentation)}")
		lines.append("\(hubIndentation)let hub = Instantiator<Hub>(__safeDI_hub)")
		for index in (0..<screenCount).reversed() {
			let body = indentation(3 + index)
			var arguments = ["\(serviceLabel(index)): \(serviceLabel(index))"]
			arguments += screenIndicesOpenedAbove(index).map { "\(screenLabel($0)): \(screenLabel($0))" }
			arguments.append(index + 1 < screenCount ? "\(screenLabel(index + 1)): \(screenLabel(index + 1))" : "hub: hub")
			lines.append("\(body)return \(screenName(index))(\(arguments.joined(separator: ", ")))")
			lines.append("\(indentation(2 + index))}")
			lines.append("\(indentation(2 + index))let \(screenLabel(index)) = Instantiator<\(screenName(index))>(__safeDI_\(screenLabel(index)))")
		}
		lines.append("        self.init(\(screenLabel(0)): \(screenLabel(0)))")
		lines.append("    }")
		lines.append("}")
		return lines.joined(separator: "\n")
	}
}
