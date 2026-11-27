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

/// The walk of a tree a lazy cycle builds again is skipped where nothing the tree reads is new to it, or where what is new
/// is a label no judgement of the walk can fire for. Each test of a diagnostic gives the walk one to find, read in one way
/// a set of the labels a tree reads could leave out, or in one way a label can stay where a judgement fires: a mistake in
/// either set skips the walk that reports it. Each test of a dependency tree gives the walk nothing to find, on a shape it
/// cannot finish.
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
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screen00() -> Screen00 {
			            let service00 = Service()
			            let screen01 = Instantiator<Screen01>(__safeDI_screen01)
			            return Screen00(service00: service00, screen01: screen01)
			        }
			        func __safeDI_screen01() -> Screen01 {
			            let service01 = Service()
			            let screen00 = Instantiator<Screen00>(__safeDI_screen00)
			            let screen02 = Instantiator<Screen02>(__safeDI_screen02)
			            return Screen01(service01: service01, screen00: screen00, screen02: screen02)
			        }
			        func __safeDI_screen02() -> Screen02 {
			            let service02 = Service()
			            let screen00 = Instantiator<Screen00>(__safeDI_screen00)
			            let screen01 = Instantiator<Screen01>(__safeDI_screen01)
			            let screen03 = Instantiator<Screen03>(__safeDI_screen03)
			            return Screen02(service02: service02, screen00: screen00, screen01: screen01, screen03: screen03)
			        }
			        func __safeDI_screen03() -> Screen03 {
			            let service03 = Service()
			            let screen00 = Instantiator<Screen00>(__safeDI_screen00)
			            let screen01 = Instantiator<Screen01>(__safeDI_screen01)
			            let screen02 = Instantiator<Screen02>(__safeDI_screen02)
			            let screen04 = Instantiator<Screen04>(__safeDI_screen04)
			            return Screen03(service03: service03, screen00: screen00, screen01: screen01, screen02: screen02, screen04: screen04)
			        }
			        func __safeDI_screen04() -> Screen04 {
			            let service04 = Service()
			            let screen00 = Instantiator<Screen00>(__safeDI_screen00)
			            let screen01 = Instantiator<Screen01>(__safeDI_screen01)
			            let screen02 = Instantiator<Screen02>(__safeDI_screen02)
			            let screen03 = Instantiator<Screen03>(__safeDI_screen03)
			            let screen05 = Instantiator<Screen05>(__safeDI_screen05)
			            return Screen04(service04: service04, screen00: screen00, screen01: screen01, screen02: screen02, screen03: screen03, screen05: screen05)
			        }
			        func __safeDI_screen05() -> Screen05 {
			            let service05 = Service()
			            let screen01 = Instantiator<Screen01>(__safeDI_screen01)
			            let screen02 = Instantiator<Screen02>(__safeDI_screen02)
			            let screen03 = Instantiator<Screen03>(__safeDI_screen03)
			            let screen04 = Instantiator<Screen04>(__safeDI_screen04)
			            let screen06 = Instantiator<Screen06>(__safeDI_screen06)
			            return Screen05(service05: service05, screen01: screen01, screen02: screen02, screen03: screen03, screen04: screen04, screen06: screen06)
			        }
			        func __safeDI_screen06() -> Screen06 {
			            let service06 = Service()
			            let screen02 = Instantiator<Screen02>(__safeDI_screen02)
			            let screen03 = Instantiator<Screen03>(__safeDI_screen03)
			            let screen04 = Instantiator<Screen04>(__safeDI_screen04)
			            let screen05 = Instantiator<Screen05>(__safeDI_screen05)
			            let screen07 = Instantiator<Screen07>(__safeDI_screen07)
			            return Screen06(service06: service06, screen02: screen02, screen03: screen03, screen04: screen04, screen05: screen05, screen07: screen07)
			        }
			        func __safeDI_screen07() -> Screen07 {
			            let service07 = Service()
			            let screen03 = Instantiator<Screen03>(__safeDI_screen03)
			            let screen04 = Instantiator<Screen04>(__safeDI_screen04)
			            let screen05 = Instantiator<Screen05>(__safeDI_screen05)
			            let screen06 = Instantiator<Screen06>(__safeDI_screen06)
			            let screen08 = Instantiator<Screen08>(__safeDI_screen08)
			            return Screen07(service07: service07, screen03: screen03, screen04: screen04, screen05: screen05, screen06: screen06, screen08: screen08)
			        }
			        func __safeDI_screen08() -> Screen08 {
			            let service08 = Service()
			            let screen04 = Instantiator<Screen04>(__safeDI_screen04)
			            let screen05 = Instantiator<Screen05>(__safeDI_screen05)
			            let screen06 = Instantiator<Screen06>(__safeDI_screen06)
			            let screen07 = Instantiator<Screen07>(__safeDI_screen07)
			            let screen09 = Instantiator<Screen09>(__safeDI_screen09)
			            return Screen08(service08: service08, screen04: screen04, screen05: screen05, screen06: screen06, screen07: screen07, screen09: screen09)
			        }
			        func __safeDI_screen09() -> Screen09 {
			            let service09 = Service()
			            let screen05 = Instantiator<Screen05>(__safeDI_screen05)
			            let screen06 = Instantiator<Screen06>(__safeDI_screen06)
			            let screen07 = Instantiator<Screen07>(__safeDI_screen07)
			            let screen08 = Instantiator<Screen08>(__safeDI_screen08)
			            let screen10 = Instantiator<Screen10>(__safeDI_screen10)
			            return Screen09(service09: service09, screen05: screen05, screen06: screen06, screen07: screen07, screen08: screen08, screen10: screen10)
			        }
			        func __safeDI_screen10() -> Screen10 {
			            let service10 = Service()
			            let screen06 = Instantiator<Screen06>(__safeDI_screen06)
			            let screen07 = Instantiator<Screen07>(__safeDI_screen07)
			            let screen08 = Instantiator<Screen08>(__safeDI_screen08)
			            let screen09 = Instantiator<Screen09>(__safeDI_screen09)
			            let screen11 = Instantiator<Screen11>(__safeDI_screen11)
			            return Screen10(service10: service10, screen06: screen06, screen07: screen07, screen08: screen08, screen09: screen09, screen11: screen11)
			        }
			        func __safeDI_screen11() -> Screen11 {
			            let service11 = Service()
			            let screen07 = Instantiator<Screen07>(__safeDI_screen07)
			            let screen08 = Instantiator<Screen08>(__safeDI_screen08)
			            let screen09 = Instantiator<Screen09>(__safeDI_screen09)
			            let screen10 = Instantiator<Screen10>(__safeDI_screen10)
			            let screen12 = Instantiator<Screen12>(__safeDI_screen12)
			            return Screen11(service11: service11, screen07: screen07, screen08: screen08, screen09: screen09, screen10: screen10, screen12: screen12)
			        }
			        func __safeDI_screen12() -> Screen12 {
			            let service12 = Service()
			            let screen08 = Instantiator<Screen08>(__safeDI_screen08)
			            let screen09 = Instantiator<Screen09>(__safeDI_screen09)
			            let screen10 = Instantiator<Screen10>(__safeDI_screen10)
			            let screen11 = Instantiator<Screen11>(__safeDI_screen11)
			            let screen13 = Instantiator<Screen13>(__safeDI_screen13)
			            return Screen12(service12: service12, screen08: screen08, screen09: screen09, screen10: screen10, screen11: screen11, screen13: screen13)
			        }
			        func __safeDI_screen13() -> Screen13 {
			            let service13 = Service()
			            let screen09 = Instantiator<Screen09>(__safeDI_screen09)
			            let screen10 = Instantiator<Screen10>(__safeDI_screen10)
			            let screen11 = Instantiator<Screen11>(__safeDI_screen11)
			            let screen12 = Instantiator<Screen12>(__safeDI_screen12)
			            let screen14 = Instantiator<Screen14>(__safeDI_screen14)
			            return Screen13(service13: service13, screen09: screen09, screen10: screen10, screen11: screen11, screen12: screen12, screen14: screen14)
			        }
			        func __safeDI_screen14() -> Screen14 {
			            let service14 = Service()
			            let screen10 = Instantiator<Screen10>(__safeDI_screen10)
			            let screen11 = Instantiator<Screen11>(__safeDI_screen11)
			            let screen12 = Instantiator<Screen12>(__safeDI_screen12)
			            let screen13 = Instantiator<Screen13>(__safeDI_screen13)
			            let screen15 = Instantiator<Screen15>(__safeDI_screen15)
			            return Screen14(service14: service14, screen10: screen10, screen11: screen11, screen12: screen12, screen13: screen13, screen15: screen15)
			        }
			        func __safeDI_screen15() -> Screen15 {
			            let service15 = Service()
			            let screen11 = Instantiator<Screen11>(__safeDI_screen11)
			            let screen12 = Instantiator<Screen12>(__safeDI_screen12)
			            let screen13 = Instantiator<Screen13>(__safeDI_screen13)
			            let screen14 = Instantiator<Screen14>(__safeDI_screen14)
			            let screen16 = Instantiator<Screen16>(__safeDI_screen16)
			            return Screen15(service15: service15, screen11: screen11, screen12: screen12, screen13: screen13, screen14: screen14, screen16: screen16)
			        }
			        func __safeDI_screen16() -> Screen16 {
			            let service16 = Service()
			            let screen12 = Instantiator<Screen12>(__safeDI_screen12)
			            let screen13 = Instantiator<Screen13>(__safeDI_screen13)
			            let screen14 = Instantiator<Screen14>(__safeDI_screen14)
			            let screen15 = Instantiator<Screen15>(__safeDI_screen15)
			            let screen17 = Instantiator<Screen17>(__safeDI_screen17)
			            return Screen16(service16: service16, screen12: screen12, screen13: screen13, screen14: screen14, screen15: screen15, screen17: screen17)
			        }
			        func __safeDI_screen17() -> Screen17 {
			            let service17 = Service()
			            let screen13 = Instantiator<Screen13>(__safeDI_screen13)
			            let screen14 = Instantiator<Screen14>(__safeDI_screen14)
			            let screen15 = Instantiator<Screen15>(__safeDI_screen15)
			            let screen16 = Instantiator<Screen16>(__safeDI_screen16)
			            let screen18 = Instantiator<Screen18>(__safeDI_screen18)
			            return Screen17(service17: service17, screen13: screen13, screen14: screen14, screen15: screen15, screen16: screen16, screen18: screen18)
			        }
			        func __safeDI_screen18() -> Screen18 {
			            let service18 = Service()
			            let screen14 = Instantiator<Screen14>(__safeDI_screen14)
			            let screen15 = Instantiator<Screen15>(__safeDI_screen15)
			            let screen16 = Instantiator<Screen16>(__safeDI_screen16)
			            let screen17 = Instantiator<Screen17>(__safeDI_screen17)
			            let screen19 = Instantiator<Screen19>(__safeDI_screen19)
			            return Screen18(service18: service18, screen14: screen14, screen15: screen15, screen16: screen16, screen17: screen17, screen19: screen19)
			        }
			        func __safeDI_screen19() -> Screen19 {
			            let service19 = Service()
			            let screen15 = Instantiator<Screen15>(__safeDI_screen15)
			            let screen16 = Instantiator<Screen16>(__safeDI_screen16)
			            let screen17 = Instantiator<Screen17>(__safeDI_screen17)
			            let screen18 = Instantiator<Screen18>(__safeDI_screen18)
			            let hub = Instantiator<Hub>(__safeDI_hub)
			            return Screen19(service19: service19, screen15: screen15, screen16: screen16, screen17: screen17, screen18: screen18, hub: hub)
			        }
			        func __safeDI_hub() -> Hub {
			            let service00 = Service()
			            let service01 = Service()
			            let service02 = Service()
			            let service03 = Service()
			            let service04 = Service()
			            let service05 = Service()
			            let service06 = Service()
			            let service07 = Service()
			            let service08 = Service()
			            let service09 = Service()
			            let service10 = Service()
			            let service11 = Service()
			            let service12 = Service()
			            let service13 = Service()
			            let service14 = Service()
			            let service15 = Service()
			            let service16 = Service()
			            let service17 = Service()
			            let service18 = Service()
			            let service19 = Service()
			            let screen19 = Instantiator<Screen19>(__safeDI_screen19)
			            return Hub(service00: service00, service01: service01, service02: service02, service03: service03, service04: service04, service05: service05, service06: service06, service07: service07, service08: service08, service09: service09, service10: service10, service11: service11, service12: service12, service13: service13, service14: service14, service15: service15, service16: service16, service17: service17, service18: service18, service19: service19, screen19: screen19)
			        }
			        let screen00 = Instantiator<Screen00>(__safeDI_screen00)
			        self.init(screen00: screen00)
			    }
			}
			""",
		])
	}

	// MARK: Tests – A label no judgement fires for

	// Every screen receives `context`, and `Hub` declares it again between the last screen and the cycle that builds it again,
	// so every tree a cycle builds again reads a label new to it. The walk is skipped anyway for a label no judgement can fire
	// for: one whose every declaration every read accepts, and that no tree built for it reads. The first two tests break the
	// first condition and give the walk the hidden-label errors it then must find; the cycle error of
	// `generate_throwsCycleError_whenByValueReceiveOfLazilyInstantiatedDeclarationStillBeingBuiltIsReadThroughItsLabel` is
	// one only a label that a tree built for it reads can give.

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenRedeclaredLabelHasADeclarationOfAnotherType() async {
		// `Hub` declares `context: OtherContext`, which no screen's receive of `context: Context` accepts.
		var fixture = Self.screensAndHubFixture(
			screenCount: 2,
			sharedContext: (screenDeclaration: "@Received let context: Context", hubDeclaration: "@Instantiated let context: OtherContext"),
		)
		fixture.append(seamFixtureType(named: "OtherContext", isFinalClass: true, declarations: []))
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen00.swift"]):10:5: error: @Received property `context: Context` is hidden in chain: Root -> Instantiator<Screen00> -> Instantiator<Screen01> -> Instantiator<Hub> -> Instantiator<Screen01> -> Screen00. `Hub` declares `context: OtherContext` with the same label, so the types below `Hub` receive `context: OtherContext` instead. Give `context: OtherContext` on `Hub` a different label to fix.
			\(fixtures["Hub.swift"]):12:5: note: `context: OtherContext` is declared here
			\(fixtures["Screen01.swift"]):11:5: error: @Received property `context: Context` is hidden in chain: Root -> Instantiator<Screen00> -> Instantiator<Screen01> -> Instantiator<Hub> -> Screen01. `Hub` declares `context: OtherContext` with the same label, so the types below `Hub` receive `context: OtherContext` instead. Give `context: OtherContext` on `Hub` a different label to fix.
			\(fixtures["Hub.swift"]):12:5: note: `context: OtherContext` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenRequiredAliasReadsLabelDeclaredInAFormOnlyAReceiveOnlyIfAvailableReads() async {
		// `Hub` forwards `context: Context?`, which a receive of `context` only if available would read, but each screen's
		// required alias of `context: Context` does not.
		let fixture = Self.screensAndHubFixture(
			screenCount: 2,
			sharedContext: (
				screenDeclaration: #"@Received(fulfilledByDependencyNamed: "context", ofType: Context.self) let renamedContext: Context"#,
				hubDeclaration: "@Forwarded let context: Context?",
			),
		)
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen00.swift"]):10:5: error: @Received property `context: Context` is hidden in chain: Root -> Instantiator<Screen00> -> Instantiator<Screen01> -> Instantiator<Hub> -> Instantiator<Screen01> -> Screen00. `Hub` declares `context: Context?` with the same label, so the types below `Hub` receive `context: Context?` instead. Give `context: Context?` on `Hub` a different label to fix.
			\(fixtures["Hub.swift"]):12:5: note: `context: Context?` is declared here
			\(fixtures["Screen01.swift"]):11:5: error: @Received property `context: Context` is hidden in chain: Root -> Instantiator<Screen00> -> Instantiator<Screen01> -> Instantiator<Hub> -> Screen01. `Hub` declares `context: Context?` with the same label, so the types below `Hub` receive `context: Context?` instead. Give `context: Context?` on `Hub` a different label to fix.
			\(fixtures["Hub.swift"]):12:5: note: `context: Context?` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesDependencyTreeWithoutWalkingCycles_whenEveryDeclarationOfRedeclaredLabelIsOneEveryReadAccepts() async throws {
		// Without the skip this shape takes over ten minutes: every tree reads `context`, which `Hub` declares again, so the
		// walk runs, and its work grows with the number of subsets of the hub's labels it can reach. With the skip the test
		// finishes in well under a second. As above, the size is the assertion.
		let screenCount = 24
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.screensAndHubFixture(
				screenCount: screenCount,
				sharedContext: (screenDeclaration: "@Received let context: Context", hubDeclaration: "@Instantiated let context: Context"),
			),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let context = Context()
			        func __safeDI_screen00(context: Context) -> Screen00 {
			            let service00 = Service()
			            let screen01 = Instantiator<Screen01> {
			                __safeDI_screen01(context: context)
			            }
			            return Screen00(service00: service00, context: context, screen01: screen01)
			        }
			        func __safeDI_screen01(context: Context) -> Screen01 {
			            let service01 = Service()
			            let screen00 = Instantiator<Screen00> {
			                __safeDI_screen00(context: context)
			            }
			            let screen02 = Instantiator<Screen02> {
			                __safeDI_screen02(context: context)
			            }
			            return Screen01(service01: service01, context: context, screen00: screen00, screen02: screen02)
			        }
			        func __safeDI_screen02(context: Context) -> Screen02 {
			            let service02 = Service()
			            let screen00 = Instantiator<Screen00> {
			                __safeDI_screen00(context: context)
			            }
			            let screen01 = Instantiator<Screen01> {
			                __safeDI_screen01(context: context)
			            }
			            let screen03 = Instantiator<Screen03> {
			                __safeDI_screen03(context: context)
			            }
			            return Screen02(service02: service02, context: context, screen00: screen00, screen01: screen01, screen03: screen03)
			        }
			        func __safeDI_screen03(context: Context) -> Screen03 {
			            let service03 = Service()
			            let screen00 = Instantiator<Screen00> {
			                __safeDI_screen00(context: context)
			            }
			            let screen01 = Instantiator<Screen01> {
			                __safeDI_screen01(context: context)
			            }
			            let screen02 = Instantiator<Screen02> {
			                __safeDI_screen02(context: context)
			            }
			            let screen04 = Instantiator<Screen04> {
			                __safeDI_screen04(context: context)
			            }
			            return Screen03(service03: service03, context: context, screen00: screen00, screen01: screen01, screen02: screen02, screen04: screen04)
			        }
			        func __safeDI_screen04(context: Context) -> Screen04 {
			            let service04 = Service()
			            let screen00 = Instantiator<Screen00> {
			                __safeDI_screen00(context: context)
			            }
			            let screen01 = Instantiator<Screen01> {
			                __safeDI_screen01(context: context)
			            }
			            let screen02 = Instantiator<Screen02> {
			                __safeDI_screen02(context: context)
			            }
			            let screen03 = Instantiator<Screen03> {
			                __safeDI_screen03(context: context)
			            }
			            let screen05 = Instantiator<Screen05> {
			                __safeDI_screen05(context: context)
			            }
			            return Screen04(service04: service04, context: context, screen00: screen00, screen01: screen01, screen02: screen02, screen03: screen03, screen05: screen05)
			        }
			        func __safeDI_screen05(context: Context) -> Screen05 {
			            let service05 = Service()
			            let screen01 = Instantiator<Screen01> {
			                __safeDI_screen01(context: context)
			            }
			            let screen02 = Instantiator<Screen02> {
			                __safeDI_screen02(context: context)
			            }
			            let screen03 = Instantiator<Screen03> {
			                __safeDI_screen03(context: context)
			            }
			            let screen04 = Instantiator<Screen04> {
			                __safeDI_screen04(context: context)
			            }
			            let screen06 = Instantiator<Screen06> {
			                __safeDI_screen06(context: context)
			            }
			            return Screen05(service05: service05, context: context, screen01: screen01, screen02: screen02, screen03: screen03, screen04: screen04, screen06: screen06)
			        }
			        func __safeDI_screen06(context: Context) -> Screen06 {
			            let service06 = Service()
			            let screen02 = Instantiator<Screen02> {
			                __safeDI_screen02(context: context)
			            }
			            let screen03 = Instantiator<Screen03> {
			                __safeDI_screen03(context: context)
			            }
			            let screen04 = Instantiator<Screen04> {
			                __safeDI_screen04(context: context)
			            }
			            let screen05 = Instantiator<Screen05> {
			                __safeDI_screen05(context: context)
			            }
			            let screen07 = Instantiator<Screen07> {
			                __safeDI_screen07(context: context)
			            }
			            return Screen06(service06: service06, context: context, screen02: screen02, screen03: screen03, screen04: screen04, screen05: screen05, screen07: screen07)
			        }
			        func __safeDI_screen07(context: Context) -> Screen07 {
			            let service07 = Service()
			            let screen03 = Instantiator<Screen03> {
			                __safeDI_screen03(context: context)
			            }
			            let screen04 = Instantiator<Screen04> {
			                __safeDI_screen04(context: context)
			            }
			            let screen05 = Instantiator<Screen05> {
			                __safeDI_screen05(context: context)
			            }
			            let screen06 = Instantiator<Screen06> {
			                __safeDI_screen06(context: context)
			            }
			            let screen08 = Instantiator<Screen08> {
			                __safeDI_screen08(context: context)
			            }
			            return Screen07(service07: service07, context: context, screen03: screen03, screen04: screen04, screen05: screen05, screen06: screen06, screen08: screen08)
			        }
			        func __safeDI_screen08(context: Context) -> Screen08 {
			            let service08 = Service()
			            let screen04 = Instantiator<Screen04> {
			                __safeDI_screen04(context: context)
			            }
			            let screen05 = Instantiator<Screen05> {
			                __safeDI_screen05(context: context)
			            }
			            let screen06 = Instantiator<Screen06> {
			                __safeDI_screen06(context: context)
			            }
			            let screen07 = Instantiator<Screen07> {
			                __safeDI_screen07(context: context)
			            }
			            let screen09 = Instantiator<Screen09> {
			                __safeDI_screen09(context: context)
			            }
			            return Screen08(service08: service08, context: context, screen04: screen04, screen05: screen05, screen06: screen06, screen07: screen07, screen09: screen09)
			        }
			        func __safeDI_screen09(context: Context) -> Screen09 {
			            let service09 = Service()
			            let screen05 = Instantiator<Screen05> {
			                __safeDI_screen05(context: context)
			            }
			            let screen06 = Instantiator<Screen06> {
			                __safeDI_screen06(context: context)
			            }
			            let screen07 = Instantiator<Screen07> {
			                __safeDI_screen07(context: context)
			            }
			            let screen08 = Instantiator<Screen08> {
			                __safeDI_screen08(context: context)
			            }
			            let screen10 = Instantiator<Screen10> {
			                __safeDI_screen10(context: context)
			            }
			            return Screen09(service09: service09, context: context, screen05: screen05, screen06: screen06, screen07: screen07, screen08: screen08, screen10: screen10)
			        }
			        func __safeDI_screen10(context: Context) -> Screen10 {
			            let service10 = Service()
			            let screen06 = Instantiator<Screen06> {
			                __safeDI_screen06(context: context)
			            }
			            let screen07 = Instantiator<Screen07> {
			                __safeDI_screen07(context: context)
			            }
			            let screen08 = Instantiator<Screen08> {
			                __safeDI_screen08(context: context)
			            }
			            let screen09 = Instantiator<Screen09> {
			                __safeDI_screen09(context: context)
			            }
			            let screen11 = Instantiator<Screen11> {
			                __safeDI_screen11(context: context)
			            }
			            return Screen10(service10: service10, context: context, screen06: screen06, screen07: screen07, screen08: screen08, screen09: screen09, screen11: screen11)
			        }
			        func __safeDI_screen11(context: Context) -> Screen11 {
			            let service11 = Service()
			            let screen07 = Instantiator<Screen07> {
			                __safeDI_screen07(context: context)
			            }
			            let screen08 = Instantiator<Screen08> {
			                __safeDI_screen08(context: context)
			            }
			            let screen09 = Instantiator<Screen09> {
			                __safeDI_screen09(context: context)
			            }
			            let screen10 = Instantiator<Screen10> {
			                __safeDI_screen10(context: context)
			            }
			            let screen12 = Instantiator<Screen12> {
			                __safeDI_screen12(context: context)
			            }
			            return Screen11(service11: service11, context: context, screen07: screen07, screen08: screen08, screen09: screen09, screen10: screen10, screen12: screen12)
			        }
			        func __safeDI_screen12(context: Context) -> Screen12 {
			            let service12 = Service()
			            let screen08 = Instantiator<Screen08> {
			                __safeDI_screen08(context: context)
			            }
			            let screen09 = Instantiator<Screen09> {
			                __safeDI_screen09(context: context)
			            }
			            let screen10 = Instantiator<Screen10> {
			                __safeDI_screen10(context: context)
			            }
			            let screen11 = Instantiator<Screen11> {
			                __safeDI_screen11(context: context)
			            }
			            let screen13 = Instantiator<Screen13> {
			                __safeDI_screen13(context: context)
			            }
			            return Screen12(service12: service12, context: context, screen08: screen08, screen09: screen09, screen10: screen10, screen11: screen11, screen13: screen13)
			        }
			        func __safeDI_screen13(context: Context) -> Screen13 {
			            let service13 = Service()
			            let screen09 = Instantiator<Screen09> {
			                __safeDI_screen09(context: context)
			            }
			            let screen10 = Instantiator<Screen10> {
			                __safeDI_screen10(context: context)
			            }
			            let screen11 = Instantiator<Screen11> {
			                __safeDI_screen11(context: context)
			            }
			            let screen12 = Instantiator<Screen12> {
			                __safeDI_screen12(context: context)
			            }
			            let screen14 = Instantiator<Screen14> {
			                __safeDI_screen14(context: context)
			            }
			            return Screen13(service13: service13, context: context, screen09: screen09, screen10: screen10, screen11: screen11, screen12: screen12, screen14: screen14)
			        }
			        func __safeDI_screen14(context: Context) -> Screen14 {
			            let service14 = Service()
			            let screen10 = Instantiator<Screen10> {
			                __safeDI_screen10(context: context)
			            }
			            let screen11 = Instantiator<Screen11> {
			                __safeDI_screen11(context: context)
			            }
			            let screen12 = Instantiator<Screen12> {
			                __safeDI_screen12(context: context)
			            }
			            let screen13 = Instantiator<Screen13> {
			                __safeDI_screen13(context: context)
			            }
			            let screen15 = Instantiator<Screen15> {
			                __safeDI_screen15(context: context)
			            }
			            return Screen14(service14: service14, context: context, screen10: screen10, screen11: screen11, screen12: screen12, screen13: screen13, screen15: screen15)
			        }
			        func __safeDI_screen15(context: Context) -> Screen15 {
			            let service15 = Service()
			            let screen11 = Instantiator<Screen11> {
			                __safeDI_screen11(context: context)
			            }
			            let screen12 = Instantiator<Screen12> {
			                __safeDI_screen12(context: context)
			            }
			            let screen13 = Instantiator<Screen13> {
			                __safeDI_screen13(context: context)
			            }
			            let screen14 = Instantiator<Screen14> {
			                __safeDI_screen14(context: context)
			            }
			            let screen16 = Instantiator<Screen16> {
			                __safeDI_screen16(context: context)
			            }
			            return Screen15(service15: service15, context: context, screen11: screen11, screen12: screen12, screen13: screen13, screen14: screen14, screen16: screen16)
			        }
			        func __safeDI_screen16(context: Context) -> Screen16 {
			            let service16 = Service()
			            let screen12 = Instantiator<Screen12> {
			                __safeDI_screen12(context: context)
			            }
			            let screen13 = Instantiator<Screen13> {
			                __safeDI_screen13(context: context)
			            }
			            let screen14 = Instantiator<Screen14> {
			                __safeDI_screen14(context: context)
			            }
			            let screen15 = Instantiator<Screen15> {
			                __safeDI_screen15(context: context)
			            }
			            let screen17 = Instantiator<Screen17> {
			                __safeDI_screen17(context: context)
			            }
			            return Screen16(service16: service16, context: context, screen12: screen12, screen13: screen13, screen14: screen14, screen15: screen15, screen17: screen17)
			        }
			        func __safeDI_screen17(context: Context) -> Screen17 {
			            let service17 = Service()
			            let screen13 = Instantiator<Screen13> {
			                __safeDI_screen13(context: context)
			            }
			            let screen14 = Instantiator<Screen14> {
			                __safeDI_screen14(context: context)
			            }
			            let screen15 = Instantiator<Screen15> {
			                __safeDI_screen15(context: context)
			            }
			            let screen16 = Instantiator<Screen16> {
			                __safeDI_screen16(context: context)
			            }
			            let screen18 = Instantiator<Screen18> {
			                __safeDI_screen18(context: context)
			            }
			            return Screen17(service17: service17, context: context, screen13: screen13, screen14: screen14, screen15: screen15, screen16: screen16, screen18: screen18)
			        }
			        func __safeDI_screen18(context: Context) -> Screen18 {
			            let service18 = Service()
			            let screen14 = Instantiator<Screen14> {
			                __safeDI_screen14(context: context)
			            }
			            let screen15 = Instantiator<Screen15> {
			                __safeDI_screen15(context: context)
			            }
			            let screen16 = Instantiator<Screen16> {
			                __safeDI_screen16(context: context)
			            }
			            let screen17 = Instantiator<Screen17> {
			                __safeDI_screen17(context: context)
			            }
			            let screen19 = Instantiator<Screen19> {
			                __safeDI_screen19(context: context)
			            }
			            return Screen18(service18: service18, context: context, screen14: screen14, screen15: screen15, screen16: screen16, screen17: screen17, screen19: screen19)
			        }
			        func __safeDI_screen19(context: Context) -> Screen19 {
			            let service19 = Service()
			            let screen15 = Instantiator<Screen15> {
			                __safeDI_screen15(context: context)
			            }
			            let screen16 = Instantiator<Screen16> {
			                __safeDI_screen16(context: context)
			            }
			            let screen17 = Instantiator<Screen17> {
			                __safeDI_screen17(context: context)
			            }
			            let screen18 = Instantiator<Screen18> {
			                __safeDI_screen18(context: context)
			            }
			            let screen20 = Instantiator<Screen20> {
			                __safeDI_screen20(context: context)
			            }
			            return Screen19(service19: service19, context: context, screen15: screen15, screen16: screen16, screen17: screen17, screen18: screen18, screen20: screen20)
			        }
			        func __safeDI_screen20(context: Context) -> Screen20 {
			            let service20 = Service()
			            let screen16 = Instantiator<Screen16> {
			                __safeDI_screen16(context: context)
			            }
			            let screen17 = Instantiator<Screen17> {
			                __safeDI_screen17(context: context)
			            }
			            let screen18 = Instantiator<Screen18> {
			                __safeDI_screen18(context: context)
			            }
			            let screen19 = Instantiator<Screen19> {
			                __safeDI_screen19(context: context)
			            }
			            let screen21 = Instantiator<Screen21> {
			                __safeDI_screen21(context: context)
			            }
			            return Screen20(service20: service20, context: context, screen16: screen16, screen17: screen17, screen18: screen18, screen19: screen19, screen21: screen21)
			        }
			        func __safeDI_screen21(context: Context) -> Screen21 {
			            let service21 = Service()
			            let screen17 = Instantiator<Screen17> {
			                __safeDI_screen17(context: context)
			            }
			            let screen18 = Instantiator<Screen18> {
			                __safeDI_screen18(context: context)
			            }
			            let screen19 = Instantiator<Screen19> {
			                __safeDI_screen19(context: context)
			            }
			            let screen20 = Instantiator<Screen20> {
			                __safeDI_screen20(context: context)
			            }
			            let screen22 = Instantiator<Screen22> {
			                __safeDI_screen22(context: context)
			            }
			            return Screen21(service21: service21, context: context, screen17: screen17, screen18: screen18, screen19: screen19, screen20: screen20, screen22: screen22)
			        }
			        func __safeDI_screen22(context: Context) -> Screen22 {
			            let service22 = Service()
			            let screen18 = Instantiator<Screen18> {
			                __safeDI_screen18(context: context)
			            }
			            let screen19 = Instantiator<Screen19> {
			                __safeDI_screen19(context: context)
			            }
			            let screen20 = Instantiator<Screen20> {
			                __safeDI_screen20(context: context)
			            }
			            let screen21 = Instantiator<Screen21> {
			                __safeDI_screen21(context: context)
			            }
			            let screen23 = Instantiator<Screen23> {
			                __safeDI_screen23(context: context)
			            }
			            return Screen22(service22: service22, context: context, screen18: screen18, screen19: screen19, screen20: screen20, screen21: screen21, screen23: screen23)
			        }
			        func __safeDI_screen23(context: Context) -> Screen23 {
			            let service23 = Service()
			            let screen19 = Instantiator<Screen19> {
			                __safeDI_screen19(context: context)
			            }
			            let screen20 = Instantiator<Screen20> {
			                __safeDI_screen20(context: context)
			            }
			            let screen21 = Instantiator<Screen21> {
			                __safeDI_screen21(context: context)
			            }
			            let screen22 = Instantiator<Screen22> {
			                __safeDI_screen22(context: context)
			            }
			            let hub = Instantiator<Hub>(__safeDI_hub)
			            return Screen23(service23: service23, context: context, screen19: screen19, screen20: screen20, screen21: screen21, screen22: screen22, hub: hub)
			        }
			        func __safeDI_hub() -> Hub {
			            let service00 = Service()
			            let service01 = Service()
			            let service02 = Service()
			            let service03 = Service()
			            let service04 = Service()
			            let service05 = Service()
			            let service06 = Service()
			            let service07 = Service()
			            let service08 = Service()
			            let service09 = Service()
			            let service10 = Service()
			            let service11 = Service()
			            let service12 = Service()
			            let service13 = Service()
			            let service14 = Service()
			            let service15 = Service()
			            let service16 = Service()
			            let service17 = Service()
			            let service18 = Service()
			            let service19 = Service()
			            let service20 = Service()
			            let service21 = Service()
			            let service22 = Service()
			            let service23 = Service()
			            let context = Context()
			            let screen23 = Instantiator<Screen23> {
			                __safeDI_screen23(context: context)
			            }
			            return Hub(service00: service00, service01: service01, service02: service02, service03: service03, service04: service04, service05: service05, service06: service06, service07: service07, service08: service08, service09: service09, service10: service10, service11: service11, service12: service12, service13: service13, service14: service14, service15: service15, service16: service16, service17: service17, service18: service18, service19: service19, service20: service20, service21: service21, service22: service22, service23: service23, context: context, screen23: screen23)
			        }
			        let screen00 = Instantiator<Screen00> {
			            __safeDI_screen00(context: context)
			        }
			        self.init(context: context, screen00: screen00)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenFeatureDeclaringLabelWithTypeOfItsOwnOpensAgainFeatureThatReceivesRootsDeclaration() async {
		// `Entry1` declares `state: State1`, which its own screen receives, and that screen opens `Entry0` again, whose
		// screen receives `Root`'s `state: RootState`. Each declaration is the closest of a read that accepts it on the
		// tree's first build; only in the tree of `Entry0` built again is `Entry1`'s the closest declaration of `Screen0`'s
		// read, since `Entry0` declares no state of its own between them.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let state: RootState", "@Instantiated let entry0Builder: Instantiator<Entry0>"]),
			seamFixtureType(named: "Entry0", isFinalClass: true, declarations: ["@Instantiated let screen0Builder: Instantiator<Screen0>"]),
			seamFixtureType(named: "Screen0", isFinalClass: true, declarations: ["@Received let state: RootState", "@Instantiated let entry1Builder: Instantiator<Entry1>"]),
			seamFixtureType(named: "Entry1", isFinalClass: true, declarations: ["@Instantiated let state: State1", "@Instantiated let screen1Builder: Instantiator<Screen1>"]),
			seamFixtureType(named: "Screen1", isFinalClass: true, declarations: ["@Received let state: State1", "@Instantiated let entry0Builder: Instantiator<Entry0>"]),
			seamFixtureType(named: "RootState", isFinalClass: true, declarations: []),
			seamFixtureType(named: "State1", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen0.swift"]):8:5: error: @Received property `state: RootState` is hidden in chain: Root -> Instantiator<Entry0> -> Instantiator<Screen0> -> Instantiator<Entry1> -> Instantiator<Screen1> -> Instantiator<Entry0> -> Screen0. `Entry1` declares `state: State1` with the same label, so the types below `Entry1` receive `state: State1` instead. Give `state: State1` on `Entry1` a different label to fix.
			\(fixtures["Entry1.swift"]):8:5: note: `state: State1` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenError_whenReadIsReachedBeneathHidingDeclarationBothThroughScopeThatDeclaresLabelAgainAndThroughOneThatDoesNot() async {
		// `M` declares `x: Y` between `C` and the cycle-closing scope that builds `C` again. `C` reaches `R`, which receives
		// `x: X`, through `E`, which declares `x: X` again, and through `Q`, which declares nothing: beneath `Q`, `M`'s is
		// the closest declaration of `R`'s read.
		let fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "C", isFinalClass: true, declarations: ["@Instantiated let mBuilder: Instantiator<M>", "@Instantiated let eBuilder: Instantiator<E>", "@Instantiated let qBuilder: Instantiator<Q>"]),
			seamFixtureType(named: "M", isFinalClass: true, declarations: ["@Instantiated let x: Y", "@Instantiated let cBuilder: Instantiator<C>"]),
			seamFixtureType(named: "E", isFinalClass: true, declarations: ["@Instantiated let x: X", "@Instantiated let rBuilder: Instantiator<R>"]),
			seamFixtureType(named: "Q", isFinalClass: true, declarations: ["@Instantiated let rBuilder: Instantiator<R>"]),
			seamFixtureType(named: "R", isFinalClass: true, declarations: ["@Received let x: X"]),
			seamFixtureType(named: "X", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Y", isFinalClass: true, declarations: []),
		]
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["R.swift"]):7:5: error: @Received property `x: X` is hidden in chain: Root -> Instantiator<C> -> Instantiator<M> -> Instantiator<C> -> Instantiator<Q> -> R. `M` declares `x: Y` with the same label, so the types below `M` receive `x: Y` instead. Give `x: Y` on `M` a different label to fix.
			\(fixtures["M.swift"]):8:5: note: `x: Y` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
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
	/// - Parameter sharedContext: When not `nil`, `Root` also declares `context: Context`, each screen also makes
	///   `screenDeclaration` after its `Service`, and `Hub` makes `hubDeclaration` after the screens' `Service`s.
	private static func screensAndHubFixture(screenCount: Int, sharedContext: (screenDeclaration: String, hubDeclaration: String)? = nil) -> [String] {
		var rootDeclarations = ["@Instantiated let \(screenLabel(0)): Instantiator<\(screenName(0))>"]
		var hubDeclarations = (0..<screenCount).map { "@Instantiated let \(serviceLabel($0)): Service" }
		if let sharedContext {
			rootDeclarations.insert("@Instantiated let context: Context", at: 0)
			hubDeclarations.append(sharedContext.hubDeclaration)
		}
		hubDeclarations.append("@Instantiated let \(screenLabel(screenCount - 1)): Instantiator<\(screenName(screenCount - 1))>")
		var fixture = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: rootDeclarations),
			seamFixtureType(named: "Service", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Hub", isFinalClass: true, declarations: hubDeclarations),
		]
		if sharedContext != nil {
			fixture.append(seamFixtureType(named: "Context", isFinalClass: true, declarations: []))
		}
		for index in 0..<screenCount {
			var declarations = ["@Instantiated let \(serviceLabel(index)): Service"]
			if let sharedContext {
				declarations.append(sharedContext.screenDeclaration)
			}
			declarations += screenIndicesOpenedAbove(index).map { "@Instantiated let \(screenLabel($0)): Instantiator<\(screenName($0))>" }
			declarations.append(index + 1 < screenCount ? "@Instantiated let \(screenLabel(index + 1)): Instantiator<\(screenName(index + 1))>" : "@Instantiated let hub: Instantiator<Hub>")
			fixture.append(seamFixtureType(named: screenName(index), isFinalClass: true, declarations: declarations))
		}
		return fixture
	}
}
