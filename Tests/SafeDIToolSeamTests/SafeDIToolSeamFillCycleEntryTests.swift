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

/// A cycle that runs through a fill is reported by the walk of the filling module's own trees, which builds every seam the
/// module calls inline with the module's fills: no walk starts from a called seam's own root. Each graph here puts a
/// property above the seam, or beside it, that the fill builds or receives again, so that the walk from the module's
/// roots enters the cycle elsewhere than a walk from the seam's root would, and pins the error, or that there is none.
struct SafeDIToolSeamFillCycleEntryTests: ~Copyable {
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

	@Test(arguments: SafeDIToolSeamFillCycleEntryTests.rejectedGraphs)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsTheCycleItsOwnTreesReach_whenCycleRunsThroughFillOfCalledSeam(graph: Graph) async {
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			graph.diagnostics.map { "\(fixtures[$0.moduleName]!["\($0.moduleName).swift"])\($0.text)" }.joined(separator: "\n")
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: graph.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test(arguments: SafeDIToolSeamFillCycleEntryTests.acceptedGraphs)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsFill_whenNoCycleItsOwnTreesReachRunsThroughFillOfCalledSeam(graph: Graph) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: graph.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles.isEmpty == false)
	}

	// MARK: Graphs

	/// A graph of two modules, each one file: `Feature` declares a seam whose tree holds a hole, and `App` fills it.
	struct Graph: Sendable, CustomTestStringConvertible {
		/// What sets the graph apart.
		let testDescription: String
		let feature: String
		let app: String
		/// The diagnostics `App`'s run reports, each after the path of its module's one file; empty for a graph it accepts.
		let diagnostics: [(moduleName: String, text: String)]

		var modules: [ModuleFixture] {
			[
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: ["Feature.swift": feature]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContentByFilePath: ["App.swift": app], dependencies: ["Feature"]),
			]
		}
	}

	/// A seam whose tree instantiates `p: any P`, which only `App` sees fulfilled.
	private static let holeFeature = """
	import SafeDI
	public protocol P {}
	@Instantiable(generateDependencyTree: true)
	public final class S: Instantiable {
	    public init(p: any P) { self.p = p }
	    @Instantiated let p: any P
	}
	"""

	/// A seam whose tree builds `Row` with an instantiator, where `Row` instantiates the seam again and `widget: any Widget`, which only `App` sees fulfilled.
	private static let rowFeature = """
	import SafeDI
	public protocol Widget {}
	@Instantiable
	public final class Row: Instantiable {
	    public init(inner: Inner, widget: any Widget) { self.inner = inner; self.widget = widget }
	    @Instantiated let inner: Inner
	    @Instantiated let widget: any Widget
	}
	@Instantiable(generateDependencyTree: true)
	public final class Inner: Instantiable {
	    public init(rowMaker: Instantiator<Row>) { self.rowMaker = rowMaker }
	    @Instantiated let rowMaker: Instantiator<Row>
	}
	"""

	/// A seam that instantiates `aBuilder` and `router: any Router`, which only `App` sees fulfilled, where the type `aBuilder` builds receives `router`.
	private static let routerFeature = """
	import SafeDI
	public protocol Router {}
	@Instantiable
	public final class AScreen: Instantiable {
	    public init(router: any Router) { self.router = router }
	    @Received let router: any Router
	}
	@Instantiable(generateDependencyTree: true)
	public final class SignedIn: Instantiable {
	    public init(aBuilder: Instantiator<AScreen>, router: any Router) { self.aBuilder = aBuilder; self.router = router }
	    @Instantiated let aBuilder: Instantiator<AScreen>
	    @Instantiated let router: any Router
	}
	"""

	static let rejectedGraphs = [
		Graph(
			testDescription: "the root builds X as a constant, and the fill builds X again",
			feature: holeFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(x: X) { self.x = x }
			    @Instantiated let x: X
			}
			@Instantiable
			public final class X: Instantiable {
			    public init(s: S) { self.s = s }
			    @Instantiated let s: S
			}
			@Instantiable(fulfillingAdditionalTypes: [(any P).self])
			public final class PImpl: Instantiable, P {
			    public init(x: X) { self.x = x }
			    @Instantiated let x: X
			}
			""",
			diagnostics: [
				("App", ":16:5: error: Dependency cycle: `X` -> `S` -> `any P` -> `X`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `x: X`, `s: S`, `p: any P` to an instantiator."),
				("App", ":8:1: note: `X` is part of the cycle"),
				("Feature", ":3:1: note: `S` is part of the cycle"),
				("App", ":13:1: note: `P` is part of the cycle"),
			],
		),
		Graph(
			testDescription: "the root builds X lazily, and the fill builds X again",
			feature: holeFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(x: LazilyInstantiated<X>) { self.x = x }
			    @Instantiated let x: LazilyInstantiated<X>
			}
			@Instantiable
			public final class X: Instantiable {
			    public init(s: S) { self.s = s }
			    @Instantiated let s: S
			}
			@Instantiable(fulfillingAdditionalTypes: [(any P).self])
			public final class PImpl: Instantiable, P {
			    public init(x: X) { self.x = x }
			    @Instantiated let x: X
			}
			""",
			diagnostics: [
				("App", ":16:5: error: Dependency cycle: `X` -> `S` -> `any P` -> `X`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `x: X`, `s: S`, `p: any P` to an instantiator. A lazily instantiated dependency is created once, so it cannot break a dependency cycle: `x: LazilyInstantiated<X>` is validated as `x: X`."),
				("App", ":8:1: note: `X` is part of the cycle"),
				("Feature", ":3:1: note: `S` is part of the cycle"),
				("App", ":13:1: note: `P` is part of the cycle"),
			],
		),
		Graph(
			testDescription: "the root builds X with an instantiator, and the fill builds X again",
			feature: holeFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(xBuilder: Instantiator<X>) { self.xBuilder = xBuilder }
			    @Instantiated let xBuilder: Instantiator<X>
			}
			@Instantiable
			public final class X: Instantiable {
			    public init(s: S) { self.s = s }
			    @Instantiated let s: S
			}
			@Instantiable(fulfillingAdditionalTypes: [(any P).self])
			public final class PImpl: Instantiable, P {
			    public init(x: X) { self.x = x }
			    @Instantiated let x: X
			}
			""",
			diagnostics: [
				("App", ":11:5: error: Dependency cycle: `S` -> `any P` -> `X` -> `S`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `s: S`, `p: any P`, `x: X` to an instantiator."),
				("Feature", ":3:1: note: `S` is part of the cycle"),
				("App", ":13:1: note: `P` is part of the cycle"),
				("App", ":8:1: note: `X` is part of the cycle"),
			],
		),
		Graph(
			testDescription: "a type between the root and the seam builds X lazily and a sibling receives it, and the fill builds X again",
			feature: holeFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(m: M) { self.m = m }
			    @Instantiated let m: M
			}
			@Instantiable
			public final class M: Instantiable {
			    public init(x: LazilyInstantiated<X>, y: Y) { self.x = x; self.y = y }
			    @Instantiated let x: LazilyInstantiated<X>
			    @Instantiated let y: Y
			}
			@Instantiable
			public final class Y: Instantiable {
			    public init(x: X) { self.x = x }
			    @Received let x: X
			}
			@Instantiable
			public final class X: Instantiable {
			    public init(s: S) { self.s = s }
			    @Instantiated let s: S
			}
			@Instantiable(fulfillingAdditionalTypes: [(any P).self])
			public final class PImpl: Instantiable, P {
			    public init(x: X) { self.x = x }
			    @Instantiated let x: X
			}
			""",
			diagnostics: [
				("App", ":27:5: error: Dependency cycle: `X` -> `S` -> `any P` -> `X`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `x: X`, `s: S`, `p: any P` to an instantiator. A lazily instantiated dependency is created once, so it cannot break a dependency cycle: `x: LazilyInstantiated<X>` is validated as `x: X`."),
				("App", ":19:1: note: `X` is part of the cycle"),
				("Feature", ":3:1: note: `S` is part of the cycle"),
				("App", ":24:1: note: `P` is part of the cycle"),
			],
		),
		Graph(
			testDescription: "the root builds X lazily beside the seam, and the fill receives X",
			feature: holeFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(x: LazilyInstantiated<X>, s: S) { self.x = x; self.s = s }
			    @Instantiated let x: LazilyInstantiated<X>
			    @Instantiated let s: S
			}
			@Instantiable
			public final class X: Instantiable {
			    public init(s: S) { self.s = s }
			    @Instantiated let s: S
			}
			@Instantiable(fulfillingAdditionalTypes: [(any P).self])
			public final class PImpl: Instantiable, P {
			    public init(x: X) { self.x = x }
			    @Received let x: X
			}
			""",
			diagnostics: [
				("App", ":17:5: error: Dependency cycle: `X` -> `S` -> `any P` -> `X`. `PImpl` receives `x: X`, which is still being built when `PImpl` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required. A lazily instantiated dependency is created once, so it cannot break a dependency cycle: `x: LazilyInstantiated<X>` is validated as `x: X`."),
				("App", ":9:1: note: `X` is part of the cycle"),
				("Feature", ":3:1: note: `S` is part of the cycle"),
				("App", ":14:1: note: `P` is part of the cycle"),
			],
		),
		Graph(
			testDescription: "the root builds the hole's type lazily beside the seam, and the fill builds the seam",
			feature: holeFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(p: LazilyInstantiated<any P>, s: S) { self.p = p; self.s = s }
			    @Instantiated let p: LazilyInstantiated<any P>
			    @Instantiated let s: S
			}
			@Instantiable(fulfillingAdditionalTypes: [(any P).self])
			public final class PImpl: Instantiable, P {
			    public init(s: S) { self.s = s }
			    @Instantiated let s: S
			}
			""",
			diagnostics: [
				("Feature", ":6:5: error: Dependency cycle: `any P` -> `S` -> `any P`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `p: any P`, `s: S` to an instantiator. A lazily instantiated dependency is created once, so it cannot break a dependency cycle: `p: LazilyInstantiated<any P>` is validated as `p: any P`."),
				("App", ":9:1: note: `P` is part of the cycle"),
				("Feature", ":3:1: note: `S` is part of the cycle"),
			],
		),
		Graph(
			testDescription: "the root builds the seam lazily, and the fill builds the seam",
			feature: holeFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(s: LazilyInstantiated<S>) { self.s = s }
			    @Instantiated let s: LazilyInstantiated<S>
			}
			@Instantiable(fulfillingAdditionalTypes: [(any P).self])
			public final class PImpl: Instantiable, P {
			    public init(s: S) { self.s = s }
			    @Instantiated let s: S
			}
			""",
			diagnostics: [
				("App", ":11:5: error: Dependency cycle: `S` -> `any P` -> `S`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `s: S`, `p: any P` to an instantiator. A lazily instantiated dependency is created once, so it cannot break a dependency cycle: `s: LazilyInstantiated<S>` is validated as `s: S`."),
				("Feature", ":3:1: note: `S` is part of the cycle"),
				("App", ":8:1: note: `P` is part of the cycle"),
			],
		),
		Graph(
			testDescription: "the root builds the seam with an instantiator, and the fill builds the seam",
			feature: holeFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(sBuilder: Instantiator<S>) { self.sBuilder = sBuilder }
			    @Instantiated let sBuilder: Instantiator<S>
			}
			@Instantiable(fulfillingAdditionalTypes: [(any P).self])
			public final class PImpl: Instantiable, P {
			    public init(s: S) { self.s = s }
			    @Instantiated let s: S
			}
			""",
			diagnostics: [
				("Feature", ":6:5: error: Dependency cycle: `any P` -> `S` -> `any P`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `p: any P`, `s: S` to an instantiator."),
				("App", ":8:1: note: `P` is part of the cycle"),
				("Feature", ":3:1: note: `S` is part of the cycle"),
			],
		),
		Graph(
			testDescription: "the root builds X as a constant, and the fill receives X",
			feature: holeFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(x: X) { self.x = x }
			    @Instantiated let x: X
			}
			@Instantiable
			public final class X: Instantiable {
			    public init(s: S) { self.s = s }
			    @Instantiated let s: S
			}
			@Instantiable(fulfillingAdditionalTypes: [(any P).self])
			public final class PImpl: Instantiable, P {
			    public init(x: X) { self.x = x }
			    @Received let x: X
			}
			""",
			diagnostics: [
				("App", ":16:5: error: Dependency cycle: `X` -> `S` -> `any P` -> `X`. `PImpl` receives `x: X`, which is still being built when `PImpl` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required."),
				("App", ":8:1: note: `X` is part of the cycle"),
				("Feature", ":3:1: note: `S` is part of the cycle"),
				("App", ":13:1: note: `P` is part of the cycle"),
			],
		),
		Graph(
			testDescription: "the root builds the seam's own instantiator above the seam, and the fill builds it again",
			feature: rowFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(rowMaker: Instantiator<Row>) { self.rowMaker = rowMaker }
			    @Instantiated let rowMaker: Instantiator<Row>
			}
			@Instantiable(fulfillingAdditionalTypes: [(any Widget).self])
			public final class DefaultWidget: Instantiable, Widget {
			    public init(rowMaker: Instantiator<Row>) { self.rowMaker = rowMaker }
			    @Instantiated let rowMaker: Instantiator<Row>
			}
			""",
			diagnostics: [
				("App", ":11:5: error: SafeDI cannot fill the builder for `Row`’s `widget: any Widget` (`widget` of `widgetBuilder`) in `Inner`’s dependency tree: `DefaultWidget`, which fills it, instantiates `rowMaker: Instantiator<Row>`, which `Inner`’s tree is building where it builds `widget` (Inner -> rowMaker -> Row -> widget -> DefaultWidget -> rowMaker). Code generated outside module `Feature` cannot refer to the function `Inner`’s initializer builds `Row` with, and building it again would hand it other values than `Inner`’s tree holds. Instantiate `Inner` where `DefaultWidget` builds `Row` (`@Instantiated let innerBuilder: Instantiator<Inner>`), so the cycle re-enters through the initializer SafeDI generates for `Inner`; declare an @Instantiable type that fulfills `Widget` in module `Feature` or a module it lists among its SafeDI dependencies; or give `rowMaker` on `DefaultWidget` another label, so the cycle closes at `widget` itself."),
				("Feature", ":12:5: note: `Inner` instantiates `rowMaker: Instantiator<Row>` here."),
			],
		),
		Graph(
			testDescription: "a seam of the filling module receives the instantiator the fill receives",
			feature: routerFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(generateDependencyTree: true)
			public final class Host: Instantiable {
			    public init(signedIn: SignedIn, aBuilder: Instantiator<AScreen>) { self.signedIn = signedIn; self.aBuilder = aBuilder }
			    @Instantiated let signedIn: SignedIn
			    @Received let aBuilder: Instantiator<AScreen>
			}
			@Instantiable(fulfillingAdditionalTypes: [(any Router).self])
			public final class LiveRouter: Instantiable, Router {
			    public init(aBuilder: Instantiator<AScreen>) { self.aBuilder = aBuilder }
			    @Received let aBuilder: Instantiator<AScreen>
			}
			""",
			diagnostics: [
				("App", ":12:5: error: Dependency cycle: @Instantiated `aBuilder: Instantiator<AScreen>` -> @Received `router: any Router` -> @Received `aBuilder: Instantiator<AScreen>`. `aBuilder: Instantiator<AScreen>` is received while it is still being instantiated. Remove this @Received property."),
			],
		),
		Graph(
			testDescription: "an instantiator above the seam forwards the instantiator the fill receives",
			feature: routerFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(hostBuilder: Instantiator<Host>) { self.hostBuilder = hostBuilder }
			    @Instantiated let hostBuilder: Instantiator<Host>
			}
			@Instantiable
			public final class Host: Instantiable {
			    public init(signedIn: SignedIn, aBuilder: Instantiator<AScreen>) { self.signedIn = signedIn; self.aBuilder = aBuilder }
			    @Instantiated let signedIn: SignedIn
			    @Forwarded let aBuilder: Instantiator<AScreen>
			}
			@Instantiable(fulfillingAdditionalTypes: [(any Router).self])
			public final class LiveRouter: Instantiable, Router {
			    public init(aBuilder: Instantiator<AScreen>) { self.aBuilder = aBuilder }
			    @Received let aBuilder: Instantiator<AScreen>
			}
			""",
			diagnostics: [
				("App", ":17:5: error: Dependency cycle: @Instantiated `aBuilder: Instantiator<AScreen>` -> @Received `router: any Router` -> @Received `aBuilder: Instantiator<AScreen>`. `aBuilder: Instantiator<AScreen>` is received while it is still being instantiated. Remove this @Received property."),
			],
		),
		Graph(
			testDescription: "only a type with a generated mock builds the seam",
			feature: routerFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(signedIn: SignedIn) { self.signedIn = signedIn }
			    @Instantiated let signedIn: SignedIn
			}
			@Instantiable(fulfillingAdditionalTypes: [(any Router).self])
			public final class LiveRouter: Instantiable, Router {
			    public init(aBuilder: Instantiator<AScreen>) { self.aBuilder = aBuilder }
			    @Received let aBuilder: Instantiator<AScreen>
			}
			""",
			diagnostics: [
				("App", ":11:5: error: Dependency cycle: @Instantiated `aBuilder: Instantiator<AScreen>` -> @Received `router: any Router` -> @Received `aBuilder: Instantiator<AScreen>`. `aBuilder: Instantiator<AScreen>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required."),
			],
		),
		Graph(
			testDescription: "a root with a generated mock builds the seam",
			feature: routerFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(isRoot: true, generateMock: true)
			public final class Screen: Instantiable {
			    public init(signedIn: SignedIn) { self.signedIn = signedIn }
			    @Instantiated let signedIn: SignedIn
			}
			@Instantiable(fulfillingAdditionalTypes: [(any Router).self])
			public final class LiveRouter: Instantiable, Router {
			    public init(aBuilder: Instantiator<AScreen>) { self.aBuilder = aBuilder }
			    @Received let aBuilder: Instantiator<AScreen>
			}
			""",
			diagnostics: [
				("App", ":11:5: error: Dependency cycle: @Instantiated `aBuilder: Instantiator<AScreen>` -> @Received `router: any Router` -> @Received `aBuilder: Instantiator<AScreen>`. `aBuilder: Instantiator<AScreen>` is received while it is still being instantiated. Remove this @Received property."),
			],
		),
	]

	static let acceptedGraphs = [
		Graph(
			testDescription: "the root builds X with an instantiator, and the fill receives that instantiator",
			feature: holeFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(xBuilder: Instantiator<X>) { self.xBuilder = xBuilder }
			    @Instantiated let xBuilder: Instantiator<X>
			}
			@Instantiable
			public final class X: Instantiable {
			    public init(s: S) { self.s = s }
			    @Instantiated let s: S
			}
			@Instantiable(fulfillingAdditionalTypes: [(any P).self])
			public final class PImpl: Instantiable, P {
			    public init(xBuilder: Instantiator<X>) { self.xBuilder = xBuilder }
			    @Received let xBuilder: Instantiator<X>
			}
			""",
			diagnostics: [],
		),
		Graph(
			testDescription: "no root or mock of the filling module builds the type that builds the seam",
			feature: routerFeature,
			app: """
			import Feature
			import SafeDI
			@Instantiable
			public final class Screen: Instantiable {
			    public init(signedIn: SignedIn) { self.signedIn = signedIn }
			    @Instantiated let signedIn: SignedIn
			}
			@Instantiable(fulfillingAdditionalTypes: [(any Router).self])
			public final class LiveRouter: Instantiable, Router {
			    public init(aBuilder: Instantiator<AScreen>) { self.aBuilder = aBuilder }
			    @Received let aBuilder: Instantiator<AScreen>
			}
			""",
			diagnostics: [],
		),
	]

	private var filesToDelete: [URL]
}
