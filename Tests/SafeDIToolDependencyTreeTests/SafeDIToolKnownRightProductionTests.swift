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

/// Compares the tree each production shape's generated `Root()` builds with a tree built by hand, by value.
///
/// The generated mocks and the inline builds that every other value comparison takes as its known-right side come from
/// the same generator as the code under test, so a misreading of a rule there agrees with itself. Here the known-right
/// side is a function written from the Manual's rules and the fixture alone, in a file the tool does not read, which
/// calls each initializer directly. Each shape is one graph of probe pairs, and the shapes are compared together, so
/// they compile and link once.
struct SafeDIToolKnownRightProductionTests {
	@Test(arguments: KnownRightProductionShape.all)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func init_buildsTheTreeTheManualDescribes_forEachProductionShape(_ shape: KnownRightProductionShape) async throws {
		guard compileVerificationIsEnabled else { return }
		let comparisons = try #require(try await knownRightProductionComparisons.value)
		let comparison = try #require(comparisons.first { $0.shape == shape.name })
		#expect(comparison.error == nil, "\(comparison.error ?? "")")
		#expect(comparison.comparedPairCount == shape.probePairs.count)
		for difference in comparison.differences {
			Issue.record("The generated tree differs from the tree built by hand at \(difference)\n\(comparison.report)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func init_comparesEveryShapesValues_whenCompileVerificationIsEnabled() async throws {
		guard compileVerificationIsEnabled else { return }
		let comparisons = try #require(try await knownRightProductionComparisons.value)
		#expect(comparisons.map(\.shape) == KnownRightProductionShape.all.map(\.name))
		#expect(comparisons.allSatisfy { $0.error == nil && $0.describedValueCount > 0 })
		print("Known-right production shapes: \(comparisons.count) shapes, \(comparisons.reduce(0) { $0 + $1.comparedPairCount }) probe pairs, \(comparisons.reduce(0) { $0 + $1.describedValueCount }) values compared")
	}
}

/// What comparing one shape found.
struct KnownRightProductionComparison: Sendable {
	let shape: String
	let comparedPairCount: Int
	/// The lines of the feature path's description: one per value the comparator compared.
	let describedValueCount: Int
	let differences: [String]
	let report: String
	let error: String?
}

/// Generates each shape, then compares all of them in one batch: one compile and one link.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) private let knownRightProductionComparisons = SharedTestWork { () async throws -> [KnownRightProductionComparison]? in
	var filesToDelete = [URL]()
	defer {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}
	var graphs = [DifferentialValueGraph]()
	// A shape the tool rejects is reported as its own failure, so the other shapes are still compared.
	var generationErrors = [String: String]()
	for shape in KnownRightProductionShape.all {
		let generatedFiles: [String: String]
		do {
			let output = try await executeSafeDIToolTest(
				swiftFileContent: shape.fixture,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				// The comparison below compiles the generated code with the fixture.
				skipCompileVerification: true,
			)
			generatedFiles = output.generatedFiles ?? [:]
		} catch {
			generationErrors[shape.name] = "\(error)"
			continue
		}
		var fixtureFiles = [String: String]()
		for (index, file) in shape.fixture.enumerated() {
			fixtureFiles["\(shape.name)Fixture\(index).swift"] = file
		}
		// The tree built by hand, in a file the tool did not read.
		fixtureFiles["\(shape.name)HandBuilt.swift"] = shape.handBuiltTree
		graphs.append(DifferentialValueGraph(
			name: shape.name,
			path: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: generatedFiles),
			probePairs: shape.probePairs.map { DifferentialValueProbePair(name: $0.feature, featureExpression: $0.feature, knownRightExpression: $0.knownRight) },
		))
	}
	guard let comparisons = try await DifferentialValueOracle.compare(graphs: graphs, filesToDelete: &filesToDelete) else { return nil }
	var resultsByShape = [String: KnownRightProductionComparison]()
	for (graph, comparison) in zip(graphs, comparisons) {
		let pairCount = graph.probes.count
		switch comparison.result {
		case let .success(result):
			resultsByShape[graph.name] = KnownRightProductionComparison(
				shape: graph.name,
				comparedPairCount: pairCount,
				describedValueCount: result.featureDescription.split(separator: "\n").count,
				differences: result.differences.map(\.description),
				report: result.report,
				error: nil,
			)
		case let .failure(error):
			resultsByShape[graph.name] = KnownRightProductionComparison(shape: graph.name, comparedPairCount: 0, describedValueCount: 0, differences: [], report: "", error: "\(error)")
		}
	}
	return KnownRightProductionShape.all.map { shape in
		resultsByShape[shape.name] ?? KnownRightProductionComparison(shape: shape.name, comparedPairCount: 0, describedValueCount: 0, differences: [], report: "", error: generationErrors[shape.name])
	}
}

