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

/// The approved differences the check of node records rewrites before it reports a root as differing
/// (`ApprovedDifferences`). No records write the optional channel under rule A yet, so the records' side of each case
/// here is written by hand, as rule A states it, and the tree's side is what the tool generates for the fixture.
struct ApprovedDifferencesTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – entry 13, the optional channel

	@Test
	mutating func rewrite_writesTheTreesText_whenNilIsPassedBesideSendableLazyAndLazyWrappers() async throws {
		let treeText = try await treeText(of: Self.twoWrappersAndNilFixture)
		let nodeRecordsText = Self.generatedFilePreamble + Self.twoWrappersAndNilUnderRuleA
		#expect(nodeRecordsText != treeText)
		// The `nil` moves from the lazy wrapper's function, which the facts give it to, to the Sendable lazy wrapper's, the
		// first place's: that one's parameter becomes optional and the lazy one's is optional no more.
		#expect(OptionalChannelRewrite.rewritten(nodeRecordsText, treeText: treeText)?.text == treeText)
		#expect(ApprovedDifferences.normalized(nodeRecordsText: nodeRecordsText, treeText: treeText, by: [ApprovedDifferences.optionalChannel])?.entries == ["13[SendableLazilyInstantiated]"])
	}

	@Test
	mutating func rewrite_writesTheTreesText_whenNilIsPassedBesideTwoWrappersAndValue() async throws {
		let treeText = try await treeText(of: Self.twoWrappersValueAndNilFixture)
		let nodeRecordsText = Self.generatedFilePreamble + Self.twoWrappersValueAndNilUnderRuleA
		#expect(nodeRecordsText != treeText)
		// The `nil` moves to the function of the wrapper the tree declares optional, the first place's; the function of the
		// declared form stays for the place that passes a value, declared where that place calls it.
		#expect(OptionalChannelRewrite.rewritten(nodeRecordsText, treeText: treeText)?.text == treeText)
		#expect(ApprovedDifferences.normalized(nodeRecordsText: nodeRecordsText, treeText: treeText, by: [ApprovedDifferences.optionalChannel])?.entries == ["13[LazilyInstantiated]"])
	}

	@Test
	mutating func rewrite_movesNilOnce_whenAnotherReadersFunctionDeclaresOtherWrapperOptional() async throws {
		let treeText = try await treeText(of: Self.twoReadersFixture)
		let nodeRecordsText = Self.generatedFilePreamble + Self.twoWrappersValueAndNilUnderRuleA.replacingOccurrences(of: Self.rootInitializerCallOfTwoWrappersValueAndNil, with: Self.secondReaderAsBothTextsWriteIt)
		#expect(nodeRecordsText != treeText)
		// `Bud`'s function takes the Sendable lazy wrapper as an optional in the tree, beside `Leaf`'s lazy one. `Leaf`'s
		// `nil` moves to its lazy function, which the tree's function of that name declares optional, and moves no further:
		// a choice read from the whole of the tree's text would move it on to the Sendable lazy function and back for ever.
		#expect(OptionalChannelRewrite.rewritten(nodeRecordsText, treeText: treeText)?.text == treeText)
		#expect(ApprovedDifferences.normalized(nodeRecordsText: nodeRecordsText, treeText: treeText, by: [ApprovedDifferences.optionalChannel])?.entries == ["13[LazilyInstantiated]"])
	}

	@Test
	func retargetCalls_renamesOnlyCallThatPassesNil_whenLineHoldsTwoCalls() {
		var code = FunctionText("let pair = (__safeDI_leaf_(theme: nil), __safeDI_leaf_(theme: theme))")
		code.retargetCalls(of: "__safeDI_leaf_", passingNilFor: "theme", to: "__safeDI_leaf")
		#expect(code.text == "let pair = (__safeDI_leaf(theme: nil), __safeDI_leaf_(theme: theme))")
	}

	@Test
	mutating func rewrite_returnsNil_whenTextAlreadyHandsNilToWrapperTreeDeclaresOptional() async throws {
		// One wrapper and `nil` are one function in both texts: there is no call to move.
		let treeText = try await treeText(of: Self.twoWrappersValueAndNilFixture)
		#expect(OptionalChannelRewrite.rewritten(treeText, treeText: treeText) == nil)
	}

	@Test
	mutating func normalized_returnsNil_whenWrappersFunctionReadsWrapperWhereTreeReadsItsInstance() async throws {
		let treeText = try await treeText(of: Self.twoWrappersValueAndNilFixture)
		// The function the rewrite makes optional hands `Twig` the wrapper itself, which no entry approves. The rewrite
		// changes only the reads of the wrapper's instance, so the text still differs. The mutation this test names: a
		// rewrite that also turned a bare `theme` argument of that function into `theme?.instance` would approve this text,
		// and this test would fail.
		let nodeRecordsText = (Self.generatedFilePreamble + Self.twoWrappersValueAndNilUnderRuleA).replacingOccurrences(of: """
		        func __safeDI_leafBuilder(theme: LazilyInstantiated<Theme>) -> Leaf {
		            let twig = Twig(theme: theme.instance)
		""", with: """
		        func __safeDI_leafBuilder(theme: LazilyInstantiated<Theme>) -> Leaf {
		            let twig = Twig(theme: theme)
		""")
		#expect(nodeRecordsText != Self.generatedFilePreamble + Self.twoWrappersValueAndNilUnderRuleA)
		#expect(OptionalChannelRewrite.rewritten(nodeRecordsText, treeText: treeText) != nil)
		#expect(ApprovedDifferences.normalized(nodeRecordsText: nodeRecordsText, treeText: treeText, by: [ApprovedDifferences.optionalChannel]) == nil)
	}

	@Test
	func all_listsNoEntry_untilRootDiffersByIt() {
		// Entry 13 is listed with the first root laid out under rule A, so that the tally fails no run for it before.
		#expect(ApprovedDifferences.all.map(\.entry) == [])
	}

	@Test
	mutating func normalized_returnsNil_whenRewrittenTextStillDiffersFromTrees() async throws {
		let treeText = try await treeText(of: Self.twoWrappersAndNilFixture)
		// A second difference, which no entry approves: the root's argument is another value.
		let nodeRecordsText = (Self.generatedFilePreamble + Self.twoWrappersAndNilUnderRuleA).replacingOccurrences(of: "self.init(second: second, first: first, third: third)", with: "self.init(second: second, first: first, third: __safeDI_third())")
		#expect(OptionalChannelRewrite.rewritten(nodeRecordsText, treeText: treeText) != nil)
		#expect(ApprovedDifferences.normalized(nodeRecordsText: nodeRecordsText, treeText: treeText, by: [ApprovedDifferences.optionalChannel]) == nil)
	}

	@Test
	func normalized_returnsNil_whenTextsAreEqual() {
		#expect(ApprovedDifferences.normalized(nodeRecordsText: "let a = A()", treeText: "let a = A()") == nil)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The code the tool generates for `Root` of `fixture`, whose world node records refuse, so its tree writes it.
	private mutating func treeText(of fixture: String) async throws -> String {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		let output = try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: ["Fixture.swift": fixture], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var refusals = [String?]()
		for await report in stream {
			refusals.append(report.refusal)
		}
		#expect(refusals == ["nodeHasSeveralVariants"])
		return try #require(output.generatedFiles?.values.first { $0.contains("extension Root {") })
	}

	private static let generatedFilePreamble = generatedFileHeader + """
	#if canImport(SafeDI)
	import SafeDI
	#endif


	"""

	/// `twoWrappersValueAndNilFixture` with a second reader, `Bud`, whose read `Fifth` answers with a Sendable lazy
	/// wrapper and `Sixth` with nothing: one wrapper and nothing, which both texts write as one function.
	private static let twoReadersFixture = """
	import SafeDI
	@Instantiable(isRoot: true) public final class Root: Instantiable {
	    public init(first: First, second: Second, third: Third, fourth: Fourth, fifth: Fifth, sixth: Sixth) { self.first = first; self.second = second; self.third = third; self.fourth = fourth; self.fifth = fifth; self.sixth = sixth }
	    @Instantiated let first: First
	    @Instantiated let second: Second
	    @Instantiated let third: Third
	    @Instantiated let fourth: Fourth
	    @Instantiated let fifth: Fifth
	    @Instantiated let sixth: Sixth
	}
	@Instantiable public final class First: Instantiable {
	    public init(theme: LazilyInstantiated<Theme>, leafBuilder: Instantiator<Leaf>) { self.theme = theme; self.leafBuilder = leafBuilder }
	    @Instantiated let theme: LazilyInstantiated<Theme>
	    @Instantiated let leafBuilder: Instantiator<Leaf>
	}
	@Instantiable public final class Leaf: Instantiable {
	    public init(theme: Theme?, twig: Twig) { self.theme = theme; self.twig = twig }
	    @Received(onlyIfAvailable: true) let theme: Theme?
	    @Instantiated let twig: Twig
	}
	@Instantiable public final class Twig: Instantiable {
	    public init(theme: Theme?) { self.theme = theme }
	    @Received(onlyIfAvailable: true) let theme: Theme?
	}
	@Instantiable public final class Theme: Instantiable, Sendable {
	    public init() {}
	}
	@Instantiable public final class Third: Instantiable {
	    public init(leafBuilder: Instantiator<Leaf>) { self.leafBuilder = leafBuilder }
	    @Instantiated let leafBuilder: Instantiator<Leaf>
	}
	@Instantiable public final class Second: Instantiable {
	    public init(theme: SendableLazilyInstantiated<Theme>, leafBuilder: Instantiator<Leaf>) { self.theme = theme; self.leafBuilder = leafBuilder }
	    @Instantiated let theme: SendableLazilyInstantiated<Theme>
	    @Instantiated let leafBuilder: Instantiator<Leaf>
	}
	@Instantiable public final class Fourth: Instantiable {
	    public init(theme: Theme, leafBuilder: Instantiator<Leaf>) { self.theme = theme; self.leafBuilder = leafBuilder }
	    @Instantiated let theme: Theme
	    @Instantiated let leafBuilder: Instantiator<Leaf>
	}
	@Instantiable public final class Bud: Instantiable {
	    public init(theme: Theme?) { self.theme = theme }
	    @Received(onlyIfAvailable: true) let theme: Theme?
	}
	@Instantiable public final class Fifth: Instantiable {
	    public init(theme: SendableLazilyInstantiated<Theme>, budBuilder: Instantiator<Bud>) { self.theme = theme; self.budBuilder = budBuilder }
	    @Instantiated let theme: SendableLazilyInstantiated<Theme>
	    @Instantiated let budBuilder: Instantiator<Bud>
	}
	@Instantiable public final class Sixth: Instantiable {
	    public init(budBuilder: Instantiator<Bud>) { self.budBuilder = budBuilder }
	    @Instantiated let budBuilder: Instantiator<Bud>
	}
	"""

	private static let rootInitializerCallOfTwoWrappersValueAndNil = """
	        self.init(first: first, second: second, third: third, fourth: fourth)
	    }
	}
	"""

	/// What the tree writes for `Bud`'s places and the root's initializer call of `twoReadersFixture`, which rule A
	/// writes the same.
	private static let secondReaderAsBothTextsWriteIt = """
	        func __safeDI_budBuilder(theme: SendableLazilyInstantiated<Theme>?) -> Bud {
	            Bud(theme: theme?.instance)
	        }
	        func __safeDI_fifth() -> Fifth {
	            let theme = SendableLazilyInstantiated<Theme>(__safeDI_theme_)
	            let budBuilder = Instantiator<Bud> {
	                __safeDI_budBuilder(theme: theme)
	            }
	            return Fifth(theme: theme, budBuilder: budBuilder)
	        }
	        let fifth: Fifth = __safeDI_fifth()
	        func __safeDI_sixth() -> Sixth {
	            let budBuilder = Instantiator<Bud> {
	                __safeDI_budBuilder(theme: nil)
	            }
	            return Sixth(budBuilder: budBuilder)
	        }
	        let sixth: Sixth = __safeDI_sixth()
	        self.init(first: first, second: second, third: third, fourth: fourth, fifth: fifth, sixth: sixth)
	    }
	}
	"""

	/// `Second`, the root's first place, answers `Leaf`'s read of `theme` with a Sendable lazy wrapper, `First` with a
	/// lazy wrapper, and `Third` with nothing.
	private static let twoWrappersAndNilFixture = """
	import SafeDI
	@Instantiable(isRoot: true) public final class Root: Instantiable {
	    public init(second: Second, first: First, third: Third) { self.second = second; self.first = first; self.third = third }
	    @Instantiated let second: Second
	    @Instantiated let first: First
	    @Instantiated let third: Third
	}
	@Instantiable public final class First: Instantiable {
	    public init(theme: LazilyInstantiated<Theme>, leafBuilder: Instantiator<Leaf>) { self.theme = theme; self.leafBuilder = leafBuilder }
	    @Instantiated let theme: LazilyInstantiated<Theme>
	    @Instantiated let leafBuilder: Instantiator<Leaf>
	}
	@Instantiable public final class Leaf: Instantiable {
	    public init(theme: Theme?, twig: Twig) { self.theme = theme; self.twig = twig }
	    @Received(onlyIfAvailable: true) let theme: Theme?
	    @Instantiated let twig: Twig
	}
	@Instantiable public final class Twig: Instantiable {
	    public init(theme: Theme?) { self.theme = theme }
	    @Received(onlyIfAvailable: true) let theme: Theme?
	}
	@Instantiable public final class Theme: Instantiable, Sendable {
	    public init() {}
	}
	@Instantiable public final class Third: Instantiable {
	    public init(leafBuilder: Instantiator<Leaf>) { self.leafBuilder = leafBuilder }
	    @Instantiated let leafBuilder: Instantiator<Leaf>
	}
	@Instantiable public final class Second: Instantiable {
	    public init(theme: SendableLazilyInstantiated<Theme>, leafBuilder: Instantiator<Leaf>) { self.theme = theme; self.leafBuilder = leafBuilder }
	    @Instantiated let theme: SendableLazilyInstantiated<Theme>
	    @Instantiated let leafBuilder: Instantiator<Leaf>
	}
	"""

	/// `twoWrappersAndNilFixture`'s root as rule A lays it out: the `nil` goes to the lazy wrapper's function, whose
	/// parameter is optional, and the Sendable lazy wrapper's function takes the wrapper.
	private static let twoWrappersAndNilUnderRuleA = """
	extension Root {
	    public convenience init() {
	        @Sendable nonisolated func __safeDI_theme() -> Theme {
	            Theme()
	        }
	        func __safeDI_leafBuilder(theme: SendableLazilyInstantiated<Theme>) -> Leaf {
	            let twig = Twig(theme: theme.instance)
	            return Leaf(theme: theme.instance, twig: twig)
	        }
	        func __safeDI_second() -> Second {
	            let theme = SendableLazilyInstantiated<Theme>(__safeDI_theme)
	            let leafBuilder = Instantiator<Leaf> {
	                __safeDI_leafBuilder(theme: theme)
	            }
	            return Second(theme: theme, leafBuilder: leafBuilder)
	        }
	        let second: Second = __safeDI_second()
	        func __safeDI_theme_() -> Theme {
	            Theme()
	        }
	        func __safeDI_leafBuilder_(theme: LazilyInstantiated<Theme>?) -> Leaf {
	            let twig = Twig(theme: theme?.instance)
	            return Leaf(theme: theme?.instance, twig: twig)
	        }
	        func __safeDI_first() -> First {
	            let theme = LazilyInstantiated<Theme>(__safeDI_theme_)
	            let leafBuilder = Instantiator<Leaf> {
	                __safeDI_leafBuilder_(theme: theme)
	            }
	            return First(theme: theme, leafBuilder: leafBuilder)
	        }
	        let first: First = __safeDI_first()
	        func __safeDI_third() -> Third {
	            let leafBuilder = Instantiator<Leaf> {
	                __safeDI_leafBuilder_(theme: nil)
	            }
	            return Third(leafBuilder: leafBuilder)
	        }
	        let third: Third = __safeDI_third()
	        self.init(second: second, first: first, third: third)
	    }
	}
	"""

	/// `First` and `Second` answer `Leaf`'s read of `theme` with a lazy and a Sendable lazy wrapper, `Third` with nothing,
	/// and `Fourth` with a value.
	private static let twoWrappersValueAndNilFixture = """
	import SafeDI
	@Instantiable(isRoot: true) public final class Root: Instantiable {
	    public init(first: First, second: Second, third: Third, fourth: Fourth) { self.first = first; self.second = second; self.third = third; self.fourth = fourth }
	    @Instantiated let first: First
	    @Instantiated let second: Second
	    @Instantiated let third: Third
	    @Instantiated let fourth: Fourth
	}
	@Instantiable public final class First: Instantiable {
	    public init(theme: LazilyInstantiated<Theme>, leafBuilder: Instantiator<Leaf>) { self.theme = theme; self.leafBuilder = leafBuilder }
	    @Instantiated let theme: LazilyInstantiated<Theme>
	    @Instantiated let leafBuilder: Instantiator<Leaf>
	}
	@Instantiable public final class Leaf: Instantiable {
	    public init(theme: Theme?, twig: Twig) { self.theme = theme; self.twig = twig }
	    @Received(onlyIfAvailable: true) let theme: Theme?
	    @Instantiated let twig: Twig
	}
	@Instantiable public final class Twig: Instantiable {
	    public init(theme: Theme?) { self.theme = theme }
	    @Received(onlyIfAvailable: true) let theme: Theme?
	}
	@Instantiable public final class Theme: Instantiable, Sendable {
	    public init() {}
	}
	@Instantiable public final class Third: Instantiable {
	    public init(leafBuilder: Instantiator<Leaf>) { self.leafBuilder = leafBuilder }
	    @Instantiated let leafBuilder: Instantiator<Leaf>
	}
	@Instantiable public final class Second: Instantiable {
	    public init(theme: SendableLazilyInstantiated<Theme>, leafBuilder: Instantiator<Leaf>) { self.theme = theme; self.leafBuilder = leafBuilder }
	    @Instantiated let theme: SendableLazilyInstantiated<Theme>
	    @Instantiated let leafBuilder: Instantiator<Leaf>
	}
	@Instantiable public final class Fourth: Instantiable {
	    public init(theme: Theme, leafBuilder: Instantiator<Leaf>) { self.theme = theme; self.leafBuilder = leafBuilder }
	    @Instantiated let theme: Theme
	    @Instantiated let leafBuilder: Instantiator<Leaf>
	}
	"""

	/// `twoWrappersValueAndNilFixture`'s root as rule A lays it out: one function per wrapper, each taking the wrapper, and
	/// one function of the declared form for the `nil` and the value.
	private static let twoWrappersValueAndNilUnderRuleA = """
	extension Root {
	    public convenience init() {
	        func __safeDI_theme() -> Theme {
	            Theme()
	        }
	        func __safeDI_leafBuilder(theme: LazilyInstantiated<Theme>) -> Leaf {
	            let twig = Twig(theme: theme.instance)
	            return Leaf(theme: theme.instance, twig: twig)
	        }
	        func __safeDI_first() -> First {
	            let theme = LazilyInstantiated<Theme>(__safeDI_theme)
	            let leafBuilder = Instantiator<Leaf> {
	                __safeDI_leafBuilder(theme: theme)
	            }
	            return First(theme: theme, leafBuilder: leafBuilder)
	        }
	        let first: First = __safeDI_first()
	        @Sendable nonisolated func __safeDI_theme_() -> Theme {
	            Theme()
	        }
	        func __safeDI_leafBuilder_(theme: SendableLazilyInstantiated<Theme>) -> Leaf {
	            let twig = Twig(theme: theme.instance)
	            return Leaf(theme: theme.instance, twig: twig)
	        }
	        func __safeDI_second() -> Second {
	            let theme = SendableLazilyInstantiated<Theme>(__safeDI_theme_)
	            let leafBuilder = Instantiator<Leaf> {
	                __safeDI_leafBuilder_(theme: theme)
	            }
	            return Second(theme: theme, leafBuilder: leafBuilder)
	        }
	        let second: Second = __safeDI_second()
	        func __safeDI_leafBuilder__(theme: Theme?) -> Leaf {
	            let twig = Twig(theme: theme)
	            return Leaf(theme: theme, twig: twig)
	        }
	        func __safeDI_third() -> Third {
	            let leafBuilder = Instantiator<Leaf> {
	                __safeDI_leafBuilder__(theme: nil)
	            }
	            return Third(leafBuilder: leafBuilder)
	        }
	        let third: Third = __safeDI_third()
	        func __safeDI_fourth() -> Fourth {
	            let theme = Theme()
	            let leafBuilder = Instantiator<Leaf> {
	                __safeDI_leafBuilder__(theme: theme)
	            }
	            return Fourth(theme: theme, leafBuilder: leafBuilder)
	        }
	        let fourth: Fourth = __safeDI_fourth()
	        self.init(first: first, second: second, third: third, fourth: fourth)
	    }
	}
	"""
}
