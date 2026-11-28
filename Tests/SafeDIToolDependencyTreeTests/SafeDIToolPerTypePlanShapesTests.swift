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

/// Which production roots that reach a cycle have their code laid out from their per-type plan, and which shape keeps
/// each other one on today's tree (`DependencyTreeGenerator.shapeOutsidePerTypePlan(inTreeOf:cache:)`). Each test also
/// generates its graph with every root kept on today's tree, and expects the same files.
struct SafeDIToolPerTypePlanShapesTests: ~Copyable {
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
	mutating func generate_writesTodaysParameterOrder_whenPlanLaysOutFunctionWhoseTreeFirstReceivesLabelsAtCycleClosingCall() async throws {
		// The base corpus's seed 2185. `PlanScreen1`'s function takes the values its tree receives in the order the tree
		// first meets them, at the calls that close the cycle as well (`ScopeGenerator.inOrderTheBodyFirstReceives`); a walk
		// that skips those calls meets `planService0` before `planModel1`. Today's tree is kept within any limit, and every
		// root of the plan's run is abandoned at once, so each root the plan admits is laid out from its plan.
		let choices = try await choicesGeneratingTodaysCode(
			of: GraphFuzzerGenerator.fixture(forSeed: 2_185).swiftFileContent.joined(separator: "\n\n"),
			comparingWithTreesWithin: .max,
		)

		#expect(choices["S2185_PlanRoot"] == .some(nil))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenScreensOnCycleReceiveValueTheirCycleDeclares() async throws {
		// Screens open each other through instantiators, one forwarded a value and instantiating a leaf, the other receiving the leaf.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Forwarded let count: Int
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(leaf: Leaf, count: Int, s1Builder: Instantiator<S1>) { self.leaf = leaf; self.count = count; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleReceivesValueRootDeclares() async throws {
		// A screen receives a value the root declares, which today's function captures, and so does the plan's.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleHoldsLazilyInstantiatedNothingReads() async throws {
		// A screen holds a `LazilyInstantiated`.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let leaf: LazilyInstantiated<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: LazilyInstantiated<Leaf>, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleForwardsLabelRootDeclaresInAnotherForm() async throws {
		// The root declares a label as a `LazilyInstantiated`, a screen on a cycle is forwarded it as a value, and the
		// screen that one opens receives it, so the forwarded form is the one the cycle's functions pass.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: LazilyInstantiated<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: LazilyInstantiated<Leaf>, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Forwarded let leaf: Leaf
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(leaf: Leaf, s1Builder: Instantiator<S1>) { self.leaf = leaf; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenLazilyInstantiatedTwinClosesCycleOnConstant() async throws {
		// `Root` and `Detail` build `home: Home` and `Panel` builds `home: LazilyInstantiated<Home>`, twins: a path closes
		// the cycle on whichever of the two it built first, which the layout by type does not write yet.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let home: Home
		    public init(home: Home) { self.home = home }
		}

		@Instantiable public final class Home: Instantiable {
		    @Instantiated let detailBuilder: Instantiator<Detail>
		    public init(detailBuilder: Instantiator<Detail>) { self.detailBuilder = detailBuilder }
		}

		@Instantiable public final class Detail: Instantiable {
		    @Instantiated let panelBuilder: Instantiator<Panel>
		    @Instantiated let home: Home
		    public init(panelBuilder: Instantiator<Panel>, home: Home) { self.panelBuilder = panelBuilder; self.home = home }
		}

		@Instantiable public final class Panel: Instantiable {
		    @Instantiated let home: LazilyInstantiated<Home>
		    public init(home: LazilyInstantiated<Home>) { self.home = home }
		}
		""")

		#expect(choices == ["Root": .noLayout])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTreeWithCodeOfLastRelease_whenSendableLazilyInstantiatedTwinClosesCycleOnConstant() async throws {
		// `Root` and `Detail` build `home: Home` and `Panel` builds `home: SendableLazilyInstantiated<Home>`, twins of one
		// identity: one function builds it, `@Sendable` since the wrapper holds it. `Home` says it is `Sendable` itself, which
		// no generated code decides.
		// Release 2.4.0 generated the text below. The test fails the day the lift that takes this reason lands, and from then
		// on the text must hold on the plan.
		let (choices, files) = try await choicesAndFilesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let home: Home
		    public init(home: Home) { self.home = home }
		}

		@Instantiable public final class Home: Instantiable, @unchecked Sendable {
		    @Instantiated let detailBuilder: Instantiator<Detail>
		    public init(detailBuilder: Instantiator<Detail>) { self.detailBuilder = detailBuilder }
		}

		@Instantiable public final class Detail: Instantiable {
		    @Instantiated let panelBuilder: Instantiator<Panel>
		    @Instantiated let home: Home
		    public init(panelBuilder: Instantiator<Panel>, home: Home) { self.panelBuilder = panelBuilder; self.home = home }
		}

		@Instantiable public final class Panel: Instantiable {
		    @Instantiated let home: SendableLazilyInstantiated<Home>
		    public init(home: SendableLazilyInstantiated<Home>) { self.home = home }
		}
		""")

		#expect(choices == ["Root": .holdsLazilyInstantiated])
		#expect(files["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_home() -> Home {
		            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		            return Home(detailBuilder: detailBuilder)
		        }
		        @Sendable nonisolated func __safeDI_detailBuilder() -> Detail {
		            let panelBuilder = Instantiator<Panel>(__safeDI_panelBuilder)
		            let home: Home = __safeDI_home()
		            return Detail(panelBuilder: panelBuilder, home: home)
		        }
		        @Sendable nonisolated func __safeDI_panelBuilder() -> Panel {
		            let home = SendableLazilyInstantiated<Home>(__safeDI_home)
		            return Panel(home: home)
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""", "Unexpected output \(files["Root+SafeDI.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTreeWithCodeOfLastRelease_whenTwinsAreBeneathSiblingsThatEachDeclareReceivedLabel() async throws {
		// `A` builds `home: Home` and `B` builds `home: LazilyInstantiated<Home>`, twins beneath two siblings that each declare
		// the `theme` a type beneath `Home` receives: the one function of the identity takes it as a parameter.
		// Release 2.4.0 generated the text below. The test fails the day the lift that takes this reason lands, and from then
		// on the text must hold on the plan.
		let (choices, files) = try await choicesAndFilesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let aBuilder: Instantiator<A>
		    @Instantiated let bBuilder: Instantiator<B>
		    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) { self.aBuilder = aBuilder; self.bBuilder = bBuilder }
		}

		@Instantiable public final class A: Instantiable {
		    @Instantiated let theme: Theme
		    @Instantiated let home: Home
		    public init(theme: Theme, home: Home) { self.theme = theme; self.home = home }
		}

		@Instantiable public final class B: Instantiable {
		    @Instantiated let theme: Theme
		    @Instantiated let home: LazilyInstantiated<Home>
		    public init(theme: Theme, home: LazilyInstantiated<Home>) { self.theme = theme; self.home = home }
		}

		@Instantiable public final class Home: Instantiable {
		    @Instantiated let reader: Reader
		    @Instantiated let nextBuilder: Instantiator<Next>
		    public init(reader: Reader, nextBuilder: Instantiator<Next>) { self.reader = reader; self.nextBuilder = nextBuilder }
		}

		@Instantiable public final class Reader: Instantiable {
		    @Received let theme: Theme
		    public init(theme: Theme) { self.theme = theme }
		}

		@Instantiable public final class Next: Instantiable {
		    @Instantiated let home: Home
		    public init(home: Home) { self.home = home }
		}

		@Instantiable public final class Theme: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": .receivesLabelDeclaredOutsideItsCycle])
		#expect(files["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_home(theme: Theme) -> Home {
		            let reader = Reader(theme: theme)
		            let nextBuilder = Instantiator<Next> {
		                __safeDI_nextBuilder(theme: theme)
		            }
		            return Home(reader: reader, nextBuilder: nextBuilder)
		        }
		        func __safeDI_nextBuilder(theme: Theme) -> Next {
		            let home: Home = __safeDI_home(theme: theme)
		            return Next(home: home)
		        }
		        func __safeDI_aBuilder() -> A {
		            let theme = Theme()
		            let home: Home = __safeDI_home(theme: theme)
		            return A(theme: theme, home: home)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        func __safeDI_bBuilder() -> B {
		            let theme = Theme()
		            let home = LazilyInstantiated<Home> {
		                __safeDI_home(theme: theme)
		            }
		            return B(theme: theme, home: home)
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
		    }
		}
		""", "Unexpected output \(files["Root+SafeDI.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTreeWithCodeOfLastRelease_whenTwinsAreErasedToConcreteExistential() async throws {
		// `Root` and `Detail` build `home: AnyScreen` and `Panel` builds `home: LazilyInstantiated<AnyScreen>`, each fulfilled by
		// `Home` and erased, twins of one identity: one function builds `Home`, and each declaration wraps its call.
		// `noLayout` is the layout's refusal of a plan that was built. For twins that are not erased the stage is
		// `TypeKeyRefusal.bodyBuildsNoPlace`: the path is building the constant, so the wrapper's call is of the constant's
		// function, whose body is built by the calling scope, `Panel`, which declares no constant `home`. No observation
		// hands a test the stage, so this test holds the reason only.
		// Release 2.4.0 generated the text below. The test fails the day the lift that takes this reason lands, and from then
		// on the text must hold on the plan.
		let (choices, files) = try await choicesAndFilesGeneratingTodaysCode(of: """
		public protocol Screen {}

		public final class AnyScreen: Screen {
		    public init(_ screen: some Screen) {}
		}

		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated(fulfilledByType: "Home", erasedToConcreteExistential: true) let home: AnyScreen
		    public init(home: AnyScreen) { self.home = home }
		}

		@Instantiable public final class Home: Instantiable, Screen {
		    @Instantiated let detailBuilder: Instantiator<Detail>
		    public init(detailBuilder: Instantiator<Detail>) { self.detailBuilder = detailBuilder }
		}

		@Instantiable public final class Detail: Instantiable {
		    @Instantiated let panelBuilder: Instantiator<Panel>
		    @Instantiated(fulfilledByType: "Home", erasedToConcreteExistential: true) let home: AnyScreen
		    public init(panelBuilder: Instantiator<Panel>, home: AnyScreen) { self.panelBuilder = panelBuilder; self.home = home }
		}

		@Instantiable public final class Panel: Instantiable {
		    @Instantiated(fulfilledByType: "Home", erasedToConcreteExistential: true) let home: LazilyInstantiated<AnyScreen>
		    public init(home: LazilyInstantiated<AnyScreen>) { self.home = home }
		}
		""")

		#expect(choices == ["Root": .noLayout])
		#expect(files["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		            return Home(detailBuilder: detailBuilder)
		        }
		        func __safeDI_detailBuilder() -> Detail {
		            let panelBuilder = Instantiator<Panel>(__safeDI_panelBuilder)
		            let home = AnyScreen(__safeDI_home())
		            return Detail(panelBuilder: panelBuilder, home: home)
		        }
		        func __safeDI_panelBuilder() -> Panel {
		            let home = LazilyInstantiated<AnyScreen> {
		                AnyScreen(__safeDI_home())
		            }
		            return Panel(home: home)
		        }
		        let home = AnyScreen(__safeDI_home())
		        self.init(home: home)
		    }
		}
		""", "Unexpected output \(files["Root+SafeDI.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesCodeOfLastRelease_whenSeamCutsRootsTreeFromTwinsOfItsOwn() async throws {
		// `Root` and `Detail` build `home: Home`, and `Panel`, which the seam `Feature` builds, builds
		// `home: LazilyInstantiated<Home>`. A seam cuts the identity: `Root`'s tree calls the seam's generated initializer
		// and holds only the constant, so it holds no twin and is laid out from its plan. The seam's own tree holds both
		// declarations, twins of one identity, the lazy one reached first: one function builds `Home`, which the wrapper
		// wraps and the constant calls. A seam's own tree is always built per path, so no choice is observed for it.
		// Release 2.4.0 generated the text below for both, and 2.4.1 added `@inline(never)` to a seam's functions.
		// The test fails the day a seam's own tree is laid out from a plan, and from then on the text must hold on the plan.
		let (choices, files) = try await choicesAndFilesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let home: Home
		    public init(home: Home) { self.home = home }
		}

		@Instantiable public final class Home: Instantiable {
		    @Instantiated let detailBuilder: Instantiator<Detail>
		    public init(detailBuilder: Instantiator<Detail>) { self.detailBuilder = detailBuilder }
		}

		@Instantiable public final class Detail: Instantiable {
		    @Instantiated let feature: Feature
		    @Instantiated let home: Home
		    public init(feature: Feature, home: Home) { self.feature = feature; self.home = home }
		}

		@Instantiable(generateDependencyTree: true) public final class Feature: Instantiable {
		    @Instantiated let panelBuilder: Instantiator<Panel>
		    public init(panelBuilder: Instantiator<Panel>) { self.panelBuilder = panelBuilder }
		}

		@Instantiable public final class Panel: Instantiable {
		    @Instantiated let home: LazilyInstantiated<Home>
		    public init(home: LazilyInstantiated<Home>) { self.home = home }
		}
		""")

