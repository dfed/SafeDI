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
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

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
			""",
		])
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
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_screenABuilder() -> ScreenA {
			            let screenBBuilder = Instantiator<ScreenB>(__safeDI_screenBBuilder)
			            _ = ScreenA.__safeDI_ScreenA_6F3BBC02A1B01D96.self\(Self.callComment(module: "Feature"))
			            func __safeDI_widgetBuilder_ScreenA() -> ScreenA.__safeDI_WidgetCarrier<any Widget> {
			                .init(widget: {
			                    let widget: any Widget = DefaultWidget(screenBBuilder: screenBBuilder)
			                    return widget
			                })
			            }
			            return ScreenA(__safeDI_widgetBuilder: __safeDI_widgetBuilder_ScreenA())
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
			""",
		])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
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
			""",
		])
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: inlineFixture(feature), app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().flow.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsBuilderInsideItsOwnFunctionInSeamsInitializerAndPublicMock_whenItsTypeRenamesItBesideAnOnlyIfAvailableReceiveOfABuilderWaitingOnItThroughAValue() async throws {
		// `t4Builder`'s receive of `t2Builder` is left `nil`, since `t2Builder` waits on `t3`, which waits on `t4Builder`;
		// `t4Builder` still receives itself, in the seam's initializer and in its public mock alike.
		let feature = [
			seamFixtureType(named: "T2", declarations: ["@Received(onlyIfAvailable: true) let t3: T3?"]),
			seamFixtureType(named: "T3", declarations: ["@Instantiated let t4: T4"]),
			seamFixtureType(named: "T4", declarations: ["@Received(fulfilledByDependencyNamed: \"t4Builder\", ofType: Instantiator<T4>.self) let t4BuilderAlias: Instantiator<T4>", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"]),
			seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"])
				.replacingOccurrences(of: "@Instantiable(generateDependencyTree: true)", with: "@Instantiable(generateDependencyTree: true, generateMock: .public)"),
		]
		let root = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let flow: Flow"])
		let modules = Self.modules(feature: feature, app: [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let fixtures = try #require(output.modules["Feature"]).fixtures
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Flow {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        func __safeDI_t4Builder() -> T4 {
		            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
		            #sourceLocation(file: "\(fixtures["T4.swift"])", line: 8)
		            let t4BuilderAlias: Instantiator<T4> = t4Builder
		            #sourceLocation()
		            return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil)
		        }
		        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
		        func __safeDI_t3() -> T3 {
		            func __safeDI_t4() -> T4 {
		                #sourceLocation(file: "\(fixtures["T4.swift"])", line: 8)
		                let t4BuilderAlias: Instantiator<T4> = t4Builder
		                #sourceLocation()
		                return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil)
		            }
		            let t4: T4 = __safeDI_t4()
		            return T3(t4: t4)
		        }
		        let t3: T3 = __safeDI_t3()
		        func __safeDI_t2Builder() -> T2 {
		            T2(t3: t3)
		        }
		        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
		        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
		    }
		}

		extension Flow {
		    public enum __safeDI_Flow_CBF29CE484222325 {}
		}

		#if DEBUG
		extension Flow {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            t4Builder: ((Instantiator<T4>, Instantiator<T2>?) -> T4)? = nil,
		            t3: __safeDI_Feature_T3_MockConfiguration = .init(),
		            t2Builder: ((T3?) -> T2)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                t4Builder: t4Builder,
		                t3: t3,
		                t2Builder: t2Builder
		            )
		        }

		        public var t4Builder: ((Instantiator<T4>, Instantiator<T2>?) -> T4)? { __safeDI_storage.t4Builder }
		        public var t3: __safeDI_Feature_T3_MockConfiguration { __safeDI_storage.t3 }
		        public var t2Builder: ((T3?) -> T2)? { __safeDI_storage.t2Builder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                t4Builder: ((Instantiator<T4>, Instantiator<T2>?) -> T4)?,
		                t3: __safeDI_Feature_T3_MockConfiguration,
		                t2Builder: ((T3?) -> T2)?
		            ) {
		                self.t4Builder = t4Builder
		                self.t3 = t3
		                self.t2Builder = t2Builder
		            }

		            let t4Builder: ((Instantiator<T4>, Instantiator<T2>?) -> T4)?
		            let t3: __safeDI_Feature_T3_MockConfiguration
		            let t2Builder: ((T3?) -> T2)?
		        }
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Flow {
		        Flow.__safeDI_mock(safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Flow {
		        func __safeDI_t4Builder() -> T4 {
		            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
		            #sourceLocation(file: "\(fixtures["T4.swift"])", line: 8)
		            let t4BuilderAlias: Instantiator<T4> = t4Builder
		            #sourceLocation()
		            return if let safeDIBuilder = safeDIOverrides.t4Builder { safeDIBuilder(t4BuilderAlias, nil) } else { T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil) }
		        }
		        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
		        func __safeDI_t3() -> T3 {
		            func __safeDI_t4() -> T4 {
		                #sourceLocation(file: "\(fixtures["T4.swift"])", line: 8)
		                let t4BuilderAlias: Instantiator<T4> = t4Builder
		                #sourceLocation()
		                return if let safeDIBuilder = safeDIOverrides.t3.t4 { safeDIBuilder(t4BuilderAlias, nil) } else { T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil) }
		            }
		            let t4: T4 = __safeDI_t4()
		            return T3.__safeDI_init(t4: t4, safeDIBuilder: safeDIOverrides.t3.safeDIBuilder)
		        }
		        let t3: T3 = __safeDI_t3()
		        func __safeDI_t2Builder() -> T2 {
		            if let safeDIBuilder = safeDIOverrides.t2Builder { safeDIBuilder(t3) } else { T2(t3: t3) }
		        }
		        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
		        return Flow(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
		    }
		}

		extension Flow {
		    public enum __safeDI_Flow_mock_51799E6AA5E7B634 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `T3` is constructed within the public mock trees of module `Feature`.
		nonisolated public struct __safeDI_Feature_T3_MockConfiguration {
		    public init(
		        t4: ((Instantiator<T4>, Instantiator<T2>?) -> T4)? = nil,
		        _ safeDIBuilder: ((T4) -> T3)? = nil
		    ) {
		        __safeDI_storage = __safeDI_Storage(
		            t4: t4,
		            safeDIBuilder: safeDIBuilder
		        )
		    }

		    public var t4: ((Instantiator<T4>, Instantiator<T2>?) -> T4)? { __safeDI_storage.t4 }
		    /// Overrides how `T3` is constructed. Parameters match the type’s initializer or custom mock method.
		    public var safeDIBuilder: ((T4) -> T3)? { __safeDI_storage.safeDIBuilder }

		    private let __safeDI_storage: __safeDI_Storage

		    private final class __safeDI_Storage {
		        init(
		            t4: ((Instantiator<T4>, Instantiator<T2>?) -> T4)?,
		            safeDIBuilder: ((T4) -> T3)?
		        ) {
		            self.t4 = t4
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let t4: ((Instantiator<T4>, Instantiator<T2>?) -> T4)?
		        let safeDIBuilder: ((T4) -> T3)?
		    }
		}

		extension T3 {
		    static func __safeDI_init(t4: T4, safeDIBuilder: ((T4) -> T3)?) -> T3 {
		        if let safeDIBuilder { safeDIBuilder(t4) } else { T3(t4: t4) }
		    }
		}
		#endif

		"""])
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature.map { $0.replacingOccurrences(of: "generateDependencyTree: true, ", with: "") }, app: [root]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().flow.t4Builder.instantiate().t4BuilderAlias.instantiate()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderToTypeItBuildsInSeamsInitializer_whenThatTypeReceivesItOnlyIfAvailableBesideAReceiveLeftNilThroughAValue() async throws {
		// `t4Builder`'s receive of `t2Builder` is left `nil`, since `t2Builder` waits on `t3`, which requires `t4Builder`;
		// `T4` still gets `t4Builder`, which builds it.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(feature: Self.typeReceivingItsBuilderBesideReceiveLeftNilFeature(seamAttributes: ""), app: [Self.flowRoot]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Flow {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        func __safeDI_t4Builder() -> T4 {
		            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
		            return T4(t4Builder: t4Builder, t2Builder: nil)
		        }
		        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
		        let t3 = T3(t4Builder: t4Builder)
		        func __safeDI_t2Builder() -> T2 {
		            T2(t3: t3)
		        }
		        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
		        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
		    }
		}

		extension Flow {
		    public enum __safeDI_Flow_CBF29CE484222325 {}
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderToTypeItBuildsInSeamsPublicMock_whenThatTypeReceivesItOnlyIfAvailableBesideAReceiveLeftNilThroughAValue() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(feature: Self.typeReceivingItsBuilderBesideReceiveLeftNilFeature(seamAttributes: ", generateMock: .public"), app: [Self.flowRoot]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, ["Feature.swift": generatedFileHeader + """
		extension Flow {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public init() {
		        func __safeDI_t4Builder() -> T4 {
		            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
		            return T4(t4Builder: t4Builder, t2Builder: nil)
		        }
		        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
		        let t3 = T3(t4Builder: t4Builder)
		        func __safeDI_t2Builder() -> T2 {
		            T2(t3: t3)
		        }
		        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
		        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
		    }
		}

		extension Flow {
		    public enum __safeDI_Flow_CBF29CE484222325 {}
		}

		#if DEBUG
		extension Flow {
		    /// Overrides for the mock dependency tree.
		    nonisolated public struct SafeDIOverrides {
		        public init(
		            t4Builder: ((Instantiator<T4>?, Instantiator<T2>?) -> T4)? = nil,
		            t3: ((Instantiator<T4>) -> T3)? = nil,
		            t2Builder: ((T3?) -> T2)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                t4Builder: t4Builder,
		                t3: t3,
		                t2Builder: t2Builder
		            )
		        }

		        public var t4Builder: ((Instantiator<T4>?, Instantiator<T2>?) -> T4)? { __safeDI_storage.t4Builder }
		        public var t3: ((Instantiator<T4>) -> T3)? { __safeDI_storage.t3 }
		        public var t2Builder: ((T3?) -> T2)? { __safeDI_storage.t2Builder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                t4Builder: ((Instantiator<T4>?, Instantiator<T2>?) -> T4)?,
		                t3: ((Instantiator<T4>) -> T3)?,
		                t2Builder: ((T3?) -> T2)?
		            ) {
		                self.t4Builder = t4Builder
		                self.t3 = t3
		                self.t2Builder = t2Builder
		            }

		            let t4Builder: ((Instantiator<T4>?, Instantiator<T2>?) -> T4)?
		            let t3: ((Instantiator<T4>) -> T3)?
		            let t2Builder: ((T3?) -> T2)?
		        }
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Flow {
		        Flow.__safeDI_mock(safeDIOverrides: safeDIOverrides)
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Flow {
		        func __safeDI_t4Builder() -> T4 {
		            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
		            return if let safeDIBuilder = safeDIOverrides.t4Builder { safeDIBuilder(t4Builder, nil) } else { T4(t4Builder: t4Builder, t2Builder: nil) }
		        }
		        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
		        let t3 = if let safeDIBuilder = safeDIOverrides.t3 { safeDIBuilder(t4Builder) } else { T3(t4Builder: t4Builder) }
		        func __safeDI_t2Builder() -> T2 {
		            if let safeDIBuilder = safeDIOverrides.t2Builder { safeDIBuilder(t3) } else { T2(t3: t3) }
		        }
		        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
		        return Flow(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
		    }
		}

		extension Flow {
		    public enum __safeDI_Flow_mock_51799E6AA5E7B634 {}
		}
		#endif
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsWhatTheVisibleBuildBuilds_whenTypeInSeamsTreeReceivesItsBuilderOnlyIfAvailableBesideAReceiveLeftNilThroughAValue() async throws {
		let feature = Self.typeReceivingItsBuilderBesideReceiveLeftNilFeature(seamAttributes: "")
		let modules = Self.modules(feature: feature, app: [Self.flowRoot])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesEqualVisibleBuild(output, modules: modules, visibleModules: Self.modules(feature: feature.map { $0.replacingOccurrences(of: "@Instantiable(generateDependencyTree: true)", with: "@Instantiable") }, app: [Self.flowRoot]), probes: [
			DifferentialValueProbe("Root()"),
			DifferentialValueProbe("Root().flow.t4Builder.instantiate().t4Builder?.instantiate()"),
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Flow {
			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
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
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

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
			""",
		])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Flow {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier<__safeDI_Built> {
			        public let aBuilder: __safeDI_WidgetCarrier_A<__safeDI_Built>

			        public init(aBuilder: __safeDI_WidgetCarrier_A<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(aBuilder: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_A<__safeDI_Built> {
			        public let widget: (Instantiator<B>) -> __safeDI_Built

			        public init(widget: @escaping (Instantiator<B>) -> __safeDI_Built) {
			            self.widget = widget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(widget: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_widgetBuilder: __safeDI_WidgetCarrier<any Widget>) {
			        let __safeDI_widgetBuilder_aBuilder = __safeDI_widgetBuilder.aBuilder
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            let widget: any Widget = __safeDI_widgetBuilder_aBuilder.widget(bBuilder)
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
			    public enum __safeDI_Flow_A812EE8BDE488F76 {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_widgetBuilder_Flow() -> Flow.__safeDI_WidgetCarrier<any Widget> {
			            .init(aBuilder: __safeDI_widgetBuilder_Flow_A_Scope())
			        }
			        func __safeDI_widgetBuilder_Flow_A_Scope() -> Flow.__safeDI_WidgetCarrier_A<any Widget> {
			            .init(widget: { scope_bBuilder in
			                let bBuilder = scope_bBuilder
			                let widget: any Widget = DefaultWidget(bBuilder: bBuilder)
			                return widget
			            })
			        }
			        func __safeDI_flow() -> Flow {
			            _ = Flow.__safeDI_Flow_A812EE8BDE488F76.self\(Self.callComment(module: "Feature"))
			            return Flow(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Flow())
			        }
			        let flow: Flow = __safeDI_flow()
			        self.init(flow: flow)
			    }
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Flow {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_A<__safeDI_Built> {
			        public let widget: (SendableInstantiator<B>) -> __safeDI_Built

			        public init(widget: @escaping (SendableInstantiator<B>) -> __safeDI_Built) {
			            self.widget = widget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(widget: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetSendableCarrier<__safeDI_Built>: Sendable {
			        public let aBuilder: @Sendable () -> __safeDI_WidgetCarrier_A<__safeDI_Built>

			        public init(aBuilder: @escaping @Sendable () -> __safeDI_WidgetCarrier_A<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(aBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_widgetSendableBuilder: __safeDI_WidgetSendableCarrier<any Widget>) {
			        @Sendable nonisolated func __safeDI_aBuilder() -> A {
			            let __safeDI_widgetSendableBuilder_aBuilder = __safeDI_widgetSendableBuilder.aBuilder()
			            let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
			            let widget: any Widget = __safeDI_widgetSendableBuilder_aBuilder.widget(bBuilder)
			            return A(bBuilder: bBuilder, widget: widget)
			        }
			        let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
			        @Sendable nonisolated func __safeDI_bBuilder() -> B {
			            let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}

			extension Flow {
			    public enum __safeDI_Flow_F90885A67E70FC66 {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        @Sendable nonisolated func __safeDI_widgetSendableBuilder_Flow() -> Flow.__safeDI_WidgetSendableCarrier<any Widget> {
			            .init(aBuilder: { __safeDI_widgetBuilder_Flow_A_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_widgetBuilder_Flow_A_Scope() -> Flow.__safeDI_WidgetCarrier_A<any Widget> {
			            .init(widget: { scope_bBuilder in
			                let bBuilder = scope_bBuilder
			                let widget: any Widget = DefaultWidget(bBuilder: bBuilder)
			                return widget
			            })
			        }
			        func __safeDI_flow() -> Flow {
			            _ = Flow.__safeDI_Flow_F90885A67E70FC66.self\(Self.callComment(module: "Feature"))
			            return Flow(__safeDI_widgetSendableBuilder: __safeDI_widgetSendableBuilder_Flow())
			        }
			        let flow: Flow = __safeDI_flow()
			        self.init(flow: flow)
			    }
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Flow {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier<__safeDI_Built> {
			        public let xBuilder: __safeDI_WidgetCarrier_X<__safeDI_Built>

			        public init(xBuilder: __safeDI_WidgetCarrier_X<__safeDI_Built>) {
			            self.xBuilder = xBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(xBuilder: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_X<__safeDI_Built> {
			        public let p: __safeDI_WidgetCarrier_P<__safeDI_Built>

			        public init(p: __safeDI_WidgetCarrier_P<__safeDI_Built>) {
			            self.p = p
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(p: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_P<__safeDI_Built> {
			        public let aBuilder: __safeDI_WidgetCarrier_A<__safeDI_Built>

			        public init(aBuilder: __safeDI_WidgetCarrier_A<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(aBuilder: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_A<__safeDI_Built> {
			        public let widget: (Instantiator<B>, Instantiator<X>) -> __safeDI_Built

			        public init(widget: @escaping (Instantiator<B>, Instantiator<X>) -> __safeDI_Built) {
			            self.widget = widget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(widget: { _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_widgetBuilder: __safeDI_WidgetCarrier<any Widget>) {
			        let __safeDI_widgetBuilder_xBuilder = __safeDI_widgetBuilder.xBuilder
			        func __safeDI_xBuilder() -> X {
			            let __safeDI_widgetBuilder_p = __safeDI_widgetBuilder_xBuilder.p
			            func __safeDI_p() -> P {
			                let __safeDI_widgetBuilder_aBuilder = __safeDI_widgetBuilder_p.aBuilder
			                func __safeDI_aBuilder() -> A {
			                    let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                    let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			                    let widget: any Widget = __safeDI_widgetBuilder_aBuilder.widget(bBuilder, xBuilder)
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
			    public enum __safeDI_Flow_924FCAF3F7011E9C {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_widgetBuilder_Flow() -> Flow.__safeDI_WidgetCarrier<any Widget> {
			            .init(xBuilder: __safeDI_widgetBuilder_Flow_X_Scope())
			        }
			        func __safeDI_widgetBuilder_Flow_X_Scope() -> Flow.__safeDI_WidgetCarrier_X<any Widget> {
			            .init(p: __safeDI_widgetBuilder_Flow_P_Scope())
			        }
			        func __safeDI_widgetBuilder_Flow_P_Scope() -> Flow.__safeDI_WidgetCarrier_P<any Widget> {
			            .init(aBuilder: __safeDI_widgetBuilder_Flow_A_Scope())
			        }
			        func __safeDI_widgetBuilder_Flow_A_Scope() -> Flow.__safeDI_WidgetCarrier_A<any Widget> {
			            .init(widget: { scope_bBuilder, scope_xBuilder in
			                let bBuilder = scope_bBuilder
			                let widget: any Widget = DefaultWidget(bBuilder: bBuilder)
			                return widget
			            })
			        }
			        func __safeDI_flow() -> Flow {
			            _ = Flow.__safeDI_Flow_924FCAF3F7011E9C.self\(Self.callComment(module: "Feature"))
			            return Flow(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Flow())
			        }
			        let flow: Flow = __safeDI_flow()
			        self.init(flow: flow)
			    }
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Flow {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier<__safeDI_Built> {
			        public let aBuilder: __safeDI_WidgetCarrier_A<__safeDI_Built>
			        public let bBuilder: __safeDI_WidgetCarrier_B<__safeDI_Built>

			        public init(aBuilder: __safeDI_WidgetCarrier_A<__safeDI_Built>, bBuilder: __safeDI_WidgetCarrier_B<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			            self.bBuilder = bBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(aBuilder: .init(__safeDI_noScope: __safeDI_builder), bBuilder: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_A<__safeDI_Built> {
			        public let widget: (Instantiator<B>, Mark) -> __safeDI_Built

			        public init(widget: @escaping (Instantiator<B>, Mark) -> __safeDI_Built) {
			            self.widget = widget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(widget: { _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_B<__safeDI_Built> {
			        public let widget: (Instantiator<A>, Mark) -> __safeDI_Built

			        public init(widget: @escaping (Instantiator<A>, Mark) -> __safeDI_Built) {
			            self.widget = widget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(widget: { _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_widgetBuilder: __safeDI_WidgetCarrier<any Widget>) {
			        let __safeDI_aBuilder_loopLevels = __safeDI_LoopLevels_882C7FF9310B1D89(
			            __safeDI_widgetBuilder_aBuilder: __safeDI_widgetBuilder.aBuilder,
			            __safeDI_widgetBuilder_bBuilder: __safeDI_widgetBuilder.bBuilder
			        )
			        func __safeDI_aBuilder() -> A {
			            let __safeDI_widgetBuilder_aBuilder = __safeDI_aBuilder_loopLevels.__safeDI_widgetBuilder_aBuilder
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            let mark = Mark()
			            let widget: any Widget = __safeDI_widgetBuilder_aBuilder.widget(bBuilder, mark)
			            return A(mark: mark, bBuilder: bBuilder, widget: widget)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        func __safeDI_bBuilder() -> B {
			            let __safeDI_widgetBuilder_bBuilder = __safeDI_aBuilder_loopLevels.__safeDI_widgetBuilder_bBuilder
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let mark = Mark()
			            let widget: any Widget = __safeDI_widgetBuilder_bBuilder.widget(aBuilder, mark)
			            return B(mark: mark, aBuilder: aBuilder, widget: widget)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
			    }

			    /// Holds the payloads of a loop of builders, so that each builder function of the loop captures one reference.
			    nonisolated private final class __safeDI_LoopLevels_882C7FF9310B1D89 {
			        init(
			            __safeDI_widgetBuilder_aBuilder: __safeDI_WidgetCarrier_A<any Widget>,
			            __safeDI_widgetBuilder_bBuilder: __safeDI_WidgetCarrier_B<any Widget>
			        ) {
			            self.__safeDI_widgetBuilder_aBuilder = __safeDI_widgetBuilder_aBuilder
			            self.__safeDI_widgetBuilder_bBuilder = __safeDI_widgetBuilder_bBuilder
			        }

			        let __safeDI_widgetBuilder_aBuilder: __safeDI_WidgetCarrier_A<any Widget>
			        let __safeDI_widgetBuilder_bBuilder: __safeDI_WidgetCarrier_B<any Widget>
			    }
			}

			extension Flow {
			    public enum __safeDI_Flow_B9495D8C150DFE63 {}
			}
			""",
		])
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, [
			"App.swift": generatedFileHeader + """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_widgetBuilder_Flow() -> Flow.__safeDI_WidgetCarrier<any Widget> {
			            .init(aBuilder: __safeDI_widgetBuilder_Flow_A_Scope(), bBuilder: __safeDI_widgetBuilder_Flow_B_Scope())
			        }
			        func __safeDI_widgetBuilder_Flow_A_Scope() -> Flow.__safeDI_WidgetCarrier_A<any Widget> {
			            .init(widget: { scope_bBuilder, scope_mark in
			                let mark = scope_mark
			                let widget: any Widget = DefaultWidget(mark: mark)
			                return widget
			            })
			        }
			        func __safeDI_widgetBuilder_Flow_B_Scope() -> Flow.__safeDI_WidgetCarrier_B<any Widget> {
			            .init(widget: { scope_aBuilder, scope_mark in
			                let mark = scope_mark
			                let widget: any Widget = DefaultWidget(mark: mark)
			                return widget
			            })
			        }
			        func __safeDI_flow() -> Flow {
			            _ = Flow.__safeDI_Flow_B9495D8C150DFE63.self\(Self.callComment(module: "Feature"))
			            return Flow(__safeDI_widgetBuilder: __safeDI_widgetBuilder_Flow())
			        }
			        let flow: Flow = __safeDI_flow()
			        self.init(flow: flow)
			    }
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Flow {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier<__safeDI_Built> {
			        public let bBuilder: __safeDI_WidgetCarrier_B<__safeDI_Built>

			        public init(bBuilder: __safeDI_WidgetCarrier_B<__safeDI_Built>) {
			            self.bBuilder = bBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(bBuilder: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_B<__safeDI_Built> {
			        public let widget: (Instantiator<A>, Mark) -> __safeDI_Built

			        public init(widget: @escaping (Instantiator<A>, Mark) -> __safeDI_Built) {
			            self.widget = widget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(widget: { _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_widgetBuilder: __safeDI_WidgetCarrier<any Widget>) {
			        let __safeDI_widgetBuilder_bBuilder = __safeDI_widgetBuilder.bBuilder
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            let mark = Mark()
			            return A(mark: mark, bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let mark = Mark()
			            let widget: any Widget = __safeDI_widgetBuilder_bBuilder.widget(aBuilder, mark)
			            return B(mark: mark, aBuilder: aBuilder, widget: widget)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}

			extension Flow {
			    public enum __safeDI_Flow_718D345E8C7D7CDC {}
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Flow {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier<__safeDI_Built> {
			        public let aBuilder: __safeDI_WidgetCarrier_A<__safeDI_Built>
			        public let bBuilder: __safeDI_WidgetCarrier_B<__safeDI_Built>
			        public let leaf: (Instantiator<A>, Instantiator<B>, Instantiator<C>) -> __safeDI_WidgetCarrier_Leaf<__safeDI_Built>

			        public init(aBuilder: __safeDI_WidgetCarrier_A<__safeDI_Built>, bBuilder: __safeDI_WidgetCarrier_B<__safeDI_Built>, leaf: @escaping (Instantiator<A>, Instantiator<B>, Instantiator<C>) -> __safeDI_WidgetCarrier_Leaf<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			            self.bBuilder = bBuilder
			            self.leaf = leaf
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(aBuilder: .init(__safeDI_noScope: __safeDI_builder), bBuilder: .init(__safeDI_noScope: __safeDI_builder), leaf: { _, _, _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_A<__safeDI_Built> {
			        public let leaf: (Instantiator<C>, Mark) -> __safeDI_WidgetCarrier_Leaf<__safeDI_Built>
			        public let widget: (Instantiator<C>, Mark, Leaf) -> __safeDI_Built

			        public init(leaf: @escaping (Instantiator<C>, Mark) -> __safeDI_WidgetCarrier_Leaf<__safeDI_Built>, widget: @escaping (Instantiator<C>, Mark, Leaf) -> __safeDI_Built) {
			            self.leaf = leaf
			            self.widget = widget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(leaf: { _, _ in .init(__safeDI_noScope: __safeDI_builder) }, widget: { _, _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_B<__safeDI_Built> {
			        public let leaf: (Instantiator<A>, Instantiator<C>) -> __safeDI_WidgetCarrier_Leaf<__safeDI_Built>

			        public init(leaf: @escaping (Instantiator<A>, Instantiator<C>) -> __safeDI_WidgetCarrier_Leaf<__safeDI_Built>) {
			            self.leaf = leaf
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(leaf: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_Leaf<__safeDI_Built> {
			        public let widget: () -> __safeDI_Built

			        public init(widget: @escaping () -> __safeDI_Built) {
			            self.widget = widget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(widget: { __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_widgetBuilder: __safeDI_WidgetCarrier<any Widget>) {
			        let __safeDI_aBuilder_loopLevels = __safeDI_LoopLevels_882C7FF9310B1D89(
			            __safeDI_widgetBuilder_aBuilder: __safeDI_widgetBuilder.aBuilder,
			            __safeDI_widgetBuilder_bBuilder: __safeDI_widgetBuilder.bBuilder
			        )
			        func __safeDI_aBuilder() -> A {
			            let __safeDI_widgetBuilder_aBuilder = __safeDI_aBuilder_loopLevels.__safeDI_widgetBuilder_aBuilder
			            let cBuilder = Instantiator<C> {
			                __safeDI_cBuilder(id: $0)
			            }
			            let mark = Mark()
			            let __safeDI_widgetBuilder_leaf = __safeDI_widgetBuilder_aBuilder.leaf(cBuilder, mark)
			            func __safeDI_leaf() -> Leaf {
			                let widget: any Widget = __safeDI_widgetBuilder_leaf.widget()
			                return Leaf(cBuilder: cBuilder, widget: widget)
			            }
			            let leaf: Leaf = __safeDI_leaf()
			            let widget: any Widget = __safeDI_widgetBuilder_aBuilder.widget(cBuilder, mark, leaf)
			            return A(mark: mark, leaf: leaf, widget: widget)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        func __safeDI_bBuilder() -> B {
			            let __safeDI_widgetBuilder_bBuilder = __safeDI_aBuilder_loopLevels.__safeDI_widgetBuilder_bBuilder
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let cBuilder = Instantiator<C> {
			                __safeDI_cBuilder(id: $0)
			            }
			            let __safeDI_widgetBuilder_leaf = __safeDI_widgetBuilder_bBuilder.leaf(aBuilder, cBuilder)
			            func __safeDI_leaf() -> Leaf {
			                let widget: any Widget = __safeDI_widgetBuilder_leaf.widget()
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
			        let __safeDI_widgetBuilder_leaf = __safeDI_widgetBuilder.leaf(aBuilder, bBuilder, cBuilder)
			        func __safeDI_leaf() -> Leaf {
			            let widget: any Widget = __safeDI_widgetBuilder_leaf.widget()
			            return Leaf(cBuilder: cBuilder, widget: widget)
			        }
			        let leaf: Leaf = __safeDI_leaf()
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder, cBuilder: cBuilder, leaf: leaf)
			    }

			    /// Holds the payloads of a loop of builders, so that each builder function of the loop captures one reference.
			    nonisolated private final class __safeDI_LoopLevels_882C7FF9310B1D89 {
			        init(
			            __safeDI_widgetBuilder_aBuilder: __safeDI_WidgetCarrier_A<any Widget>,
			            __safeDI_widgetBuilder_bBuilder: __safeDI_WidgetCarrier_B<any Widget>
			        ) {
			            self.__safeDI_widgetBuilder_aBuilder = __safeDI_widgetBuilder_aBuilder
			            self.__safeDI_widgetBuilder_bBuilder = __safeDI_widgetBuilder_bBuilder
			        }

			        let __safeDI_widgetBuilder_aBuilder: __safeDI_WidgetCarrier_A<any Widget>
			        let __safeDI_widgetBuilder_bBuilder: __safeDI_WidgetCarrier_B<any Widget>
			    }
			}

			extension Flow {
			    public enum __safeDI_Flow_2A5D7C0AC32A2FE8 {}
			}
			""",
		])
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
		expectGeneratedFiles(output.modules["Feature"]?.generatedFiles, [
			"Feature.swift": generatedFileHeader + """
			extension Hub {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier<__safeDI_Built> {
			        public let flow: (Instantiator<B>?) -> __safeDI_WidgetCarrier_Flow<__safeDI_Built>
			        public let a: (Instantiator<B>?, Flow) -> __safeDI_WidgetCarrier_A<__safeDI_Built>

			        public init(flow: @escaping (Instantiator<B>?) -> __safeDI_WidgetCarrier_Flow<__safeDI_Built>, a: @escaping (Instantiator<B>?, Flow) -> __safeDI_WidgetCarrier_A<__safeDI_Built>) {
			            self.flow = flow
			            self.a = a
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(flow: { _ in .init(__safeDI_noScope: __safeDI_builder) }, a: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_Flow<__safeDI_Built> {
			        public let aBuilder: __safeDI_WidgetCarrier_A<__safeDI_Built>

			        public init(aBuilder: __safeDI_WidgetCarrier_A<__safeDI_Built>) {
			            self.aBuilder = aBuilder
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(aBuilder: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_WidgetCarrier_A<__safeDI_Built> {
			        public let widget: (Instantiator<B>?, Mark) -> __safeDI_Built

			        public init(widget: @escaping (Instantiator<B>?, Mark) -> __safeDI_Built) {
			            self.widget = widget
			        }

			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(widget: { _, _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_bBuilder bBuilder: Instantiator<B>?, __safeDI_widgetBuilder: __safeDI_WidgetCarrier<any Widget>) {
			        let __safeDI_widgetBuilder_flow = __safeDI_widgetBuilder.flow(bBuilder)
			        func __safeDI_flow() -> Flow {
			            let __safeDI_widgetBuilder_aBuilder = __safeDI_widgetBuilder_flow.aBuilder
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                let mark = Mark()
			                let widget: any Widget = __safeDI_widgetBuilder_aBuilder.widget(bBuilder, mark)
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
			        let __safeDI_widgetBuilder_a = __safeDI_widgetBuilder.a(bBuilder, flow)
			        func __safeDI_a() -> A {
			            let mark = Mark()
			            let widget: any Widget = __safeDI_widgetBuilder_a.widget(bBuilder, mark)
			            return A(mark: mark, bBuilder: bBuilder, widget: widget)
			        }
			        let a: A = __safeDI_a()
			        self.init(flow: flow, a: a)
			    }
			}

			extension Hub {
			    public enum __safeDI_Hub_4A13B76BB56BF2A2 {}
			}
			""",
		])
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
			\(fixtures["App"]!["DefaultDetail.swift"]):9:5: error: `DefaultDetail` receives `\(property)`, which `Screen`’s tree is building where it calls the builder for `Screen`’s `detailBuilder: ErasedInstantiator<(), any Detail>` (`detailBuilder` of `defaultDetail_DetailBuilder`). Inline, `DefaultDetail` can get an instantiator of its own, made from the function `Screen`’s initializer declares for `detailBuilder`, which code generated outside module `Feature` cannot refer to. Instantiate `detailBuilder` on a type above `Screen`, and receive it on `Screen` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `DefaultDetail` in module `Feature` or a module it lists among its SafeDI dependencies.
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
			\(fixtures["App"]!["DefaultWidget.swift"]):9:5: error: `DefaultWidget` receives `\(property)`, which `Flow`’s tree is building where it calls the builder for `A`’s `widget: any Widget` (`widget` of `widgetBuilder`). Inline, `DefaultWidget` can get an instantiator of its own, made from the function `Flow`’s initializer declares for `aBuilder`, which code generated outside module `Feature` cannot refer to. Instantiate `aBuilder` on a type above `Flow`, and receive it on `Flow` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `Widget` in module `Feature` or a module it lists among its SafeDI dependencies.
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
		// builder is handed does not carry `settingsBuilder`, which `Screen` builds after it. `DefaultSettings` receives the
		// `detailBuilder` `Screen` instantiates, so no type above `Screen` can build `settingsBuilder`: one type of `App` that
		// instantiates both, in place of both, puts the loop in one tree.
		let receive = onlyIfAvailable
			? "@Received(onlyIfAvailable: true) let settingsBuilder: ErasedInstantiator<(), any Settings>?"
			: "@Received let settingsBuilder: ErasedInstantiator<(), any Settings>"
		let property = onlyIfAvailable ? "settingsBuilder: ErasedInstantiator<(), any Settings>?" : "settingsBuilder: ErasedInstantiator<(), any Settings>"
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["DefaultDetail.swift"]):9:5: error: `DefaultDetail` receives `\(property)`, which `Screen`’s tree builds only after it calls the builder for `Screen`’s `detailBuilder: ErasedInstantiator<(), any Detail>` (`detailBuilder` of `defaultDetail_DetailBuilder`), so SafeDI does not hand it to that builder. Declare `settingsBuilder` and `detailBuilder` on one type of module `App` instead, and have `Screen` instantiate a protocol that type fulfills in their place, so that type’s tree builds both, or declare an @Instantiable type that fulfills `DefaultDetail` in module `Feature` or a module it lists among its SafeDI dependencies.
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
		expectGeneratedFiles(generatedFiles, [
			"App.swift": generatedFileHeader + """
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
			            _ = Screen0.__safeDI_Screen0_50893F9C0248B961.self // If this line does not compile, compile the code SafeDI generates for module M0 into M0: under Bazel, add M0’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
			            _ = Screen1.__safeDI_Screen1_2BE0865BD7D69A88.self // If this line does not compile, compile the code SafeDI generates for module M1 into M1: under Bazel, add M1’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
			            _ = Screen2.__safeDI_Screen2_C1C57A76086D5BFE.self // If this line does not compile, compile the code SafeDI generates for module M2 into M2: under Bazel, add M2’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
			            _ = Screen3.__safeDI_Screen3_524F9E2FFF78377C.self // If this line does not compile, compile the code SafeDI generates for module M3 into M3: under Bazel, add M3’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
			            _ = Screen4.__safeDI_Screen4_FE5AE1EC58BBBC5A.self // If this line does not compile, compile the code SafeDI generates for module M4 into M4: under Bazel, add M4’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
			            _ = Screen5.__safeDI_Screen5_10637ED15C1B66CA.self // If this line does not compile, compile the code SafeDI generates for module M5 into M5: under Bazel, add M5’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
			            _ = Screen6.__safeDI_Screen6_2D1B4945D0F7A293.self // If this line does not compile, compile the code SafeDI generates for module M6 into M6: under Bazel, add M6’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
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
			            _ = Screen7.__safeDI_Screen7_B62CF5DD79251747.self // If this line does not compile, compile the code SafeDI generates for module M7 into M7: under Bazel, add M7’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Screen7(__safeDI_id: id, __safeDI_service: service, __safeDI_screen0Builder: screen0Builder, __safeDI_screen2Builder: screen2Builder, __safeDI_screen3Builder: screen3Builder)
			        }
			        let screen7Builder = ErasedInstantiator<Int, Screen> {
			            __safeDI_screen7Builder(id: $0)
			        }
			        self.init(service: service, screen0Builder: screen0Builder, screen1Builder: screen1Builder, screen2Builder: screen2Builder, screen3Builder: screen3Builder, screen4Builder: screen4Builder, screen5Builder: screen5Builder, screen6Builder: screen6Builder, screen7Builder: screen7Builder)
			    }
			}

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: (() -> Service)? = nil,
			            screen0Builder: Screen0.SafeDIMockConfiguration = .init(),
			            screen1Builder: Screen1.SafeDIMockConfiguration = .init(),
			            screen2Builder: Screen2.SafeDIMockConfiguration = .init(),
			            screen3Builder: Screen3.SafeDIMockConfiguration = .init(),
			            screen4Builder: Screen4.SafeDIMockConfiguration = .init(),
			            screen5Builder: Screen5.SafeDIMockConfiguration = .init(),
			            screen6Builder: Screen6.SafeDIMockConfiguration = .init(),
			            screen7Builder: Screen7.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                service: service,
			                screen0Builder: screen0Builder,
			                screen1Builder: screen1Builder,
			                screen2Builder: screen2Builder,
			                screen3Builder: screen3Builder,
			                screen4Builder: screen4Builder,
			                screen5Builder: screen5Builder,
			                screen6Builder: screen6Builder,
			                screen7Builder: screen7Builder
			            )
			        }

			        var service: (() -> Service)? { __safeDI_storage.service }
			        var screen0Builder: Screen0.SafeDIMockConfiguration { __safeDI_storage.screen0Builder }
			        var screen1Builder: Screen1.SafeDIMockConfiguration { __safeDI_storage.screen1Builder }
			        var screen2Builder: Screen2.SafeDIMockConfiguration { __safeDI_storage.screen2Builder }
			        var screen3Builder: Screen3.SafeDIMockConfiguration { __safeDI_storage.screen3Builder }
			        var screen4Builder: Screen4.SafeDIMockConfiguration { __safeDI_storage.screen4Builder }
			        var screen5Builder: Screen5.SafeDIMockConfiguration { __safeDI_storage.screen5Builder }
			        var screen6Builder: Screen6.SafeDIMockConfiguration { __safeDI_storage.screen6Builder }
			        var screen7Builder: Screen7.SafeDIMockConfiguration { __safeDI_storage.screen7Builder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                service: (() -> Service)?,
			                screen0Builder: Screen0.SafeDIMockConfiguration,
			                screen1Builder: Screen1.SafeDIMockConfiguration,
			                screen2Builder: Screen2.SafeDIMockConfiguration,
			                screen3Builder: Screen3.SafeDIMockConfiguration,
			                screen4Builder: Screen4.SafeDIMockConfiguration,
			                screen5Builder: Screen5.SafeDIMockConfiguration,
			                screen6Builder: Screen6.SafeDIMockConfiguration,
			                screen7Builder: Screen7.SafeDIMockConfiguration
			            ) {
			                self.service = service
			                self.screen0Builder = screen0Builder
			                self.screen1Builder = screen1Builder
			                self.screen2Builder = screen2Builder
			                self.screen3Builder = screen3Builder
			                self.screen4Builder = screen4Builder
			                self.screen5Builder = screen5Builder
			                self.screen6Builder = screen6Builder
			                self.screen7Builder = screen7Builder
			            }

			            let service: (() -> Service)?
			            let screen0Builder: Screen0.SafeDIMockConfiguration
			            let screen1Builder: Screen1.SafeDIMockConfiguration
			            let screen2Builder: Screen2.SafeDIMockConfiguration
			            let screen3Builder: Screen3.SafeDIMockConfiguration
			            let screen4Builder: Screen4.SafeDIMockConfiguration
			            let screen5Builder: Screen5.SafeDIMockConfiguration
			            let screen6Builder: Screen6.SafeDIMockConfiguration
			            let screen7Builder: Screen7.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service() }
			        func __safeDI_screen0Builder(id: Int, __safeDI_Screen0_configuration: Screen0.SafeDIMockConfiguration) -> Screen {
			            let screen2Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen2Builder(id: $0, __safeDI_Screen2_configuration: safeDIOverrides.screen2Builder)
			            }
			            let screen3Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen3Builder(id: $0, __safeDI_Screen3_configuration: safeDIOverrides.screen3Builder)
			            }
			            let screen4Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen4Builder(id: $0, __safeDI_Screen4_configuration: safeDIOverrides.screen4Builder)
			            }
			            let model0 = if let safeDIBuilder = __safeDI_Screen0_configuration.model0 { safeDIBuilder(id, service) } else { Model0(id: id, service: service) }
			            return if let safeDIBuilder = __safeDI_Screen0_configuration.safeDIBuilder { safeDIBuilder(id, service, model0, screen2Builder, screen3Builder, screen4Builder) } else { Screen0(id: id, service: service, model0: model0, screen2Builder: screen2Builder, screen3Builder: screen3Builder, screen4Builder: screen4Builder) }
			        }
			        func __safeDI_screen1Builder(id: Int, __safeDI_Screen1_configuration: Screen1.SafeDIMockConfiguration) -> Screen {
			            let screen2Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen2Builder(id: $0, __safeDI_Screen2_configuration: safeDIOverrides.screen2Builder)
			            }
			            let screen3Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen3Builder(id: $0, __safeDI_Screen3_configuration: safeDIOverrides.screen3Builder)
			            }
			            let screen7Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen7Builder(id: $0, __safeDI_Screen7_configuration: safeDIOverrides.screen7Builder)
			            }
			            let model1 = if let safeDIBuilder = __safeDI_Screen1_configuration.model1 { safeDIBuilder(id, service) } else { Model1(id: id, service: service) }
			            return if let safeDIBuilder = __safeDI_Screen1_configuration.safeDIBuilder { safeDIBuilder(id, service, model1, screen2Builder, screen3Builder, screen7Builder) } else { Screen1(id: id, service: service, model1: model1, screen2Builder: screen2Builder, screen3Builder: screen3Builder, screen7Builder: screen7Builder) }
			        }
			        func __safeDI_screen2Builder(id: Int, __safeDI_Screen2_configuration: Screen2.SafeDIMockConfiguration) -> Screen {
			            let screen1Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen1Builder(id: $0, __safeDI_Screen1_configuration: safeDIOverrides.screen1Builder)
			            }
			            let screen4Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen4Builder(id: $0, __safeDI_Screen4_configuration: safeDIOverrides.screen4Builder)
			            }
			            let screen7Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen7Builder(id: $0, __safeDI_Screen7_configuration: safeDIOverrides.screen7Builder)
			            }
			            let model2 = if let safeDIBuilder = __safeDI_Screen2_configuration.model2 { safeDIBuilder(id, service) } else { Model2(id: id, service: service) }
			            return if let safeDIBuilder = __safeDI_Screen2_configuration.safeDIBuilder { safeDIBuilder(id, service, model2, screen1Builder, screen4Builder, screen7Builder) } else { Screen2(id: id, service: service, model2: model2, screen1Builder: screen1Builder, screen4Builder: screen4Builder, screen7Builder: screen7Builder) }
			        }
			        func __safeDI_screen3Builder(id: Int, __safeDI_Screen3_configuration: Screen3.SafeDIMockConfiguration) -> Screen {
			            let screen0Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen0Builder(id: $0, __safeDI_Screen0_configuration: safeDIOverrides.screen0Builder)
			            }
			            let screen2Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen2Builder(id: $0, __safeDI_Screen2_configuration: safeDIOverrides.screen2Builder)
			            }
			            let screen6Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen6Builder(id: $0, __safeDI_Screen6_configuration: safeDIOverrides.screen6Builder)
			            }
			            let model3 = if let safeDIBuilder = __safeDI_Screen3_configuration.model3 { safeDIBuilder(id, service) } else { Model3(id: id, service: service) }
			            return if let safeDIBuilder = __safeDI_Screen3_configuration.safeDIBuilder { safeDIBuilder(id, service, model3, screen0Builder, screen2Builder, screen6Builder) } else { Screen3(id: id, service: service, model3: model3, screen0Builder: screen0Builder, screen2Builder: screen2Builder, screen6Builder: screen6Builder) }
			        }
			        func __safeDI_screen4Builder(id: Int, __safeDI_Screen4_configuration: Screen4.SafeDIMockConfiguration) -> Screen {
			            let screen2Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen2Builder(id: $0, __safeDI_Screen2_configuration: safeDIOverrides.screen2Builder)
			            }
			            let screen3Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen3Builder(id: $0, __safeDI_Screen3_configuration: safeDIOverrides.screen3Builder)
			            }
			            let screen5Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen5Builder(id: $0, __safeDI_Screen5_configuration: safeDIOverrides.screen5Builder)
			            }
			            let model4 = if let safeDIBuilder = __safeDI_Screen4_configuration.model4 { safeDIBuilder(id, service) } else { Model4(id: id, service: service) }
			            return if let safeDIBuilder = __safeDI_Screen4_configuration.safeDIBuilder { safeDIBuilder(id, service, model4, screen2Builder, screen3Builder, screen5Builder) } else { Screen4(id: id, service: service, model4: model4, screen2Builder: screen2Builder, screen3Builder: screen3Builder, screen5Builder: screen5Builder) }
			        }
			        func __safeDI_screen5Builder(id: Int, __safeDI_Screen5_configuration: Screen5.SafeDIMockConfiguration) -> Screen {
			            let screen3Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen3Builder(id: $0, __safeDI_Screen3_configuration: safeDIOverrides.screen3Builder)
			            }
			            let screen6Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen6Builder(id: $0, __safeDI_Screen6_configuration: safeDIOverrides.screen6Builder)
			            }
			            let screen7Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen7Builder(id: $0, __safeDI_Screen7_configuration: safeDIOverrides.screen7Builder)
			            }
			            let model5 = if let safeDIBuilder = __safeDI_Screen5_configuration.model5 { safeDIBuilder(id, service) } else { Model5(id: id, service: service) }
			            return if let safeDIBuilder = __safeDI_Screen5_configuration.safeDIBuilder { safeDIBuilder(id, service, model5, screen3Builder, screen6Builder, screen7Builder) } else { Screen5(id: id, service: service, model5: model5, screen3Builder: screen3Builder, screen6Builder: screen6Builder, screen7Builder: screen7Builder) }
			        }
			        func __safeDI_screen6Builder(id: Int, __safeDI_Screen6_configuration: Screen6.SafeDIMockConfiguration) -> Screen {
			            let screen0Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen0Builder(id: $0, __safeDI_Screen0_configuration: safeDIOverrides.screen0Builder)
			            }
			            let screen4Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen4Builder(id: $0, __safeDI_Screen4_configuration: safeDIOverrides.screen4Builder)
			            }
			            let screen5Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen5Builder(id: $0, __safeDI_Screen5_configuration: safeDIOverrides.screen5Builder)
			            }
			            let model6 = if let safeDIBuilder = __safeDI_Screen6_configuration.model6 { safeDIBuilder(id, service) } else { Model6(id: id, service: service) }
			            return if let safeDIBuilder = __safeDI_Screen6_configuration.safeDIBuilder { safeDIBuilder(id, service, model6, screen0Builder, screen4Builder, screen5Builder) } else { Screen6(id: id, service: service, model6: model6, screen0Builder: screen0Builder, screen4Builder: screen4Builder, screen5Builder: screen5Builder) }
			        }
			        func __safeDI_screen7Builder(id: Int, __safeDI_Screen7_configuration: Screen7.SafeDIMockConfiguration) -> Screen {
			            let screen0Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen0Builder(id: $0, __safeDI_Screen0_configuration: safeDIOverrides.screen0Builder)
			            }
			            let screen2Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen2Builder(id: $0, __safeDI_Screen2_configuration: safeDIOverrides.screen2Builder)
			            }
			            let screen3Builder = ErasedInstantiator<Int, Screen> {
			                __safeDI_screen3Builder(id: $0, __safeDI_Screen3_configuration: safeDIOverrides.screen3Builder)
			            }
			            let model7 = if let safeDIBuilder = __safeDI_Screen7_configuration.model7 { safeDIBuilder(id, service) } else { Model7(id: id, service: service) }
			            return if let safeDIBuilder = __safeDI_Screen7_configuration.safeDIBuilder { safeDIBuilder(id, service, model7, screen0Builder, screen2Builder, screen3Builder) } else { Screen7(id: id, service: service, model7: model7, screen0Builder: screen0Builder, screen2Builder: screen2Builder, screen3Builder: screen3Builder) }
			        }
			        let screen0Builder = ErasedInstantiator<Int, Screen> {
			            __safeDI_screen0Builder(id: $0, __safeDI_Screen0_configuration: safeDIOverrides.screen0Builder)
			        }
			        let screen1Builder = ErasedInstantiator<Int, Screen> {
			            __safeDI_screen1Builder(id: $0, __safeDI_Screen1_configuration: safeDIOverrides.screen1Builder)
			        }
			        let screen2Builder = ErasedInstantiator<Int, Screen> {
			            __safeDI_screen2Builder(id: $0, __safeDI_Screen2_configuration: safeDIOverrides.screen2Builder)
			        }
			        let screen3Builder = ErasedInstantiator<Int, Screen> {
			            __safeDI_screen3Builder(id: $0, __safeDI_Screen3_configuration: safeDIOverrides.screen3Builder)
			        }
			        let screen4Builder = ErasedInstantiator<Int, Screen> {
			            __safeDI_screen4Builder(id: $0, __safeDI_Screen4_configuration: safeDIOverrides.screen4Builder)
			        }
			        let screen5Builder = ErasedInstantiator<Int, Screen> {
			            __safeDI_screen5Builder(id: $0, __safeDI_Screen5_configuration: safeDIOverrides.screen5Builder)
			        }
			        let screen6Builder = ErasedInstantiator<Int, Screen> {
			            __safeDI_screen6Builder(id: $0, __safeDI_Screen6_configuration: safeDIOverrides.screen6Builder)
			        }
			        let screen7Builder = ErasedInstantiator<Int, Screen> {
			            __safeDI_screen7Builder(id: $0, __safeDI_Screen7_configuration: safeDIOverrides.screen7Builder)
			        }
			        return Root(service: service, screen0Builder: screen0Builder, screen1Builder: screen1Builder, screen2Builder: screen2Builder, screen3Builder: screen3Builder, screen4Builder: screen4Builder, screen5Builder: screen5Builder, screen6Builder: screen6Builder, screen7Builder: screen7Builder)
			    }
			}
			#endif

			#if DEBUG
			extension Screen0 {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            model0: ((Int, Service) -> Model0)? = nil,
			            _ safeDIBuilder: ((Int, Service, Model0, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen0)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                model0: model0,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var model0: ((Int, Service) -> Model0)? { __safeDI_storage.model0 }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int, Service, Model0, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen0)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                model0: ((Int, Service) -> Model0)?,
			                safeDIBuilder: ((Int, Service, Model0, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen0)?
			            ) {
			                self.model0 = model0
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let model0: ((Int, Service) -> Model0)?
			            let safeDIBuilder: ((Int, Service, Model0, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen0)?
			        }
			    }
			}

			extension Screen1 {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            model1: ((Int, Service) -> Model1)? = nil,
			            _ safeDIBuilder: ((Int, Service, Model1, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen1)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                model1: model1,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var model1: ((Int, Service) -> Model1)? { __safeDI_storage.model1 }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int, Service, Model1, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen1)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                model1: ((Int, Service) -> Model1)?,
			                safeDIBuilder: ((Int, Service, Model1, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen1)?
			            ) {
			                self.model1 = model1
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let model1: ((Int, Service) -> Model1)?
			            let safeDIBuilder: ((Int, Service, Model1, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen1)?
			        }
			    }
			}

			extension Screen2 {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            model2: ((Int, Service) -> Model2)? = nil,
			            _ safeDIBuilder: ((Int, Service, Model2, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen2)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                model2: model2,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var model2: ((Int, Service) -> Model2)? { __safeDI_storage.model2 }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int, Service, Model2, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen2)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                model2: ((Int, Service) -> Model2)?,
			                safeDIBuilder: ((Int, Service, Model2, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen2)?
			            ) {
			                self.model2 = model2
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let model2: ((Int, Service) -> Model2)?
			            let safeDIBuilder: ((Int, Service, Model2, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen2)?
			        }
			    }
			}

			extension Screen3 {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            model3: ((Int, Service) -> Model3)? = nil,
			            _ safeDIBuilder: ((Int, Service, Model3, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen3)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                model3: model3,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var model3: ((Int, Service) -> Model3)? { __safeDI_storage.model3 }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int, Service, Model3, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen3)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                model3: ((Int, Service) -> Model3)?,
			                safeDIBuilder: ((Int, Service, Model3, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen3)?
			            ) {
			                self.model3 = model3
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let model3: ((Int, Service) -> Model3)?
			            let safeDIBuilder: ((Int, Service, Model3, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen3)?
			        }
			    }
			}

			extension Screen4 {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            model4: ((Int, Service) -> Model4)? = nil,
			            _ safeDIBuilder: ((Int, Service, Model4, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen4)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                model4: model4,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var model4: ((Int, Service) -> Model4)? { __safeDI_storage.model4 }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int, Service, Model4, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen4)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                model4: ((Int, Service) -> Model4)?,
			                safeDIBuilder: ((Int, Service, Model4, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen4)?
			            ) {
			                self.model4 = model4
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let model4: ((Int, Service) -> Model4)?
			            let safeDIBuilder: ((Int, Service, Model4, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen4)?
			        }
			    }
			}

			extension Screen5 {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            model5: ((Int, Service) -> Model5)? = nil,
			            _ safeDIBuilder: ((Int, Service, Model5, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen5)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                model5: model5,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var model5: ((Int, Service) -> Model5)? { __safeDI_storage.model5 }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int, Service, Model5, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen5)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                model5: ((Int, Service) -> Model5)?,
			                safeDIBuilder: ((Int, Service, Model5, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen5)?
			            ) {
			                self.model5 = model5
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let model5: ((Int, Service) -> Model5)?
			            let safeDIBuilder: ((Int, Service, Model5, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen5)?
			        }
			    }
			}

			extension Screen6 {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            model6: ((Int, Service) -> Model6)? = nil,
			            _ safeDIBuilder: ((Int, Service, Model6, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen6)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                model6: model6,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var model6: ((Int, Service) -> Model6)? { __safeDI_storage.model6 }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int, Service, Model6, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen6)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                model6: ((Int, Service) -> Model6)?,
			                safeDIBuilder: ((Int, Service, Model6, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen6)?
			            ) {
			                self.model6 = model6
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let model6: ((Int, Service) -> Model6)?
			            let safeDIBuilder: ((Int, Service, Model6, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen6)?
			        }
			    }
			}

			extension Screen7 {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            model7: ((Int, Service) -> Model7)? = nil,
			            _ safeDIBuilder: ((Int, Service, Model7, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen7)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                model7: model7,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var model7: ((Int, Service) -> Model7)? { __safeDI_storage.model7 }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Int, Service, Model7, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen7)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                model7: ((Int, Service) -> Model7)?,
			                safeDIBuilder: ((Int, Service, Model7, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen7)?
			            ) {
			                self.model7 = model7
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let model7: ((Int, Service) -> Model7)?
			            let safeDIBuilder: ((Int, Service, Model7, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>, ErasedInstantiator<Int, Screen>) -> Screen7)?
			        }
			    }
			}
			#endif

			""",
		])
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

	/// The feature module of a seam, `Flow`, declared with `generateDependencyTree: true` and `seamAttributes`, whose `T4`
	/// receives `t4Builder`, which builds it, only if available, and `t2Builder` only if available, which waits on `t3`,
	/// which requires `t4Builder`.
	private static func typeReceivingItsBuilderBesideReceiveLeftNilFeature(seamAttributes: String) -> [String] {
		[
			seamFixtureType(named: "T2", declarations: ["@Received(onlyIfAvailable: true) let t3: T3?"]),
			seamFixtureType(named: "T3", declarations: ["@Received let t4Builder: Instantiator<T4>"]),
			seamFixtureType(named: "T4", declarations: ["@Received(onlyIfAvailable: true) let t4Builder: Instantiator<T4>?", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"]),
			seamFixtureType(named: "Flow", isSeam: true, declarations: ["@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"])
				.replacingOccurrences(of: "@Instantiable(generateDependencyTree: true)", with: "@Instantiable(generateDependencyTree: true\(seamAttributes))"),
		]
	}

	/// The root of the app module that instantiates `Flow`.
	private static let flowRoot = seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let flow: Flow"])

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
		lines += ["        ) {", "            __safeDI_storage = __safeDI_Storage(", "                service: service" + (screens.isEmpty ? "" : ",")]
		lines += screens.enumerated().map { position, screen in "                screen\(screen)Builder: screen\(screen)Builder" + (position == screens.count - 1 ? "" : ",") }
		lines += ["            )", "        }", "", "        var service: (() -> Service)? { __safeDI_storage.service }"]
		lines += screens.map { "        var screen\($0)Builder: Screen\($0).SafeDIMockConfiguration { __safeDI_storage.screen\($0)Builder }" }
		lines += ["", "        private let __safeDI_storage: __safeDI_Storage", "", "        private final class __safeDI_Storage {", "            init(", "                service: (() -> Service)?" + (screens.isEmpty ? "" : ",")]
		lines += screens.enumerated().map { position, screen in "                screen\(screen)Builder: Screen\(screen).SafeDIMockConfiguration" + (position == screens.count - 1 ? "" : ",") }
		lines += ["            ) {", "                self.service = service"]
		lines += screens.map { "                self.screen\($0)Builder = screen\($0)Builder" }
		lines += ["            }", "", "            let service: (() -> Service)?"]
		lines += screens.map { "            let screen\($0)Builder: Screen\($0).SafeDIMockConfiguration" }
		lines += ["        }", "    }", "", "    static func mock(", "        safeDIOverrides: SafeDIOverrides = .init()", "    ) -> Root {"]
		lines.append("        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service() }")
		// A loop's members declare every function first, then every wrapper. Every screen's function is handed its
		// configuration, which a member's rebinding reads from the mock's overrides, as the loop's level declares it.
		func mockWrapper(of screen: Int, indentation: String) -> [String] {
			[
				"\(indentation)let screen\(screen)Builder = ErasedInstantiator<Int, Screen> {",
				"\(indentation)    __safeDI_screen\(screen)Builder(id: $0, __safeDI_Screen\(screen)_configuration: safeDIOverrides.screen\(screen)Builder)",
				"\(indentation)}",
			]
		}
		for unit in units {
			for screen in unit {
				let opened = edges[screen].map { "screen\($0)Builder" }
				let configuration = "__safeDI_Screen\(screen)_configuration"
				lines.append("        func __safeDI_screen\(screen)Builder(id: Int, __safeDI_Screen\(screen)_configuration: Screen\(screen).SafeDIMockConfiguration) -> Screen {")
				for openedScreen in screensRebound(by: screen) {
					lines += mockWrapper(of: openedScreen, indentation: "            ")
				}
				lines.append("            let model\(screen) = if let safeDIBuilder = \(configuration).model\(screen) { safeDIBuilder(id, service) } else { Model\(screen)(id: id, service: service) }")
				let builderArguments = (["id", "service", "model\(screen)"] + opened).joined(separator: ", ")
				let initializerArguments = (["id: id", "service: service", "model\(screen): model\(screen)"] + opened.map { "\($0): \($0)" }).joined(separator: ", ")
				lines.append("            return if let safeDIBuilder = \(configuration).safeDIBuilder { safeDIBuilder(\(builderArguments)) } else { Screen\(screen)(\(initializerArguments)) }")
				lines.append("        }")
			}
			for screen in unit {
				lines += mockWrapper(of: screen, indentation: "        ")
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
				"            __safeDI_storage = __safeDI_Storage(",
				"                model\(screen): model\(screen),",
				"                safeDIBuilder: safeDIBuilder",
				"            )",
				"        }",
				"",
				"        var model\(screen): ((Int, Service) -> Model\(screen))? { __safeDI_storage.model\(screen) }",
				"        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.",
				"        var safeDIBuilder: \(builderType) { __safeDI_storage.safeDIBuilder }",
				"",
				"        private let __safeDI_storage: __safeDI_Storage",
				"",
				"        private final class __safeDI_Storage {",
				"            init(",
				"                model\(screen): ((Int, Service) -> Model\(screen))?,",
				"                safeDIBuilder: \(builderType)",
				"            ) {",
				"                self.model\(screen) = model\(screen)",
				"                self.safeDIBuilder = safeDIBuilder",
				"            }",
				"",
				"            let model\(screen): ((Int, Service) -> Model\(screen))?",
				"            let safeDIBuilder: \(builderType)",
				"        }",
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
