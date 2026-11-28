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
	mutating func rewrite_writesTheTreesText_whenNilIsPassedBesideOneWrapper() async throws {
		let treeText = try await treeText(of: Self.wrapperAndNilFixture)
		let nodeRecordsText = Self.generatedFilePreamble + Self.wrapperAndNilUnderRuleA
		#expect(nodeRecordsText != treeText)
		// The call that passes `nil` moves to the wrapper's function, whose parameter becomes optional, and the function of
		// the declared form, which nothing calls any more, is removed.
		#expect(OptionalChannelRewrite.rewritten(nodeRecordsText, treeText: treeText) == treeText)
		#expect(ApprovedDifferences.normalized(nodeRecordsText: nodeRecordsText, treeText: treeText)?.entries == [13])
	}

	@Test
	mutating func rewrite_writesTheTreesText_whenNilIsPassedBesideTwoWrappersAndValue() async throws {
		let treeText = try await treeText(of: Self.twoWrappersValueAndNilFixture)
		let nodeRecordsText = Self.generatedFilePreamble + Self.twoWrappersValueAndNilUnderRuleA
		#expect(nodeRecordsText != treeText)
		// The `nil` moves to the function of the wrapper the tree declares optional, the first place's; the function of the
		// declared form stays for the place that passes a value, declared where that place calls it.
		#expect(OptionalChannelRewrite.rewritten(nodeRecordsText, treeText: treeText) == treeText)
		#expect(ApprovedDifferences.normalized(nodeRecordsText: nodeRecordsText, treeText: treeText)?.entries == [13])
	}

	@Test
	mutating func rewrite_returnsNil_whenNoCallPassesNilBesideWrapper() async throws {
		let treeText = try await treeText(of: Self.wrapperAndNilFixture)
		#expect(OptionalChannelRewrite.rewritten(treeText, treeText: treeText) == nil)
	}

	@Test
	mutating func normalized_returnsNil_whenRewrittenTextStillDiffersFromTrees() async throws {
		let treeText = try await treeText(of: Self.wrapperAndNilFixture)
		// A second difference, which no entry approves: the root's argument is another value.
		let nodeRecordsText = (Self.generatedFilePreamble + Self.wrapperAndNilUnderRuleA).replacingOccurrences(of: "self.init(first: first, third: third)", with: "self.init(first: first, third: __safeDI_third())")
		#expect(OptionalChannelRewrite.rewritten(nodeRecordsText, treeText: treeText) != nil)
		#expect(ApprovedDifferences.normalized(nodeRecordsText: nodeRecordsText, treeText: treeText) == nil)
	}

	@Test
	func normalized_returnsNil_whenTextsAreEqual() {
		#expect(ApprovedDifferences.normalized(nodeRecordsText: "let a = A()", treeText: "let a = A()") == nil)
	}

	// MARK: Tests – entry 28, one function for properties of one type

	@Test(arguments: [Self.shuffledLabels, Self.shuffledLabels.reversed()], [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootThatSharesOneFunction_whenTwentyPropertiesOfOneTypeAreDeclaredUnderShuffledLabels(labels: [String], rootFileIsReadFirst: Bool) async throws {
		// Files are read in path order, so the two orders of the root's file and its types' file show that the function is
		// named by the root's declaration order alone.
		let fixtureFiles = Self.twentyPropertiesFixtureFiles(labels: labels, rootFileIsReadFirst: rootFileIsReadFirst)
		let treeOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.map { NodeRecordsChecks.outcome(of: $0).approvedEntries } == [[28]])
		let rootFile = try #require(output.generatedFiles?["Root+SafeDI.swift"])
		// The records declare one function, named for the property declared first, never for the label that sorts first,
		// and every property calls it.
		#expect(rootFile.components(separatedBy: "func __safeDI_").count - 1 == 2)
		#expect(rootFile.contains("func __safeDI_\(labels[0])() -> Shared {"))
		#expect(output.generatedFiles != treeOutput.generatedFiles)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: output.generatedFiles ?? [:]),
			knownRight: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: treeOutput.generatedFiles ?? [:]),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	mutating func rewrite_writesTheTreesText_whenPropertiesOfOneTypeShareTheFirstPropertysFunction() async throws {
		let texts = try await Self.sharedFunctionTexts(labels: Self.shuffledLabels, filesToDelete: &filesToDelete)
		#expect(texts.nodeRecords != texts.tree)
		#expect(SharedFunctionRewrite.rewritten(texts.nodeRecords, treeText: texts.tree) == texts.tree)
		#expect(ApprovedDifferences.normalized(nodeRecordsText: texts.nodeRecords, treeText: texts.tree)?.entries == [28])
	}

	@Test
	mutating func rewrite_returnsNil_whenSharedFunctionIsNamedForALaterProperty() async throws {
		let labels = Self.shuffledLabels
		let texts = try await Self.sharedFunctionTexts(labels: labels, filesToDelete: &filesToDelete)
		// The function is named for the second property, which the first calls: a name chosen by anything but the order
		// the walk builds the properties in is no approved difference.
		let renamed = texts.nodeRecords.replacingOccurrences(of: "__safeDI_\(labels[0])(", with: "__safeDI_\(labels[1])(")
		#expect(SharedFunctionRewrite.rewritten(renamed, treeText: texts.tree) == nil)
		#expect(ApprovedDifferences.normalized(nodeRecordsText: renamed, treeText: texts.tree) == nil)
	}

	@Test
	mutating func normalized_returnsNil_whenTreesCopiesDifferBeyondTheirNames() async throws {
		let labels = Self.shuffledLabels
		let texts = try await Self.sharedFunctionTexts(labels: labels, filesToDelete: &filesToDelete)
		// The tree's copy for the last property builds its leaf another way, so one function cannot stand for it.
		var treeLines = texts.tree.components(separatedBy: "\n")
		let lastCopy = try #require(treeLines.firstIndex(of: "        func __safeDI_\(labels[labels.count - 1])() -> Shared {"))
		let leafLine = try #require(treeLines[lastCopy...].firstIndex { $0.contains("Leaf()") })
		treeLines[leafLine] = treeLines[leafLine].replacingOccurrences(of: "Leaf()", with: "Leaf(other: ())")
		let treeText = treeLines.joined(separator: "\n")
		#expect(SharedFunctionRewrite.rewritten(texts.nodeRecords, treeText: treeText) != nil)
		#expect(ApprovedDifferences.normalized(nodeRecordsText: texts.nodeRecords, treeText: treeText) == nil)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Twenty labels in an order no sort gives: the first is neither the least nor the greatest.
	private static let shuffledLabels = [
		"kiwi", "apple", "zebra", "mango", "cedar", "quail", "birch", "ostrich", "yak", "lemon",
		"fig", "walnut", "heron", "date", "umbra", "newt", "panda", "raven", "grape", "toucan",
	]

	/// `Root` builds twenty properties of `Shared`, declared in the order of `labels`; `Shared` builds a lazy `Leaf`, so
	/// each property is built in a function of its own. `Root` is in a file of its own, whose path sorts before or after
	/// the file of `Shared` and `Leaf`.
	private static func twentyPropertiesFixtureFiles(labels: [String], rootFileIsReadFirst: Bool) -> [String: String] {
		var root = """
		import SafeDI
		@Instantiable(isRoot: true) public final class Root: Instantiable {

		"""
		root += "    public init(" + labels.map { "\($0): Shared" }.joined(separator: ", ") + ") {}\n"
		for label in labels {
			root += "    @Instantiated let \(label): Shared\n"
		}
		root += "}\n"
		let types = """
		import SafeDI
		@Instantiable public final class Shared: Instantiable {
		    public init(leaf: LazilyInstantiated<Leaf>) { self.leaf = leaf }
		    @Instantiated let leaf: LazilyInstantiated<Leaf>
		}
		@Instantiable public final class Leaf: Instantiable {
		    public init() {}
		}
		"""
		return rootFileIsReadFirst ? ["A_Root.swift": root, "B_Types.swift": types] : ["B_Root.swift": root, "A_Types.swift": types]
	}

	/// The texts the check of node records compared for `Root` of `twentyPropertiesFixtureFiles(labels:rootFileIsReadFirst:)`.
	private static func sharedFunctionTexts(labels: [String], filesToDelete: inout [URL]) async throws -> NodeRecordsComparedTexts {
		let (_, reports) = try await layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: twentyPropertiesFixtureFiles(labels: labels, rootFileIsReadFirst: true), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		return try #require(reports.first { $0.root == "Root" }?.comparedTexts)
	}

	private static func layingOutRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
				try await body(&filesMade)
			}
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream {
			reports.append(report)
		}
		return (output, reports)
	}

	/// The code the tool generates for `Root` of `fixture`, which its tree writes: node records lay a root out only where
	/// a test asks, and the check of node records fails the test where their code differs from the tree's.
	private mutating func treeText(of fixture: String) async throws -> String {
		let output = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: ["Fixture.swift": fixture], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		return try #require(output.generatedFiles?.values.first { $0.contains("extension Root {") })
	}

	private static let generatedFilePreamble = generatedFileHeader + """
	#if canImport(SafeDI)
	import SafeDI
	#endif


	"""

	/// `First` answers `Leaf`'s read of `theme` with a lazy wrapper, and `Third` with nothing.
	private static let wrapperAndNilFixture = """
	import SafeDI
	@Instantiable(isRoot: true) public final class Root: Instantiable {
	    public init(first: First, third: Third) { self.first = first; self.third = third }
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
	@Instantiable public final class Theme: Instantiable {
	    public init() {}
	}
	@Instantiable public final class Third: Instantiable {
	    public init(leafBuilder: Instantiator<Leaf>) { self.leafBuilder = leafBuilder }
	    @Instantiated let leafBuilder: Instantiator<Leaf>
	}
	"""

	/// `wrapperAndNilFixture`'s root as rule A lays it out: the wrapper's function takes the wrapper, and the call that
	/// passes `nil` has the function of the declared form.
	private static let wrapperAndNilUnderRuleA = """
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
	        func __safeDI_leafBuilder_(theme: Theme?) -> Leaf {
	            let twig = Twig(theme: theme)
	            return Leaf(theme: theme, twig: twig)
	        }
	        func __safeDI_third() -> Third {
	            let leafBuilder = Instantiator<Leaf> {
	                __safeDI_leafBuilder_(theme: nil)
	            }
	            return Third(leafBuilder: leafBuilder)
	        }
	        let third: Third = __safeDI_third()
	        self.init(first: first, third: third)
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