/// A production tree, the tree the Manual says its root builds, written by hand, and the expressions that build each.
struct KnownRightProductionShape: Sendable, CustomTestStringConvertible {
	/// The shape's name, which prefixes every type it declares, so the shapes compile together.
	let name: String
	/// The files the tool reads.
	let fixture: [String]
	/// A file the tool does not read, which declares the shape's stamp counter and builds the tree by hand.
	let handBuiltTree: String
	/// The generated build and the hand build of each value compared, by default `Root()` and `expectedRoot()`.
	let probePairs: [(feature: String, knownRight: String)]

	var testDescription: String {
		name
	}

	init(_ name: String, fixture: [String], handBuiltTree: String, probePairs: [(feature: String, knownRight: String)]? = nil) {
		self.name = name
		self.fixture = fixture
		self.handBuiltTree = """
		\(DifferentialValueCreationStamp.counterDeclaration(named: "\(name)Counter"))

		\(handBuiltTree)
		"""
		self.probePairs = probePairs ?? [("\(name)Root()", "expected\(name)Root()")]
	}

	/// A stamped `public final class` named `name` that stores each of `declarations`, with an initializer taking each,
	/// and `@Instantiable` (`attribute`) unless `attribute` is empty.
	static func stampedClass(
		_ name: String,
		of shape: String,
		attribute: String = "@Instantiable",
		declarations: [String] = [],
		conformances: String = "",
	) -> String {
		let properties = declarations.map { declaration -> (label: String, type: String) in
			let property = declaration[declaration.range(of: "let ")!.upperBound...]
			return (String(property.prefix { $0 != ":" }), property.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces))
		}
		let parameters = properties.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
		let assignments = properties.map { "        self.\($0.label) = \($0.label)\n" }.joined()
		let instantiable = attribute.isEmpty ? "" : "Instantiable"
		let inheritance = [instantiable, conformances].filter { !$0.isEmpty }.joined(separator: ", ")
		return """
		\(attribute.isEmpty ? "" : "\(attribute)\n")public final class \(name)\(inheritance.isEmpty ? "" : ": \(inheritance)") {
		    public init(\(parameters)) {
		\(assignments)    }

		\(declarations.map { "    \($0)\n" }.joined())    \(DifferentialValueCreationStamp.property(counterNamed: "\(shape)Counter"))
		}
		"""
	}

	static let all: [KnownRightProductionShape] = [
		// A1: a grandchild beneath `branch` receives the root's `service`: the same instance.
		KnownRightProductionShape(
			"A1",
			fixture: [
				stampedClass("A1Root", of: "A1", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let service: A1Service", "@Instantiated let branch: A1Branch"]),
				stampedClass("A1Branch", of: "A1", declarations: ["@Instantiated let leaf: A1Leaf"]),
				stampedClass("A1Leaf", of: "A1", declarations: ["@Received let service: A1Service"]),
				stampedClass("A1Service", of: "A1"),
			],
			handBuiltTree: """
			func expectedA1Root() -> A1Root {
			    let service = A1Service()
			    return A1Root(service: service, branch: A1Branch(leaf: A1Leaf(service: service)))
			}
			""",
		),
		// A2: `x` is declared by the root and again by `inner`. A receiver takes the nearest declaration above it: beneath
		// `inner` it is `inner`'s, beside `inner` the root's.
		KnownRightProductionShape(
			"A2",
			fixture: [
				stampedClass("A2Root", of: "A2", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let x: A2X", "@Instantiated let inner: A2Inner", "@Instantiated let beside: A2Beside"]),
				stampedClass("A2Inner", of: "A2", declarations: ["@Instantiated let x: A2X", "@Instantiated let below: A2Below"]),
				stampedClass("A2Below", of: "A2", declarations: ["@Received let x: A2X"]),
				stampedClass("A2Beside", of: "A2", declarations: ["@Received let x: A2X"]),
				stampedClass("A2X", of: "A2"),
			],
			handBuiltTree: """
			func expectedA2Root() -> A2Root {
			    let x = A2X()
			    let innerX = A2X()
			    return A2Root(x: x, inner: A2Inner(x: innerX, below: A2Below(x: innerX)), beside: A2Beside(x: x))
			}
			""",
		),
		// A3: two sibling branches each instantiate `x`, with a receiver of `x` beneath each: each its own branch's.
		KnownRightProductionShape(
			"A3",
			fixture: [
				stampedClass("A3Root", of: "A3", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let left: A3Left", "@Instantiated let right: A3Right"]),
				stampedClass("A3Left", of: "A3", declarations: ["@Instantiated let x: A3X", "@Instantiated let leaf: A3Leaf"]),
				stampedClass("A3Right", of: "A3", declarations: ["@Instantiated let x: A3X", "@Instantiated let leaf: A3Leaf"]),
				stampedClass("A3Leaf", of: "A3", declarations: ["@Received let x: A3X"]),
				stampedClass("A3X", of: "A3"),
			],
			handBuiltTree: """
			func expectedA3Root() -> A3Root {
			    let leftX = A3X()
			    let rightX = A3X()
			    return A3Root(left: A3Left(x: leftX, leaf: A3Leaf(x: leftX)), right: A3Right(x: rightX, leaf: A3Leaf(x: rightX)))
			}
			""",
		),
		// A4: `A4Item` is built under two parents at different depths, each receiving its own parent's `x`.
		KnownRightProductionShape(
			"A4",
			fixture: [
				stampedClass("A4Root", of: "A4", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let first: A4First", "@Instantiated let second: A4Second"]),
				stampedClass("A4First", of: "A4", declarations: ["@Instantiated let x: A4X", "@Instantiated let item: A4Item"]),
				stampedClass("A4Second", of: "A4", declarations: ["@Instantiated let x: A4X", "@Instantiated let middle: A4Middle"]),
				stampedClass("A4Middle", of: "A4", declarations: ["@Instantiated let item: A4Item"]),
				stampedClass("A4Item", of: "A4", declarations: ["@Received let x: A4X"]),
				stampedClass("A4X", of: "A4"),
			],
			handBuiltTree: """
			func expectedA4Root() -> A4Root {
			    let firstX = A4X()
			    let secondX = A4X()
			    return A4Root(
			        first: A4First(x: firstX, item: A4Item(x: firstX)),
			        second: A4Second(x: secondX, middle: A4Middle(item: A4Item(x: secondX))),
			    )
			}
			""",
		),
		// A5: an `Instantiator` of a child that forwards `id`, received by its grandchild: each call's own id.
		KnownRightProductionShape(
			"A5",
			fixture: [
				stampedClass("A5Root", of: "A5", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let childBuilder: Instantiator<A5Child>"]),
				stampedClass("A5Child", of: "A5", declarations: ["@Forwarded let id: Int", "@Instantiated let grandchild: A5Grandchild"]),
				stampedClass("A5Grandchild", of: "A5", declarations: ["@Received let id: Int"]),
			],
			handBuiltTree: """
			func expectedA5Root() -> A5Root {
			    A5Root(childBuilder: Instantiator<A5Child> { id in
			        A5Child(id: id, grandchild: A5Grandchild(id: id))
			    })
			}
			""",
			probePairs: [(
				"{ let root = A5Root(); return (root, root.childBuilder.instantiate(1), root.childBuilder.instantiate(2)) }()",
				"{ let root = expectedA5Root(); return (root, root.childBuilder.instantiate(1), root.childBuilder.instantiate(2)) }()",
			)],
		),
		// A6: a child behind an `Instantiator` receives the root's `shared` and instantiates `own`: every call shares one
		// `shared` and builds its own `own`.
		KnownRightProductionShape(
			"A6",
			fixture: [
				stampedClass("A6Root", of: "A6", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let shared: A6Shared", "@Instantiated let childBuilder: Instantiator<A6Child>"]),
				stampedClass("A6Child", of: "A6", declarations: ["@Received let shared: A6Shared", "@Instantiated let own: A6Own"]),
				stampedClass("A6Shared", of: "A6"),
				stampedClass("A6Own", of: "A6"),
			],
			handBuiltTree: """
			func expectedA6Root() -> A6Root {
			    let shared = A6Shared()
			    return A6Root(shared: shared, childBuilder: Instantiator<A6Child> { A6Child(shared: shared, own: A6Own()) })
			}
			""",
		),
		// A7: `A7A`, behind an `Instantiator`, forwards `value` and holds an `Instantiator<A7B>`; each `A7B` reads the value
		// of the `A7A` that built it.
		KnownRightProductionShape(
			"A7",
			fixture: [
				stampedClass("A7Root", of: "A7", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let aBuilder: Instantiator<A7A>"]),
				stampedClass("A7A", of: "A7", declarations: ["@Forwarded let value: Int", "@Instantiated let bBuilder: Instantiator<A7B>"]),
				stampedClass("A7B", of: "A7", declarations: ["@Received let value: Int"]),
			],
			handBuiltTree: """
			func expectedA7Root() -> A7Root {
			    A7Root(aBuilder: Instantiator<A7A> { value in
			        A7A(value: value, bBuilder: Instantiator<A7B> { A7B(value: value) })
			    })
			}
			""",
			probePairs: [(
				"{ let root = A7Root(); return (root, root.aBuilder.instantiate(1), root.aBuilder.instantiate(2)) }()",
				"{ let root = expectedA7Root(); return (root, root.aBuilder.instantiate(1), root.aBuilder.instantiate(2)) }()",
			)],
		),
		// A8: a receive only if available that nothing above declares: `nil`.
		KnownRightProductionShape(
			"A8",
			fixture: [
				stampedClass("A8Root", of: "A8", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let child: A8Child"]),
				stampedClass("A8Child", of: "A8", declarations: ["@Received(onlyIfAvailable: true) let x: A8X?"]),
				stampedClass("A8X", of: "A8"),
			],
			handBuiltTree: """
			func expectedA8Root() -> A8Root {
			    A8Root(child: A8Child(x: nil))
			}
			""",
		),
		// A9: a receive only if available of the root's `x`: the root's instance.
		KnownRightProductionShape(
			"A9",
			fixture: [
				stampedClass("A9Root", of: "A9", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let x: A9X", "@Instantiated let child: A9Child"]),
				stampedClass("A9Child", of: "A9", declarations: ["@Received(onlyIfAvailable: true) let x: A9X?"]),
				stampedClass("A9X", of: "A9"),
			],
			handBuiltTree: """
			func expectedA9Root() -> A9Root {
			    let x = A9X()
			    return A9Root(x: x, child: A9Child(x: x))
			}
			""",
		),
		// A10a: the receive only if available is of the root's own `x`, declared after the child. The root's properties
		// are above its children whatever their order, and SafeDI builds `x` first, so the child gets the root's `x`.
		KnownRightProductionShape(
			"A10a",
			fixture: [
				stampedClass("A10aRoot", of: "A10a", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let child: A10aChild", "@Instantiated let x: A10aX"]),
				stampedClass("A10aChild", of: "A10a", declarations: ["@Received(onlyIfAvailable: true) let x: A10aX?"]),
				stampedClass("A10aX", of: "A10a"),
			],
			handBuiltTree: """
			func expectedA10aRoot() -> A10aRoot {
			    let x = A10aX()
			    return A10aRoot(child: A10aChild(x: x), x: x)
			}
			""",
		),
		// A10b: the only `x` is one a sibling declared later instantiates inside itself, which is not above the child:
		// `nil`.
		KnownRightProductionShape(
			"A10b",
			fixture: [
				stampedClass("A10bRoot", of: "A10b", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let child: A10bChild", "@Instantiated let sibling: A10bSibling"]),
				stampedClass("A10bChild", of: "A10b", declarations: ["@Received(onlyIfAvailable: true) let x: A10bX?"]),
				stampedClass("A10bSibling", of: "A10b", declarations: ["@Instantiated let x: A10bX"]),
				stampedClass("A10bX", of: "A10b"),
			],
			handBuiltTree: """
			func expectedA10bRoot() -> A10bRoot {
			    A10bRoot(child: A10bChild(x: nil), sibling: A10bSibling(x: A10bX()))
			}
			""",
		),
		// A11: `A11Item` is built twice, beneath `holder`, which declares `x`, and at the root, which does not: the
		// instance at one, `nil` at the other.
		KnownRightProductionShape(
			"A11",
			fixture: [
				stampedClass("A11Root", of: "A11", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let holder: A11Holder", "@Instantiated let item: A11Item"]),
				stampedClass("A11Holder", of: "A11", declarations: ["@Instantiated let x: A11X", "@Instantiated let item: A11Item"]),
				stampedClass("A11Item", of: "A11", declarations: ["@Received(onlyIfAvailable: true) let x: A11X?"]),
				stampedClass("A11X", of: "A11"),
			],
			handBuiltTree: """
			func expectedA11Root() -> A11Root {
			    let x = A11X()
			    return A11Root(holder: A11Holder(x: x, item: A11Item(x: x)), item: A11Item(x: nil))
			}
			""",
		),
		// A12: `child` renames the root's `x` to `y`, which a grandchild receives: both the root's instance.
		KnownRightProductionShape(
			"A12",
			fixture: [
				stampedClass("A12Root", of: "A12", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let x: A12X", "@Instantiated let child: A12Child"]),
				stampedClass("A12Child", of: "A12", declarations: [#"@Received(fulfilledByDependencyNamed: "x", ofType: A12X.self) let y: A12X"#, "@Instantiated let grandchild: A12Grandchild"]),
				stampedClass("A12Grandchild", of: "A12", declarations: ["@Received let y: A12X"]),
				stampedClass("A12X", of: "A12"),
			],
			handBuiltTree: """
			func expectedA12Root() -> A12Root {
			    let x = A12X()
			    return A12Root(x: x, child: A12Child(y: x, grandchild: A12Grandchild(y: x)))
			}
			""",
		),
		// A13: a rename only if available of the root's non-optional `x`: the root's instance.
		KnownRightProductionShape(
			"A13",
			fixture: [
				stampedClass("A13Root", of: "A13", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let x: A13X", "@Instantiated let child: A13Child"]),
				stampedClass("A13Child", of: "A13", declarations: [#"@Received(fulfilledByDependencyNamed: "x", ofType: A13X.self, onlyIfAvailable: true) let y: A13X?"#]),
				stampedClass("A13X", of: "A13"),
			],
			handBuiltTree: """
			func expectedA13Root() -> A13Root {
			    let x = A13X()
			    return A13Root(x: x, child: A13Child(y: x))
			}
			""",
		),
		// A14: a rename only if available whose source nothing declares: `nil`.
		KnownRightProductionShape(
			"A14",
			fixture: [
				stampedClass("A14Root", of: "A14", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let child: A14Child"]),
				stampedClass("A14Child", of: "A14", declarations: [#"@Received(fulfilledByDependencyNamed: "x", ofType: A14X.self, onlyIfAvailable: true) let y: A14X?"#]),
				stampedClass("A14X", of: "A14"),
			],
			handBuiltTree: """
			func expectedA14Root() -> A14Root {
			    A14Root(child: A14Child(y: nil))
			}
			""",
		),
		// A15: the root instantiates `x` lazily, and two children built later receive `x` by value: both the wrapper's one
		// instance.
		KnownRightProductionShape(
			"A15",
			fixture: [
				stampedClass("A15Root", of: "A15", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let x: LazilyInstantiated<A15X>", "@Instantiated let firstBuilder: Instantiator<A15First>", "@Instantiated let secondBuilder: Instantiator<A15Second>"]),
				stampedClass("A15First", of: "A15", declarations: ["@Received let x: A15X"]),
				stampedClass("A15Second", of: "A15", declarations: ["@Received let x: A15X"]),
				stampedClass("A15X", of: "A15"),
			],
			handBuiltTree: """
			func expectedA15Root() -> A15Root {
			    let x = LazilyInstantiated<A15X> { A15X() }
			    return A15Root(
			        x: x,
			        firstBuilder: Instantiator<A15First> { A15First(x: x.instance) },
			        secondBuilder: Instantiator<A15Second> { A15Second(x: x.instance) },
			    )
			}
			""",
		),
		// A16: one child receives the lazy wrapper, one built later receives its instance: one instance.
		KnownRightProductionShape(
			"A16",
			fixture: [
				stampedClass("A16Root", of: "A16", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let x: LazilyInstantiated<A16X>", "@Instantiated let holder: A16Holder", "@Instantiated let readerBuilder: Instantiator<A16Reader>"]),
				stampedClass("A16Holder", of: "A16", declarations: ["@Received let x: LazilyInstantiated<A16X>"]),
				stampedClass("A16Reader", of: "A16", declarations: ["@Received let x: A16X"]),
				stampedClass("A16X", of: "A16"),
			],
			handBuiltTree: """
			func expectedA16Root() -> A16Root {
			    let x = LazilyInstantiated<A16X> { A16X() }
			    return A16Root(x: x, holder: A16Holder(x: x), readerBuilder: Instantiator<A16Reader> { A16Reader(x: x.instance) })
			}
			""",
		),
		// A17: a lazy wrapper nobody reads by value while the tree is built: its instance is not built when `Root()` returns.
		KnownRightProductionShape(
			"A17",
			fixture: [
				stampedClass("A17Root", of: "A17", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let x: LazilyInstantiated<A17X>", "@Instantiated let holder: A17Holder"]),
				stampedClass("A17Holder", of: "A17", declarations: ["@Received let x: LazilyInstantiated<A17X>"]),
				stampedClass("A17X", of: "A17"),
			],
			handBuiltTree: """
			func expectedA17Root() -> A17Root {
			    let x = LazilyInstantiated<A17X> { A17X() }
			    return A17Root(x: x, holder: A17Holder(x: x))
			}
			""",
		),
		// A18: a `SendableLazilyInstantiated` received as the wrapper by two children: one instance across both.
		KnownRightProductionShape(
			"A18",
			fixture: [
				stampedClass("A18Root", of: "A18", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let x: SendableLazilyInstantiated<A18X>", "@Instantiated let first: A18First", "@Instantiated let second: A18Second"]),
				stampedClass("A18First", of: "A18", declarations: ["@Received let x: SendableLazilyInstantiated<A18X>"]),
				stampedClass("A18Second", of: "A18", declarations: ["@Received let x: SendableLazilyInstantiated<A18X>"]),
				stampedClass("A18X", of: "A18", conformances: "Sendable"),
			],
			handBuiltTree: """
			func expectedA18Root() -> A18Root {
			    let x = SendableLazilyInstantiated<A18X> { A18X() }
			    return A18Root(x: x, first: A18First(x: x), second: A18Second(x: x))
			}
			""",
		),
		// A19: a cycle closed by instantiators, `A19A` building `A19B` and `A19B` building `A19A`, each receiving the root's
		// `shared`: each lap builds a new `A19A` and `A19B`, and all share one `shared`.
		KnownRightProductionShape(
			"A19",
			fixture: [
				stampedClass("A19Root", of: "A19", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let shared: A19Shared", "@Instantiated let entryBuilder: Instantiator<A19A>"]),
				stampedClass("A19A", of: "A19", declarations: ["@Received let shared: A19Shared", "@Instantiated let bBuilder: Instantiator<A19B>"]),
				stampedClass("A19B", of: "A19", declarations: ["@Received let shared: A19Shared", "@Instantiated let aBuilder: Instantiator<A19A>"]),
				stampedClass("A19Shared", of: "A19"),
			],
			handBuiltTree: """
			func expectedA19Root() -> A19Root {
			    let shared = A19Shared()
			    func a() -> A19A {
			        A19A(shared: shared, bBuilder: Instantiator<A19B> { b() })
			    }
			    func b() -> A19B {
			        A19B(shared: shared, aBuilder: Instantiator<A19A> { a() })
			    }
			    return A19Root(shared: shared, entryBuilder: Instantiator<A19A> { a() })
			}
			""",
		),
		// A20, swapped for its nearest valid neighbor: a received property that is not an instantiator cannot close a cycle,
		// a `LazilyInstantiated` one included, so the cycle is closed by the type that holds the lazy wrapper:
		// `A20A` builds `A20B` through an instantiator, and `A20B` instantiates `A20A` again lazily. Each `A20B`'s wrapper
		// yields a new `A20A`, built when its instance is first read, and every lap shares the root's `shared`. The second
		// probe's value is an `A20B`, so a wrapper whose instance is read before that `A20B` is built is marked as built
		// before the probe's value; under `A20Root()` alone, that read happens inside an instantiator and passes.
		KnownRightProductionShape(
			"A20",
			fixture: [
				stampedClass("A20Root", of: "A20", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let shared: A20Shared", "@Instantiated let entry: A20A"]),
				stampedClass("A20A", of: "A20", declarations: ["@Instantiated let bBuilder: Instantiator<A20B>"]),
				stampedClass("A20B", of: "A20", declarations: ["@Received let shared: A20Shared", "@Instantiated let a: LazilyInstantiated<A20A>"]),
				stampedClass("A20Shared", of: "A20"),
			],
			handBuiltTree: """
			func expectedA20Root() -> A20Root {
			    let shared = A20Shared()
			    func a() -> A20A {
			        A20A(bBuilder: Instantiator<A20B> { b() })
			    }
			    func b() -> A20B {
			        A20B(shared: shared, a: LazilyInstantiated<A20A> { a() })
			    }
			    return A20Root(shared: shared, entry: a())
			}
			""",
			probePairs: [
				("A20Root()", "expectedA20Root()"),
				("A20Root().entry.bBuilder.instantiate()", "expectedA20Root().entry.bBuilder.instantiate()"),
			],
		),
		// A21: two instantiators at the root receive each other: walking a, b, a alternates the types, and each step holds
		// its own forwarded id.
		KnownRightProductionShape(
			"A21",
			fixture: [
				stampedClass("A21Root", of: "A21", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let aBuilder: Instantiator<A21A>", "@Instantiated let bBuilder: Instantiator<A21B>"]),
				stampedClass("A21A", of: "A21", declarations: ["@Forwarded let id: Int", "@Received let bBuilder: Instantiator<A21B>"]),
				stampedClass("A21B", of: "A21", declarations: ["@Forwarded let id: Int", "@Received let aBuilder: Instantiator<A21A>"]),
			],
			handBuiltTree: """
			func expectedA21Root() -> A21Root {
			    func a(_ id: Int) -> A21A {
			        A21A(id: id, bBuilder: Instantiator<A21B> { b($0) })
			    }
			    func b(_ id: Int) -> A21B {
			        A21B(id: id, aBuilder: Instantiator<A21A> { a($0) })
			    }
			    return A21Root(aBuilder: Instantiator<A21A> { a($0) }, bBuilder: Instantiator<A21B> { b($0) })
			}
			""",
			probePairs: [(
				"{ let root = A21Root(); let a1 = root.aBuilder.instantiate(1); let b2 = a1.bBuilder.instantiate(2); return (root, a1, b2, b2.aBuilder.instantiate(3)) }()",
				"{ let root = expectedA21Root(); let a1 = root.aBuilder.instantiate(1); let b2 = a1.bBuilder.instantiate(2); return (root, a1, b2, b2.aBuilder.instantiate(3)) }()",
			)],
		),
		// A22: the root erases its `A22Concrete` into `A22AnyService`, which a child receives: one erasure around one
		// `A22Concrete`.
		KnownRightProductionShape(
			"A22",
			fixture: [
				stampedClass("A22Root", of: "A22", attribute: "@Instantiable(isRoot: true)", declarations: [#"@Instantiated(fulfilledByType: "A22Concrete", erasedToConcreteExistential: true) let service: A22AnyService"#, "@Instantiated let child: A22Child"]),
				stampedClass("A22Child", of: "A22", declarations: ["@Received let service: A22AnyService"]),
				stampedClass("A22Concrete", of: "A22", conformances: "A22Service"),
				"""
				public protocol A22Service: AnyObject {}

				public final class A22AnyService: A22Service {
				    public init(_ service: some A22Service) {
				        self.service = service
				    }

				    let service: any A22Service
				    let differentialValueCreationStamp = A22Counter.next()
				}
				""",
			],
			handBuiltTree: """
			func expectedA22Root() -> A22Root {
			    let service = A22AnyService(A22Concrete())
			    return A22Root(service: service, child: A22Child(service: service))
			}
			""",
		),
		// A23: `fulfilledByType` names one of two conformers: the root holds the one it names.
		KnownRightProductionShape(
			"A23",
			fixture: [
				stampedClass("A23Root", of: "A23", attribute: "@Instantiable(isRoot: true)", declarations: [#"@Instantiated(fulfilledByType: "A23Second") let service: any A23Service"#]),
				stampedClass("A23First", of: "A23", attribute: "@Instantiable(fulfillingAdditionalTypes: [A23Service.self])", conformances: "A23Service"),
				stampedClass("A23Second", of: "A23", conformances: "A23Service"),
				"public protocol A23Service: AnyObject {}",
			],
			handBuiltTree: """
			func expectedA23Root() -> A23Root {
			    A23Root(service: A23Second())
			}
			""",
		),
		// A24: an extension's `instantiate(…)` receives the root's `session` and returns a type SafeDI does not declare,
		// which holds that `session`.
		KnownRightProductionShape(
			"A24",
			fixture: [
				stampedClass("A24Root", of: "A24", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let session: A24Session", "@Instantiated let client: A24Client"]),
				stampedClass("A24Session", of: "A24"),
				stampedClass("A24Client", of: "A24", attribute: "", declarations: ["let session: A24Session"]),
				"""
				@Instantiable
				extension A24Client: Instantiable {
				    public static func instantiate(session: A24Session) -> A24Client {
				        A24Client(session: session)
				    }
				}
				""",
			],
			handBuiltTree: """
			func expectedA24Root() -> A24Root {
			    let session = A24Session()
			    return A24Root(session: session, client: A24Client.instantiate(session: session))
			}
			""",
		),
		// A25: a default-valued parameter of a type built through an `Instantiator` is not a dependency: SafeDI leaves it
		// out of each call, so each construction evaluates the default.
		KnownRightProductionShape(
			"A25",
			fixture: [
				stampedClass("A25Root", of: "A25", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let shared: A25Shared", "@Instantiated let childBuilder: Instantiator<A25Child>"]),
				"""
				@Instantiable
				public final class A25Child: Instantiable {
				    public init(shared: A25Shared, marker: A25Marker = A25Marker()) {
				        self.shared = shared
				        self.marker = marker
				    }

				    @Received let shared: A25Shared
				    let marker: A25Marker
				    let differentialValueCreationStamp = A25Counter.next()
				}
				""",
				stampedClass("A25Shared", of: "A25"),
				stampedClass("A25Marker", of: "A25", attribute: ""),
			],
			handBuiltTree: """
			func expectedA25Root() -> A25Root {
			    let shared = A25Shared()
			    return A25Root(shared: shared, childBuilder: Instantiator<A25Child> { A25Child(shared: shared) })
			}
			""",
		),
		// A26: two lazy cycles that share a type: `A26W` builds `A26U`, which builds `A26W` again and also `A26P`, which
		// declares its own `l` and builds `A26U` again. Every `A26V` beneath that `A26P` receives the `A26P`'s `l`, the
		// nearest declaration above it, and every other `A26V` the root's.
		KnownRightProductionShape(
			"A26",
			fixture: [
				stampedClass("A26Root", of: "A26", attribute: "@Instantiable(isRoot: true)", declarations: ["@Instantiated let l: A26L", "@Instantiated let wBuilder: Instantiator<A26W>"]),
				stampedClass("A26W", of: "A26", declarations: ["@Instantiated let uBuilder: Instantiator<A26U>", "@Instantiated let vBuilder: Instantiator<A26V>"]),
				stampedClass("A26U", of: "A26", declarations: ["@Instantiated let pBuilder: Instantiator<A26P>", "@Instantiated let wBuilder: Instantiator<A26W>"]),
				stampedClass("A26P", of: "A26", declarations: ["@Instantiated let l: A26L", "@Instantiated let uBuilder: Instantiator<A26U>"]),
				stampedClass("A26V", of: "A26", declarations: ["@Received let l: A26L"]),
				stampedClass("A26L", of: "A26"),
			],
			handBuiltTree: """
			func expectedA26Root() -> A26Root {
			    func w(l: A26L) -> A26W {
			        A26W(uBuilder: Instantiator<A26U> { u(l: l) }, vBuilder: Instantiator<A26V> { A26V(l: l) })
			    }
			    func u(l: A26L) -> A26U {
			        A26U(pBuilder: Instantiator<A26P> {
			            let pL = A26L()
			            return A26P(l: pL, uBuilder: Instantiator<A26U> { u(l: pL) })
			        }, wBuilder: Instantiator<A26W> { w(l: l) })
			    }
			    let l = A26L()
			    return A26Root(l: l, wBuilder: Instantiator<A26W> { w(l: l) })
			}
			""",
		),
	]
}
