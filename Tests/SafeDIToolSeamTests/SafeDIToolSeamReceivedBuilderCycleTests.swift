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

/// Loops of instantiators that receive one another, where a seam is on the loop or holds one: the caller passes a seam the
/// rebinding its loop member's function makes, a seam's own tree rebinds a loop it declares, and a hole's site inside a loop
/// member's function carries that function's rebindings. A hole's implementation cannot receive an instantiator the seam's
/// tree is building, since the seam's module cannot see what the implementation receives.
struct SafeDIToolSeamReceivedBuilderCycleTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: The caller's loop

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesSeamTheRebinding_whenSeamReceivesInstantiatorOnlyIfAvailableInsideCallersLoop() async throws {
		// `Root` declares `screenABuilder` and `screenBBuilder`. `ScreenB` requires `screenABuilder`, and `Detail`, in the
		// tree of `ScreenA`, a seam, receives `screenBBuilder` only if available: the two instantiators are a loop, so the
		// call of `ScreenA` inside `screenABuilder`'s function passes the wrapper that function makes again of
		// `screenBBuilder`'s, where it passed `nil` before.
		let feature = [
			seamFixtureType(named: "Detail", declarations: ["@Received(onlyIfAvailable: true) let screenBBuilder: Instantiator<ScreenB>?"]),
			seamFixtureType(named: "ScreenA", isSeam: true, declarations: ["@Instantiated let detail: Detail"]),
			seamFixtureType(named: "ScreenB", declarations: ["@Received let screenABuilder: Instantiator<ScreenA>"]),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screenABuilder: Instantiator<ScreenA>", "@Instantiated let screenBBuilder: Instantiator<ScreenB>"])
		let modules = Self.modules(feature: feature, app: [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_screenABuilder() -> ScreenA {
		            let screenBBuilder = Instantiator<ScreenB>(__safeDI_screenBBuilder)
		            _ = ScreenA.__safeDI_ScreenA_965B4443E5BE6EBC.self\(Self.callComment(module: "Feature"))
		            return ScreenA(__safeDI_screenBBuilder: screenBBuilder)
		        }
		        let screenABuilder = Instantiator<ScreenA>(__safeDI_screenABuilder)
		        func __safeDI_screenBBuilder() -> ScreenB {
		            let screenABuilder = Instantiator<ScreenA>(__safeDI_screenABuilder)
		            return ScreenB(screenABuilder: screenABuilder)
		        }
		        let screenBBuilder = Instantiator<ScreenB>(__safeDI_screenBBuilder)
		        self.init(screenABuilder: screenABuilder, screenBBuilder: screenBBuilder)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: inlineFixture(feature), app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().screenABuilder.instantiate().detail.screenBBuilder?.instantiate()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fillReadsCallersRebinding_whenFillReceivesInstantiatorOfCallersLoop() async throws {
		// `DefaultWidget`, which fills `ScreenA`'s `widget`, receives `screenBBuilder`, and `ScreenB` requires
		// `screenABuilder`: inline, the two instantiators of `Root` are a loop. The fill is declared inside
		// `screenABuilder`'s function, so it reads the wrapper that function makes again of `screenBBuilder`'s by name.
		let feature = [
			"public protocol Widget {}",
			seamFixtureType(named: "ScreenA", isSeam: true, declarations: ["@Instantiated let widget: any Widget"]),
			seamFixtureType(named: "ScreenB", declarations: ["@Received let screenABuilder: Instantiator<ScreenA>"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received let screenBBuilder: Instantiator<ScreenB>"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screenABuilder: Instantiator<ScreenA>", "@Instantiated let screenBBuilder: Instantiator<ScreenB>"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_screenABuilder() -> ScreenA {
		            let screenBBuilder = Instantiator<ScreenB>(__safeDI_screenBBuilder)
		            _ = ScreenA.__safeDI_ScreenA_A0792761FA8A7C8E.self\(Self.callComment(module: "Feature"))
		            func __safeDI_widgetBuilder_ScreenA(_ scope: ScreenA.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case .widget:
		                    let widget: any Widget = DefaultWidget(screenBBuilder: screenBBuilder)
		                    return widget
		                }
		            }
		            return ScreenA(__safeDI_widgetBuilder: __safeDI_widgetBuilder_ScreenA)
		        }
		        let screenABuilder = Instantiator<ScreenA>(__safeDI_screenABuilder)
		        func __safeDI_screenBBuilder() -> ScreenB {
		            let screenABuilder = Instantiator<ScreenA>(__safeDI_screenABuilder)
		            return ScreenB(screenABuilder: screenABuilder)
		        }
		        let screenBBuilder = Instantiator<ScreenB>(__safeDI_screenBBuilder)
		        self.init(screenABuilder: screenABuilder, screenBBuilder: screenBBuilder)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: inlineFixture(feature + fulfillers), app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().screenABuilder.instantiate().widget"),
		])
	}

	// MARK: A loop inside a seam's tree

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsLoopInSeamsInitializer_whenSeamDeclaresInstantiatorsThatReceiveEachOther() async throws {
		// `Flow`, a seam, declares `aBuilder` and `bBuilder`, whose types receive each other: the initializer `Feature`
		// generates for `Flow` rebinds each in the other's function, as a root's `init()` would.
		let feature = [
			seamFixtureType(named: "A", declarations: ["@Received let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Received let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let flow: Flow"])
		let modules = Self.modules(feature: feature, app: [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", imports: [], rootFiles: ["Flow": """
		extension Flow {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        func __safeDI_aBuilder() -> A {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            return A(bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        func __safeDI_bBuilder() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            return B(aBuilder: aBuilder)
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
		    }
		}

		extension Flow {
		    public enum __safeDI_Flow_CBF29CE484222325 {}
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: inlineFixture(feature), app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().flow.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesReceivedFunctionApart_whenSeamTakesDeferredParameterOfItsName() async throws {
		// `Other`, in `Flow`'s tree, receives `screenBuilder_received` from `Flow`'s caller, so `Flow`'s initializer binds the
		// deferred parameter `__safeDI_screenBuilder_received`, which the function every wrapper of `screenBuilder` hands
		// would hide in the initializer's body: that function takes another name.
		let feature = [
			seamFixtureType(named: "Session", declarations: []),
			seamFixtureType(named: "Thing", declarations: []),
			seamFixtureType(named: "Other", declarations: ["@Received let screenBuilder_received: Thing"]),
			seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"]),
			seamFixtureType(named: "Detail", declarations: ["@Received let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Step", declarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"]),
			seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let other: Other"]),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screenBuilder_received: Thing", "@Instantiated let flow: Flow"])
		let modules = Self.modules(feature: feature, app: [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", imports: [], rootFiles: ["Flow": """
		extension Flow {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_screenBuilder_received: @autoclosure @escaping () -> Thing) {
		        let screenBuilder_received = LazilyInstantiated<Thing>(__safeDI_screenBuilder_received)
		        let session = Session()
		        func __safeDI_screenBuilder(session: Session) -> Screen {
		            let screenBuilder = Instantiator<Screen> {
		                __safeDI_screenBuilder(session: session)
		            }
		            func __safeDI_stepBuilder() -> Step {
		                let session = Session()
		                let screenBuilder = Instantiator<Screen> {
		                    __safeDI_screenBuilder(session: session)
		                }
		                return Step(session: session, screenBuilder: screenBuilder)
		            }
		            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
		            let detail = Detail(screenBuilder: screenBuilder)
		            return Screen(session: session, stepBuilder: stepBuilder, detail: detail)
		        }
		        func __safeDI_screenBuilder_received_() -> Screen {
		            __safeDI_screenBuilder(session: session)
		        }
		        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received_)
		        let other = Other(screenBuilder_received: screenBuilder_received.instance)
		        self.init(session: session, screenBuilder: screenBuilder, other: other)
		    }
		}

		extension Flow {
		    public enum __safeDI_Flow_F559CB2F60F73CA3 {}
		}
		"""]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        let screenBuilder_received = Thing()
		        func __safeDI_flow() -> Flow {
		            _ = Flow.__safeDI_Flow_F559CB2F60F73CA3.self\(Self.callComment(module: "Feature"))
		            return Flow(__safeDI_screenBuilder_received: screenBuilder_received)
		        }
		        let flow: Flow = __safeDI_flow()
		        self.init(screenBuilder_received: screenBuilder_received, flow: flow)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: inlineFixture(feature), app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().flow.screenBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesRebindingInHolesScope_whenHoleIsBuiltInsideLoopMembersFunction() async throws {
		// `A`'s `widget` is a hole, built inside `aBuilder`'s function, which begins by wrapping `bBuilder`'s function again
		// since `A` receives `bBuilder`. That wrapper is the nearest declaration of `bBuilder` at the hole, so the scope the
		// builder is handed carries it, and `DefaultWidget`, which fills the builder and receives `bBuilder`, reads it there.
		let feature = [
			"public protocol Widget {}",
			seamFixtureType(named: "A", declarations: ["@Received let bBuilder: Instantiator<B>", "@Instantiated let widget: any Widget"]),
			seamFixtureType(named: "B", declarations: ["@Received let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received let bBuilder: Instantiator<B>"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let flow: Flow"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", imports: [], rootFiles: ["Flow": """
		extension Flow {
		    @frozen public enum SafeDIScope_Widget {
		        case aBuilder(aBuilder_Values, SafeDIScope_Widget.A_Scope)

		        public struct aBuilder_Values {}

		        @frozen public enum A_Scope {
		            case widget(widget_Values)

		            public struct widget_Values {
		                public let bBuilder: Instantiator<B>
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_widgetBuilder: @escaping (SafeDIScope_Widget) -> any Widget) {
		        let __safeDI_widgetValues_aBuilder = SafeDIScope_Widget.aBuilder_Values()
		        func __safeDI_aBuilder() -> A {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            let widget: any Widget = __safeDI_widgetBuilder(.aBuilder(__safeDI_widgetValues_aBuilder, .widget(SafeDIScope_Widget.A_Scope.widget_Values(bBuilder: bBuilder))))
		            return A(bBuilder: bBuilder, widget: widget)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        func __safeDI_bBuilder() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            return B(aBuilder: aBuilder)
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
		    }
		}

		extension Flow {
		    public enum __safeDI_Flow_9367E336398C16B0 {}
		}
		"""]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_flow() -> Flow {
		            _ = Flow.__safeDI_Flow_9367E336398C16B0.self\(Self.callComment(module: "Feature"))
		            func __safeDI_widgetBuilder_Flow(_ scope: Flow.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .aBuilder(_, scope): return __safeDI_widgetBuilder_Flow_A_Scope(scope)
		                }
		            }
		            func __safeDI_widgetBuilder_Flow_A_Scope(_ scope: Flow.SafeDIScope_Widget.A_Scope) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let bBuilder = scope.bBuilder
		                    let widget: any Widget = DefaultWidget(bBuilder: bBuilder)
		                    return widget
		                }
		            }
		            return Flow(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Flow)
		        }
		        let flow: Flow = __safeDI_flow()
		        self.init(flow: flow)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: inlineFixture(feature + fulfillers), app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().flow.aBuilder.instantiate().widget"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesRebindingInHolesSendableScope_whenHoleIsBuiltInsideSendableLoopMembersFunction() async throws {
		// The loop above with `SendableInstantiator`s: `aBuilder`'s function is `@Sendable`, so `widget` is a case of the
		// `@Sendable` enum, and `A`'s level carries the wrapper the function makes again of `bBuilder`'s function.
		let feature = [
			"public protocol Widget: Sendable {}",
			seamFixtureType(named: "A", declarations: ["@Received let bBuilder: SendableInstantiator<B>", "@Instantiated let widget: any Widget"], conformances: ", Sendable"),
			seamFixtureType(named: "B", declarations: ["@Received let aBuilder: SendableInstantiator<A>"], conformances: ", Sendable"),
			seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let aBuilder: SendableInstantiator<A>", "@Instantiated let bBuilder: SendableInstantiator<B>"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received let bBuilder: SendableInstantiator<B>"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let flow: Flow"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", imports: [], rootFiles: ["Flow": """
		extension Flow {
		    @frozen public enum SafeDIScope_Widget {
		        @frozen public enum A_Scope {
		            case widget(widget_Values)

		            public struct widget_Values {
		                public let bBuilder: SendableInstantiator<B>
		            }
		        }
		    }

		    @frozen public enum SafeDISendableScope_Widget {
		        case aBuilder(SafeDIScope_Widget.A_Scope)
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_widgetSendableBuilder: @escaping @Sendable (SafeDISendableScope_Widget) -> any Widget) {
		        @Sendable func __safeDI_aBuilder() -> A {
		            let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
		            let widget: any Widget = __safeDI_widgetSendableBuilder(.aBuilder(.widget(SafeDIScope_Widget.A_Scope.widget_Values(bBuilder: bBuilder))))
		            return A(bBuilder: bBuilder, widget: widget)
		        }
		        let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
		        @Sendable func __safeDI_bBuilder() -> B {
		            let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
		            return B(aBuilder: aBuilder)
		        }
		        let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
		        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
		    }
		}

		extension Flow {
		    public enum __safeDI_Flow_05DBCEB3CE79CFA6 {}
		}
		"""]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_flow() -> Flow {
		            _ = Flow.__safeDI_Flow_05DBCEB3CE79CFA6.self\(Self.callComment(module: "Feature"))
		            @Sendable func __safeDI_widgetSendableBuilder_Flow(_ scope: Flow.SafeDISendableScope_Widget) -> any Widget {
		                switch scope {
		                case let .aBuilder(scope): return __safeDI_widgetBuilder_Flow_A_Scope(scope)
		                }
		            }
		            @Sendable func __safeDI_widgetBuilder_Flow_A_Scope(_ scope: Flow.SafeDIScope_Widget.A_Scope) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let bBuilder = scope.bBuilder
		                    let widget: any Widget = DefaultWidget(bBuilder: bBuilder)
		                    return widget
		                }
		            }
		            return Flow(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Flow)
		        }
		        let flow: Flow = __safeDI_flow()
		        self.init(flow: flow)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: inlineFixture(feature + fulfillers), app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().flow.aBuilder.instantiate().widget"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesRebindingInHolesScope_whenLoopMemberIsInsideFunctionACycleClosesOn() async throws {
		// `A` builds `X` again, so a cycle closes on `xBuilder`'s function, and `P`, between that function and `A`, declares
		// the loop of `aBuilder` and `bBuilder`. `A`'s `widget` is a hole inside `aBuilder`'s function, whose wrapper of
		// `bBuilder`'s function is made again at each level of the cycle, as inline makes it, so `DefaultWidget`, which
		// fills the builder and receives `bBuilder`, reads that level's wrapper from the scope it is handed.
		let feature = [
			"public protocol Widget {}",
			seamFixtureType(named: "A", declarations: ["@Received let bBuilder: Instantiator<B>", "@Instantiated let widget: any Widget", "@Instantiated let xBuilder: Instantiator<X>"]),
			seamFixtureType(named: "B", declarations: ["@Received let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "P", declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "X", declarations: ["@Instantiated let p: P"]),
			seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let xBuilder: Instantiator<X>"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received let bBuilder: Instantiator<B>"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let flow: Flow"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", imports: [], rootFiles: ["Flow": """
		extension Flow {
		    @frozen public enum SafeDIScope_Widget {
		        case xBuilder(xBuilder_Values, SafeDIScope_Widget.X_Scope)

		        public struct xBuilder_Values {}

		        @frozen public enum X_Scope {
		            case p(p_Values, SafeDIScope_Widget.P_Scope)

		            public struct p_Values {}
		        }

		        @frozen public enum P_Scope {
		            case aBuilder(aBuilder_Values, SafeDIScope_Widget.A_Scope)

		            public struct aBuilder_Values {}
		        }

		        @frozen public enum A_Scope {
		            case widget(widget_Values)

		            public struct widget_Values {
		                public let bBuilder: Instantiator<B>
		                public let xBuilder: Instantiator<X>
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_widgetBuilder: @escaping (SafeDIScope_Widget) -> any Widget) {
		        let __safeDI_widgetValues_xBuilder = SafeDIScope_Widget.xBuilder_Values()
		        func __safeDI_xBuilder() -> X {
		            let __safeDI_widgetValues_p = SafeDIScope_Widget.X_Scope.p_Values()
		            func __safeDI_p() -> P {
		                let __safeDI_widgetValues_aBuilder = SafeDIScope_Widget.P_Scope.aBuilder_Values()
		                func __safeDI_aBuilder() -> A {
		                    let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		                    let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		                    let widget: any Widget = __safeDI_widgetBuilder(.xBuilder(__safeDI_widgetValues_xBuilder, .p(__safeDI_widgetValues_p, .aBuilder(__safeDI_widgetValues_aBuilder, .widget(SafeDIScope_Widget.A_Scope.widget_Values(bBuilder: bBuilder, xBuilder: xBuilder))))))
		                    return A(bBuilder: bBuilder, widget: widget, xBuilder: xBuilder)
		                }
		                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		                func __safeDI_bBuilder() -> B {
		                    let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		                    return B(aBuilder: aBuilder)
		                }
		                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		                return P(aBuilder: aBuilder, bBuilder: bBuilder)
		            }
		            let p: P = __safeDI_p()
		            return X(p: p)
		        }
		        let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		        self.init(xBuilder: xBuilder)
		    }
		}

		extension Flow {
		    public enum __safeDI_Flow_3E3E253138724B42 {}
		}
		"""]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_flow() -> Flow {
		            _ = Flow.__safeDI_Flow_3E3E253138724B42.self\(Self.callComment(module: "Feature"))
		            func __safeDI_widgetBuilder_Flow(_ scope: Flow.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .xBuilder(_, scope): return __safeDI_widgetBuilder_Flow_X_Scope(scope)
		                }
		            }
		            func __safeDI_widgetBuilder_Flow_X_Scope(_ scope: Flow.SafeDIScope_Widget.X_Scope) -> any Widget {
		                switch scope {
		                case let .p(_, scope): return __safeDI_widgetBuilder_Flow_P_Scope(scope)
		                }
		            }
		            func __safeDI_widgetBuilder_Flow_P_Scope(_ scope: Flow.SafeDIScope_Widget.P_Scope) -> any Widget {
		                switch scope {
		                case let .aBuilder(_, scope): return __safeDI_widgetBuilder_Flow_A_Scope(scope)
		                }
		            }
		            func __safeDI_widgetBuilder_Flow_A_Scope(_ scope: Flow.SafeDIScope_Widget.A_Scope) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let bBuilder = scope.bBuilder
		                    let widget: any Widget = DefaultWidget(bBuilder: bBuilder)
		                    return widget
		                }
		            }
		            return Flow(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Flow)
		        }
		        let flow: Flow = __safeDI_flow()
		        self.init(flow: flow)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: inlineFixture(feature + fulfillers), app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().flow.xBuilder.instantiate().p.aBuilder.instantiate().widget"),
			DifferentialValueProbe("Root().flow.xBuilder.instantiate().p.aBuilder.instantiate().xBuilder.instantiate().p.aBuilder.instantiate().widget"),
			DifferentialValueProbe("Root().flow.xBuilder.instantiate().p.bBuilder.instantiate().aBuilder.instantiate().xBuilder.instantiate().p.aBuilder.instantiate().widget"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsEveryMembersPayloadBeforeLoop_whenHoleIsBuiltInsideEachLoopMembersFunction() async throws {
		// `A` and `B` open each other, and each holds a `widget` hole. `bBuilder`'s function, which `aBuilder`'s calls, reads
		// `bBuilder`'s payload, so both payloads are bound before the loop's first function. `bBuilder`'s payload holds no
		// `aBuilder`: the loop is still being built where the payloads are bound, and `B`'s level carries the wrapper its own
		// function makes again.
		let feature = [
			"public protocol Widget {}",
			seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
			seamFixtureType(named: "A", declarations: ["@Instantiated let mark: Mark", "@Received let bBuilder: Instantiator<B>", "@Instantiated let widget: any Widget"]),
			seamFixtureType(named: "B", declarations: ["@Instantiated let mark: Mark", "@Received let aBuilder: Instantiator<A>", "@Instantiated let widget: any Widget"]),
			seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received let mark: Mark"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let flow: Flow"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", imports: [], rootFiles: ["Flow": """
		extension Flow {
		    @frozen public enum SafeDIScope_Widget {
		        case aBuilder(aBuilder_Values, SafeDIScope_Widget.A_Scope)
		        case bBuilder(bBuilder_Values, SafeDIScope_Widget.B_Scope)

		        public struct aBuilder_Values {}

		        public struct bBuilder_Values {}

		        @frozen public enum A_Scope {
		            case widget(widget_Values)

		            public struct widget_Values {
		                public let bBuilder: Instantiator<B>
		                public let mark: Mark
		            }
		        }

		        @frozen public enum B_Scope {
		            case widget(widget_Values)

		            public struct widget_Values {
		                public let aBuilder: Instantiator<A>
		                public let mark: Mark
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_widgetBuilder: @escaping (SafeDIScope_Widget) -> any Widget) {
		        let __safeDI_widgetValues_aBuilder = SafeDIScope_Widget.aBuilder_Values()
		        let __safeDI_widgetValues_bBuilder = SafeDIScope_Widget.bBuilder_Values()
		        func __safeDI_aBuilder() -> A {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            let mark = Mark()
		            let widget: any Widget = __safeDI_widgetBuilder(.aBuilder(__safeDI_widgetValues_aBuilder, .widget(SafeDIScope_Widget.A_Scope.widget_Values(bBuilder: bBuilder, mark: mark))))
		            return A(mark: mark, bBuilder: bBuilder, widget: widget)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        func __safeDI_bBuilder() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            let mark = Mark()
		            let widget: any Widget = __safeDI_widgetBuilder(.bBuilder(__safeDI_widgetValues_bBuilder, .widget(SafeDIScope_Widget.B_Scope.widget_Values(aBuilder: aBuilder, mark: mark))))
		            return B(mark: mark, aBuilder: aBuilder, widget: widget)
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
		    }
		}

		extension Flow {
		    public enum __safeDI_Flow_F6CC9DA5320C1EA1 {}
		}
		"""]))
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, Self.generatedFiles(module: "App", imports: ["Feature"], rootFiles: ["Root": """
		extension Root {
		    public init() {
		        func __safeDI_flow() -> Flow {
		            _ = Flow.__safeDI_Flow_F6CC9DA5320C1EA1.self\(Self.callComment(module: "Feature"))
		            func __safeDI_widgetBuilder_Flow(_ scope: Flow.SafeDIScope_Widget) -> any Widget {
		                switch scope {
		                case let .aBuilder(_, scope): return __safeDI_widgetBuilder_Flow_A_Scope(scope)
		                case let .bBuilder(_, scope): return __safeDI_widgetBuilder_Flow_B_Scope(scope)
		                }
		            }
		            func __safeDI_widgetBuilder_Flow_A_Scope(_ scope: Flow.SafeDIScope_Widget.A_Scope) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let mark = scope.mark
		                    let widget: any Widget = DefaultWidget(mark: mark)
		                    return widget
		                }
		            }
		            func __safeDI_widgetBuilder_Flow_B_Scope(_ scope: Flow.SafeDIScope_Widget.B_Scope) -> any Widget {
		                switch scope {
		                case let .widget(scope):
		                    let mark = scope.mark
		                    let widget: any Widget = DefaultWidget(mark: mark)
		                    return widget
		                }
		            }
		            return Flow(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Flow)
		        }
		        let flow: Flow = __safeDI_flow()
		        self.init(flow: flow)
		    }
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: inlineFixture(feature + fulfillers), app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().flow.aBuilder.instantiate()"),
			DifferentialValueProbe("Root().flow.bBuilder.instantiate()"),
			DifferentialValueProbe("Root().flow.aBuilder.instantiate().bBuilder.instantiate()"),
			DifferentialValueProbe("Root().flow.bBuilder.instantiate().aBuilder.instantiate()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsLaterMembersPayloadBeforeLoop_whenOnlyLaterLoopMemberHoldsHole() async throws {
		// Only `B`, the loop's second member, holds a hole. `aBuilder`'s function, the loop's first, calls `bBuilder`'s, which
		// reads `bBuilder`'s payload, so the payload is bound before `aBuilder`'s function.
		let feature = [
			"public protocol Widget {}",
			seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
			seamFixtureType(named: "A", declarations: ["@Instantiated let mark: Mark", "@Received let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "B", declarations: ["@Instantiated let mark: Mark", "@Received let aBuilder: Instantiator<A>", "@Instantiated let widget: any Widget"]),
			seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received let mark: Mark"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let flow: Flow"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", imports: [], rootFiles: ["Flow": """
		extension Flow {
		    @frozen public enum SafeDIScope_Widget {
		        case bBuilder(bBuilder_Values, SafeDIScope_Widget.B_Scope)

		        public struct bBuilder_Values {}

		        @frozen public enum B_Scope {
		            case widget(widget_Values)

		            public struct widget_Values {
		                public let aBuilder: Instantiator<A>
		                public let mark: Mark
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_widgetBuilder: @escaping (SafeDIScope_Widget) -> any Widget) {
		        let __safeDI_widgetValues_bBuilder = SafeDIScope_Widget.bBuilder_Values()
		        func __safeDI_aBuilder() -> A {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            let mark = Mark()
		            return A(mark: mark, bBuilder: bBuilder)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        func __safeDI_bBuilder() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            let mark = Mark()
		            let widget: any Widget = __safeDI_widgetBuilder(.bBuilder(__safeDI_widgetValues_bBuilder, .widget(SafeDIScope_Widget.B_Scope.widget_Values(aBuilder: aBuilder, mark: mark))))
		            return B(mark: mark, aBuilder: aBuilder, widget: widget)
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
		    }
		}

		extension Flow {
		    public enum __safeDI_Flow_CD7A050A95E64A1A {}
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: inlineFixture(feature + fulfillers), app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().flow.aBuilder.instantiate().bBuilder.instantiate()"),
			DifferentialValueProbe("Root().flow.bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsEveryMembersPayloadBeforeLoop_whenThreeLoopMembersShareTypeHoldingHole() async throws {
		// `A`, `B` and `C` open one another in turn, and `A`, `B` and the seam each build a `Leaf`, which receives `cBuilder`
		// and holds a hole. Every member's payload is bound before the loop's first function, and none holds another member.
		let feature = [
			"public protocol Widget {}",
			seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
			seamFixtureType(named: "Leaf", declarations: ["@Received let cBuilder: Instantiator<C>", "@Instantiated let widget: any Widget"]),
			seamFixtureType(named: "A", declarations: ["@Instantiated let mark: Mark", "@Instantiated let leaf: Leaf", "@Instantiated let widget: any Widget"]),
			seamFixtureType(named: "B", declarations: ["@Received let aBuilder: Instantiator<A>", "@Instantiated let leaf: Leaf"]),
			seamFixtureType(named: "C", declarations: ["@Received let bBuilder: Instantiator<B>", "@Forwarded let id: Int"]),
			seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let leaf: Leaf"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received(onlyIfAvailable: true) let cBuilder: Instantiator<C>?", "@Received(onlyIfAvailable: true) let mark: Mark?"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let flow: Flow"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", imports: [], rootFiles: ["Flow": """
		extension Flow {
		    @frozen public enum SafeDIScope_Widget {
		        case aBuilder(aBuilder_Values, SafeDIScope_Widget.A_Scope)
		        case bBuilder(bBuilder_Values, SafeDIScope_Widget.B_Scope)
		        case leaf(leaf_Values, SafeDIScope_Widget.Leaf_Scope)

		        public struct aBuilder_Values {}

		        public struct bBuilder_Values {}

		        public struct leaf_Values {
		            public let aBuilder: Instantiator<A>
		            public let bBuilder: Instantiator<B>
		            public let cBuilder: Instantiator<C>
		        }

		        @frozen public enum A_Scope {
		            case leaf(leaf_Values, SafeDIScope_Widget.Leaf_Scope)
		            case widget(widget_Values)

		            public struct leaf_Values {
		                public let cBuilder: Instantiator<C>
		                public let mark: Mark
		            }

		            public struct widget_Values {
		                public let cBuilder: Instantiator<C>
		                public let mark: Mark
		                public let leaf: Leaf
		            }
		        }

		        @frozen public enum B_Scope {
		            case leaf(leaf_Values, SafeDIScope_Widget.Leaf_Scope)

		            public struct leaf_Values {
		                public let aBuilder: Instantiator<A>
		                public let cBuilder: Instantiator<C>
		            }
		        }

		        @frozen public enum Leaf_Scope {
		            case widget(widget_Values)

		            public struct widget_Values {}
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_widgetBuilder: @escaping (SafeDIScope_Widget) -> any Widget) {
		        let __safeDI_widgetValues_aBuilder = SafeDIScope_Widget.aBuilder_Values()
		        let __safeDI_widgetValues_bBuilder = SafeDIScope_Widget.bBuilder_Values()
		        func __safeDI_aBuilder() -> A {
		            let cBuilder = Instantiator<C> {
		                __safeDI_cBuilder(id: $0)
		            }
		            let mark = Mark()
		            let __safeDI_widgetValues_leaf = SafeDIScope_Widget.A_Scope.leaf_Values(cBuilder: cBuilder, mark: mark)
		            func __safeDI_leaf() -> Leaf {
		                let widget: any Widget = __safeDI_widgetBuilder(.aBuilder(__safeDI_widgetValues_aBuilder, .leaf(__safeDI_widgetValues_leaf, .widget(SafeDIScope_Widget.Leaf_Scope.widget_Values()))))
		                return Leaf(cBuilder: cBuilder, widget: widget)
		            }
		            let leaf: Leaf = __safeDI_leaf()
		            let widget: any Widget = __safeDI_widgetBuilder(.aBuilder(__safeDI_widgetValues_aBuilder, .widget(SafeDIScope_Widget.A_Scope.widget_Values(cBuilder: cBuilder, mark: mark, leaf: leaf))))
		            return A(mark: mark, leaf: leaf, widget: widget)
		        }
		        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		        func __safeDI_bBuilder() -> B {
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            let cBuilder = Instantiator<C> {
		                __safeDI_cBuilder(id: $0)
		            }
		            let __safeDI_widgetValues_leaf = SafeDIScope_Widget.B_Scope.leaf_Values(aBuilder: aBuilder, cBuilder: cBuilder)
		            func __safeDI_leaf() -> Leaf {
		                let widget: any Widget = __safeDI_widgetBuilder(.bBuilder(__safeDI_widgetValues_bBuilder, .leaf(__safeDI_widgetValues_leaf, .widget(SafeDIScope_Widget.Leaf_Scope.widget_Values()))))
		                return Leaf(cBuilder: cBuilder, widget: widget)
		            }
		            let leaf: Leaf = __safeDI_leaf()
		            return B(aBuilder: aBuilder, leaf: leaf)
		        }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        func __safeDI_cBuilder(id: Int) -> C {
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            return C(bBuilder: bBuilder, id: id)
		        }
		        let cBuilder = Instantiator<C> {
		            __safeDI_cBuilder(id: $0)
		        }
		        let __safeDI_widgetValues_leaf = SafeDIScope_Widget.leaf_Values(aBuilder: aBuilder, bBuilder: bBuilder, cBuilder: cBuilder)
		        func __safeDI_leaf() -> Leaf {
		            let widget: any Widget = __safeDI_widgetBuilder(.leaf(__safeDI_widgetValues_leaf, .widget(SafeDIScope_Widget.Leaf_Scope.widget_Values())))
		            return Leaf(cBuilder: cBuilder, widget: widget)
		        }
		        let leaf: Leaf = __safeDI_leaf()
		        self.init(aBuilder: aBuilder, bBuilder: bBuilder, cBuilder: cBuilder, leaf: leaf)
		    }
		}

		extension Flow {
		    public enum __safeDI_Flow_302E02075DB211F6 {}
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: inlineFixture(feature + fulfillers), app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().flow.aBuilder.instantiate()"),
			DifferentialValueProbe("Root().flow.bBuilder.instantiate()"),
			DifferentialValueProbe("Root().flow.cBuilder.instantiate(3).bBuilder.instantiate().aBuilder.instantiate()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_givesLevelOptionalFormOfRebinding_whenLoopMemberReceivesInstantiatorOnlyIfAvailableAndIsAlsoBuiltByValue() async throws {
		// `A` receives `bBuilder` only if available. Inside `Flow`'s loop, `aBuilder`'s function wraps `bBuilder` again; the seam
		// also builds an `A` by value, where `bBuilder` is the seam's optional parameter. `A`'s level takes the optional form,
		// which both builds bind.
		let feature = [
			"public protocol Widget {}",
			seamFixtureType(named: "Mark", isFinalClass: true, declarations: []),
			seamFixtureType(named: "A", declarations: ["@Instantiated let mark: Mark", "@Received(onlyIfAvailable: true) let bBuilder: Instantiator<B>?", "@Instantiated let widget: any Widget"]),
			seamFixtureType(named: "B", declarations: ["@Received let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "Flow", declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"]),
			seamFixtureType(named: "Hub", isSeam: true, declarations: ["@Instantiated let flow: Flow", "@Instantiated let a: A"]),
		]
		let fulfillers = [Self.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: ["@Received(onlyIfAvailable: true) let bBuilder: Instantiator<B>?", "@Received let mark: Mark"])]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let hub: Hub"])
		let modules = Self.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, Self.generatedFiles(module: "Feature", imports: [], rootFiles: ["Hub": """
		extension Hub {
		    @frozen public enum SafeDIScope_Widget {
		        case flow(flow_Values, SafeDIScope_Widget.Flow_Scope)
		        case a(a_Values, SafeDIScope_Widget.A_Scope)

		        public struct flow_Values {
		            public let bBuilder: Instantiator<B>?
		        }

		        public struct a_Values {
		            public let bBuilder: Instantiator<B>?
		            public let flow: Flow
		        }

		        @frozen public enum Flow_Scope {
		            case aBuilder(aBuilder_Values, SafeDIScope_Widget.A_Scope)

		            public struct aBuilder_Values {}
		        }

		        @frozen public enum A_Scope {
		            case widget(widget_Values)

		            public struct widget_Values {
		                public let bBuilder: Instantiator<B>?
		                public let mark: Mark
		            }
		        }
		    }

		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module's `#SafeDIConfiguration`.
		    public init(__safeDI_bBuilder bBuilder: Instantiator<B>?, __safeDI_widgetBuilder: @escaping (SafeDIScope_Widget) -> any Widget) {
		        let __safeDI_widgetValues_flow = SafeDIScope_Widget.flow_Values(bBuilder: bBuilder)
		        func __safeDI_flow() -> Flow {
		            let __safeDI_widgetValues_aBuilder = SafeDIScope_Widget.Flow_Scope.aBuilder_Values()
		            func __safeDI_aBuilder() -> A {
		                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		                let mark = Mark()
		                let widget: any Widget = __safeDI_widgetBuilder(.flow(__safeDI_widgetValues_flow, .aBuilder(__safeDI_widgetValues_aBuilder, .widget(SafeDIScope_Widget.A_Scope.widget_Values(bBuilder: bBuilder, mark: mark)))))
		                return A(mark: mark, bBuilder: bBuilder, widget: widget)
		            }
		            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		            func __safeDI_bBuilder() -> B {
		                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
		                return B(aBuilder: aBuilder)
		            }
		            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		            return Flow(aBuilder: aBuilder, bBuilder: bBuilder)
		        }
		        let flow: Flow = __safeDI_flow()
		        let __safeDI_widgetValues_a = SafeDIScope_Widget.a_Values(bBuilder: bBuilder, flow: flow)
		        func __safeDI_a() -> A {
		            let mark = Mark()
		            let widget: any Widget = __safeDI_widgetBuilder(.a(__safeDI_widgetValues_a, .widget(SafeDIScope_Widget.A_Scope.widget_Values(bBuilder: bBuilder, mark: mark))))
		            return A(mark: mark, bBuilder: bBuilder, widget: widget)
		        }
		        let a: A = __safeDI_a()
		        self.init(flow: flow, a: a)
		    }
		}

		extension Hub {
		    public enum __safeDI_Hub_3C2B120FAB051AB0 {}
		}
		"""]))
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: inlineFixture(feature + fulfillers), app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().hub.flow.aBuilder.instantiate().widget"),
			DifferentialValueProbe("Root().hub.a.widget"),
		])
	}

	// MARK: A hole's implementation that receives an instantiator the seam's tree is building

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReceivesInstantiatorBeingBuilt_whenFillReceivesHolesOwnInstantiator(onlyIfAvailable: Bool) async {
		// `DefaultDetail` fills `Screen`'s `detailBuilder` and receives `detailBuilder`. Inline, it would get a wrapper of
		// the function that builds it, but that function is in `Screen`'s initializer, which code `App` generates cannot
		// refer to: an error, whether the receive is required or only if available.
		let receive = onlyIfAvailable
			? "@Received(onlyIfAvailable: true) let detailBuilder: ErasedInstantiator<(), any Detail>?"
			: "@Received let detailBuilder: ErasedInstantiator<(), any Detail>"
		let property = onlyIfAvailable ? "detailBuilder: ErasedInstantiator<(), any Detail>?" : "detailBuilder: ErasedInstantiator<(), any Detail>"
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultDetail.swift"]):9:5: error: `DefaultDetail` receives `\(property)`, which `Screen`’s tree is building where it calls the builder for `Screen`’s `detailBuilder: ErasedInstantiator<(), any Detail>` (case `detailBuilder` of `defaultDetailBuilder`). Inline, `DefaultDetail` can get an instantiator of its own, made from the function `Screen`’s initializer declares for `detailBuilder`, which code generated outside module `Feature` cannot refer to. Instantiate `detailBuilder` on a type above `Screen`, and receive it on `Screen` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `DefaultDetail` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Screen.swift"]):7:5: note: `Screen` instantiates `detailBuilder: ErasedInstantiator<(), any Detail>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Detail {}",
						seamFixtureType(named: "Screen", isSeam: true, declarations: [#"@Instantiated(fulfilledByType: "DefaultDetail") let detailBuilder: ErasedInstantiator<(), any Detail>"#]),
					],
					app: [
						seamFixtureType(named: "DefaultDetail", declarations: [receive], conformances: ", Detail"),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screen: Screen"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReceivesInstantiatorBeingBuilt_whenFillReceivesInstantiatorOfScopeOnHolesPath(onlyIfAvailable: Bool) async {
		// `DefaultWidget` fills the builder for `A`'s `widget` and receives `aBuilder`, which builds `A`. Inline, `aBuilder`'s
		// function would wrap itself again for it, but that function is in `Flow`'s initializer, and `Feature` does not see
		// the receive: an error, whether the receive is required or only if available.
		let receive = onlyIfAvailable ? "@Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?" : "@Received let aBuilder: Instantiator<A>"
		let property = onlyIfAvailable ? "aBuilder: Instantiator<A>?" : "aBuilder: Instantiator<A>"
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultWidget.swift"]):9:5: error: `DefaultWidget` receives `\(property)`, which `Flow`’s tree is building where it calls the builder for `A`’s `widget: any Widget` (case `A_Scope.widget` of `widgetBuilder`). Inline, `DefaultWidget` can get an instantiator of its own, made from the function `Flow`’s initializer declares for `aBuilder`, which code generated outside module `Feature` cannot refer to. Instantiate `aBuilder` on a type above `Flow`, and receive it on `Flow` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `Widget` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Flow.swift"]):7:5: note: `Flow` instantiates `aBuilder: Instantiator<A>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Widget {}",
						seamFixtureType(named: "A", declarations: ["@Instantiated let widget: any Widget"]),
						seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
					],
					app: [
						Self.fulfillingType(named: "DefaultWidget", fulfilling: "Widget", declarations: [receive]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let flow: Flow"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsFillReadsValueTheScopeDoesNotCarry_whenImplementationsOfTwoHolesReceiveEachOthersInstantiators(onlyIfAvailable: Bool) async {
		// `DefaultDetail` and `DefaultSettings` fill `Screen`'s two holes and receive each other's instantiators. Inline, the
		// two are a loop. `Screen`'s module sees neither receive, so it builds `detailBuilder` first, and the scope its
		// builder is handed does not carry `settingsBuilder`, which `Screen` builds after it.
		let receive = onlyIfAvailable
			? "@Received(onlyIfAvailable: true) let settingsBuilder: ErasedInstantiator<(), any Settings>?"
			: "@Received let settingsBuilder: ErasedInstantiator<(), any Settings>"
		let property = onlyIfAvailable ? "settingsBuilder: ErasedInstantiator<(), any Settings>?" : "settingsBuilder: ErasedInstantiator<(), any Settings>"
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultDetail.swift"]):9:5: error: `DefaultDetail` receives `\(property)`, which `Screen`’s tree builds only after it calls the builder for `Screen`’s `detailBuilder: ErasedInstantiator<(), any Detail>` (case `detailBuilder` of `defaultDetailBuilder`), so that builder’s scope does not carry it. Instantiate `settingsBuilder` on a type above `Screen`, and receive it on `Screen` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `DefaultDetail` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["Screen.swift"]):9:5: note: `Screen` declares `settingsBuilder: ErasedInstantiator<(), any Settings>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: Self.modules(
					feature: [
						"public protocol Detail {}\npublic protocol Settings {}",
						seamFixtureType(named: "Screen", isSeam: true, declarations: [
							#"@Instantiated(fulfilledByType: "DefaultDetail") let detailBuilder: ErasedInstantiator<(), any Detail>"#,
							#"@Instantiated(fulfilledByType: "DefaultSettings") let settingsBuilder: ErasedInstantiator<(), any Settings>"#,
						]),
					],
					app: [
						seamFixtureType(named: "DefaultDetail", declarations: [receive], conformances: ", Detail"),
						seamFixtureType(named: "DefaultSettings", declarations: ["@Received let detailBuilder: ErasedInstantiator<(), any Detail>"], conformances: ", Settings"),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screen: Screen"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Screens in modules of their own that open one another

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsEachScreensInstantiators_whenSeamsInModulesOfTheirOwnReceiveEachOthersErasedInstantiators() async throws {
		// Eight screens, each a seam in a module of its own that sees only `Core`, receive three erased instantiators each,
		// which `Root` declares, one for each screen; each screen's module generates its seam, and `Root`'s module calls it.
		// The instantiators are one loop, so each screen's function in `Root`'s initializer begins by wrapping again the
		// functions of the screens its screen opens, and passes those wrappers to the screen's initializer by name.
		let edges = [[2, 3, 4], [2, 3, 7], [1, 4, 7], [0, 2, 6], [2, 3, 5], [3, 6, 7], [0, 4, 5], [0, 2, 3]]
		let modules = Self.screenModules(edges: edges, rootGeneratesMock: false)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(M0)
		import M0
		#endif
		#if canImport(M1)
		import M1
		#endif
		#if canImport(M2)
		import M2
		#endif
		#if canImport(M3)
		import M3
		#endif
		#if canImport(M4)
		import M4
		#endif
		#if canImport(M5)
		import M5
		#endif
		#if canImport(M6)
		import M6
		#endif
		#if canImport(M7)
		import M7
		#endif

		extension Root {
		    public convenience init() {
		        let service = Service()
		        func __safeDI_screen0Builder(id: Int) -> Screen0 {
		            let screen2Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen2Builder(id: $0)
		            }
		            let screen3Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen3Builder(id: $0)
		            }
		            let screen4Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen4Builder(id: $0)
		            }
		            _ = Screen0.__safeDI_Screen0_50893F9C0248B961.self\(Self.callComment(module: "M0"))
		            return Screen0(__safeDI_id: id, __safeDI_service: service, __safeDI_screen2Builder: screen2Builder, __safeDI_screen3Builder: screen3Builder, __safeDI_screen4Builder: screen4Builder)
		        }
		        let screen0Builder = ErasedInstantiator<Int, Screen> {
		            __safeDI_screen0Builder(id: $0)
		        }
		        func __safeDI_screen1Builder(id: Int) -> Screen1 {
		            let screen2Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen2Builder(id: $0)
		            }
		            let screen3Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen3Builder(id: $0)
		            }
		            let screen7Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen7Builder(id: $0)
		            }
		            _ = Screen1.__safeDI_Screen1_2BE0865BD7D69A88.self\(Self.callComment(module: "M1"))
		            return Screen1(__safeDI_id: id, __safeDI_service: service, __safeDI_screen2Builder: screen2Builder, __safeDI_screen3Builder: screen3Builder, __safeDI_screen7Builder: screen7Builder)
		        }
		        let screen1Builder = ErasedInstantiator<Int, Screen> {
		            __safeDI_screen1Builder(id: $0)
		        }
		        func __safeDI_screen2Builder(id: Int) -> Screen2 {
		            let screen1Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen1Builder(id: $0)
		            }
		            let screen4Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen4Builder(id: $0)
		            }
		            let screen7Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen7Builder(id: $0)
		            }
		            _ = Screen2.__safeDI_Screen2_C1C57A76086D5BFE.self\(Self.callComment(module: "M2"))
		            return Screen2(__safeDI_id: id, __safeDI_service: service, __safeDI_screen1Builder: screen1Builder, __safeDI_screen4Builder: screen4Builder, __safeDI_screen7Builder: screen7Builder)
		        }
		        let screen2Builder = ErasedInstantiator<Int, Screen> {
		            __safeDI_screen2Builder(id: $0)
		        }
		        func __safeDI_screen3Builder(id: Int) -> Screen3 {
		            let screen0Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen0Builder(id: $0)
		            }
		            let screen2Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen2Builder(id: $0)
		            }
		            let screen6Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen6Builder(id: $0)
		            }
		            _ = Screen3.__safeDI_Screen3_524F9E2FFF78377C.self\(Self.callComment(module: "M3"))
		            return Screen3(__safeDI_id: id, __safeDI_service: service, __safeDI_screen0Builder: screen0Builder, __safeDI_screen2Builder: screen2Builder, __safeDI_screen6Builder: screen6Builder)
		        }
		        let screen3Builder = ErasedInstantiator<Int, Screen> {
		            __safeDI_screen3Builder(id: $0)
		        }
		        func __safeDI_screen4Builder(id: Int) -> Screen4 {
		            let screen2Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen2Builder(id: $0)
		            }
		            let screen3Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen3Builder(id: $0)
		            }
		            let screen5Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen5Builder(id: $0)
		            }
		            _ = Screen4.__safeDI_Screen4_FE5AE1EC58BBBC5A.self\(Self.callComment(module: "M4"))
		            return Screen4(__safeDI_id: id, __safeDI_service: service, __safeDI_screen2Builder: screen2Builder, __safeDI_screen3Builder: screen3Builder, __safeDI_screen5Builder: screen5Builder)
		        }
		        let screen4Builder = ErasedInstantiator<Int, Screen> {
		            __safeDI_screen4Builder(id: $0)
		        }
		        func __safeDI_screen5Builder(id: Int) -> Screen5 {
		            let screen3Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen3Builder(id: $0)
		            }
		            let screen6Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen6Builder(id: $0)
		            }
		            let screen7Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen7Builder(id: $0)
		            }
		            _ = Screen5.__safeDI_Screen5_10637ED15C1B66CA.self\(Self.callComment(module: "M5"))
		            return Screen5(__safeDI_id: id, __safeDI_service: service, __safeDI_screen3Builder: screen3Builder, __safeDI_screen6Builder: screen6Builder, __safeDI_screen7Builder: screen7Builder)
		        }
		        let screen5Builder = ErasedInstantiator<Int, Screen> {
		            __safeDI_screen5Builder(id: $0)
		        }
		        func __safeDI_screen6Builder(id: Int) -> Screen6 {
		            let screen0Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen0Builder(id: $0)
		            }
		            let screen4Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen4Builder(id: $0)
		            }
		            let screen5Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen5Builder(id: $0)
		            }
		            _ = Screen6.__safeDI_Screen6_2D1B4945D0F7A293.self\(Self.callComment(module: "M6"))
		            return Screen6(__safeDI_id: id, __safeDI_service: service, __safeDI_screen0Builder: screen0Builder, __safeDI_screen4Builder: screen4Builder, __safeDI_screen5Builder: screen5Builder)
		        }
		        let screen6Builder = ErasedInstantiator<Int, Screen> {
		            __safeDI_screen6Builder(id: $0)
		        }
		        func __safeDI_screen7Builder(id: Int) -> Screen7 {
		            let screen0Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen0Builder(id: $0)
		            }
		            let screen2Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen2Builder(id: $0)
		            }
		            let screen3Builder = ErasedInstantiator<Int, Screen> {
		                __safeDI_screen3Builder(id: $0)
		            }
		            _ = Screen7.__safeDI_Screen7_B62CF5DD79251747.self\(Self.callComment(module: "M7"))
		            return Screen7(__safeDI_id: id, __safeDI_service: service, __safeDI_screen0Builder: screen0Builder, __safeDI_screen2Builder: screen2Builder, __safeDI_screen3Builder: screen3Builder)
		        }
		        let screen7Builder = ErasedInstantiator<Int, Screen> {
		            __safeDI_screen7Builder(id: $0)
		        }
		        self.init(service: service, screen0Builder: screen0Builder, screen1Builder: screen1Builder, screen2Builder: screen2Builder, screen3Builder: screen3Builder, screen4Builder: screen4Builder, screen5Builder: screen5Builder, screen6Builder: screen6Builder, screen7Builder: screen7Builder)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsEachScreensInstantiatorsInRootsMock_whenRootOfSeamsInModulesOfTheirOwnGeneratesMock() async throws {
		// The eight screens above, under a root that generates its mock: the mock builds every screen's tree inline, and
		// rebinds the loop as production does, with the functions of the loop's members first and their wrappers after.
		let edges = [[2, 3, 4], [2, 3, 7], [1, 4, 7], [0, 2, 6], [2, 3, 5], [3, 6, 7], [0, 4, 5], [0, 2, 3]]
		let modules = Self.screenModules(edges: edges, rootGeneratesMock: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let generatedFiles = try #require(output.modules["App"]?.generatedFiles)
		expectGeneratedFiles(generatedFiles, try ["App.swift": Self.expectedScreenRootFile(edges: edges, units: [Array(edges.indices)], output: output, rootGeneratesMock: true)])
	}

	// The comparison with the file built from the edge list, which has a fixed number of lines per screen, is what fails if
	// the root's code grows faster than the screens do. The test sets no time limit: in a full run its wall time is mostly
	// waiting behind other tests' compile checks, which a limit would measure instead of `generate`.
	@Test(arguments: [40, 64], [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_growsLinearly_whenManySeamsInModulesOfTheirOwnReceiveEachOthersErasedInstantiators(screenCount: Int, rootGeneratesMock: Bool) async throws {
		// Every screen but `Screen0` opens three others on a ring, so they are one loop; `Screen0` opens three of them and
		// none opens it, so it is built after the loop and reads the wrappers the loop's members share. Each member's
		// function rebinds the three screens it opens, so the root's initializer, and its mock, have a fixed number of lines
		// per screen. The modules compile as the eight screens' do, so only the generated code is compared.
		let ringCount = screenCount - 1
		let edges = [[1, 2, 3]] + (0..<ringCount).map { member in
			[1, 3, 7].map { (member + $0) % ringCount + 1 }.sorted()
		}
		let modules = Self.screenModules(edges: edges, rootGeneratesMock: rootGeneratesMock)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let generatedFiles = try #require(output.modules["App"]?.generatedFiles)
		expectGeneratedFiles(generatedFiles, try ["App.swift": Self.expectedScreenRootFile(edges: edges, units: [Array(1..<screenCount), [0]], output: output, rootGeneratesMock: rootGeneratesMock)])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Core`, which declares `Service` and the open class `Screen`; one module `M<i>` per screen, which sees only `Core` and
	/// declares `Screen<i>`, a seam that forwards `id`, receives `service`, instantiates a `Model<i>` that receives both, and
	/// receives an erased instantiator of each screen `edges[i]` names, in that order; and `App`, whose `Root` declares
	/// `service` and an erased instantiator of each screen, in order, which the screen's module fulfills.
	private static func screenModules(edges: [[Int]], rootGeneratesMock: Bool) -> [ModuleFixture] {
		let core = ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [
			"""
			@Instantiable
			public final class Service: Instantiable {
			    public init() {}
			}

			open class Screen {
			    public init() {}
			}
			""",
		])
		let screens = edges.enumerated().map { index, opened in
			let properties = [("@Forwarded", "id", "Int"), ("@Received", "service", "Service"), ("@Instantiated", "model\(index)", "Model\(index)")]
				+ opened.map { ("@Received", "screen\($0)Builder", "ErasedInstantiator<Int, Screen>") }
			return ModuleFixture(name: "M\(index)", packageName: "Shop", swiftFileContent: [
				"""
				import Core

				@Instantiable(generateDependencyTree: true)
				public final class Screen\(index): Screen, Instantiable {
				    public init(\(properties.map { "\($0.1): \($0.2)" }.joined(separator: ", "))) {
				\(properties.map { "        self.\($0.1) = \($0.1)" }.joined(separator: "\n"))
				        super.init()
				    }

				\(properties.map { "    \($0.0) let \($0.1): \($0.2)" }.joined(separator: "\n"))
				}

				@Instantiable
				public final class Model\(index): Instantiable {
				    public init(id: Int, service: Service) {
				        self.id = id
				        self.service = service
				    }

				    @Received let id: Int
				    @Received let service: Service
				}
				""",
			], dependencies: ["Core"])
		}
		let rootProperties = [("@Instantiated", "service", "Service")]
			+ edges.indices.map { (#"@Instantiated(fulfilledByType: "Screen\#($0)")"#, "screen\($0)Builder", "ErasedInstantiator<Int, Screen>") }
		let app = ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
			"""
			import Core
			\(edges.indices.map { "import M\($0)" }.joined(separator: "\n"))

			@Instantiable(isRoot: true\(rootGeneratesMock ? ", generateMock: true" : ""))
			public final class Root: Instantiable {
			    init(\(rootProperties.map { "\($0.1): \($0.2)" }.joined(separator: ", "))) {
			\(rootProperties.map { "        self.\($0.1) = \($0.1)" }.joined(separator: "\n"))
			    }

			\(rootProperties.map { "    \($0.0) let \($0.1): \($0.2)" }.joined(separator: "\n"))
			}
			""",
		], dependencies: ["Core"] + edges.indices.map { "M\($0)" })
		return [core] + screens + [app]
	}

	/// The comment on the line before a call of a seam of `module`.
	private static func callComment(module: String) -> String {
		MultiModuleIntegration.moduleInfo.seamCallComment(type: "", declaringModule: module)
	}

	/// The file `App` generates for the `Root` of `screenModules(edges:rootGeneratesMock:)`, whose screens are built in
	/// `units`, in order: a unit of more than one screen is a loop, its members in declaration order, and a unit of one
	/// screen is on no loop. A member of a loop rebinds each screen of its loop it opens, and reads every other screen it
	/// opens from the wrapper the root shares. Each screen's guard is read from the file its own module generates.
	private static func expectedScreenRootFile(edges: [[Int]], units: [[Int]], output: MultiModuleTestOutput, rootGeneratesMock: Bool) throws -> String {
		var guardNames = [Int: String]()
		for index in edges.indices {
			let file = try #require(output.modules["M\(index)"]?.generatedFiles["M\(index).swift"])
			let guardName = try #require(file.split(separator: "\n").lazy.compactMap { line -> Substring? in
				guard let range = line.range(of: "public enum ") else { return nil }
				return line[range.upperBound...].prefix { $0 != " " }
			}.first)
			guardNames[index] = String(guardName)
		}
		var unitOfScreen = [Int: Int]()
		for (unitIndex, unit) in units.enumerated() {
			for screen in unit {
				unitOfScreen[screen] = unitIndex
			}
		}
		func screensRebound(by screen: Int) -> [Int] {
			guard let unit = unitOfScreen[screen], units[unit].count > 1 else { return [] }
			return edges[screen].filter { unitOfScreen[$0] == unit }
		}
		func wrapper(of screen: Int, indentation: String) -> [String] {
			[
				"\(indentation)let screen\(screen)Builder = ErasedInstantiator<Int, Screen> {",
				"\(indentation)    __safeDI_screen\(screen)Builder(id: $0)",
				"\(indentation)}",
			]
		}
		let screens = Array(units.joined())
		let rootArguments = "service: service" + edges.indices.map { ", screen\($0)Builder: screen\($0)Builder" }.joined()
		var lines = (["Core"] + edges.indices.map { "M\($0)" }).sorted().flatMap { ["#if canImport(\($0))", "import \($0)", "#endif"] }
		lines += ["", "extension Root {", "    public convenience init() {", "        let service = Service()"]
		for screen in screens {
			lines.append("        func __safeDI_screen\(screen)Builder(id: Int) -> Screen\(screen) {")
			for opened in screensRebound(by: screen) {
				lines += wrapper(of: opened, indentation: "            ")
			}
			lines.append("            _ = Screen\(screen).\(guardNames[screen] ?? "").self\(callComment(module: "M\(screen)"))")
			lines.append("            return Screen\(screen)(__safeDI_id: id, __safeDI_service: service" + edges[screen].map { ", __safeDI_screen\($0)Builder: screen\($0)Builder" }.joined() + ")")
			lines.append("        }")
			lines += wrapper(of: screen, indentation: "        ")
		}
		lines += ["        self.init(\(rootArguments))", "    }", "}"]
		guard rootGeneratesMock else { return generatedFileHeader + lines.joined(separator: "\n") }
		lines += ["", "#if DEBUG", "extension Root {", "    /// Overrides for the mock dependency tree.", "    struct SafeDIOverrides {", "        init("]
		lines.append("            service: (() -> Service)? = nil,")
		for (position, screen) in screens.enumerated() {
			lines.append("            screen\(screen)Builder: Screen\(screen).SafeDIMockConfiguration = .init()" + (position == screens.count - 1 ? "" : ","))
		}
		lines += ["        ) {", "            self.service = service"]
		lines += screens.map { "            self.screen\($0)Builder = screen\($0)Builder" }
		lines += ["        }", "", "        let service: (() -> Service)?"]
		lines += screens.map { "        let screen\($0)Builder: Screen\($0).SafeDIMockConfiguration" }
		lines += ["    }", "", "    static func mock(", "        safeDIOverrides: SafeDIOverrides = .init()", "    ) -> Root {"]
		lines.append("        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service() }")
		// A loop's members declare every function first, then every wrapper.
		for unit in units {
			for screen in unit {
				let opened = edges[screen].map { "screen\($0)Builder" }
				lines.append("        func __safeDI_screen\(screen)Builder(id: Int) -> Screen {")
				for openedScreen in screensRebound(by: screen) {
					lines += wrapper(of: openedScreen, indentation: "            ")
				}
				lines.append("            let model\(screen) = if let safeDIBuilder = safeDIOverrides.screen\(screen)Builder.model\(screen) { safeDIBuilder(id, service) } else { Model\(screen)(id: id, service: service) }")
				let builderArguments = (["id", "service", "model\(screen)"] + opened).joined(separator: ", ")
				let initializerArguments = (["id: id", "service: service", "model\(screen): model\(screen)"] + opened.map { "\($0): \($0)" }).joined(separator: ", ")
				lines.append("            return if let safeDIBuilder = safeDIOverrides.screen\(screen)Builder.safeDIBuilder { safeDIBuilder(\(builderArguments)) } else { Screen\(screen)(\(initializerArguments)) }")
				lines.append("        }")
			}
			for screen in unit {
				lines += wrapper(of: screen, indentation: "        ")
			}
		}
		lines += ["        return Root(\(rootArguments))", "    }", "}", "#endif", "", "#if DEBUG"]
		for (position, screen) in screens.enumerated() {
			let builderType = "((" + (["Int", "Service", "Model\(screen)"] + edges[screen].map { _ in "ErasedInstantiator<Int, Screen>" }).joined(separator: ", ") + ") -> Screen\(screen))?"
			lines += [
				"extension Screen\(screen) {",
				"    /// Configuration for how this type is constructed within a mock tree.",
				"    struct SafeDIMockConfiguration {",
				"        init(",
				"            model\(screen): ((Int, Service) -> Model\(screen))? = nil,",
				"            _ safeDIBuilder: \(builderType) = nil",
				"        ) {",
				"            self.model\(screen) = model\(screen)",
				"            self.safeDIBuilder = safeDIBuilder",
				"        }",
				"",
				"        let model\(screen): ((Int, Service) -> Model\(screen))?",
				"        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.",
				"        let safeDIBuilder: \(builderType)",
				"    }",
				"}",
			]
			if position < screens.count - 1 {
				lines.append("")
			}
		}
		lines += ["#endif", ""]
		return generatedFileHeader + lines.joined(separator: "\n")
	}

	private static func modules(feature: [String], app: [String]) -> [ModuleFixture] {
		SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: app)
	}

	private static func fulfillingType(named name: String, fulfilling fulfilledType: String, declarations: [String]) -> String {
		SafeDIToolSeamBuilderParameterTests.fulfillingType(named: name, fulfilling: fulfilledType, declarations: declarations)
	}

	private static func generatedFiles(module: String, imports: [String], rootFiles: [String: String]) -> [String: String] {
		SafeDIToolSeamBuilderParameterTests.generatedFiles(module: module, integration: .moduleInfo, imports: imports, rootFiles: rootFiles)
	}

	/// Expects the values `output`, the run of `modules`, builds for each probe to equal those the run of `visibleModules`
	/// builds, the same graph built inline, with every fulfilling declaration in the seam's module.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesEqualVisibleBuild(
		_ output: MultiModuleTestOutput,
		modules: [ModuleFixture],
		visibleModules: [ModuleFixture],
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		guard compileVerificationIsEnabled else { return }
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visibleModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// Expects `generatedFiles` to equal `expected`, recording the files generated when they do not, so a failure shows
	/// the output in full.
	private func expectGeneratedFiles(_ generatedFiles: [String: String]?, _ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}
}
