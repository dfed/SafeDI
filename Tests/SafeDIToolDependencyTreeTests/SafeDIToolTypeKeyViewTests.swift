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

/// How many views the type key lays a production root's body out over (`GenerationWork.Step.layingOutTypeKeyViews`). A
/// view stands for every place of one plan node that agrees on what it reads outside the node, so the views of a tree
/// that reaches each type along many paths grow with its types and the forms of what they read, not with its paths. Each
/// count is the one the type key's views have on the shape; each comment names the places they stand for.
struct SafeDIToolTypeKeyViewTests: ~Copyable {
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
	mutating func generate_laysOutOneViewPerType_whenTreeReachesEachTypeOnManyPaths() async throws {
		// Four layers of three types, each instantiating the three of the layer beneath. The 81 places of the last layer build
		// constants in place, so 3 + 9 + 27 = 39 places have a builder function; the places of each type read nothing, so
		// they agree, and each type is one view.
		let letters = ["A", "B", "C"]
		var fixture = [seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: letters.map { "@Instantiated let l1\($0.lowercased()): L1\($0)" })]
		for layer in 1...4 {
			for letter in letters {
				let declarations = layer < 4 ? letters.map { "@Instantiated let l\(layer + 1)\($0.lowercased()): L\(layer + 1)\($0)" } : []
				fixture.append(seamFixtureType(named: "L\(layer)\(letter)", isFinalClass: true, declarations: declarations))
			}
		}
		#expect(try await viewCounts(of: fixture) == [9])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutViewsThatGrowWithTheLayers_whenScreensOpenTheNextLayerInline() async throws {
		// N5's screens without seams, as 2.2.0 builds them: layers of four screens, each opening three of the next layer's
		// through an `Instantiator`, so the places of the last layer grow three times with each layer. Every screen's places
		// read the same `service` and their own `id`, so each screen and its model is one view whatever the paths: the views
		// grow by four with each two layers' eight screens and models apart from the last layer's, which build in place.
		var counts = [[Int]]()
		for layerCount in [4, 6] {
			try await counts.append(viewCounts(of: Self.screensOpeningTheNextLayer(layerCount: layerCount)))
		}
		#expect(counts == [[21], [29]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutViewsOfTheReportedGraph_whenTwelveScreensOpenEachOther() async throws {
		// The graph issue #646 reported, at twelve screens: each opens three others through an `Instantiator`, and each
		// declares, receives, receives if available, or ignores a `Context`. A screen's places are apart wherever the
		// `Context` they read, or the function their builders' closers call reads, is another declaration, so the 12 screens
		// are 232 views, of 12 classes in the type key's layout.
		let roles: [ContextRole] = [.receivesIfAvailable, .none, .declares, .none, .receivesIfAvailable, .receivesIfAvailable, .declares, .declares, .none, .receives, .receivesIfAvailable, .declares]
		let targets = [[2, 3, 10], [2, 8, 10], [4, 7, 11], [0, 7, 8], [0, 8, 10], [1, 3, 10], [0, 10, 11], [3, 6, 11], [3, 7, 9], [3, 5, 8], [3, 7, 11], [0, 6, 8]]
		let counts = try await viewCounts(of: Self.screensOpeningEachOther(roles: roles, targets: targets))
		#expect(counts == [232])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutViewsThatGrowWithTheScreens_whenScreensOpenEachOtherAtTwoSizes() async throws {
		// The reported graph's form at eight and twelve screens, each screen `i` opening screens `i + 1`, `i + 3` and `i + 7`
		// (modulo the count) and taking the `i`th of the four roles in turn. Here the views grow with the declarations of
		// `Context` each screen can be reached beneath, which grow with the screens' cycles: 133 at eight screens and 1,918 at
		// twelve.
		var counts = [[Int]]()
		for screenCount in [8, 12] {
			let roles = (0..<screenCount).map { ContextRole.allCases[$0 % ContextRole.allCases.count] }
			let targets = (0..<screenCount).map { screen in [1, 3, 7].map { (screen + $0) % screenCount }.sorted() }
			try await counts.append(viewCounts(of: Self.screensOpeningEachOther(roles: roles, targets: targets)))
		}
		#expect(counts == [[133], [1_918]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_findsRootFunctionsReadingLevelsThatDoNotGrowWithThePaths_whenScreensOpenTheNextLayerInline() async throws {
		// The layered screens above, whose last layer's places grow three times with each layer. No place holds a root
		// function, and each place records so as it is built, so the walk for root functions reads the root's own levels
		// and no place's tree: its levels are the same at four and six layers. A walk of every place's tree read 3^layers.
		var counts = [[Int]]()
		for layerCount in [4, 6] {
			try await counts.append(workCounts(of: Self.screensOpeningTheNextLayer(layerCount: layerCount), by: .findingRootFunctions))
		}
		#expect(counts == [[4], [4]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_checksEachReadAtEveryMemberOncePerClass_whenScreensOpenEachOtherAtTwoSizes() async throws {
		// The reported graph's form at eight and twelve screens, as above, whose views grow from 133 to 1,918 while their
		// classes stay one per screen: each read is asked once per class, reading each member once, so the work grows with
		// the views (766 and 11,047). Asking it for every member read a class's members once per member, growing with the
		// square of a class's members (15,076 and 2,180,277).
		var totals = [Int]()
		for screenCount in [8, 12] {
			let roles = (0..<screenCount).map { ContextRole.allCases[$0 % ContextRole.allCases.count] }
			let targets = (0..<screenCount).map { screen in [1, 3, 7].map { (screen + $0) % screenCount }.sorted() }
			try await totals.append(workCounts(of: Self.screensOpeningEachOther(roles: roles, targets: targets), by: .checkingReadsAtEveryMember).reduce(0, +))
		}
		#expect(totals == [766, 11_047])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutOneViewPerScreen_whenEachScreenReceivesTheRouterItsParentDeclares() async throws {
		// Layers of three screens, each declaring a router of its own, receiving its parent's and opening the three screens of
		// the next layer through an `Instantiator`. A screen's places read their parent's router, a statement of another place
		// at each of the three parents, so keyed by where that declaration is they were a view per path (3, 9, 27, ...);
		// keyed by what it is (a statement of type `Router` outside the screen), each screen is one view at every layer.
		var counts = [[Int]]()
		for layerCount in [4, 6] {
			try await counts.append(viewCounts(of: Self.screensReceivingTheirParentsRouter(layerCount: layerCount)))
		}
		#expect(counts == [[12], [18]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutOneViewPerScreen_whenEachScreenReceivesTheBuilderItsGrandparentDeclares() async throws {
		// Layers of three screens, each opening the three screens of the next layer through an `Instantiator`, and each below
		// the second layer receiving the `Instantiator` its grandparent declares, which builds its parent's type: a loop of
		// builders, whose members' functions wrap one another again. Each rebinding is a place closing a cycle on a sibling's
		// function, keyed by kind, so each screen is one view, three per layer, where a view per path made three times as
		// many views at each layer.
		var counts = [[Int]]()
		for layerCount in [4, 6] {
			try await counts.append(viewCounts(of: Self.screensReceivingTheirGrandparentsBuilder(layerCount: layerCount)))
		}
		#expect(counts == [[12], [18]])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutLoopOnce_whenLoopMembersTreeClosesCycleOnFunctionAboveLoop() async throws {
		// `Flow`'s `aBuilder` and `bBuilder` receive each other, a loop of builders beneath both `First` and `Second`, and
		// `Detail`, beneath `A`, builds `Flow` again through `flowBuilder`: a cycle closing on the function above the loop. The
		// member `B` closes on `A`, whose function closes on that outer function from beneath its own body, so `B`'s view keys
		// what it closes on by declaration rather than by kind. The loop is still laid out once for both parents.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
				seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let flowBuilder: Instantiator<Flow>"]),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let flowBuilder: Instantiator<Flow>"]),
				seamFixtureType(named: "Flow", isFinalClass: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
				seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Received let bBuilder: Instantiator<B>", "@Instantiated let detail: Detail"]),
				seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Received let aBuilder: Instantiator<A>"]),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Instantiated let flowBuilder: Instantiator<Flow>"]),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_flowBuilder() -> Flow {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            return Flow(aBuilder: aBuilder, bBuilder: bBuilder)
		        }
		        func __safeDI_aBuilder() -> A {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            let detail: Detail = __safeDI_detail()
		            return A(bBuilder: bBuilder, detail: detail)
		        }
		        func __safeDI_detail() -> Detail {
		            let flowBuilder = Instantiator<Flow>(__safeDI_flowBuilder)
		            return Detail(flowBuilder: flowBuilder)
		        }
		        func __safeDI_bBuilder() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            return B(aBuilder: aBuilder)
		        }
		        func __safeDI_first() -> First {
		            let flowBuilder = Instantiator<Flow>(__safeDI_flowBuilder)
		            return First(flowBuilder: flowBuilder)
		        }
		        let first: First = __safeDI_first()
		        func __safeDI_second() -> Second {
		            let flowBuilder = Instantiator<Flow>(__safeDI_flowBuilder)
		            return Second(flowBuilder: flowBuilder)
		        }
		        let second: Second = __safeDI_second()
		        self.init(first: first, second: second)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEachParentsRouter_whenParentsOfTwoTypesOpenOneScreen() async throws {
		// Two parents of different types each declare a `router` and open one `Detail` that receives it: `Detail`'s places
		// share one view and one function, which takes the router as a parameter, and each call passes its own parent's.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
				seamFixtureType(named: "Router", isFinalClass: true, declarations: ["@Forwarded let name: String"]),
				seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let router: Instantiator<Router>", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let router: Instantiator<Router>", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Received let router: Instantiator<Router>"]),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_router(name: String) -> Router {
		            Router(name: name)
		        }
		        func __safeDI_detailBuilder(router: Instantiator<Router>) -> Detail {
		            Detail(router: router)
		        }
		        func __safeDI_first() -> First {
		            let router = Instantiator<Router> {
		                __safeDI_router(name: $0)
		            }
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            return First(router: router, detailBuilder: detailBuilder)
		        }
		        let first: First = __safeDI_first()
		        func __safeDI_second() -> Second {
		            let router = Instantiator<Router> {
		                __safeDI_router(name: $0)
		            }
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            return Second(router: router, detailBuilder: detailBuilder)
		        }
		        let second: Second = __safeDI_second()
		        self.init(first: first, second: second)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutAViewPerSpelling_whenParentsSpellTheRoutersTypeApart() async throws {
		// The parents above, one spelling the router's type `any Routing` and the other `Routing`, which name one type: a
		// view's key holds each declaration's type as spelled, so `Detail`'s places are two views, and two functions, each
		// typed as its parent spells the router.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
				"public protocol Routing {}",
				seamFixtureType(named: "LiveRouter", isFinalClass: true, declarations: [], conformances: ", Routing"),
				seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated(fulfilledByType: \"LiveRouter\") let router: any Routing", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated(fulfilledByType: \"LiveRouter\") let router: Routing", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Received let router: any Routing"]),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_detailBuilder(router: any Routing) -> Detail {
		            Detail(router: router)
		        }
		        func __safeDI_first() -> First {
		            let router: any Routing = LiveRouter()
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            return First(router: router, detailBuilder: detailBuilder)
		        }
		        let first: First = __safeDI_first()
		        func __safeDI_detailBuilder_(router: Routing) -> Detail {
		            Detail(router: router)
		        }
		        func __safeDI_second() -> Second {
		            let router: Routing = LiveRouter()
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder_(router: router)
		            }
		            return Second(router: router, detailBuilder: detailBuilder)
		        }
		        let second: Second = __safeDI_second()
		        self.init(first: first, second: second)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutOneFunctionWhoseCloserHandsOnItsParameter_whenParentsOfTwoTypesOpenAScreenThatOpensItself() async throws {
		// Two parents of different types each declare a `router` and open one `Detail`, which receives it and opens itself:
		// `Detail`'s places share one view whose edges read two declarations, and its closer hands on the function's own
		// parameter, so one function serves both parents and the closer calls it with the router it was passed.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
				seamFixtureType(named: "Router", isFinalClass: true, declarations: []),
				seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let router: Router", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let router: Router", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Received let router: Router", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_detailBuilder(router: Router) -> Detail {
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            return Detail(router: router, detailBuilder: detailBuilder)
		        }
		        func __safeDI_first() -> First {
		            let router = Router()
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            return First(router: router, detailBuilder: detailBuilder)
		        }
		        let first: First = __safeDI_first()
		        func __safeDI_second() -> Second {
		            let router = Router()
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            return Second(router: router, detailBuilder: detailBuilder)
		        }
		        let second: Second = __safeDI_second()
		        self.init(first: first, second: second)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutOneFunctionPerScreen_whenSharedScreensCycleDeclaresTheRouterAgain() async throws {
		// The parents above open a `Detail` that opens a `Mid`, which declares a `router` of its own and opens `Detail` again:
		// the cycle closes on `Detail`'s function, whose `router` parameter `Mid`'s closer passes from `Mid`'s declaration.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
				seamFixtureType(named: "Router", isFinalClass: true, declarations: []),
				seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let router: Router", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let router: Router", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Received let router: Router", "@Instantiated let midBuilder: Instantiator<Mid>"]),
				seamFixtureType(named: "Mid", isFinalClass: true, declarations: ["@Instantiated let router: Router", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_detailBuilder(router: Router) -> Detail {
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return Detail(router: router, midBuilder: midBuilder)
		        }
		        func __safeDI_midBuilder() -> Mid {
		            let router = Router()
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            return Mid(router: router, detailBuilder: detailBuilder)
		        }
		        func __safeDI_first() -> First {
		            let router = Router()
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            return First(router: router, detailBuilder: detailBuilder)
		        }
		        let first: First = __safeDI_first()
		        func __safeDI_second() -> Second {
		            let router = Router()
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            return Second(router: router, detailBuilder: detailBuilder)
		        }
		        let second: Second = __safeDI_second()
		        self.init(first: first, second: second)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutOneFunctionPerScreen_whenEveryScreenBuildsALeafFromTheRouterItReads() async throws {
		// The graph above, where `First`, `Second`, `Detail` and `Mid` each build a `Leaf` that receives the `router` they
		// read: each `Leaf` reads the nearest declaration, and `Detail`'s function, shared by both parents, hands its own.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
				seamFixtureType(named: "Router", isFinalClass: true, declarations: []),
				seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let router: Router", "@Instantiated let detailBuilder: Instantiator<Detail>", "@Instantiated let leaf: Leaf"]),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let router: Router", "@Instantiated let detailBuilder: Instantiator<Detail>", "@Instantiated let leaf: Leaf"]),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Received let router: Router", "@Instantiated let midBuilder: Instantiator<Mid>", "@Instantiated let leaf: Leaf"]),
				seamFixtureType(named: "Mid", isFinalClass: true, declarations: ["@Instantiated let router: Router", "@Instantiated let detailBuilder: Instantiator<Detail>", "@Instantiated let leaf: Leaf"]),
				seamFixtureType(named: "Leaf", isFinalClass: true, declarations: ["@Received let router: Router"]),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_detailBuilder(router: Router) -> Detail {
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            let leaf = Leaf(router: router)
		            return Detail(router: router, midBuilder: midBuilder, leaf: leaf)
		        }
		        func __safeDI_midBuilder() -> Mid {
		            let router = Router()
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            let leaf = Leaf(router: router)
		            return Mid(router: router, detailBuilder: detailBuilder, leaf: leaf)
		        }
		        func __safeDI_first() -> First {
		            let router = Router()
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            let leaf = Leaf(router: router)
		            return First(router: router, detailBuilder: detailBuilder, leaf: leaf)
		        }
		        let first: First = __safeDI_first()
		        func __safeDI_second() -> Second {
		            let router = Router()
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            let leaf = Leaf(router: router)
		            return Second(router: router, detailBuilder: detailBuilder, leaf: leaf)
		        }
		        let second: Second = __safeDI_second()
		        self.init(first: first, second: second)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutViewsThatGrowWithTheRenames_whenEachTypeOfAChainKeepsTheLabelOfTheRenameAboveIt() async throws {
		// A chain of `n` types, each renaming the `authToken` the type above it renames, keeping its label and retyping it to
		// a protocol the one above refines. Each rename reads the one above it, so each type is one view whatever the chain's
		// length: the views grow by one with each rename.
		var counts = [[Int]]()
		for renameCount in [2, 4, 8] {
			try await counts.append(viewCounts(of: Self.typesRenamingTheRenameAboveThem(renameCount: renameCount)))
		}
		#expect(counts == [[2], [4], [8]])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `layerCount` layers of three screens beneath a root that opens the first layer: each screen instantiates a `Router`
	/// of its own, receives the router of the screen that opened it, and opens the three screens of the next layer through
	/// an `Instantiator`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutOneFunctionPerScreenOfACycle_whenTheCloserHandsOnTheParameterItsEnclosingScreenWasPassed() async throws {
		// Two parents each declare a `router` and open `Detail`, which opens `Mid`, which opens `Detail` again; both receive
		// the router. `Mid`'s closer hands on `Detail`'s parameter through `Mid`'s own, a climb through an enclosing screen:
		// one function per screen serves both parents.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
				seamFixtureType(named: "Router", isFinalClass: true, declarations: []),
				seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let router: Router", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let router: Router", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Received let router: Router", "@Instantiated let midBuilder: Instantiator<Mid>"]),
				seamFixtureType(named: "Mid", isFinalClass: true, declarations: ["@Received let router: Router", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_detailBuilder(router: Router) -> Detail {
		            let midBuilder = Instantiator<Mid> {
		                __safeDI_midBuilder(router: router)
		            }
		            return Detail(router: router, midBuilder: midBuilder)
		        }
		        func __safeDI_midBuilder(router: Router) -> Mid {
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            return Mid(router: router, detailBuilder: detailBuilder)
		        }
		        func __safeDI_first() -> First {
		            let router = Router()
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            return First(router: router, detailBuilder: detailBuilder)
		        }
		        let first: First = __safeDI_first()
		        func __safeDI_second() -> Second {
		            let router = Router()
		            let detailBuilder = Instantiator<Detail> {
		                __safeDI_detailBuilder(router: router)
		            }
		            return Second(router: router, detailBuilder: detailBuilder)
		        }
		        let second: Second = __safeDI_second()
		        self.init(first: first, second: second)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsThePathKeysBody_whenACloserLeavesNilALabelTheFunctionItCallsTakes() async throws {
		// As above, but `Mid` receives the router only if available, as another type, so it is passed `nil`: its closer
		// has no `router` to pass the `router` that `Detail`'s function takes, so the layout gives up, and the root keeps the
		// path key's body.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
				seamFixtureType(named: "Router", isFinalClass: true, declarations: []),
				seamFixtureType(named: "First", isFinalClass: true, declarations: ["@Instantiated let router: Router", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Second", isFinalClass: true, declarations: ["@Instantiated let router: Router", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: ["@Received let router: Router", "@Instantiated let midBuilder: Instantiator<Mid>"]),
				seamFixtureType(named: "Other", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Mid", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let router: Other?", "@Instantiated let detailBuilder: Instantiator<Detail>"]),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.dependencyTreeFiles["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_first() -> First {
		            let router = Router()
		            func __safeDI_detailBuilder() -> Detail {
		                func __safeDI_midBuilder() -> Mid {
		                    let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		                    return Mid(router: nil, detailBuilder: detailBuilder)
		                }
		                let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		                return Detail(router: router, midBuilder: midBuilder)
		            }
		            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		            return First(router: router, detailBuilder: detailBuilder)
		        }
		        let first: First = __safeDI_first()
		        func __safeDI_second() -> Second {
		            let router = Router()
		            func __safeDI_detailBuilder() -> Detail {
		                func __safeDI_midBuilder() -> Mid {
		                    let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		                    return Mid(router: nil, detailBuilder: detailBuilder)
		                }
		                let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		                return Detail(router: router, midBuilder: midBuilder)
		            }
		            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		            return Second(router: router, detailBuilder: detailBuilder)
		        }
		        let second: Second = __safeDI_second()
		        self.init(first: first, second: second)
		    }
		}
		""")
	}

	private static func screensReceivingTheirParentsRouter(layerCount: Int) -> [String] {
		var files = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: (0..<3).map { "@Instantiated let screen0x\($0)Builder: Instantiator<Screen0x\($0)>" }),
			seamFixtureType(named: "Router", isFinalClass: true, declarations: []),
		]
		for layer in 0..<layerCount {
			for position in 0..<3 {
				var declarations = ["@Instantiated let router\(layer): Router"]
				if layer > 0 {
					declarations.append("@Received let router\(layer - 1): Router")
				}
				if layer < layerCount - 1 {
					declarations += (0..<3).map { "@Instantiated let screen\(layer + 1)x\($0)Builder: Instantiator<Screen\(layer + 1)x\($0)>" }
				}
				files.append(seamFixtureType(named: "Screen\(layer)x\(position)", isFinalClass: true, declarations: declarations))
			}
		}
		return files
	}

	/// Layers of three screens beneath a root that opens the first layer's, each screen opening the three screens of the next
	/// layer through an `Instantiator`, and each screen of a layer after the first receiving the `Instantiator` of the screen
	/// of its parent's layer at its own position, which its grandparent declares.
	private static func screensReceivingTheirGrandparentsBuilder(layerCount: Int) -> [String] {
		var files = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: (0..<3).map { "@Instantiated let screen0x\($0)Builder: Instantiator<Screen0x\($0)>" }),
		]
		for layer in 0..<layerCount {
			for position in 0..<3 {
				var declarations = [String]()
				if layer > 1 {
					declarations.append("@Received let screen\(layer - 1)x\(position)Builder: Instantiator<Screen\(layer - 1)x\(position)>")
				}
				if layer < layerCount - 1 {
					declarations += (0..<3).map { "@Instantiated let screen\(layer + 1)x\($0)Builder: Instantiator<Screen\(layer + 1)x\($0)>" }
				}
				files.append(seamFixtureType(named: "Screen\(layer)x\(position)", isFinalClass: true, declarations: declarations))
			}
		}
		return files
	}

	/// A root that declares `token: Secret` above a chain of `renameCount` types, each instantiating the next. The first
	/// renames `token` to `authToken: (any Auth1)?`, and each after it keeps the label and retypes it to `(any Auth<i>)?`,
	/// a protocol `Auth<i - 1>` refines.
	private static func typesRenamingTheRenameAboveThem(renameCount: Int) -> [String] {
		var files = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let token: Secret", "@Instantiated let link1: Link1"]),
			seamFixtureType(named: "Secret", isFinalClass: true, declarations: [], conformances: ", Auth1"),
		]
		for index in 1...renameCount {
			files.append("public protocol Auth\(index)\(index < renameCount ? ": Auth\(index + 1)" : "") {}")
			var declarations = [index == 1
				? "@Received(fulfilledByDependencyNamed: \"token\", ofType: Secret.self, onlyIfAvailable: true) let authToken: (any Auth1)?"
				: "@Received(fulfilledByDependencyNamed: \"authToken\", ofType: (any Auth\(index - 1))?.self, onlyIfAvailable: true) let authToken: (any Auth\(index))?"]
			if index < renameCount {
				declarations.append("@Instantiated let link\(index + 1): Link\(index + 1)")
			}
			files.append(seamFixtureType(named: "Link\(index)", isFinalClass: true, declarations: declarations))
		}
		return files
	}

	/// What a screen of `screensOpeningEachOther` does with the `Context` its root declares.
	private enum ContextRole: CaseIterable {
		case declares
		case receives
		case receivesIfAvailable
		case none
	}

	/// The views each production root of `fixture` is laid out over, in the order the roots are laid out.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func viewCounts(of fixture: [String]) async throws -> [Int] {
		try await workCounts(of: fixture, by: .layingOutTypeKeyViews)
	}

	/// The work `step` did each time it ran while `fixture` was generated, in the order it ran.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func workCounts(of fixture: [String], by step: GenerationWork.Step) async throws -> [Int] {
		let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
		_ = try await GenerationWork.$observer.withValue({ continuation.yield($0) }) {
			try await executeSafeDIToolTest(
				swiftFileContent: fixture,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				// The code is what the type key's other tests compare; this one counts how it is laid out.
				skipCompileVerification: true,
			)
		}
		continuation.finish()
		var counts = [Int]()
		for await work in stream where work.step == step {
			counts.append(work.elementCount)
		}
		return counts
	}

	/// Screens that each forward an `id`, receive the root's `Service`, take a `Context` in `roles`' way and open the
	/// screens `targets` names through an `Instantiator`, beneath a root that declares both and opens the first screen.
	private static func screensOpeningEachOther(roles: [ContextRole], targets: [[Int]]) -> [String] {
		var files = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let service: Service", "@Instantiated let context: Context", "@Instantiated let screen0Builder: Instantiator<Screen0>"]),
			seamFixtureType(named: "Service", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Context", isFinalClass: true, declarations: []),
		]
		for (screen, role) in roles.enumerated() {
			var declarations = ["@Forwarded let id: String", "@Received let service: Service"]
			switch role {
			case .declares:
				declarations.append("@Instantiated let context: Context")
			case .receives:
				declarations.append("@Received let context: Context")
			case .receivesIfAvailable:
				declarations.append("@Received(onlyIfAvailable: true) let context: Context?")
			case .none:
				break
			}
			declarations += targets[screen].map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }
			files.append(seamFixtureType(named: "Screen\(screen)", isFinalClass: true, declarations: declarations))
		}
		return files
	}

	/// `layerCount` layers of four screens beneath a root and a home that opens the first: each screen forwards an `id`,
	/// receives the root's `Service`, instantiates a model of its own and opens the three screens of the next layer but
	/// the one at its own position through an `Instantiator`. The last layer's models instantiate an `Api` the root's
	/// module fulfills.
	private static func screensOpeningTheNextLayer(layerCount: Int) -> [String] {
		var files = [
			seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let service: Service", "@Instantiated let home: Home"]),
			seamFixtureType(named: "Service", isFinalClass: true, declarations: []) + "\npublic protocol Api {}",
			seamFixtureType(named: "Home", isFinalClass: true, declarations: (0..<4).map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }),
			seamFixtureType(named: "LiveApi", isFinalClass: true, declarations: ["@Received let id: Int", "@Received let service: Service"], conformances: ", Api")
				.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n"),
		]
		for screen in 0..<(layerCount * 4) {
			let layer = screen / 4
			let opened = layer < layerCount - 1 ? (0..<4).filter { $0 != screen % 4 }.map { (layer + 1) * 4 + $0 } : []
			files.append(seamFixtureType(
				named: "Screen\(screen)",
				isFinalClass: true,
				declarations: ["@Forwarded let id: Int", "@Received let service: Service", "@Instantiated let model\(screen): Model\(screen)"]
					+ opened.map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" },
			))
			files.append(seamFixtureType(
				named: "Model\(screen)",
				isFinalClass: true,
				declarations: ["@Received let id: Int", "@Received let service: Service"] + (opened.isEmpty ? ["@Instantiated let api: any Api"] : []),
			))
		}
		return files
	}
}
