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

/// A receive that declarations of its label with other types hide names every such declaration between it and what
/// provides it, closest first: relabeling only the closest would leave the receive hidden by the next one up the chain.
struct SafeDIToolHiddenReceiveDeclarationsTests: ~Copyable {
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
	mutating func generate_throwsHiddenErrorNamingEachHidingDeclaration_whenTwoTypesAlongTheChainDeclareTheLabelWithOtherTypes() async {
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let a: A"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let b: B"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Z", "@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Z", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `x: X` is hidden in chain: Root -> A -> B -> Reader. `B` declares `x: Z` with the same label, so the types below `B` receive `x: Z` instead, and above `B`, `A` declares `x: Y` with the same label too. Give `x: Z` on `B` and `x: Y` on `A` each a different label to fix.
			\(fixtures["B.swift"]):8:5: note: `x: Z` is declared here
			\(fixtures["A.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorNamingEachHidingDeclarationAsAList_whenThreeTypesAlongTheChainDeclareTheLabelWithOtherTypes() async {
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let a: A"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let b: B"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Z", "@Instantiated let c: C"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let x: W", "@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "W", isFinalClass: true, declarations: []),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Z", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `x: X` is hidden in chain: Root -> A -> B -> C -> Reader. `C` declares `x: W` with the same label, so the types below `C` receive `x: W` instead, and above `C`, `B` declares `x: Z` and `A` declares `x: Y` with the same label too. Give `x: W` on `C`, `x: Z` on `B`, and `x: Y` on `A` each a different label to fix.
			\(fixtures["C.swift"]):8:5: note: `x: W` is declared here
			\(fixtures["B.swift"]):8:5: note: `x: Z` is declared here
			\(fixtures["A.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorNamingNoDeclarationAboveTheOneThatProvidesTheReceive_whenATypeAboveItDeclaresTheLabelWithAnotherType() async {
		// `Root`'s `x: Y` is above `A`'s `x: X`, which `Reader` receives once `B`'s declaration is relabeled.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let a: A"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let b: B"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Z", "@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Z", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `x: X` is hidden in chain: Root -> A -> B -> Reader. `B` declares `x: Z` with the same label, so the types below `B` receive `x: Z` instead. Give `x: Z` on `B` a different label to fix.
			\(fixtures["B.swift"]):8:5: note: `x: Z` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorNamingNoDeclarationAboveTheOneThatProvidesTheReceive_whenALazilyInstantiatedDeclarationsInstanceProvidesIt() async {
		// `A`'s `x: LazilyInstantiated<X>` provides `Reader`'s by-value receive, so `Root`'s `x: Y` above it is not named.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let a: A"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let x: LazilyInstantiated<X>", "@Instantiated let b: B"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Z", "@Instantiated let c: C"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let x: W", "@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "W", isFinalClass: true, declarations: []),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Z", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `x: X` is hidden in chain: Root -> A -> B -> C -> Reader. `C` declares `x: W` with the same label, so the types below `C` receive `x: W` instead, and above `C`, `B` declares `x: Z` with the same label too. Give `x: W` on `C` and `x: Z` on `B` each a different label to fix.
			\(fixtures["C.swift"]):8:5: note: `x: W` is declared here
			\(fixtures["B.swift"]):8:5: note: `x: Z` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorNamingEachHidingDeclaration_whenTheReceiveIsOnlyIfAvailable() async {
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let a: A"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let b: B"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Z", "@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let x: X?"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Z", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `x: X?` is hidden in chain: Root -> A -> B -> Reader. `B` declares `x: Z` with the same label, so the types below `B` receive `x: Z` instead, and above `B`, `A` declares `x: Y` with the same label too. Give `x: Z` on `B` and `x: Y` on `A` each a different label to fix.
			\(fixtures["B.swift"]):8:5: note: `x: Z` is declared here
			\(fixtures["A.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorNamingEachHidingDeclaration_whenTheReceiveIsARename() async {
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let a: A"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let b: B"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Z", "@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: [#"@Received(fulfilledByDependencyNamed: "x", ofType: X.self) let renamed: X"#]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Z", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `x: X` is hidden in chain: Root -> A -> B -> Reader. `B` declares `x: Z` with the same label, so the types below `B` receive `x: Z` instead, and above `B`, `A` declares `x: Y` with the same label too. Give `x: Z` on `B` and `x: Y` on `A` each a different label to fix.
			\(fixtures["B.swift"]):8:5: note: `x: Z` is declared here
			\(fixtures["A.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorNamingEachHidingDeclarationInTheMockedTypesChain_whenTheMockedTypeReceivesTheLabel() async {
		// `Screen`'s mock binds the `x: X` it receives at its root, above every declaration in its tree.
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(x: X, a: A) {
			        self.x = x
			        self.a = a
			    }

			    @Received let x: X
			    @Instantiated let a: A
			}
			""",
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let b: B"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let x: Z", "@Instantiated let reader: Reader"]),
			seamFixtureType(named: "Reader", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Z", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Reader.swift"]):7:5: error: @Received property `x: X` is hidden in chain: Screen -> A -> B -> Reader. `B` declares `x: Z` with the same label, so the types below `B` receive `x: Z` instead, and above `B`, `A` declares `x: Y` with the same label too. Give `x: Z` on `B` and `x: Y` on `A` each a different label to fix.
			\(fixtures["B.swift"]):8:5: note: `x: Z` is declared here
			\(fixtures["A.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorNamingEachHidingDeclaration_whenTheReceiveIsOnlyInTheTreeACycleBuildsAgain() async {
		// `M` and `N` declare `x` between `C` and the cycle-closing scope that builds `C` again. Nothing in `C`'s own tree
		// receives `x`: only `R` does, which `C` reaches through the cycle-closing scope that builds `P` again.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let pBuilder: Instantiator<P>"]),
			seamFixtureType(named: "P", isFinalClass: true, declarations: ["@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let rBuilder: Instantiator<R>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let mBuilder: Instantiator<M>", "@Instantiated let pBuilder: Instantiator<P>"]),
			seamFixtureType(named: "M", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let nBuilder: Instantiator<N>"]),
			seamFixtureType(named: "N", isFinalClass: true, declarations: ["@Instantiated let x: Z", "@Instantiated let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "R", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Z", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["R.swift"]):7:5: error: @Received property `x: X` is hidden in chain: Root -> Instantiator<P> -> Instantiator<C> -> Instantiator<M> -> Instantiator<N> -> Instantiator<C> -> Instantiator<P> -> R. `N` declares `x: Z` with the same label, so the types below `N` receive `x: Z` instead, and above `N`, `M` declares `x: Y` with the same label too. Give `x: Z` on `N` and `x: Y` on `M` each a different label to fix.
			\(fixtures["N.swift"]):8:5: note: `x: Z` is declared here
			\(fixtures["M.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