		#expect(choices == ["Root": nil])
		#expect(files["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Feature {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        @inline(never) func __safeDI_home() -> Home {
		            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		            return Home(detailBuilder: detailBuilder)
		        }
		        @inline(never) func __safeDI_detailBuilder() -> Detail {
		            @inline(never) func __safeDI_feature() -> Feature {
		                _ = Feature.__safeDI_Feature_CBF29CE484222325.self
		                return Feature()
		            }
		            let feature: Feature = __safeDI_feature()
		            let home: Home = __safeDI_home()
		            return Detail(feature: feature, home: home)
		        }
		        @inline(never) func __safeDI_panelBuilder() -> Panel {
		            let home = LazilyInstantiated<Home>(__safeDI_home)
		            return Panel(home: home)
		        }
		        let panelBuilder = Instantiator<Panel>(__safeDI_panelBuilder)
		        self.init(panelBuilder: panelBuilder)
		    }
		}

		extension Feature {
		    public enum __safeDI_Feature_CBF29CE484222325 {}
		}

		extension Root {
		    public convenience init() {
		        func __safeDI_home() -> Home {
		            let detailBuilder = Instantiator<Detail>(__safeDI_detailBuilder)
		            return Home(detailBuilder: detailBuilder)
		        }
		        func __safeDI_detailBuilder() -> Detail {
		            func __safeDI_feature() -> Feature {
		                _ = Feature.__safeDI_Feature_CBF29CE484222325.self
		                return Feature()
		            }
		            let feature: Feature = __safeDI_feature()
		            let home: Home = __safeDI_home()
		            return Detail(feature: feature, home: home)
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}
		""", "Unexpected output \(files["Root+SafeDI.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleCallsSeamThatTakesNoBuilder() async throws {
		// A screen on a cycle holds a seam, whose generated initializer its function calls with what the seam receives.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let service: Service
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(service: Service, s0Builder: Instantiator<S0>) { self.service = service; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let feature: Feature
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(feature: Feature, s0Builder: Instantiator<S0>) { self.feature = feature; self.s0Builder = s0Builder }
		}

		@Instantiable(generateDependencyTree: true) public final class Feature: Instantiable {
		    @Received let service: Service
		    @Instantiated let leaf: Leaf
		    public init(service: Service, leaf: Leaf) { self.service = service; self.leaf = leaf }
		}

		@Instantiable public final class Service: Instantiable { public init() {} }

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenSeamOnCycleReceivesValueItsCycleDeclares() async throws {
		// A screen declares a value, and the screen it opens holds a seam that receives it, so the call of the seam's
		// initializer passes a parameter of its function.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let service: Service
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(service: Service, s0Builder: Instantiator<S0>) { self.service = service; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(leaf: Leaf, s1Builder: Instantiator<S1>) { self.leaf = leaf; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let feature: Feature
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(feature: Feature, s0Builder: Instantiator<S0>) { self.feature = feature; self.s0Builder = s0Builder }
		}

		@Instantiable(generateDependencyTree: true) public final class Feature: Instantiable {
		    @Received let service: Service
		    @Received let leaf: Leaf
		    @Instantiated let gadget: Gadget
		    public init(service: Service, leaf: Leaf, gadget: Gadget) { self.service = service; self.leaf = leaf; self.gadget = gadget }
		}

		@Instantiable public final class Gadget: Instantiable { public init() {} }

		@Instantiable public final class Service: Instantiable { public init() {} }

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeBeneathCycleCallsSeam() async throws {
		// A type two screens of a cycle each build holds a seam, off the cycle.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let service: Service
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(service: Service, s0Builder: Instantiator<S0>) { self.service = service; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let panel: Panel
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(panel: Panel, s1Builder: Instantiator<S1>) { self.panel = panel; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let panel: Panel
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(panel: Panel, s0Builder: Instantiator<S0>) { self.panel = panel; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Panel: Instantiable {
		    @Instantiated let feature: Feature
		    public init(feature: Feature) { self.feature = feature }
		}

		@Instantiable(generateDependencyTree: true) public final class Feature: Instantiable {
		    @Received let service: Service
		    @Instantiated let leaf: Leaf
		    public init(service: Service, leaf: Leaf) { self.service = service; self.leaf = leaf }
		}

		@Instantiable public final class Service: Instantiable { public init() {} }

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleHoldsBuilderOfSeam() async throws {
		// A screen on a cycle holds a builder of a seam, which reads what it receives only inside a builder of its
		// own.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let service: Service
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(service: Service, s0Builder: Instantiator<S0>) { self.service = service; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let featureBuilder: Instantiator<Feature>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(featureBuilder: Instantiator<Feature>, s0Builder: Instantiator<S0>) { self.featureBuilder = featureBuilder; self.s0Builder = s0Builder }
		}

		@Instantiable(generateDependencyTree: true) public final class Feature: Instantiable {
		    @Instantiated let readerBuilder: Instantiator<Reader>
		    public init(readerBuilder: Instantiator<Reader>) { self.readerBuilder = readerBuilder }
		}

		@Instantiable public final class Reader: Instantiable {
		    @Received let service: Service
		    @Instantiated let leaf: Leaf
		    public init(service: Service, leaf: Leaf) { self.service = service; self.leaf = leaf }
		}

		@Instantiable public final class Service: Instantiable { public init() {} }

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleHoldsBuilderOfSeamForwardedValue() async throws {
		// A screen on a cycle holds a builder of a seam, which is forwarded a value its call binds inside its function.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let service: Service
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(service: Service, s0Builder: Instantiator<S0>) { self.service = service; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let featureBuilder: Instantiator<Feature>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(featureBuilder: Instantiator<Feature>, s0Builder: Instantiator<S0>) { self.featureBuilder = featureBuilder; self.s0Builder = s0Builder }
		}

		@Instantiable(generateDependencyTree: true) public final class Feature: Instantiable {
		    @Forwarded let count: Int
		    @Instantiated let readerBuilder: Instantiator<Reader>
		    public init(count: Int, readerBuilder: Instantiator<Reader>) { self.count = count; self.readerBuilder = readerBuilder }
		}

		@Instantiable public final class Reader: Instantiable {
		    @Received let service: Service
		    @Instantiated let leaf: Leaf
		    public init(service: Service, leaf: Leaf) { self.service = service; self.leaf = leaf }
		}

		@Instantiable public final class Service: Instantiable { public init() {} }

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenSeamOnCycleReceivesValueOnlyIfAvailable() async throws {
		// A seam a screen on a cycle holds receives a value only if available, which its call passes or omits.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let service: Service
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(service: Service, s0Builder: Instantiator<S0>) { self.service = service; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let feature: Feature
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(feature: Feature, s0Builder: Instantiator<S0>) { self.feature = feature; self.s0Builder = s0Builder }
		}

		@Instantiable(generateDependencyTree: true) public final class Feature: Instantiable {
		    @Received let service: Service
		    @Received(onlyIfAvailable: true) let leaf: Leaf?
		    public init(service: Service, leaf: Leaf?) { self.service = service; self.leaf = leaf }
		}

		@Instantiable public final class Service: Instantiable { public init() {} }

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": .holdsValueOnlyIfAvailable])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeHoldsSendableLazilyInstantiated() async throws {
		// A screen holds a `SendableLazilyInstantiated`.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let leaf: SendableLazilyInstantiated<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: SendableLazilyInstantiated<Leaf>, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable, Sendable { public init() {} }
		""")

		#expect(choices == ["Root": .holdsLazilyInstantiated])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleReceivesInstanceOfLazilyInstantiatedItsCycleDeclares() async throws {
		// A screen declares a `LazilyInstantiated`, and the screen it opens receives its instance.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let leaf: LazilyInstantiated<Leaf>
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(leaf: LazilyInstantiated<Leaf>, s1Builder: Instantiator<S1>) { self.leaf = leaf; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleReceivesInstanceOfLazilyInstantiatedRootDeclares() async throws {
		// The root declares a `LazilyInstantiated`, and a screen on a cycle receives its instance.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: LazilyInstantiated<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: LazilyInstantiated<Leaf>, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenLazilyInstantiatedClosesCycle() async throws {
		// A screen opened through an instantiator holds a `LazilyInstantiated` of the screen that opens it.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let s0: LazilyInstantiated<S0>
		    public init(s0: LazilyInstantiated<S0>) { self.s0 = s0 }
		}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenOneParentDeclaresValueAndAnotherItsLazilyInstantiated() async throws {
		// A screen receives a value that one screen opening it declares by value and another as a `LazilyInstantiated`.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let hubBuilder: Instantiator<Hub>
		    public init(hubBuilder: Instantiator<Hub>) { self.hubBuilder = hubBuilder }
		}

		@Instantiable public final class Hub: Instantiable {
		    @Instantiated let aBuilder: Instantiator<A>
		    @Instantiated let bBuilder: Instantiator<B>
		    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) { self.aBuilder = aBuilder; self.bBuilder = bBuilder }
		}

		@Instantiable public final class A: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(leaf: Leaf, screenBuilder: Instantiator<Screen>) { self.leaf = leaf; self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class B: Instantiable {
		    @Instantiated let leaf: LazilyInstantiated<Leaf>
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(leaf: LazilyInstantiated<Leaf>, screenBuilder: Instantiator<Screen>) { self.leaf = leaf; self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class Screen: Instantiable {
		    @Received let leaf: Leaf
		    @Instantiated let hubBuilder: Instantiator<Hub>
		    public init(leaf: Leaf, hubBuilder: Instantiator<Hub>) { self.leaf = leaf; self.hubBuilder = hubBuilder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeReceivesValueOnlyIfAvailable() async throws {
		// A screen receives a value only if available.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received(onlyIfAvailable: true) let leaf: Leaf?
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf?, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": .holdsValueOnlyIfAvailable])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeForwardsOptionalValue() async throws {
		// A screen is forwarded an optional value.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Forwarded let count: Int?
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(count: Int?, s0Builder: Instantiator<S0>) { self.count = count; self.s0Builder = s0Builder }
		}
		""")

		#expect(choices == ["Root": .holdsValueOnlyIfAvailable])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleRenamesValueRootDeclares() async throws {
		// A screen renames a value the root declares, which every call of its function passes alike.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self) let other: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(other: Leaf, s0Builder: Instantiator<S0>) { self.other = other; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleRenamesValueItsCycleDeclares() async throws {
		// A screen renames a value the screen before it on the cycle declares, which each call passes on.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(leaf: Leaf, s1Builder: Instantiator<S1>) { self.leaf = leaf; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self) let other: Leaf
		    @Instantiated let s2Builder: Instantiator<S2>
		    public init(other: Leaf, s2Builder: Instantiator<S2>) { self.other = other; self.s2Builder = s2Builder }
		}

		@Instantiable public final class S2: Instantiable {
		    @Received let other: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(other: Leaf, s0Builder: Instantiator<S0>) { self.other = other; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleRenamesValueErasedToConcreteExistential() async throws {
		// A screen renames the root's value to an existential it erases to.
		let choices = try await choicesGeneratingTodaysCode(of: """
		public protocol Clock {}

		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self, erasedToConcreteExistential: true) let clock: AnyClock
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(clock: AnyClock, s1Builder: Instantiator<S1>) { self.clock = clock; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let clock: AnyClock
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(clock: AnyClock, s0Builder: Instantiator<S0>) { self.clock = clock; self.s0Builder = s0Builder }
		}

		public final class AnyClock: Clock {
		    public init(_ clock: some Clock) {}
		}

		@Instantiable public final class Leaf: Instantiable, Clock { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenAnotherRootOfModuleHoldsSendableWrapper() async throws {
		// The module names a `SendableInstantiator` beside the screens' `Instantiator`s, which once kept every root of it on
		// today's tree; `Root`'s own tree holds no `Sendable` wrapper, so it builds nothing in a `@Sendable` function.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable(isRoot: true) public final class Worker: Instantiable {
		    @Instantiated let jobBuilder: SendableInstantiator<Job>
		    public init(jobBuilder: SendableInstantiator<Job>) { self.jobBuilder = jobBuilder }
		}

		@Instantiable public final class Job: Instantiable, Sendable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeHoldsSendableWrapper() async throws {
		// A screen holds a `SendableInstantiator`, whose `@Sendable` builder function captures nothing that is not `Sendable`.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: SendableInstantiator<S0>
		    public init(s0Builder: SendableInstantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: SendableInstantiator<S1>
		    public init(s1Builder: SendableInstantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let s0Builder: SendableInstantiator<S0>
		    public init(s0Builder: SendableInstantiator<S0>) { self.s0Builder = s0Builder }
		}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test(arguments: [nil, "MainActor"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutWithOneSendableFunctionForBothFamilies_whenPlainAndSendableBuildersOpenOneTypeOnCycle(defaultIsolation: String?) async throws {
		// `Root` opens `T3` through a plain builder and through a `Sendable` one, and `T3` opens itself again. Today's tree
		// writes a function in each family; the plan writes one body for `T3` beneath both, a `@Sendable` function, which the
		// plain builder's function calls too. The order of the declarations is the layout's (the graph's order), so no name
		// or order follows which family the walk meets first.
		let output = try await planCodeDifferingFromTodays(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let plainBuilder: Instantiator<T3>
		    @Instantiated let sendableBuilder: SendableInstantiator<T3>
		    public init(plainBuilder: Instantiator<T3>, sendableBuilder: SendableInstantiator<T3>) { self.plainBuilder = plainBuilder; self.sendableBuilder = sendableBuilder }
		}

		@Instantiable public final class T3: Instantiable, @unchecked Sendable {
		    @Instantiated let againBuilder: Instantiator<T3>
		    public init(againBuilder: Instantiator<T3>) { self.againBuilder = againBuilder }
		}
		""", defaultIsolation: defaultIsolation)

		#expect(output.choices == ["Root": nil])
		#expect(output.files["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_againBuilder() -> T3 {
		            let againBuilder = Instantiator<T3>(__safeDI_againBuilder)
		            return T3(againBuilder: againBuilder)
		        }
		        func __safeDI_plainBuilder() -> T3 {
		            let againBuilder = Instantiator<T3>(__safeDI_againBuilder)
		            return T3(againBuilder: againBuilder)
		        }
		        let plainBuilder = Instantiator<T3>(__safeDI_plainBuilder)
		        let sendableBuilder = SendableInstantiator<T3>(__safeDI_againBuilder)
		        self.init(plainBuilder: plainBuilder, sendableBuilder: sendableBuilder)
		    }
		}
		""")
	}

	@Test(arguments: [nil, "MainActor"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutWithOneSendableFunctionForBothFamilies_whenErasedPlainBuilderAndSendableBuilderOpenOneTypeOnCycle(defaultIsolation: String?) async throws {
		// A generated graph's root (base corpus seed 3378) in brief: `Root` opens `T3` erased through a plain builder declared
		// first and through a `Sendable` one, and `T3` opens itself again. The plan writes a function per builder, as today's
		// tree does, but the inner `againBuilder` of the plain one calls the `@Sendable` function, which the `Sendable` route
		// opens too, where today's closes on its own function. The order of the declarations, and the name of the shared
		// function, are the layout's: the graph's order, the first place of the body in it, never which family the walk
		// meets first. The next test declares the builders the other way round and gets the same structure.
		let output = try await planCodeDifferingFromTodays(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated(fulfilledByType: "T3", erasedToConcreteExistential: true) let anyT3Builder: ErasedInstantiator<Int, AnyT3>
		    @Instantiated let t3Builder: SendableInstantiator<T3>
		    public init(anyT3Builder: ErasedInstantiator<Int, AnyT3>, t3Builder: SendableInstantiator<T3>) { self.anyT3Builder = anyT3Builder; self.t3Builder = t3Builder }
		}

		@Instantiable public final class T3: Instantiable, @unchecked Sendable {
		    @Forwarded let id: Int
		    @Instantiated let againBuilder: Instantiator<T3>
		    public init(id: Int, againBuilder: Instantiator<T3>) { self.id = id; self.againBuilder = againBuilder }
		}

		nonisolated public final class AnyT3: Sendable {
		    public init(_ value: T3) { self.value = value }
		    public let value: T3
		}
		""", defaultIsolation: defaultIsolation)

		#expect(output.choices == ["Root": nil])
		#expect(output.files["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_againBuilder(id: Int) -> T3 {
		            let againBuilder = Instantiator<T3> {
		                __safeDI_againBuilder(id: $0)
		            }
		            return T3(id: id, againBuilder: againBuilder)
		        }
		        func __safeDI_anyT3Builder(id: Int) -> T3 {
		            let againBuilder = Instantiator<T3> {
		                __safeDI_againBuilder(id: $0)
		            }
		            return T3(id: id, againBuilder: againBuilder)
		        }
		        let anyT3Builder = ErasedInstantiator<Int, AnyT3> {
		            AnyT3(__safeDI_anyT3Builder(id: $0))
		        }
		        let t3Builder = SendableInstantiator<T3> {
		            __safeDI_againBuilder(id: $0)
		        }
		        self.init(anyT3Builder: anyT3Builder, t3Builder: t3Builder)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutWithOneSendableFunctionForBothFamilies_whenSendableBuilderIsDeclaredBeforeErasedPlainBuilder() async throws {
		// The previous test's root with its two builders declared the other way round: the same two functions, and the plain
		// one's inner call still of the `@Sendable` one. The shared function is now named after `t3Builder`, the first place
		// of its body in the graph's order, and declared where that builder is.
		let output = try await planCodeDifferingFromTodays(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let t3Builder: SendableInstantiator<T3>
		    @Instantiated(fulfilledByType: "T3", erasedToConcreteExistential: true) let anyT3Builder: ErasedInstantiator<Int, AnyT3>
		    public init(anyT3Builder: ErasedInstantiator<Int, AnyT3>, t3Builder: SendableInstantiator<T3>) { self.anyT3Builder = anyT3Builder; self.t3Builder = t3Builder }
		}

		@Instantiable public final class T3: Instantiable, @unchecked Sendable {
		    @Forwarded let id: Int
		    @Instantiated let againBuilder: Instantiator<T3>
		    public init(id: Int, againBuilder: Instantiator<T3>) { self.id = id; self.againBuilder = againBuilder }
		}

		nonisolated public final class AnyT3: Sendable {
		    public init(_ value: T3) { self.value = value }
		    public let value: T3
		}
		""", defaultIsolation: nil)

		#expect(output.choices == ["Root": nil])
		#expect(output.files["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_t3Builder(id: Int) -> T3 {
		            let againBuilder = Instantiator<T3> {
		                __safeDI_t3Builder(id: $0)
		            }
		            return T3(id: id, againBuilder: againBuilder)
		        }
		        let t3Builder = SendableInstantiator<T3> {
		            __safeDI_t3Builder(id: $0)
		        }
		        func __safeDI_anyT3Builder(id: Int) -> T3 {
		            let againBuilder = Instantiator<T3> {
		                __safeDI_t3Builder(id: $0)
		            }
		            return T3(id: id, againBuilder: againBuilder)
		        }
		        let anyT3Builder = ErasedInstantiator<Int, AnyT3> {
		            AnyT3(__safeDI_anyT3Builder(id: $0))
		        }
		        self.init(anyT3Builder: anyT3Builder, t3Builder: t3Builder)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutWithBodyPerAnswer_whenPlainRouteReadsValueSendableRouteDeclaresAgain() async throws {
		// `Root` opens `S1` through a plain builder, whose function reads `Root`'s `model`, which is not `Sendable`, and opens
		// `S0` through a `Sendable` one, which declares a `model` of its own and opens `S1` again. The two routes answer
		// `model` with other declarations, so the plan builds a body of `S1` for each: the one the `Sendable` route calls is
		// a `@Sendable` function that takes `model`, and the plain builder's stays plain, capturing the `model` a `@Sendable`
		// function could not.
		let output = try await planCodeDifferingFromTodays(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let model: Model
		    @Instantiated let plainBuilder: Instantiator<S1>
		    @Instantiated let sendableBuilder: SendableInstantiator<S0>
		    public init(model: Model, plainBuilder: Instantiator<S1>, sendableBuilder: SendableInstantiator<S0>) { self.model = model; self.plainBuilder = plainBuilder; self.sendableBuilder = sendableBuilder }
		}

		@Instantiable public final class Model: Instantiable { public init() {} }

		@Instantiable public final class S0: Instantiable, @unchecked Sendable {
		    @Instantiated let model: Model
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(model: Model, s1Builder: Instantiator<S1>) { self.model = model; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable, @unchecked Sendable {
		    @Received let model: Model
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(model: Model, s0Builder: Instantiator<S0>) { self.model = model; self.s0Builder = s0Builder }
		}
		""", defaultIsolation: nil)

		#expect(output.choices == ["Root": nil])
		#expect(output.files["Root+SafeDI.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		extension Root {
		    public convenience init() {
		        let model = Model()
		        @Sendable nonisolated func __safeDI_s0Builder() -> S0 {
		            let model = Model()
		            let s1Builder = Instantiator<S1> {
		                __safeDI_s1Builder(model: model)
		            }
		            return S0(model: model, s1Builder: s1Builder)
		        }
		        @Sendable nonisolated func __safeDI_s1Builder(model: Model) -> S1 {
		            let s0Builder = Instantiator<S0>(__safeDI_s0Builder)
		            return S1(model: model, s0Builder: s0Builder)
		        }
		        func __safeDI_plainBuilder() -> S1 {
		            let s0Builder = Instantiator<S0>(__safeDI_s0Builder)
		            return S1(model: model, s0Builder: s0Builder)
		        }
		        let plainBuilder = Instantiator<S1>(__safeDI_plainBuilder)
		        let sendableBuilder = SendableInstantiator<S0>(__safeDI_s0Builder)
		        self.init(model: model, plainBuilder: plainBuilder, sendableBuilder: sendableBuilder)
		    }
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenCycleClosedInsideSendableFunctionReentersPlainOpener() async throws {
		// `S1`, built in a `@Sendable` function, closes the cycle on `S0`, which `Root` opens through a plain builder. Today's
		// tree shares one `@Sendable` function between the two, as the plan does.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable, @unchecked Sendable {
		    @Instantiated let s1Builder: SendableInstantiator<S1>
		    public init(s1Builder: SendableInstantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable, @unchecked Sendable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTodaysCaptureError_whenTwoBuildsOfTypeHandItsSendableBuilderNilAndNonSendableWrapper() async {
		// `Root` builds `T0` twice: through `anyT0Builder`, built before `lazyT4` since `T4` receives it, so `T1`'s receive only if
		// available of `lazyT4` is passed `nil`; and through `t0Builder`, built after `lazyT4`, whose `T1`, built in a `@Sendable`
		// function, would capture it: seam corpus seed 580's shape. No root reaches a cycle, so none is laid out from a plan.
		let choices = await choicesThrowingTodaysError(
			of: Self.twoBuildsHandingNilAndNonSendableWrapper,
			diagnostics: Self.twoBuildsCaptureDiagnostics,
		)

		#expect(choices.isEmpty)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTodaysCaptureError_whenTwoCallsOfVariantOnCycleAreHandedNilAndNonSendableWrapper() async {
		// `Root` builds `T0` through `anyT0Builder`, where nothing above declares `lazyT4`, so `T1`'s receive only if available
		// is passed `nil`, and `X` builds it through `t0Builder` beneath its own `lazyT4`, which `T1`, built in a `@Sendable`
		// function, would capture. `T1` is on a cycle through `T5`, so `Root` reaches a cycle and `T0`'s two builds would be
		// calls of one variant whose reads of `lazyT4` the calls answer differently. A receive only if available keeps the root
		// on today's tree, whose walk judges every path's capture.
		let choices = await choicesThrowingTodaysError(
			of: Self.twoCallsOfVariantOnCycle(t1Receives: "@Received(onlyIfAvailable: true) let t4: LazilyInstantiated<T4>?", rootDeclares: nil),
			diagnostics: { fixtures in
				"""
				\(fixtures["T1.swift"]):2:5: error: @Received property `t4: LazilyInstantiated<T4>?` cannot be received inside a `@Sendable` function in chain: Root -> X -> T0 -> T1 -> T5 -> T1. SafeDI builds `anyT1Builder: SendableErasedInstantiator<(), AnyT1>` on `T0` in a `@Sendable` function, which cannot capture `t4: LazilyInstantiated<T4>` on `X`, because `LazilyInstantiated<T4>` is not `Sendable`. Declare `t4` on `X`, and this property, as `SendableLazilyInstantiated<T4>` to fix. A `SendableLazilyInstantiated` requires its instance type, `T4`, to be `Sendable`.
				\(fixtures["X.swift"]):2:5: note: `t4: LazilyInstantiated<T4>` is declared here
				\(fixtures["T1.swift"]):2:5: error: @Received property `t4: LazilyInstantiated<T4>?` cannot be received inside a `@Sendable` function in chain: Root -> X -> T0 -> T1. SafeDI builds `anyT1Builder: SendableErasedInstantiator<(), AnyT1>` on `T0` in a `@Sendable` function, which cannot capture `t4: LazilyInstantiated<T4>` on `X`, because `LazilyInstantiated<T4>` is not `Sendable`. Declare `t4` on `X`, and this property, as `SendableLazilyInstantiated<T4>` to fix. A `SendableLazilyInstantiated` requires its instance type, `T4`, to be `Sendable`.
				\(fixtures["X.swift"]):2:5: note: `t4: LazilyInstantiated<T4>` is declared here
				"""
			},
		)

		#expect(choices == ["Root": .holdsValueOnlyIfAvailable])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTodaysCaptureError_whenTwoCallsOfVariantOnCycleReadValueAndInstanceOfNonSendableWrapper() async {
		// As above with a required receive by value: `Root` declares `t4` as a value, which `anyT0Builder`'s `T1` reads, and `X`
		// declares it as a `LazilyInstantiated`, whose instance `t0Builder`'s `T1`, built in a `@Sendable` function, would read
		// through the wrapper it captures. A label that a scope other than the root declares keeps the root on today's tree, so
		// no variant's calls are answered by different declarations.
		let choices = await choicesThrowingTodaysError(
			of: Self.twoCallsOfVariantOnCycle(t1Receives: "@Received let t4: T4", rootDeclares: "@Instantiated let t4: T4"),
			diagnostics: { fixtures in
				"""
				\(fixtures["T1.swift"]):2:5: error: @Received property `t4: T4` cannot be received inside a `@Sendable` function in chain: Root -> X -> T0 -> T1 -> T5 -> T1. SafeDI builds `anyT1Builder: SendableErasedInstantiator<(), AnyT1>` on `T0` in a `@Sendable` function, which cannot capture `t4: LazilyInstantiated<T4>` on `X`, because `LazilyInstantiated<T4>` is not `Sendable`. Declare `t4` on `X` as `SendableLazilyInstantiated<T4>` to fix. A `SendableLazilyInstantiated` requires its instance type, `T4`, to be `Sendable`.
				\(fixtures["X.swift"]):2:5: note: `t4: LazilyInstantiated<T4>` is declared here
				\(fixtures["T1.swift"]):2:5: error: @Received property `t4: T4` cannot be received inside a `@Sendable` function in chain: Root -> X -> T0 -> T1. SafeDI builds `anyT1Builder: SendableErasedInstantiator<(), AnyT1>` on `T0` in a `@Sendable` function, which cannot capture `t4: LazilyInstantiated<T4>` on `X`, because `LazilyInstantiated<T4>` is not `Sendable`. Declare `t4` on `X` as `SendableLazilyInstantiated<T4>` to fix. A `SendableLazilyInstantiated` requires its instance type, `T4`, to be `Sendable`.
				\(fixtures["X.swift"]):2:5: note: `t4: LazilyInstantiated<T4>` is declared here
				"""
			},
		)

		#expect(choices == ["Root": .receivesLabelDeclaredOutsideItsCycle])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTodaysCaptureError_whenSendableBuilderInBodyOfCycleCapturesInstantiatorDeclaredBesideIt() async {
		// `S1`, on the cycle, declares `xBuilder` outside the `@Sendable` builder function of `wBuilder`, which builds `W`,
		// which receives it.
		let choices = await choicesThrowingTodaysError(
			of: [
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let s0Builder: Instantiator<S0>
				    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
				}
				""",
				"""
				@Instantiable public final class S0: Instantiable {
				    @Instantiated let s1Builder: Instantiator<S1>
				    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
				}
				""",
				"""
				@Instantiable public final class S1: Instantiable {
				    @Instantiated let s0Builder: Instantiator<S0>
				    @Instantiated let xBuilder: Instantiator<X>
				    @Instantiated let wBuilder: SendableInstantiator<W>
				    public init(s0Builder: Instantiator<S0>, xBuilder: Instantiator<X>, wBuilder: SendableInstantiator<W>) { self.s0Builder = s0Builder; self.xBuilder = xBuilder; self.wBuilder = wBuilder }
				}
				""",
				"""
				@Instantiable public final class W: Instantiable {
				    @Received let xBuilder: Instantiator<X>
				    public init(xBuilder: Instantiator<X>) { self.xBuilder = xBuilder }
				}
				""",
				"""
				@Instantiable public final class X: Instantiable { public init() {} }
				""",
			],
			diagnostics: { fixtures in
				"""
				\(fixtures["W.swift"]):2:5: error: @Received property `xBuilder: Instantiator<X>` cannot be received inside a `@Sendable` function in chain: Root -> S0 -> S1 -> W. SafeDI builds `wBuilder: SendableInstantiator<W>` on `S1` in a `@Sendable` function, which cannot capture `xBuilder: Instantiator<X>` on `S1`, because `Instantiator<X>` is not `Sendable`. Declare `xBuilder` on `S1`, and this property, as `SendableInstantiator<X>` to fix. `SendableInstantiator<X>` builds `X` in a `@Sendable` function, so what the tree of `X` receives from outside that function must be `Sendable` too.
				\(fixtures["S1.swift"]):3:5: note: `xBuilder: Instantiator<X>` is declared here
				"""
			},
		)

		#expect(choices == ["Root": .mayCaptureNonSendableWrapper])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTodaysCaptureError_whenSendableBuilderOnCycleCapturesInstantiatorRootDeclares() async {
		// `S1`, on the cycle, builds `W` in the `@Sendable` builder function of `wBuilder`, and `W` receives the `Instantiator` the root
		// declares, which that function cannot capture.
		let choices = await choicesThrowingTodaysError(
			of: [
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let leafBuilder: Instantiator<Leaf>
				    @Instantiated let s0Builder: Instantiator<S0>
				    public init(leafBuilder: Instantiator<Leaf>, s0Builder: Instantiator<S0>) { self.leafBuilder = leafBuilder; self.s0Builder = s0Builder }
				}
				""",
				"""
				@Instantiable public final class S0: Instantiable {
				    @Instantiated let s1Builder: Instantiator<S1>
				    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
				}
				""",
				"""
				@Instantiable public final class S1: Instantiable {
				    @Instantiated let s0Builder: Instantiator<S0>
				    @Instantiated let wBuilder: SendableInstantiator<W>
				    public init(s0Builder: Instantiator<S0>, wBuilder: SendableInstantiator<W>) { self.s0Builder = s0Builder; self.wBuilder = wBuilder }
				}
				""",
				"""
				@Instantiable public final class W: Instantiable {
				    @Received let leafBuilder: Instantiator<Leaf>
				    public init(leafBuilder: Instantiator<Leaf>) { self.leafBuilder = leafBuilder }
				}
				""",
				"""
				@Instantiable public final class Leaf: Instantiable { public init() {} }
				""",
			],
			diagnostics: { fixtures in
				"""
				\(fixtures["W.swift"]):2:5: error: @Received property `leafBuilder: Instantiator<Leaf>` cannot be received inside a `@Sendable` function in chain: Root -> S0 -> S1 -> W. SafeDI builds `wBuilder: SendableInstantiator<W>` on `S1` in a `@Sendable` function, which cannot capture `leafBuilder: Instantiator<Leaf>` on `Root`, because `Instantiator<Leaf>` is not `Sendable`. Declare `leafBuilder` on `Root`, and this property, as `SendableInstantiator<Leaf>` to fix. `SendableInstantiator<Leaf>` builds `Leaf` in a `@Sendable` function, so what the tree of `Leaf` receives from outside that function must be `Sendable` too.
				\(fixtures["Root.swift"]):2:5: note: `leafBuilder: Instantiator<Leaf>` is declared here
				"""
			},
		)

		#expect(choices == ["Root": .mayCaptureNonSendableWrapper])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTodaysCaptureError_whenSendableBuilderOnCycleCapturesRenameOfInstantiatorRootDeclares() async {
		// `W`, built in the `@Sendable` builder function of `wBuilder` on the cycle, renames the `Instantiator` the root declares as a
		// value of another type, a receive of the builder that function cannot capture.
		let choices = await choicesThrowingTodaysError(
			of: [
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let leafBuilder: Instantiator<Leaf>
				    @Instantiated let s0Builder: Instantiator<S0>
				    public init(leafBuilder: Instantiator<Leaf>, s0Builder: Instantiator<S0>) { self.leafBuilder = leafBuilder; self.s0Builder = s0Builder }
				}
				""",
				"""
				@Instantiable public final class S0: Instantiable {
				    @Instantiated let s1Builder: Instantiator<S1>
				    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
				}
				""",
				"""
				@Instantiable public final class S1: Instantiable {
				    @Instantiated let s0Builder: Instantiator<S0>
				    @Instantiated let wBuilder: SendableInstantiator<W>
				    public init(s0Builder: Instantiator<S0>, wBuilder: SendableInstantiator<W>) { self.s0Builder = s0Builder; self.wBuilder = wBuilder }
				}
				""",
				"""
				@Instantiable public final class W: Instantiable {
				    @Received(fulfilledByDependencyNamed: "leafBuilder", ofType: Instantiator<Leaf>.self) let other: Any
				    public init(other: Any) { self.other = other }
				}
				""",
				"""
				@Instantiable public final class Leaf: Instantiable { public init() {} }
				""",
			],
			diagnostics: { fixtures in
				"""
				\(fixtures["W.swift"]):2:5: error: @Received property `leafBuilder: Instantiator<Leaf>` cannot be received inside a `@Sendable` function in chain: Root -> S0 -> S1 -> W. SafeDI builds `wBuilder: SendableInstantiator<W>` on `S1` in a `@Sendable` function, which cannot capture `leafBuilder: Instantiator<Leaf>` on `Root`, because `Instantiator<Leaf>` is not `Sendable`. Declare `leafBuilder` on `Root`, and this property, as `SendableInstantiator<Leaf>` to fix. `SendableInstantiator<Leaf>` builds `Leaf` in a `@Sendable` function, so what the tree of `Leaf` receives from outside that function must be `Sendable` too.
				\(fixtures["Root.swift"]):2:5: note: `leafBuilder: Instantiator<Leaf>` is declared here
				"""
			},
		)

		#expect(choices == ["Root": .mayCaptureNonSendableWrapper])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTodaysCaptureError_whenSendableBuilderOnCycleCapturesErasedInstantiatorRootDeclares() async {
		// `W`, built in the `@Sendable` builder function of `wBuilder` on the cycle, receives the erased builder the root declares,
		// which that function cannot capture.
		let choices = await choicesThrowingTodaysError(
			of: [
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated(fulfilledByType: "Row", erasedToConcreteExistential: false) let rowBuilder: ErasedInstantiator<(), any Rowish>
				    @Instantiated let s0Builder: Instantiator<S0>
				    public init(rowBuilder: ErasedInstantiator<(), any Rowish>, s0Builder: Instantiator<S0>) { self.rowBuilder = rowBuilder; self.s0Builder = s0Builder }
				}
				""",
				"""
				@Instantiable public final class S0: Instantiable {
				    @Instantiated let s1Builder: Instantiator<S1>
				    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
				}
				""",
				"""
				@Instantiable public final class S1: Instantiable {
				    @Instantiated let s0Builder: Instantiator<S0>
				    @Instantiated let wBuilder: SendableInstantiator<W>
				    public init(s0Builder: Instantiator<S0>, wBuilder: SendableInstantiator<W>) { self.s0Builder = s0Builder; self.wBuilder = wBuilder }
				}
				""",
				"""
				@Instantiable public final class W: Instantiable {
				    @Received let rowBuilder: ErasedInstantiator<(), any Rowish>
				    public init(rowBuilder: ErasedInstantiator<(), any Rowish>) { self.rowBuilder = rowBuilder }
				}
				""",
				"""
				@Instantiable public final class Row: Instantiable, Rowish { public init() {} }

				public protocol Rowish {}
				""",
			],
			diagnostics: { fixtures in
				"""
				\(fixtures["W.swift"]):2:5: error: @Received property `rowBuilder: ErasedInstantiator<(), any Rowish>` cannot be received inside a `@Sendable` function in chain: Root -> S0 -> S1 -> W. SafeDI builds `wBuilder: SendableInstantiator<W>` on `S1` in a `@Sendable` function, which cannot capture `rowBuilder: ErasedInstantiator<(), any Rowish>` on `Root`, because `ErasedInstantiator<(), any Rowish>` is not `Sendable`. Declare `rowBuilder` on `Root`, and this property, as `SendableErasedInstantiator<(), any Rowish>` to fix. `SendableErasedInstantiator<(), any Rowish>` builds `any Rowish` in a `@Sendable` function, so what the tree of `any Rowish` receives from outside that function must be `Sendable` too.
				\(fixtures["Root.swift"]):2:5: note: `rowBuilder: ErasedInstantiator<(), any Rowish>` is declared here
				"""
			},
		)

		#expect(choices == ["Root": .mayCaptureNonSendableWrapper])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTodaysCaptureError_whenSendableBuilderOnCycleCapturesInstanceOfLazilyInstantiatedDeclaredAboveIt() async {
		// `S0`, on the cycle, declares `leaf` as a `LazilyInstantiated`; `S1` builds `W` in the `@Sendable` builder function of
		// `wBuilder`, and `W` reads the instance, which that function cannot capture.
		let choices = await choicesThrowingTodaysError(
			of: [
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let s0Builder: Instantiator<S0>
				    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
				}
				""",
				"""
				@Instantiable public final class S0: Instantiable {
				    @Instantiated let leaf: LazilyInstantiated<Leaf>
				    @Instantiated let s1Builder: Instantiator<S1>
				    public init(leaf: LazilyInstantiated<Leaf>, s1Builder: Instantiator<S1>) { self.leaf = leaf; self.s1Builder = s1Builder }
				}
				""",
				"""
				@Instantiable public final class S1: Instantiable {
				    @Instantiated let s0Builder: Instantiator<S0>
				    @Instantiated let wBuilder: SendableInstantiator<W>
				    public init(s0Builder: Instantiator<S0>, wBuilder: SendableInstantiator<W>) { self.s0Builder = s0Builder; self.wBuilder = wBuilder }
				}
				""",
				"""
				@Instantiable public final class W: Instantiable {
				    @Received let leaf: Leaf
				    public init(leaf: Leaf) { self.leaf = leaf }
				}
				""",
				"""
				@Instantiable public final class Leaf: Instantiable { public init() {} }
				""",
			],
			diagnostics: { fixtures in
				"""
				\(fixtures["W.swift"]):2:5: error: @Received property `leaf: Leaf` cannot be received inside a `@Sendable` function in chain: Root -> S0 -> S1 -> W. SafeDI builds `wBuilder: SendableInstantiator<W>` on `S1` in a `@Sendable` function, which cannot capture `leaf: LazilyInstantiated<Leaf>` on `S0`, because `LazilyInstantiated<Leaf>` is not `Sendable`. Declare `leaf` on `S0` as `SendableLazilyInstantiated<Leaf>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Leaf`, to be `Sendable`.
				\(fixtures["S0.swift"]):2:5: note: `leaf: LazilyInstantiated<Leaf>` is declared here
				"""
			},
		)

		#expect(choices == ["Root": .mayCaptureNonSendableWrapper])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeIsForwardedSendableFunction() async throws {
		// A screen is forwarded a `@Sendable` function.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Forwarded let onTap: @Sendable () -> Void
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(onTap: @escaping @Sendable () -> Void, s0Builder: Instantiator<S0>) { self.onTap = onTap; self.s0Builder = s0Builder }
		}
		""")

		#expect(choices == ["Root": .holdsSendableFunction])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenCycleMemberIsInstantiatedErased() async throws {
		// A screen instantiates the screen that opened it as an `ErasedInstantiator`, which wraps a call of that screen's
		// function.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let home: Instantiator<S0>
		    public init(home: Instantiator<S0>) { self.home = home }
		}

		@Instantiable public final class S0: Instantiable, Screen {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated(fulfilledByType: "S0", erasedToConcreteExistential: false) let s0Builder: ErasedInstantiator<(), any Screen>
		    public init(s0Builder: ErasedInstantiator<(), any Screen>) { self.s0Builder = s0Builder }
		}

		public protocol Screen {}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenCycleMemberIsInstantiatedErasedToConcreteExistential() async throws {
		// Screens open one another through erased instantiators of a concrete existential, each forwarding an `id`.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated(fulfilledByType: "S0", erasedToConcreteExistential: true) let home: ErasedInstantiator<Int, AnyScreen>
		    public init(home: ErasedInstantiator<Int, AnyScreen>) { self.home = home }
		}

		@Instantiable public final class S0: Instantiable {
		    @Forwarded let id: Int
		    @Instantiated(fulfilledByType: "S1", erasedToConcreteExistential: true) let s1Builder: ErasedInstantiator<Int, AnyScreen>
		    public init(id: Int, s1Builder: ErasedInstantiator<Int, AnyScreen>) { self.id = id; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Forwarded let id: Int
		    @Instantiated(fulfilledByType: "S0", erasedToConcreteExistential: true) let s0Builder: ErasedInstantiator<Int, AnyScreen>
		    public init(id: Int, s0Builder: ErasedInstantiator<Int, AnyScreen>) { self.id = id; self.s0Builder = s0Builder }
		}

		public final class AnyScreen {
		    public init(_ screen: AnyObject) { self.screen = screen }
		    public let screen: AnyObject
		}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTodaysCaptureError_whenErasedSendableCycleMemberWrapsCallReadingLazilyInstantiatedDeclaredAboveIt() async {
		// `S0` declares `leaf` as a `LazilyInstantiated` and opens `S1` through a `SendableErasedInstantiator`, whose `@Sendable`
		// function wraps the call of `S1`'s body, and `S1` reads the instance, which that function cannot capture.
		let choices = await choicesThrowingTodaysError(
			of: [
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let s0Builder: Instantiator<S0>
				    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
				}
				""",
				"""
				@Instantiable public final class S0: Instantiable {
				    @Instantiated let leaf: LazilyInstantiated<Leaf>
				    @Instantiated(fulfilledByType: "S1", erasedToConcreteExistential: true) let s1Builder: SendableErasedInstantiator<(), AnyScreen>
				    public init(leaf: LazilyInstantiated<Leaf>, s1Builder: SendableErasedInstantiator<(), AnyScreen>) { self.leaf = leaf; self.s1Builder = s1Builder }
				}
				""",
				"""
				@Instantiable public final class S1: Instantiable {
				    @Received let leaf: Leaf
				    @Instantiated let s0Builder: Instantiator<S0>
				    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
				}
				""",
				"""
				@Instantiable public final class Leaf: Instantiable { public init() {} }
				""",
				"""
				public final class AnyScreen {
				    public init(_ screen: AnyObject) { self.screen = screen }
				    public let screen: AnyObject
				}
				""",
			],
			diagnostics: { fixtures in
				"""
				\(fixtures["S1.swift"]):2:5: error: @Received property `leaf: Leaf` cannot be received inside a `@Sendable` function in chain: Root -> S0 -> S1. SafeDI builds `s1Builder: SendableErasedInstantiator<(), AnyScreen>` on `S0` in a `@Sendable` function, which cannot capture `leaf: LazilyInstantiated<Leaf>` on `S0`, because `LazilyInstantiated<Leaf>` is not `Sendable`. Declare `leaf` on `S0` as `SendableLazilyInstantiated<Leaf>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Leaf`, to be `Sendable`.
				\(fixtures["S0.swift"]):2:5: note: `leaf: LazilyInstantiated<Leaf>` is declared here
				"""
			},
		)

		#expect(choices == ["Root": .mayCaptureNonSendableWrapper])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTodaysCaptureError_whenSendableBuilderOnCycleCallsSeamWithInstanceOfLazilyInstantiatedDeclaredAboveIt() async {
		// `S0` declares `leaf` as a `LazilyInstantiated`; `S1` builds the seam `Feature` in the `@Sendable` builder function of
		// `featureBuilder`, and the call of its initializer passes the instance, which that function cannot capture.
		let choices = await choicesThrowingTodaysError(
			of: [
				"""
				@Instantiable(isRoot: true) public final class Root: Instantiable {
				    @Instantiated let s0Builder: Instantiator<S0>
				    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
				}
				""",
				"""
				@Instantiable public final class S0: Instantiable {
				    @Instantiated let leaf: LazilyInstantiated<Leaf>
				    @Instantiated let s1Builder: Instantiator<S1>
				    public init(leaf: LazilyInstantiated<Leaf>, s1Builder: Instantiator<S1>) { self.leaf = leaf; self.s1Builder = s1Builder }
				}
				""",
				"""
				@Instantiable public final class S1: Instantiable {
				    @Instantiated let s0Builder: Instantiator<S0>
				    @Instantiated let featureBuilder: SendableInstantiator<Feature>
				    public init(s0Builder: Instantiator<S0>, featureBuilder: SendableInstantiator<Feature>) { self.s0Builder = s0Builder; self.featureBuilder = featureBuilder }
				}
				""",
				"""
				@Instantiable(generateDependencyTree: true) public final class Feature: Instantiable {
				    @Received let leaf: Leaf
				    @Instantiated let gadget: Gadget
				    public init(leaf: Leaf, gadget: Gadget) { self.leaf = leaf; self.gadget = gadget }
				}
				""",
				"""
				@Instantiable public final class Gadget: Instantiable { public init() {} }
				""",
				"""
				@Instantiable public final class Leaf: Instantiable { public init() {} }
				""",
			],
			diagnostics: { fixtures in
				"""
				\(fixtures["Feature.swift"]):2:5: error: @Received property `leaf: Leaf` cannot be received inside a `@Sendable` function in chain: Root -> S0 -> S1 -> Feature. SafeDI builds `featureBuilder: SendableInstantiator<Feature>` on `S1` in a `@Sendable` function, which cannot capture `leaf: LazilyInstantiated<Leaf>` on `S0`, because `LazilyInstantiated<Leaf>` is not `Sendable`. Declare `leaf` on `S0` as `SendableLazilyInstantiated<Leaf>` to fix. A `SendableLazilyInstantiated` requires its instance type, `Leaf`, to be `Sendable`.
				\(fixtures["S0.swift"]):2:5: note: `leaf: LazilyInstantiated<Leaf>` is declared here
				"""
			},
		)

		#expect(choices == ["Root": .mayCaptureNonSendableWrapper])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenErasedCycleMemberReceivesValueItsCycleDeclares() async throws {
		// A screen declares a model the screen it opens erased receives, and that screen opens the first again by value
		// of its builder.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let model: Model
		    @Instantiated(fulfilledByType: "S1", erasedToConcreteExistential: true) let s1Builder: ErasedInstantiator<(), AnyScreen>
		    public init(model: Model, s1Builder: ErasedInstantiator<(), AnyScreen>) { self.model = model; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let model: Model
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(model: Model, s0Builder: Instantiator<S0>) { self.model = model; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Model: Instantiable { public init() {} }

		public final class AnyScreen {
		    public init(_ screen: AnyObject) { self.screen = screen }
		    public let screen: AnyObject
		}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenCycleMemberIsBothInstantiatedErasedAndNot() async throws {
		// One screen opens another both through an `Instantiator` and erased, so the two edges call one function.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable, Screen {
		    @Instantiated let s1Builder: Instantiator<S1>
		    @Instantiated(fulfilledByType: "S1", erasedToConcreteExistential: false) let s1ErasedBuilder: ErasedInstantiator<(), any Screen>
		    public init(s1Builder: Instantiator<S1>, s1ErasedBuilder: ErasedInstantiator<(), any Screen>) { self.s1Builder = s1Builder; self.s1ErasedBuilder = s1ErasedBuilder }
		}

		@Instantiable public final class S1: Instantiable, Screen {
		    @Instantiated(fulfilledByType: "S0", erasedToConcreteExistential: false) let s0Builder: ErasedInstantiator<(), any Screen>
		    public init(s0Builder: ErasedInstantiator<(), any Screen>) { self.s0Builder = s0Builder }
		}

		public protocol Screen {}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenInitializerOnCycleDeclaresNameEscaping() async throws {
		// A screen's initializer declares a forwarded typealias of a function `@escaping`, which its function's parameter
		// spells `@escaping` too.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Forwarded let onTap: OnTap
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(onTap: @escaping OnTap, s0Builder: Instantiator<S0>) { self.onTap = onTap; self.s0Builder = s0Builder }
		}

		public typealias OnTap = () -> Void
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnNoCycleBeneathCycleDeclaresNameEscaping() async throws {
		// A screen on the cycle forwards a typealiased closure to a row on no cycle, whose initializer declares it
		// `@escaping`; the screen only passes it on, so its function takes the parameter `@escaping` from the row.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Forwarded let onTap: OnTap
		    @Instantiated let row: Row
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(onTap: @escaping OnTap, row: Row, s0Builder: Instantiator<S0>) { self.onTap = onTap; self.row = row; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Row: Instantiable {
		    @Received let onTap: OnTap
		    public init(onTap: @escaping OnTap) { self.onTap = onTap }
		}

		public typealias OnTap = () -> Void
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleReceivesNameItsCycleForwardsEscaping() async throws {
		// The screen that opens the cycle forwards a typealiased closure `@escaping`, and the screen it opens receives it
		// and declares it `@escaping` too, so every call of the cycle passes the closure on.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Forwarded let onTap: OnTap
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(onTap: @escaping OnTap, s1Builder: Instantiator<S1>) { self.onTap = onTap; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let onTap: OnTap
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(onTap: @escaping OnTap, s0Builder: Instantiator<S0>) { self.onTap = onTap; self.s0Builder = s0Builder }
		}

		public typealias OnTap = @MainActor (Int) -> Void
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTreeDeclaresLabelInTwoForms() async throws {
		// The root and a screen declare one label with two types, which nothing receives.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let leaf: Instantiator<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Instantiator<Leaf>, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenEachCycleReceivesLabelInFormOfItsOwn() async throws {
		// Two features, each a cycle, declare `state` with a type of their own, which their screens receive; each screen
		// declares `model` with a type of its own, which a panel beneath it receives.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let f0Builder: Instantiator<F0Entry>
		    @Instantiated let f1Builder: Instantiator<F1Entry>
		    public init(f0Builder: Instantiator<F0Entry>, f1Builder: Instantiator<F1Entry>) { self.f0Builder = f0Builder; self.f1Builder = f1Builder }
		}

		@Instantiable public final class F0Entry: Instantiable {
		    @Instantiated let state: F0State
		    @Instantiated let screenBuilder: Instantiator<F0Screen>
		    public init(state: F0State, screenBuilder: Instantiator<F0Screen>) { self.state = state; self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class F0Screen: Instantiable {
		    @Received let state: F0State
		    @Instantiated let model: F0Model
		    @Instantiated let panel: F0Panel
		    @Instantiated let entryBuilder: Instantiator<F0Entry>
		    public init(state: F0State, model: F0Model, panel: F0Panel, entryBuilder: Instantiator<F0Entry>) { self.state = state; self.model = model; self.panel = panel; self.entryBuilder = entryBuilder }
		}

		@Instantiable public final class F0Panel: Instantiable {
		    @Received let model: F0Model
		    public init(model: F0Model) { self.model = model }
		}

		@Instantiable public final class F1Entry: Instantiable {
		    @Instantiated let state: F1State
		    @Instantiated let screenBuilder: Instantiator<F1Screen>
		    public init(state: F1State, screenBuilder: Instantiator<F1Screen>) { self.state = state; self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class F1Screen: Instantiable {
		    @Received let state: F1State
		    @Instantiated let model: F1Model
		    @Instantiated let panel: F1Panel
		    @Instantiated let entryBuilder: Instantiator<F1Entry>
		    public init(state: F1State, model: F1Model, panel: F1Panel, entryBuilder: Instantiator<F1Entry>) { self.state = state; self.model = model; self.panel = panel; self.entryBuilder = entryBuilder }
		}

		@Instantiable public final class F1Panel: Instantiable {
		    @Received let model: F1Model
		    public init(model: F1Model) { self.model = model }
		}

		@Instantiable public final class F0State: Instantiable { public init() {} }
		@Instantiable public final class F1State: Instantiable { public init() {} }
		@Instantiable public final class F0Model: Instantiable { public init() {} }
		@Instantiable public final class F1Model: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenReceive_whenScreenOnCycleReceivesLabelAnotherPathDeclaresInOtherForm() async {
		// The plan keeps no check of a label's forms: a screen's read takes its nearest declaration's form on every path,
		// so `S1`, reached beneath the root's `state` and beneath `S0`'s, is rejected before any plan is built.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["S1.swift"]):2:5: error: @Received property `state: State` is hidden in chain: Root -> Instantiator<S1> -> Instantiator<S0> -> S1. `S0` declares `state: Instantiator<State>` with the same label, so the types below `S0` receive `state: Instantiator<State>` instead. Give `state: Instantiator<State>` on `S0` a different label to fix.
				\(fixtures["S0.swift"]):2:5: note: `state: Instantiator<State>` is declared here
				"""
			},
		) {
			try await RootTreeChoiceObservation.$scopeGeneratorLimitOverride.withValue(0) {
				try await executeSafeDIToolTest(
					swiftFileContent: [
						"""
						@Instantiable(isRoot: true) public final class Root: Instantiable {
						    @Instantiated let state: State
						    @Instantiated let s1Builder: Instantiator<S1>
						    public init(state: State, s1Builder: Instantiator<S1>) { self.state = state; self.s1Builder = s1Builder }
						}
						""",
						"""
						@Instantiable public final class S0: Instantiable {
						    @Instantiated let state: Instantiator<State>
						    @Instantiated let s1Builder: Instantiator<S1>
						    public init(state: Instantiator<State>, s1Builder: Instantiator<S1>) { self.state = state; self.s1Builder = s1Builder }
						}
						""",
						"""
						@Instantiable public final class S1: Instantiable {
						    @Received let state: State
						    @Instantiated let s0Builder: Instantiator<S0>
						    public init(state: State, s0Builder: Instantiator<S0>) { self.state = state; self.s0Builder = s0Builder }
						}
						""",
						"""
						@Instantiable public final class State: Instantiable { public init() {} }
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleRenamesInstantiatorAsAnotherType() async throws {
		// A screen renames a builder the root declares as a value of another type, which is a receive of the builder, and
		// the screen before it receives the builder by its own label.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leafBuilder: Instantiator<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leafBuilder: Instantiator<Leaf>, s0Builder: Instantiator<S0>) { self.leafBuilder = leafBuilder; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Received let leafBuilder: Instantiator<Leaf>
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(leafBuilder: Instantiator<Leaf>, s1Builder: Instantiator<S1>) { self.leafBuilder = leafBuilder; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received(fulfilledByDependencyNamed: "leafBuilder", ofType: Instantiator<Leaf>.self) let other: Any
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(other: Any, s0Builder: Instantiator<S0>) { self.other = other; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleRenamesLazilyInstantiatedAsAnotherType() async throws {
		// A screen renames a `LazilyInstantiated` the root declares as a value of another type, which is a receive of the wrapper.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: LazilyInstantiated<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: LazilyInstantiated<Leaf>, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received(fulfilledByDependencyNamed: "leaf", ofType: LazilyInstantiated<Leaf>.self) let other: Any
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(other: Any, s0Builder: Instantiator<S0>) { self.other = other; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleReceivesInstantiatorRootDeclares() async throws {
		// A screen receives an instantiator the root declares.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leafBuilder: Instantiator<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leafBuilder: Instantiator<Leaf>, s0Builder: Instantiator<S0>) { self.leafBuilder = leafBuilder; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let leafBuilder: Instantiator<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leafBuilder: Instantiator<Leaf>, s0Builder: Instantiator<S0>) { self.leafBuilder = leafBuilder; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleReceivesInstantiatorItsCycleDeclares() async throws {
		// A screen declares a builder of a row on no cycle, and the screen it opens receives that builder.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let rowBuilder: Instantiator<Row>
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(rowBuilder: Instantiator<Row>, s1Builder: Instantiator<S1>) { self.rowBuilder = rowBuilder; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let rowBuilder: Instantiator<Row>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(rowBuilder: Instantiator<Row>, s0Builder: Instantiator<S0>) { self.rowBuilder = rowBuilder; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Row: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleReceivesErasedInstantiator() async throws {
		// A screen receives an erased builder of a row the root declares.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated(fulfilledByType: "Row", erasedToConcreteExistential: false) let rowBuilder: ErasedInstantiator<(), any Rowish>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(rowBuilder: ErasedInstantiator<(), any Rowish>, s0Builder: Instantiator<S0>) { self.rowBuilder = rowBuilder; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let rowBuilder: ErasedInstantiator<(), any Rowish>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(rowBuilder: ErasedInstantiator<(), any Rowish>, s0Builder: Instantiator<S0>) { self.rowBuilder = rowBuilder; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Row: Instantiable, Rowish { public init() {} }

		public protocol Rowish {}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeOnCycleReceivesBuilderOfItsOwnCycle() async throws {
		// The root declares the builder of the first screen, and the second screen receives it to open the first again, a
		// loop of builders, whose member the layout does not make again at the call yet.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let s0Builder: Instantiator<S0>
		    @Instantiated let s2Builder: Instantiator<S2>
		    public init(s0Builder: Instantiator<S0>, s2Builder: Instantiator<S2>) { self.s0Builder = s0Builder; self.s2Builder = s2Builder }
		}

		@Instantiable public final class S2: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}
		""")

		#expect(choices == ["Root": .declaresLoopOfBuilders])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenSiblingBuildersReceiveEachOther() async throws {
		// The root declares two builders, and each one's tree receives the other's, a loop of two builders; the first is
		// on a cycle of its own.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let aBuilder: Instantiator<A>
		    @Instantiated let bBuilder: Instantiator<B>
		    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) { self.aBuilder = aBuilder; self.bBuilder = bBuilder }
		}

		@Instantiable public final class A: Instantiable {
		    @Received let bBuilder: Instantiator<B>
		    @Instantiated let cBuilder: Instantiator<C>
		    public init(bBuilder: Instantiator<B>, cBuilder: Instantiator<C>) { self.bBuilder = bBuilder; self.cBuilder = cBuilder }
		}

		@Instantiable public final class B: Instantiable {
		    @Received let aBuilder: Instantiator<A>
		    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
		}

		@Instantiable public final class C: Instantiable {
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
		}
		""")

		#expect(choices == ["Root": .declaresLoopOfBuilders])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenOneSiblingBuilderReceivesAnotherThatDoesNotReceiveIt() async throws {
		// The root declares two builders, and the first one's tree receives the second, whose tree receives nothing: no
		// loop.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let aBuilder: Instantiator<A>
		    @Instantiated let bBuilder: Instantiator<B>
		    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) { self.aBuilder = aBuilder; self.bBuilder = bBuilder }
		}

		@Instantiable public final class A: Instantiable {
		    @Received let bBuilder: Instantiator<B>
		    @Instantiated let cBuilder: Instantiator<C>
		    public init(bBuilder: Instantiator<B>, cBuilder: Instantiator<C>) { self.bBuilder = bBuilder; self.cBuilder = cBuilder }
		}

		@Instantiable public final class B: Instantiable { public init() {} }

		@Instantiable public final class C: Instantiable {
		    @Instantiated let aBuilder: Instantiator<A>
		    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
		}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleReceivesLazilyInstantiated() async throws {
		// A screen receives a `LazilyInstantiated` the root declares.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: LazilyInstantiated<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: LazilyInstantiated<Leaf>, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let leaf: LazilyInstantiated<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: LazilyInstantiated<Leaf>, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenRootAndScreenOnCycleEachHoldTypeOnNoCycleWithChildOfItsOwn() async throws {
		// The root and a screen each instantiate a type outside every cycle that instantiates a value of its own.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let box: Box
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(box: Box, s0Builder: Instantiator<S0>) { self.box = box; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let otherBox: Box
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(otherBox: Box, s0Builder: Instantiator<S0>) { self.otherBox = otherBox; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }

		@Instantiable public final class Box: Instantiable {
		    @Instantiated let leaf: Leaf
		    public init(leaf: Leaf) { self.leaf = leaf }
		}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenLayersOfScreensReceiveServiceRootDeclares() async throws {
		// Three layers of two screens, each opening the next layer's and the last opening the first's, every screen
		// receiving the root's service.
		let choices = try await choicesGeneratingTodaysCode(of: Self.layersOfScreens(layers: 3, width: 2))

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeOnCycleReceivesValueAnotherTypeDeclaresToo() async throws {
		// The root and a feature above the cycle each declare `leaf`, which a screen receives from the feature.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let feature: Feature
		    public init(leaf: Leaf, feature: Feature) { self.leaf = leaf; self.feature = feature }
		}

		@Instantiable public final class Feature: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": .receivesLabelDeclaredOutsideItsCycle])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnNoCycleIsBuiltBeneathOneCycleAndBuildsAnother() async throws {
		// `Between` is on no cycle: a screen of one cycle opens it, and it opens a screen of another, which receives a
		// value the root declares.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    @Instantiated let betweenBuilder: Instantiator<Between>
		    public init(s0Builder: Instantiator<S0>, betweenBuilder: Instantiator<Between>) { self.s0Builder = s0Builder; self.betweenBuilder = betweenBuilder }
		}

		@Instantiable public final class Between: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let leaf: Leaf
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(leaf: Leaf, s1Builder: Instantiator<S1>) { self.leaf = leaf; self.s1Builder = s1Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenScreenOnCycleOpensScreenOnNoCycleThatReceivesValueRootDeclares() async throws {
		// `Detail` is on no cycle: a screen that opens itself opens it, and its function captures the root's leaf, as the
		// screen's does.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    @Instantiated let detailBuilder: Instantiator<Detail>
		    public init(s0Builder: Instantiator<S0>, detailBuilder: Instantiator<Detail>) { self.s0Builder = s0Builder; self.detailBuilder = detailBuilder }
		}

		@Instantiable public final class Detail: Instantiable {
		    @Received let leaf: Leaf
		    public init(leaf: Leaf) { self.leaf = leaf }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenScreenOnCycleHoldsValueWithChildThatReceivesValueRootDeclares() async throws {
		// `Panel` is a value of the screen with a child of its own, and both receive the root's leaf.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    @Instantiated let panel: Panel
		    public init(s0Builder: Instantiator<S0>, panel: Panel) { self.s0Builder = s0Builder; self.panel = panel }
		}

		@Instantiable public final class Panel: Instantiable {
		    @Received let leaf: Leaf
		    @Instantiated let row: Row
		    public init(leaf: Leaf, row: Row) { self.leaf = leaf; self.row = row }
		}

		@Instantiable public final class Row: Instantiable {
		    @Received let leaf: Leaf
		    public init(leaf: Leaf) { self.leaf = leaf }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeNamedWithSendableIsHeld() async throws {
		// A type's name holds the word `Sendable`; no type of the tree is a `Sendable` wrapper or a `@Sendable` function.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let sendableThing: SendableThing
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(sendableThing: SendableThing, s0Builder: Instantiator<S0>) { self.sendableThing = sendableThing; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Received let sendableThing: SendableThing
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(sendableThing: SendableThing, s0Builder: Instantiator<S0>) { self.sendableThing = sendableThing; self.s0Builder = s0Builder }
		}

		@Instantiable public final class SendableThing: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleOpensScreenForwardedValueThatReceivesValueRootDeclares() async throws {
		// `T3` is forwarded a name and receives the root's service, which its function captures, as `T2`'s does.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let t2: T2
		    @Instantiated let service: Service
		    public init(t2: T2, service: Service) { self.t2 = t2; self.service = service }
		}

		@Instantiable public final class Service: Instantiable { public init() {} }

		@Instantiable public final class T2: Instantiable {
		    @Instantiated let t3Builder: Instantiator<T3>
		    @Instantiated let t2Builder: Instantiator<T2>
		    @Received let service: Service
		    public init(t3Builder: Instantiator<T3>, t2Builder: Instantiator<T2>, service: Service) { self.t3Builder = t3Builder; self.t2Builder = t2Builder; self.service = service }
		}

		@Instantiable public final class T3: Instantiable {
		    @Forwarded let name: String
		    @Received let service: Service
		    public init(name: String, service: Service) { self.name = name; self.service = service }
		}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTreePastTheLimitReachesNoCycle() async throws {
		// No type of the tree is built again, so there is nothing to plan and nothing to report.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(leaf: Leaf, screenBuilder: Instantiator<Screen>) { self.leaf = leaf; self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class Screen: Instantiable {
		    @Received let leaf: Leaf
		    public init(leaf: Leaf) { self.leaf = leaf }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == [:])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTreePastTheLimitHoldsFewPlacesForEachTypeItReaches() async throws {
		// A root of 4,000 services beside one screen that opens itself: its tree passes the limit the tool ships with
		// and reaches a cycle, but holds each type once or twice, so it does not grow with its paths. No plan is asked
		// for, so none is reported.
		let services = 0..<4_000
		let properties = services.map { "    @Instantiated let service\($0): Service\($0)" }.joined(separator: "\n")
		let parameters = services.map { "service\($0): Service\($0)" }.joined(separator: ", ")
		let assignments = services.map { "self.service\($0) = service\($0)" }.joined(separator: "; ")
		let declarations = services.map { "@Instantiable public final class Service\($0): Instantiable { public init() {} }" }.joined(separator: "\n")
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		\(properties)
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(\(parameters), screenBuilder: Instantiator<Screen>) { \(assignments); self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class Screen: Instantiable {
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
		}

		\(declarations)
		""", abandoningTodaysTreePast: nil, comparingWithTreesWithin: .max, skipCompileVerification: true)

		// The generated initializer takes 4,000 arguments, which the compiler takes minutes over; the code is compared
		// with the code of a run that keeps every tree.
		#expect(choices == [:])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsEveryRootOnTodaysTree_whenTreesAreWithinTheLimit() async throws {
		// Under the limit the tool ships with, no root is asked for a plan, so none is reported.
		let choices = try await choicesGeneratingTodaysCode(of: Self.layersOfScreens(layers: 2, width: 2), abandoningTodaysTreePast: nil)

		#expect(choices == [:])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenItsTreePassesTheLimitTheToolShipsWith() async throws {
		// Layers of screens whose tree per path holds more places than the limit, generated with no limit set by the test,
		// then with every tree kept per path.
		let choices = try await choicesGeneratingTodaysCode(of: Self.layersOfScreens(layers: 4, width: 3), abandoningTodaysTreePast: nil, comparingWithTreesWithin: .max)

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTodaysFirstError_whenPlanningRootPastTheLimitThrowsAnother() async {
		// Today's tree builds `S0`'s children before the root's second, so it reports `xBuilder`; the plan builds the
		// root's own body first, and would report `yBuilder`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["S0.swift"]):5:5: error: The first generic argument of `xBuilder: ErasedInstantiator<Int, AnyX>` on `S0` must be the @Forwarded properties of `X`, which it builds. Declare it as `ErasedInstantiator<String, AnyX>`.
				"""
			},
		) {
			try await RootTreeChoiceObservation.$scopeGeneratorLimitOverride.withValue(0) {
				try await executeSafeDIToolTest(
					swiftFileContent: [
						"""
						@Instantiable(isRoot: true)
						public final class Root: Instantiable {
						    public init(s0Builder: Instantiator<S0>, yBuilder: ErasedInstantiator<Int, AnyX>) { self.s0Builder = s0Builder; self.yBuilder = yBuilder }
						    @Instantiated let s0Builder: Instantiator<S0>
						    @Instantiated(fulfilledByType: "Y", erasedToConcreteExistential: true) let yBuilder: ErasedInstantiator<Int, AnyX>
						}
						""",
						"""
						@Instantiable
						public final class S0: Instantiable {
						    public init(s0Builder: Instantiator<S0>, xBuilder: ErasedInstantiator<Int, AnyX>) { self.s0Builder = s0Builder; self.xBuilder = xBuilder }
						    @Instantiated let s0Builder: Instantiator<S0>
						    @Instantiated(fulfilledByType: "X", erasedToConcreteExistential: true) let xBuilder: ErasedInstantiator<Int, AnyX>
						}
						""",
						"""
						public protocol XProtocol {}
						public final class AnyX: XProtocol { public init(_ x: some XProtocol) {} }

						@Instantiable
						public final class X: XProtocol, Instantiable {
						    public init(name: String) { self.name = name }
						    @Forwarded let name: String
						}
						""",
						"""
						@Instantiable
						public final class Y: XProtocol, Instantiable {
						    public init(name: String) { self.name = name }
						    @Forwarded let name: String
						}
						""",
					],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysParameterOrder_whenScreenClosesCycleOnItselfBeforeOthers() async throws {
		// S3 opens itself before S0 and S2, whose functions take `x` and `y`: a function takes them in the order its body
		// first receives them, never in the order a call of its own function passes them.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    @Instantiated let y: Y
		    @Instantiated let x: X
		    public init(s1Builder: Instantiator<S1>, y: Y, x: X) { self.s1Builder = s1Builder; self.y = y; self.x = x }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let x: X
		    @Instantiated let s2Builder: Instantiator<S2>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(x: X, s2Builder: Instantiator<S2>, s0Builder: Instantiator<S0>) { self.x = x; self.s2Builder = s2Builder; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S2: Instantiable {
		    @Instantiated let s3Builder: Instantiator<S3>
		    @Instantiated let s1Builder: Instantiator<S1>
		    @Received let y: Y
		    public init(s3Builder: Instantiator<S3>, s1Builder: Instantiator<S1>, y: Y) { self.s3Builder = s3Builder; self.s1Builder = s1Builder; self.y = y }
		}

		@Instantiable public final class S3: Instantiable {
		    @Instantiated let s3Builder: Instantiator<S3>
		    @Instantiated let s0Builder: Instantiator<S0>
		    @Instantiated let s2Builder: Instantiator<S2>
		    public init(s3Builder: Instantiator<S3>, s0Builder: Instantiator<S0>, s2Builder: Instantiator<S2>) { self.s3Builder = s3Builder; self.s0Builder = s0Builder; self.s2Builder = s2Builder }
		}

		@Instantiable public final class X: Instantiable { public init() {} }

		@Instantiable public final class Y: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysParameterOrder_whenInitializerTakesReceivesInOtherOrderThanDeclared() async throws {
		// S2 declares `x` before `y` and its initializer takes `y` first: S1's and S2's functions take them in declaration
		// order, as today's do.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let x: X
		    @Instantiated let y: Y
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(x: X, y: Y, s1Builder: Instantiator<S1>) { self.x = x; self.y = y; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let s2Builder: Instantiator<S2>
		    public init(s2Builder: Instantiator<S2>) { self.s2Builder = s2Builder }
		}

		@Instantiable public final class S2: Instantiable {
		    @Received let x: X
		    @Received let y: Y
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(y: Y, x: X, s0Builder: Instantiator<S0>) { self.y = y; self.x = x; self.s0Builder = s0Builder }
		}

		@Instantiable public final class X: Instantiable { public init() {} }

		@Instantiable public final class Y: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTwoScreensOnCycleEachOpenTypeOnNoCycleWithChildOfItsOwn() async throws {
		// Two screens of one cycle each hold an instantiator of a type on no cycle that instantiates a value of its own.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let boxBuilder: Instantiator<Box>
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(boxBuilder: Instantiator<Box>, s1Builder: Instantiator<S1>) { self.boxBuilder = boxBuilder; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let boxBuilder: Instantiator<Box>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(boxBuilder: Instantiator<Box>, s0Builder: Instantiator<S0>) { self.boxBuilder = boxBuilder; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }

		@Instantiable public final class Box: Instantiable {
		    @Instantiated let leaf: Leaf
		    public init(leaf: Leaf) { self.leaf = leaf }
		}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnNoCycleBuiltTwiceHoldsChildThatReceivesValueEachPlaceDeclares() async throws {
		// The root and two screens of a cycle each hold a type on no cycle whose child receives a value the root and a screen declare.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let token: Token
		    @Instantiated let box: Box
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(token: Token, box: Box, s0Builder: Instantiator<S0>) { self.token = token; self.box = box; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let token: Token
		    @Instantiated let box: Box
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(token: Token, box: Box, s1Builder: Instantiator<S1>) { self.token = token; self.box = box; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let otherBox: Box
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(otherBox: Box, s0Builder: Instantiator<S0>) { self.otherBox = otherBox; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Token: Instantiable { public init() {} }

		@Instantiable public final class Leaf: Instantiable {
		    @Received let token: Token
		    public init(token: Token) { self.token = token }
		}

		@Instantiable public final class Box: Instantiable {
		    @Instantiated let leaf: Leaf
		    public init(leaf: Leaf) { self.leaf = leaf }
		}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTwoTypesOnNoCycleEachHoldTypeWithChildrenBesideCycle() async throws {
		// Two types on no cycle each hold a type that instantiates a chain of its own, beside a cycle of screens.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let first: First
		    @Instantiated let second: Second
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(first: First, second: Second, s0Builder: Instantiator<S0>) { self.first = first; self.second = second; self.s0Builder = s0Builder }
		}

		@Instantiable public final class First: Instantiable {
		    @Instantiated let box: Box
		    public init(box: Box) { self.box = box }
		}

		@Instantiable public final class Second: Instantiable {
		    @Instantiated let boxBuilder: Instantiator<Box>
		    public init(boxBuilder: Instantiator<Box>) { self.boxBuilder = boxBuilder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }

		@Instantiable public final class Middle: Instantiable {
		    @Instantiated let leaf: Leaf
		    public init(leaf: Leaf) { self.leaf = leaf }
		}

		@Instantiable public final class Box: Instantiable {
		    @Instantiated let middle: Middle
		    public init(middle: Middle) { self.middle = middle }
		}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnNoCycleThatOpensCycleIsBuiltTwice() async throws {
		// The root holds two values of a type on no cycle that opens a cycle of screens.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let firstBox: Box
		    @Instantiated let secondBox: Box
		    public init(firstBox: Box, secondBox: Box) { self.firstBox = firstBox; self.secondBox = secondBox }
		}

		@Instantiable public final class Box: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}
		""")

		#expect(choices == ["Root": nil])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `layers` layers of `width` screens: each screen receives the root's service and opens every screen of the next
	/// layer, and the last layer's open the first's.
	private static func layersOfScreens(layers: Int, width: Int) -> String {
		var declarations = ["""
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let service: Service
		    @Instantiated let home: S0_0
		    public init(service: Service, home: S0_0) { self.service = service; self.home = home }
		}

		@Instantiable public final class Service: Instantiable { public init() {} }
		"""]
		for layer in 0..<layers {
			for screen in 0..<width {
				let next = (layer + 1) % layers
				let builders = (0..<width).map { "s\(next)_\($0)Builder" }
				let types = (0..<width).map { "S\(next)_\($0)" }
				let properties = zip(builders, types).map { "    @Instantiated let \($0): Instantiator<\($1)>" }.joined(separator: "\n")
				let parameters = zip(builders, types).map { "\($0): Instantiator<\($1)>" }.joined(separator: ", ")
				let assignments = builders.map { "self.\($0) = \($0)" }.joined(separator: "; ")
				declarations.append("""
				@Instantiable public final class S\(layer)_\(screen): Instantiable {
				    @Received let service: Service
				\(properties)
				    public init(service: Service, \(parameters)) { self.service = service; \(assignments) }
				}
				""")
			}
		}
		return declarations.joined(separator: "\n\n")
	}

	/// `Root`, which builds `T0` before and after `lazyT4`, and `T0`'s `T1`, which receives `lazyT4` only if available in a
	/// `@Sendable` function.
	private static let twoBuildsHandingNilAndNonSendableWrapper = [
		"""
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let lazyT4: LazilyInstantiated<T4>
		    @Instantiated let t0Builder: Instantiator<T0>
		    @Instantiated(fulfilledByType: "T0", erasedToConcreteExistential: true) let anyT0Builder: SendableErasedInstantiator<(), AnyT0>
		    public init(lazyT4: LazilyInstantiated<T4>, t0Builder: Instantiator<T0>, anyT0Builder: SendableErasedInstantiator<(), AnyT0>) { self.lazyT4 = lazyT4; self.t0Builder = t0Builder; self.anyT0Builder = anyT0Builder }
		}
		""",
		"""
		@Instantiable public final class T0: Instantiable, @unchecked Sendable {
		    @Instantiated(fulfilledByType: "T1", erasedToConcreteExistential: true) let anyT1Builder: SendableErasedInstantiator<(), AnyT1>
		    public init(anyT1Builder: SendableErasedInstantiator<(), AnyT1>) { self.anyT1Builder = anyT1Builder }
		}
		public final class AnyT0: Sendable {
		    public init(_ value: T0) { self.value = value }
		    public let value: T0
		}
		""",
		"""
		@Instantiable public final class T1: Instantiable, @unchecked Sendable {
		    @Received(onlyIfAvailable: true) let lazyT4: LazilyInstantiated<T4>?
		    public init(lazyT4: LazilyInstantiated<T4>?) { self.lazyT4 = lazyT4 }
		}
		public final class AnyT1: Sendable {
		    public init(_ value: T1) { self.value = value }
		    public let value: T1
		}
		""",
		"""
		@Instantiable public final class T4: Instantiable, @unchecked Sendable {
		    @Received let anyT0Builder: SendableErasedInstantiator<(), AnyT0>
		    public init(anyT0Builder: SendableErasedInstantiator<(), AnyT0>) { self.anyT0Builder = anyT0Builder }
		}
		""",
	]

	/// The capture `twoBuildsHandingNilAndNonSendableWrapper` makes through `t0Builder`'s `T0`.
	private static func twoBuildsCaptureDiagnostics(_ fixtures: FixturePaths) -> String {
		"""
		\(fixtures["T1.swift"]):2:5: error: @Received property `lazyT4: LazilyInstantiated<T4>?` cannot be received inside a `@Sendable` function in chain: Root -> T0 -> T1. SafeDI builds `anyT1Builder: SendableErasedInstantiator<(), AnyT1>` on `T0` in a `@Sendable` function, which cannot capture `lazyT4: LazilyInstantiated<T4>` on `Root`, because `LazilyInstantiated<T4>` is not `Sendable`. Declare `lazyT4` on `Root`, and this property, as `SendableLazilyInstantiated<T4>` to fix. A `SendableLazilyInstantiated` requires its instance type, `T4`, to be `Sendable`.
		\(fixtures["Root.swift"]):2:5: note: `lazyT4: LazilyInstantiated<T4>` is declared here
		"""
	}

	/// `Root`, which builds `T0` through `anyT0Builder` beside `rootDeclares`, and `X`, which builds it through `t0Builder`
	/// beneath its `t4: LazilyInstantiated<T4>`; `T0` builds `T1`, which `t1Receives`, in a `@Sendable` function, and `T1`
	/// is on a cycle through `T5`.
	private static func twoCallsOfVariantOnCycle(t1Receives: String, rootDeclares: String?) -> [String] {
		let t1Initializer = t1Receives.hasSuffix("?") ? "t4: LazilyInstantiated<T4>?" : "t4: T4"
		let rootDeclarations = rootDeclares.map { "\n    \($0)" } ?? ""
		let rootParameters = rootDeclares == nil ? "" : ", t4: T4"
		let rootAssignments = rootDeclares == nil ? "" : "; self.t4 = t4"
		return [
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated(fulfilledByType: "T0", erasedToConcreteExistential: true) let anyT0Builder: SendableErasedInstantiator<(), AnyT0>
			    @Instantiated let x: X\(rootDeclarations)
			    public init(anyT0Builder: SendableErasedInstantiator<(), AnyT0>, x: X\(rootParameters)) { self.anyT0Builder = anyT0Builder; self.x = x\(rootAssignments) }
			}
			""",
			"""
			@Instantiable public final class X: Instantiable {
			    @Instantiated let t4: LazilyInstantiated<T4>
			    @Instantiated let t0Builder: Instantiator<T0>
			    public init(t4: LazilyInstantiated<T4>, t0Builder: Instantiator<T0>) { self.t4 = t4; self.t0Builder = t0Builder }
			}
			""",
			"""
			@Instantiable public final class T0: Instantiable, @unchecked Sendable {
			    @Instantiated(fulfilledByType: "T1", erasedToConcreteExistential: true) let anyT1Builder: SendableErasedInstantiator<(), AnyT1>
			    public init(anyT1Builder: SendableErasedInstantiator<(), AnyT1>) { self.anyT1Builder = anyT1Builder }
			}
			public final class AnyT0: Sendable {
			    public init(_ value: T0) { self.value = value }
			    public let value: T0
			}
			""",
			"""
			@Instantiable public final class T1: Instantiable, @unchecked Sendable {
			    \(t1Receives)
			    @Instantiated let t5Builder: Instantiator<T5>
			    public init(\(t1Initializer), t5Builder: Instantiator<T5>) { self.t4 = t4; self.t5Builder = t5Builder }
			}
			public final class AnyT1: Sendable {
			    public init(_ value: T1) { self.value = value }
			    public let value: T1
			}
			""",
			"""
			@Instantiable public final class T5: Instantiable, @unchecked Sendable {
			    @Instantiated let t1Builder: Instantiator<T1>
			    public init(t1Builder: Instantiator<T1>) { self.t1Builder = t1Builder }
			}
			""",
			"""
			@Instantiable public final class T4: Instantiable, @unchecked Sendable { public init() {} }
			""",
		]
	}

	/// Why each root of `swiftFileContent` that reaches a cycle is kept on today's tree, `nil` for one laid out from its
	/// plan, where every root's tree per path is abandoned at once. Records an issue unless that run, and a run with every
	/// root kept on today's tree, each report `diagnostics`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func choicesThrowingTodaysError(
		of swiftFileContent: [String],
		diagnostics: @escaping (_ fixtures: FixturePaths) -> String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async -> [String: RootTreeChoiceObservation.PerPathReason?] {
		let (stream, continuation) = AsyncStream.makeStream(of: (String, RootTreeChoiceObservation.PerPathReason?).self)
		await RootTreeChoiceObservation.$scopeGeneratorLimitOverride.withValue(0) {
			await RootTreeChoiceObservation.$observer.withValue(TaskLocalFunction { root, perPathReason in
				continuation.yield((root, perPathReason))
			}) {
				await assertThrowsError(diagnostics: diagnostics, sourceLocation: sourceLocation) {
					try await executeSafeDIToolTest(
						swiftFileContent: swiftFileContent,
						buildSwiftOutputDirectory: true,
						filesToDelete: &filesToDelete,
					)
				}
			}
		}
		continuation.finish()
		var choices = [String: RootTreeChoiceObservation.PerPathReason?]()
		for await (root, perPathReason) in stream {
			choices[root] = perPathReason
		}
		await assertThrowsError(diagnostics: diagnostics, sourceLocation: sourceLocation) {
			try await executeSafeDIToolTest(
				swiftFileContent: swiftFileContent,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		return choices
	}

	/// The files generated from `swiftFileContent` with the limit at 0, compiled in a module whose declarations default to
	/// `defaultIsolation` (`nil` for none), and why each root that reaches a cycle is kept on today's tree, `nil` for one laid
	/// out from its plan. Records an issue where the files equal those generated with every root kept on today's tree: a
	/// test of this helper pins a stated change in generated code.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func planCodeDifferingFromTodays(
		of swiftFileContent: String,
		defaultIsolation: String?,
	) async throws -> (choices: [String: RootTreeChoiceObservation.PerPathReason?], files: [String: String]) {
		let (stream, continuation) = AsyncStream.makeStream(of: (String, RootTreeChoiceObservation.PerPathReason?).self)
		let output = try await RootTreeChoiceObservation.$scopeGeneratorLimitOverride.withValue(0) {
			try await RootTreeChoiceObservation.$observer.withValue(TaskLocalFunction { root, perPathReason in
				continuation.yield((root, perPathReason))
			}) {
				try await executeSafeDIToolTest(
					swiftFileContent: [swiftFileContent],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
					verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: defaultIsolation),
				)
			}
		}
		continuation.finish()
		var choices = [String: RootTreeChoiceObservation.PerPathReason?]()
		for await (root, perPathReason) in stream {
			choices[root] = perPathReason
		}
		let todaysOutput = try await executeSafeDIToolTest(
			swiftFileContent: [swiftFileContent],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: defaultIsolation),
		)
		#expect(output.dependencyTreeFiles != todaysOutput.dependencyTreeFiles)
		return (choices, output.dependencyTreeFiles)
	}

	/// Why each root of `swiftFileContent` that reaches a cycle is kept on today's tree, `nil` for one laid out from its
	/// plan. Records an issue where the files generated differ from those generated with every root kept on today's tree.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func choicesGeneratingTodaysCode(
		of swiftFileContent: String,
		abandoningTodaysTreePast scopeGeneratorLimit: Int? = 0,
		comparingWithTreesWithin todaysScopeGeneratorLimit: Int? = nil,
		skipCompileVerification: Bool = false,
	) async throws -> [String: RootTreeChoiceObservation.PerPathReason?] {
		try await choicesAndFilesGeneratingTodaysCode(
			of: swiftFileContent,
			abandoningTodaysTreePast: scopeGeneratorLimit,
			comparingWithTreesWithin: todaysScopeGeneratorLimit,
			skipCompileVerification: skipCompileVerification,
		).choices
	}

	/// `choicesGeneratingTodaysCode(of:)`'s choices, with the dependency tree files generated past the limit, by file name.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func choicesAndFilesGeneratingTodaysCode(
		of swiftFileContent: String,
		abandoningTodaysTreePast scopeGeneratorLimit: Int? = 0,
		comparingWithTreesWithin todaysScopeGeneratorLimit: Int? = nil,
		skipCompileVerification: Bool = false,
	) async throws -> (choices: [String: RootTreeChoiceObservation.PerPathReason?], files: [String: String]) {
		let (stream, continuation) = AsyncStream.makeStream(of: (String, RootTreeChoiceObservation.PerPathReason?).self)
		// With no place allowed, every root's tree per path is abandoned at once, so each root is laid out from its plan
		// wherever a root past the limit would be. `nil` leaves the limit the tool ships with.
		let output = try await RootTreeChoiceObservation.$scopeGeneratorLimitOverride.withValue(scopeGeneratorLimit) {
			try await RootTreeChoiceObservation.$observer.withValue(TaskLocalFunction { root, perPathReason in
				continuation.yield((root, perPathReason))
			}) {
				try await executeSafeDIToolTest(
					swiftFileContent: [swiftFileContent],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
					skipCompileVerification: skipCompileVerification,
				)
			}
		}
		continuation.finish()
		var choices = [String: RootTreeChoiceObservation.PerPathReason?]()
		for await (root, perPathReason) in stream {
			choices[root] = perPathReason
		}
		// Within the limit, every root keeps its tree per path.
		let todaysOutput = try await RootTreeChoiceObservation.$scopeGeneratorLimitOverride.withValue(todaysScopeGeneratorLimit) {
			try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: skipCompileVerification,
			)
		}
		#expect(output.dependencyTreeFiles == todaysOutput.dependencyTreeFiles)
		return (choices, output.dependencyTreeFiles)
	}
}
