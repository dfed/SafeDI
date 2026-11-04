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
@testable import SafeDITool

/// A lazy cycle that re-enters a seam calls the seam's generated initializer again, passing the nearest declaration of
/// each label the seam receives, as the Manual's `@Received` rule says. Inline, the builder function the cycle closes on
/// takes the labels a scope between it and the cycle-closing scope declares again as parameters, so both builds agree. A
/// call in that function's body of a tier that omits such a parameter drops the value each call of the function passes.
struct SafeDIToolSeamLazyCycleTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A lazy cycle that re-enters the seam

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclarationToSeamReenteredThroughLazyCycle_whenTypeInsideSeamDeclaresLabelSeamReceives() async throws {
		// `T3`, the seam, instantiates `T0` through an instantiator and receives `t1Builder`; `T0` declares its own `t1Builder` and
		// instantiates `T3` again. The nested call passes `T0`'s declaration, the nearest, as the `@Received` rule says, and so does
		// the inline build's cycle-closing scope, which passes it to `Root`'s builder function.
		let fixture = Self.lazyCycleFixture
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t1Builder() -> T1 {
			            T1()
			        }
			        let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			        func __safeDI_t3Builder() -> T3 {
			            _ = T3.__safeDI_T3_637A336A650792AD.self
			            return T3(t1Builder: t1Builder)
			        }
			        let t3Builder = Instantiator<T3>(__safeDI_t3Builder)
			        self.init(t1Builder: t1Builder, t3Builder: t3Builder)
			    }
			}
			""",
			"T3+SafeDI.swift": generatedFileHeader + """
			extension T3 {
			    public convenience init(t1Builder: Instantiator<T1>) {
			        func __safeDI_t0Builder() -> T0 {
			            func __safeDI_t1Builder() -> T1 {
			                T1()
			            }
			            let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			            func __safeDI_t3Builder() -> T3 {
			                _ = T3.__safeDI_T3_637A336A650792AD.self
			                return T3(t1Builder: t1Builder)
			            }
			            let t3Builder = Instantiator<T3>(__safeDI_t3Builder)
			            return T0(t1Builder: t1Builder, t3Builder: t3Builder)
			        }
			        let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
			        self.init(t0Builder: t0Builder, t1Builder: t1Builder)
			    }
			}

			extension T3 {
			    public enum __safeDI_T3_637A336A650792AD {}
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t1Builder() -> T1 {
			            T1()
			        }
			        let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			        func __safeDI_t3Builder(t1Builder: Instantiator<T1>) -> T3 {
			            func __safeDI_t0Builder() -> T0 {
			                func __safeDI_t1Builder() -> T1 {
			                    T1()
			                }
			                let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			                let t3Builder = Instantiator<T3> {
			                    __safeDI_t3Builder(t1Builder: t1Builder)
			                }
			                return T0(t1Builder: t1Builder, t3Builder: t3Builder)
			            }
			            let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
			            return T3(t0Builder: t0Builder, t1Builder: t1Builder)
			        }
			        let t3Builder = Instantiator<T3> {
			            __safeDI_t3Builder(t1Builder: t1Builder)
			        }
			        self.init(t1Builder: t1Builder, t3Builder: t3Builder)
			    }
			}
			""",
		])
		try expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(fixture), generatedFiles: output.dependencyTreeFiles),
			knownRight: DifferentialValuePath(fixtureFiles: Self.fixtureFiles(inlineFixture(fixture)), generatedFiles: inlineOutput.dependencyTreeFiles),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsHiddenErrorFromSeamsChain_whenTypeInsideSeamDeclaresLabelSeamReceivesWithAnotherType() async {
		// `T0` declares `t1Builder` as `Instantiator<Other>`, so the nested call's receive of `t1Builder: Instantiator<T1>` is hidden
		// beneath it: the hidden-label error from the seam's chain.
		let fixture = Self.hiddenCycleFixture
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["T3.swift"]):9:5: error: @Received property `t1Builder: Instantiator<T1>` is hidden in chain: T3 -> Instantiator<T0> -> T3. `T0` declares `t1Builder: Instantiator<Other>` with the same label, so the types below `T0` receive `t1Builder: Instantiator<Other>` instead. Give `t1Builder: Instantiator<Other>` on `T0` a different label to fix.
			\(fixtures["T0.swift"]):8:5: note: `t1Builder: Instantiator<Other>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// Inline, the cycle-closing scope would pass `T0`'s declaration to `Root`'s builder function: the same error, from
		// `Root`'s chain.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["T3.swift"]):9:5: error: @Received property `t1Builder: Instantiator<T1>` is hidden in chain: Root -> Instantiator<T3> -> Instantiator<T0> -> T3. `T0` declares `t1Builder: Instantiator<Other>` with the same label, so the types below `T0` receive `t1Builder: Instantiator<Other>` instead. Give `t1Builder: Instantiator<Other>` on `T0` a different label to fix.
			\(fixtures["T0.swift"]):8:5: note: `t1Builder: Instantiator<Other>` is declared here
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: inlineFixture(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: A lazy cycle around a call of a tier that omits a parameter

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtScopeBetween_whenCycleClosingScopePassesValueThatTierCalledInClosedOnFunctionOmits() async {
		// `Mid` declares `theme` between `A` and a scope that closes the cycle on `A`'s builder function, which therefore takes
		// `theme`: `Root` passes `nil`, `Mid`'s cycle-closing scope its own `theme`, and `Detour`'s the function's parameter. The
		// function's body calls `Service`'s `public` tier, which omits `theme`: built inline, the `Badge` of the `A` built again
		// under `Mid` would be handed `Mid`'s.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			Self.tierOmissionError(provider: "Mid", fixtures)
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.tierOmissionModules(appPackage: "Other", appFiles: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
				seamFixtureType(named: "A", declarations: ["@Instantiated let service: Service", "@Instantiated let midBuilder: Instantiator<Mid>", "@Instantiated let detourBuilder: Instantiator<Detour>"]),
				seamFixtureType(named: "Mid", declarations: ["@Forwarded let theme: any Theme", "@Instantiated let aBuilder: Instantiator<A>"]),
				seamFixtureType(named: "Detour", declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtScopeBetweenAlone_whenScopeDeclaringFunctionBuildsItsDeclarationAfterCallingIt() async {
		// `Root`'s `theme` receives `aBuilder`, so it is built after it, and `Root`'s call of `A`'s builder function passes `nil`:
		// only `Mid`'s cycle-closing scope passes the function a `theme` that `Service`'s `public` tier omits.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			Self.tierOmissionError(provider: "Mid", fixtures)
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.tierOmissionModules(appPackage: "Other", appFiles: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let theme: any Theme"]),
				seamFixtureType(named: "AppTheme", declarations: ["@Received let aBuilder: Instantiator<A>"], conformances: ", Theme")
					.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Theme.self])\n"),
				seamFixtureType(named: "A", declarations: ["@Instantiated let service: Service", "@Instantiated let midBuilder: Instantiator<Mid>"]),
				seamFixtureType(named: "Mid", declarations: ["@Forwarded let theme: any Theme", "@Instantiated let aBuilder: Instantiator<A>"]),
			]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtEachDeclarationCallsPass_whenFunctionsCallPassesParameterOfEnclosingFunction() async {
		// `B`'s builder function takes `theme`, which `Mid` declares before closing the cycle on it, and is declared in the body of
		// `A`'s, which takes `theme` too, since `X` declares it before closing the cycle on `A`: `A`'s function passes its parameter
		// on to `B`'s, and `Shell` and `X`'s cycle-closing scope pass it theirs. Built inline, the `Badge` in `B`'s body would be
		// handed each of the three, which `Service`'s `public` tier omits.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			["Mid", "Shell", "X"].map { Self.tierOmissionError(provider: $0, fixtures) }.joined(separator: "\n")
		}) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.tierOmissionModules(appPackage: "Other", appFiles: [
				seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let shellBuilder: Instantiator<Shell>"]),
				seamFixtureType(named: "Shell", declarations: ["@Forwarded let theme: any Theme", "@Instantiated let aBuilder: Instantiator<A>"]),
				seamFixtureType(named: "A", declarations: ["@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let xBuilder: Instantiator<X>"]),
				seamFixtureType(named: "X", declarations: ["@Forwarded let theme: any Theme", "@Instantiated let aBuilder: Instantiator<A>"]),
				seamFixtureType(named: "B", declarations: ["@Instantiated let service: Service", "@Instantiated let midBuilder: Instantiator<Mid>"]),
				seamFixtureType(named: "Mid", declarations: ["@Forwarded let theme: any Theme", "@Instantiated let bBuilder: Instantiator<B>"]),
			]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsTierPassingNothing_whenCycleClosingScopeIsBuiltInsideTreeOfDeclarationBetween() async throws {
		// The cycle closes inside the tree of `Mid`'s `theme`, which is still being built there, so the cycle-closing scope passes
		// `nil`, as `Root` does: no call holds a value the `public` tier omits. The values agree with a build in `Feature`'s
		// package, whose `package` tier takes `theme`.
		let appFiles = [
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let aBuilder: Instantiator<A>"]),
			seamFixtureType(named: "A", declarations: ["@Instantiated let service: Service", "@Instantiated let midBuilder: Instantiator<Mid>"]),
			seamFixtureType(named: "Mid", declarations: ["@Instantiated let theme: any Theme"]),
			seamFixtureType(named: "AppTheme", declarations: ["@Instantiated let aBuilder: Instantiator<A>"], conformances: ", Theme")
				.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Theme.self])\n"),
		]
		let modules = Self.tierOmissionModules(appPackage: "Other", appFiles: appFiles)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		extension Root {
		    public init() {
		        func __safeDI_aBuilder(theme: (any Theme)?) -> A {
		            func __safeDI_service() -> Service {
		                _ = Service.__safeDI_Service_27F6F01DC5D0EF8E.self
		                return Service()
		            }
		            let service: Service = __safeDI_service()
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_theme() -> AppTheme {
		                    let aBuilder = Instantiator<A> {
		                        __safeDI_aBuilder(theme: nil)
		                    }
		                    return AppTheme(aBuilder: aBuilder)
		                }
		                let theme: any Theme = __safeDI_theme()
		                return Mid(theme: theme)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A(service: service, midBuilder: midBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(theme: nil)
		        }
		        self.init(aBuilder: aBuilder)
		    }
		}
		"""])
		guard compileVerificationIsEnabled else { return }
		#expect(try #require(output.compilation).failure == nil)
		let samePackageModules = Self.tierOmissionModules(appPackage: "Shop", appFiles: appFiles)
		let samePackageOutput = try await executeSafeDIToolMultiModuleTest(modules: samePackageModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try expectDifferentialValuesAgree(
			feature: Self.differentialValuePath(of: output, modules: modules),
			knownRight: Self.differentialValuePath(of: samePackageOutput, modules: samePackageModules),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesLazyCycleOnHolePropertyInsideFill_whenRootFillsSeamsBuilder() async throws {
		// `Root` fills the builder of `Service`'s erased hole `routerBuilder` with `Router`, whose `tBuilder` builds `T`, which
		// instantiates `routerBuilder` again: a lazy cycle that closes on the hole's property inside the fill. `T` declares
		// `analytics` again, so the function the cycle closes on, declared inside the fill, takes `analytics`, which the
		// fill passes from the field it binds and `T` passes its own, as any scope's function does. Generation ends, and
		// every module compiles.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "pkg", swiftFileContent: [
					"""
					@Instantiable
					public final class Analytics: Instantiable {
					    public init() {}
					}

					public protocol Routing {}

					public struct AnyRouting {
					    public init(_ routing: any Routing) {}
					}

					@Instantiable
					public struct Profile: Instantiable {
					    public init(routing: AnyRouting) {
					        self.routing = routing
					    }

					    @Received let routing: AnyRouting
					}

					@Instantiable(generateDependencyTree: true)
					public final class Service: Instantiable {
					    public init(analytics: Analytics, routerBuilder: ErasedInstantiator<(), AnyRouting>) {
					        self.analytics = analytics
					        self.routerBuilder = routerBuilder
					    }

					    @Received let analytics: Analytics
					    @Instantiated(fulfilledByType: "Router", erasedToConcreteExistential: true) let routerBuilder: ErasedInstantiator<(), AnyRouting>
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
					"""
					import Core

					@Instantiable
					public final class Router: Instantiable, Routing {
					    public init(analytics: Analytics, tBuilder: Instantiator<T>) {
					        self.analytics = analytics
					        self.tBuilder = tBuilder
					    }

					    @Received let analytics: Analytics
					    @Instantiated let tBuilder: Instantiator<T>
					}

					@Instantiable
					public final class T: Instantiable {
					    public init(analytics: Analytics, routerBuilder: ErasedInstantiator<(), AnyRouting>) {
					        self.analytics = analytics
					        self.routerBuilder = routerBuilder
					    }

					    @Instantiated let analytics: Analytics
					    @Instantiated(fulfilledByType: "Router", erasedToConcreteExistential: true) let routerBuilder: ErasedInstantiator<(), AnyRouting>
					}

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(analytics: Analytics, service: Service) {
					        self.analytics = analytics
					        self.service = service
					    }

					    @Instantiated let analytics: Analytics
					    @Instantiated let service: Service
					}
					""",
				], dependencies: ["Core"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif

		extension Root {
		    public convenience init() {
		        let analytics = Analytics()
		        func __safeDI_service() -> Service {
		            _ = Service.__safeDI_Service_F2D3F3FED14603BE.self
		            func __safeDI_routerBuilderBuilder(_ scope: Service.SafeDIScope_Service_routerBuilder) -> ErasedInstantiator<(), AnyRouting> {
		                let analytics = scope.analytics
		                func __safeDI_routerBuilder(analytics: Analytics) -> Router {
		                    func __safeDI_tBuilder() -> T {
		                        let analytics = Analytics()
		                        let routerBuilder = ErasedInstantiator<(), AnyRouting> {
		                            AnyRouting(__safeDI_routerBuilder(analytics: analytics))
		                        }
		                        return T(analytics: analytics, routerBuilder: routerBuilder)
		                    }
		                    let tBuilder = Instantiator<T>(__safeDI_tBuilder)
		                    return Router(analytics: analytics, tBuilder: tBuilder)
		                }
		                let routerBuilder = ErasedInstantiator<(), AnyRouting> {
		                    AnyRouting(__safeDI_routerBuilder(analytics: analytics))
		                }
		                return routerBuilder
		            }
		            return Service(analytics: analytics, routerBuilderBuilder: __safeDI_routerBuilderBuilder)
		        }
		        let service: Service = __safeDI_service()
		        self.init(analytics: analytics, service: service)
		    }
		}
		"""])
		if compileVerificationIsEnabled {
			let compilation = try #require(output.compilation)
			#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 })
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtScopeBetween_whenCycleClosingScopePassesValueThatPublicMockTierCalledInClosedOnFunctionOmits() async {
		// As for a seam's tier: `Screen`'s mock builds `A` again under `Mid`, and the inline mock would hand `Mid`'s `filter` to
		// `TokenCache`, in the tree of the `public` mock of `Service` that `A`'s builder function calls, which omits `filter`.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["Mid.swift"]):11:5: error: `Mid` provides `filter: Filter`, but the `public` mock SafeDI generated for `Service` in module `Core`, the narrowest one module `App` can call, does not take it: `Service.mock` takes `filter` only on its `package` tier, so this call would pass `nil` to `TokenCache`, which the inline mock would hand `filter`. `Filter` is `package` as far as SafeDI can tell: SafeDI reads no declaration of it, and every initializer, `instantiate(…)` and mock method that mentions it in module `Core` or on a type that receives it is `package` (`TokenCache.init(filter:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `TokenCache.init(filter:)` to `public`; mention `Filter` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; give `Filter` a `public` `mockOnly` mock (`@Instantiable(mockOnly: true) public extension Filter { public static func mock() -> Filter }`), which proves `Filter` `public`; or stop providing `filter` on this path.
			\(fixtures["Core"]!["Service.swift"]):15:5: note: `TokenCache` receives `filter: Filter?` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": """
					import SafeDI

					#if canImport(Foundation)
					public struct Filter {
					    public init() {}
					}
					#endif

					@Instantiable
					package struct TokenCache: Instantiable {
					    package init(filter: Filter?) {
					        self.filter = filter
					    }

					    @Received(onlyIfAvailable: true) let filter: Filter?
					}

					@Instantiable(generateMock: .public)
					public struct Service: Instantiable {
					    package init(tokenCache: TokenCache) {
					        self.tokenCache = tokenCache
					    }

					    @Instantiated let tokenCache: TokenCache
					}
					"""]),
					ModuleFixture(name: "App", packageName: "app", swiftFileContent: [
						seamFixtureType(named: "Screen", declarations: ["@Instantiated let aBuilder: Instantiator<A>"])
							.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n"),
						seamFixtureType(named: "A", declarations: ["@Instantiated let service: Service", "@Instantiated let midBuilder: Instantiator<Mid>"]),
						seamFixtureType(named: "Mid", declarations: ["@Forwarded let filter: Filter", "@Instantiated let aBuilder: Instantiator<A>"]),
					].map { "import Core\nimport SafeDI\n\n" + $0 }, dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: A lazy cycle around a call of a public mock, for a label the mock binds nothing for

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilWhereClosedOnFunctionIsDeclared_whenOnlyCallOfPublicMockReceivesLabelAndNothingAboveProvidesIt() async throws {
		// `A`'s builder function calls `Service`'s `public` mock, which takes `filter` for `TokenCache`, and takes `filter` itself, since
		// `Mid` forwards it before closing the cycle on `A`. Only that call receives `filter`, so `Screen`'s internal mock binds
		// nothing for it, and passes the function `nil`, as a production root passes `nil` where nothing above provides a receive
		// only if available. `Mid`'s cycle-closing scope passes its own `filter`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.publicMockLazyCycleModules(core: Self.coreWhosePublicMockTakesFilter, appFiles: [
			Self.screen(generateMock: "true"),
			Self.aCallingPublicMock,
			Self.midForwardingFilter,
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.aBuilder = aBuilder
		        }

		        let aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_aBuilder(filter: Filter?) -> A {
		            _ = Service.__safeDI_Service_mock_7257C1618F8CE2B3.self
		            let service = Service.mock(filter: filter, safeDIOverrides: safeDIOverrides.aBuilder.service)
		            func __safeDI_midBuilder(filter: Filter) -> Mid {
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(filter: filter)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(filter, aBuilder) } else { Mid(filter: filter, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid> {
		                __safeDI_midBuilder(filter: $0)
		            }
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(service, midBuilder) } else { A(service: service, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(filter: nil)
		        }
		        return Screen(aBuilder: aBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Mid {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            _ safeDIBuilder: ((Filter, Instantiator<A>) -> Mid)? = nil
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((Filter, Instantiator<A>) -> Mid)?
		    }
		}

		extension A {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            service: Service.SafeDIOverrides = .init(),
		            midBuilder: Mid.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((Service, Instantiator<Mid>) -> A)? = nil
		        ) {
		            self.service = service
		            self.midBuilder = midBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let service: Service.SafeDIOverrides
		        let midBuilder: Mid.SafeDIMockConfiguration
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((Service, Instantiator<Mid>) -> A)?
		    }
		}
		#endif
		""" + "\n"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilWhereClosedOnFunctionIsDeclared_whenOnlyCallOfPublicMockReceivesInstantiatorAndNothingAboveProvidesIt() async throws {
		// As for a constant: only the call of `Service`'s `public` mock receives `filterBuilder: Instantiator<Filter>?`, so `Screen`'s
		// mock passes `A`'s builder function `nil`, and `Mid`'s cycle-closing scope its own `filterBuilder`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.publicMockLazyCycleModules(core: Self.coreWhosePublicMockTakesFilterBuilder, appFiles: [
			Self.screen(generateMock: "true"),
			Self.aCallingPublicMock,
			seamFixtureType(named: "Mid", declarations: ["@Forwarded let filterBuilder: Instantiator<Filter>", "@Instantiated let aBuilder: Instantiator<A>"]),
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.aBuilder = aBuilder
		        }

		        let aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_aBuilder(filterBuilder: Instantiator<Filter>?) -> A {
		            _ = Service.__safeDI_Service_mock_7BB6CDEEAD5D6D34.self
		            let service = Service.mock(filterBuilder: filterBuilder, safeDIOverrides: safeDIOverrides.aBuilder.service)
		            func __safeDI_midBuilder(filterBuilder: Instantiator<Filter>) -> Mid {
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(filterBuilder: filterBuilder)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(filterBuilder, aBuilder) } else { Mid(filterBuilder: filterBuilder, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid> {
		                __safeDI_midBuilder(filterBuilder: $0)
		            }
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(service, midBuilder) } else { A(service: service, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(filterBuilder: nil)
		        }
		        return Screen(aBuilder: aBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Mid {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            _ safeDIBuilder: ((Instantiator<Filter>, Instantiator<A>) -> Mid)? = nil
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((Instantiator<Filter>, Instantiator<A>) -> Mid)?
		    }
		}

		extension A {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            service: Service.SafeDIOverrides = .init(),
		            midBuilder: Mid.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((Service, Instantiator<Mid>) -> A)? = nil
		        ) {
		            self.service = service
		            self.midBuilder = midBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let service: Service.SafeDIOverrides
		        let midBuilder: Mid.SafeDIMockConfiguration
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((Service, Instantiator<Mid>) -> A)?
		    }
		}
		#endif
		""" + "\n"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilWhereClosedOnFunctionIsDeclaredAndCalledAgain_whenPublicMockOmitsLabelDeclaredBetweenAndCycleClosesInsideItsTree() async throws {
		// `Service`'s `public` mock omits `filter`, and `A`'s builder function takes it, since `Mid` declares it before the cycle closes
		// on `A`. The cycle closes inside the tree of `Mid`'s `filter`, which is still being built there, so the cycle-closing scope
		// passes `nil`, as `Screen`'s mock does, which binds nothing for `filter`: no call holds a value the mock omits. The mock twin
		// of `generate_callsTierPassingNothing_whenCycleClosingScopeIsBuiltInsideTreeOfDeclarationBetween`. The values agree with a
		// build in `Core`'s package, whose mock builds `Service`'s tree and takes `filter` as an override.
		let appFiles = [
			Self.screen(generateMock: "true"),
			Self.aCallingPublicMock,
			Self.midInstantiatingFilter,
			Self.appFilter,
		]
		let modules = Self.publicMockLazyCycleModules(core: Self.coreWhosePublicMockOmitsFilter, appFiles: appFiles)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.aBuilder = aBuilder
		        }

		        let aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_aBuilder(filter: (any FilterProtocol)?) -> A {
		            _ = Service.__safeDI_Service_mock_A107C7CF39C5CB30.self
		            let service = Service.mock(safeDIOverrides: safeDIOverrides.aBuilder.service)
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_filter() -> FilterProtocol {
		                    let aBuilder = Instantiator<A> {
		                        __safeDI_aBuilder(filter: nil)
		                    }
		                    return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.filter.safeDIBuilder { safeDIBuilder(aBuilder) } else { AppFilter(aBuilder: aBuilder) }
		                }
		                let filter: FilterProtocol = __safeDI_filter()
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(filter) } else { Mid(filter: filter) }
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(service, midBuilder) } else { A(service: service, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(filter: nil)
		        }
		        return Screen(aBuilder: aBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension AppFilter {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            _ safeDIBuilder: ((Instantiator<A>) -> AppFilter)? = nil
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((Instantiator<A>) -> AppFilter)?
		    }
		}

		extension Mid {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            filter: AppFilter.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((any FilterProtocol) -> Mid)? = nil
		        ) {
		            self.filter = filter
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let filter: AppFilter.SafeDIMockConfiguration
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((any FilterProtocol) -> Mid)?
		    }
		}

		extension A {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            service: Service.SafeDIOverrides = .init(),
		            midBuilder: Mid.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((Service, Instantiator<Mid>) -> A)? = nil
		        ) {
		            self.service = service
		            self.midBuilder = midBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let service: Service.SafeDIOverrides
		        let midBuilder: Mid.SafeDIMockConfiguration
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((Service, Instantiator<Mid>) -> A)?
		    }
		}
		#endif
		""" + "\n"])
		guard compileVerificationIsEnabled else { return }
		#expect(try #require(output.compilation).failure == nil)
		let samePackageModules = Self.publicMockLazyCycleModules(core: Self.coreWhosePublicMockOmitsFilter, appPackage: "pkg", appFiles: appFiles)
		let samePackageOutput = try await executeSafeDIToolMultiModuleTest(modules: samePackageModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try expectDifferentialValuesAgree(
			feature: Self.differentialValuePath(of: output, modules: modules),
			knownRight: Self.differentialValuePath(of: samePackageOutput, modules: samePackageModules),
			probes: [DifferentialValueProbe("Screen.mock()")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func publicMock_passesNilWhereClosedOnFunctionIsDeclared_whenEveryCallOfPublicMockOmitsLabel() async throws {
		// `Screen`'s `public` mock takes, as its own parameter, a label its calls of other modules' `public` mocks take. Its one call
		// omits `filter`, so it takes none, binds nothing for `filter`, and passes `A`'s builder function `nil`. The values agree with
		// a build in `Core`'s package, whose mock builds `Service`'s tree and takes `filter` as a parameter.
		let appFiles = [
			Self.screen(generateMock: ".public"),
			Self.aCallingPublicMock,
			Self.midInstantiatingFilter,
			Self.appFilter,
		]
		let modules = Self.publicMockLazyCycleModules(core: Self.coreWhosePublicMockOmitsFilter, appFiles: appFiles)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            aBuilder: __safeDI_App_A_MockConfiguration = .init()
		        ) {
		            self.aBuilder = aBuilder
		        }

		        public let aBuilder: __safeDI_App_A_MockConfiguration
		    }

		    public static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_aBuilder(filter: (any FilterProtocol)?) -> A {
		            _ = Service.__safeDI_Service_mock_A107C7CF39C5CB30.self
		            let service = Service.mock(safeDIOverrides: safeDIOverrides.aBuilder.service)
		            func __safeDI_midBuilder() -> Mid {
		                func __safeDI_filter() -> FilterProtocol {
		                    let aBuilder = Instantiator<A> {
		                        __safeDI_aBuilder(filter: nil)
		                    }
		                    return AppFilter.__safeDI_init(aBuilder: aBuilder, safeDIBuilder: safeDIOverrides.aBuilder.midBuilder.filter.safeDIBuilder)
		                }
		                let filter: FilterProtocol = __safeDI_filter()
		                return Mid.__safeDI_init(filter: filter, safeDIBuilder: safeDIOverrides.aBuilder.midBuilder.safeDIBuilder)
		            }
		            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
		            return A.__safeDI_init(service: service, midBuilder: midBuilder, safeDIBuilder: safeDIOverrides.aBuilder.safeDIBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(filter: nil)
		        }
		        return Screen(aBuilder: aBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_51799E6AA5E7B634 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `AppFilter` is constructed within the public mock trees of module `App`.
		public struct __safeDI_App_AppFilter_MockConfiguration {
		    public init(
		        _ safeDIBuilder: ((Instantiator<A>) -> AppFilter)? = nil
		    ) {
		        self.safeDIBuilder = safeDIBuilder
		    }

		    /// Overrides how `AppFilter` is constructed. Parameters match the type’s initializer or custom mock method.
		    public let safeDIBuilder: ((Instantiator<A>) -> AppFilter)?
		}

		extension AppFilter {
		    static func __safeDI_init(aBuilder: Instantiator<A>, safeDIBuilder: ((Instantiator<A>) -> AppFilter)?) -> AppFilter {
		        if let safeDIBuilder { safeDIBuilder(aBuilder) } else { AppFilter(aBuilder: aBuilder) }
		    }
		}

		/// Configuration for how `Mid` is constructed within the public mock trees of module `App`.
		public struct __safeDI_App_Mid_MockConfiguration {
		    public init(
		        filter: __safeDI_App_AppFilter_MockConfiguration = .init(),
		        _ safeDIBuilder: ((any FilterProtocol) -> Mid)? = nil
		    ) {
		        self.filter = filter
		        self.safeDIBuilder = safeDIBuilder
		    }

		    public let filter: __safeDI_App_AppFilter_MockConfiguration
		    /// Overrides how `Mid` is constructed. Parameters match the type’s initializer or custom mock method.
		    public let safeDIBuilder: ((any FilterProtocol) -> Mid)?
		}

		extension Mid {
		    static func __safeDI_init(filter: any FilterProtocol, safeDIBuilder: ((any FilterProtocol) -> Mid)?) -> Mid {
		        if let safeDIBuilder { safeDIBuilder(filter) } else { Mid(filter: filter) }
		    }
		}

		/// Configuration for how `A` is constructed within the public mock trees of module `App`.
		public struct __safeDI_App_A_MockConfiguration {
		    public init(
		        service: Service.SafeDIOverrides = .init(),
		        midBuilder: __safeDI_App_Mid_MockConfiguration = .init(),
		        _ safeDIBuilder: ((Service, Instantiator<Mid>) -> A)? = nil
		    ) {
		        self.service = service
		        self.midBuilder = midBuilder
		        self.safeDIBuilder = safeDIBuilder
		    }

		    public let service: Service.SafeDIOverrides
		    public let midBuilder: __safeDI_App_Mid_MockConfiguration
		    /// Overrides how `A` is constructed. Parameters match the type’s initializer or custom mock method.
		    public let safeDIBuilder: ((Service, Instantiator<Mid>) -> A)?
		}

		extension A {
		    static func __safeDI_init(service: Service, midBuilder: Instantiator<Mid>, safeDIBuilder: ((Service, Instantiator<Mid>) -> A)?) -> A {
		        if let safeDIBuilder { safeDIBuilder(service, midBuilder) } else { A(service: service, midBuilder: midBuilder) }
		    }
		}
		#endif
		""" + "\n"])
		guard compileVerificationIsEnabled else { return }
		#expect(try #require(output.compilation).failure == nil)
		let samePackageModules = Self.publicMockLazyCycleModules(core: Self.coreWhosePublicMockOmitsFilter, appPackage: "pkg", appFiles: appFiles)
		let samePackageOutput = try await executeSafeDIToolMultiModuleTest(modules: samePackageModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try expectDifferentialValuesAgree(
			feature: Self.differentialValuePath(of: output, modules: modules),
			knownRight: Self.differentialValuePath(of: samePackageOutput, modules: samePackageModules),
			probes: [DifferentialValueProbe("Screen.mock()")],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilWhereClosedOnFunctionIsDeclared_whenHandWrittenMockBuildsClosedOnType() async throws {
		// `A`'s hand-written mock builds `A` in the closed-on function, which calls `Service`'s `public` mock: as when `init` builds
		// it, `Screen`'s mock passes the function `nil` for `filter`.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.publicMockLazyCycleModules(core: Self.coreWhosePublicMockTakesFilter, appFiles: [
			Self.screen(generateMock: "true"),
			"""
			@Instantiable
			public struct A: Instantiable {
			    public init(service: Service, midBuilder: Instantiator<Mid>) {
			        self.service = service
			        self.midBuilder = midBuilder
			    }

			    public static func mock(service: Service, midBuilder: Instantiator<Mid>) -> A {
			        A(service: service, midBuilder: midBuilder)
			    }

			    @Instantiated let service: Service
			    @Instantiated let midBuilder: Instantiator<Mid>
			}
			""",
			Self.midForwardingFilter,
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.aBuilder = aBuilder
		        }

		        let aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_aBuilder(filter: Filter?) -> A {
		            _ = Service.__safeDI_Service_mock_7257C1618F8CE2B3.self
		            let service = Service.mock(filter: filter, safeDIOverrides: safeDIOverrides.aBuilder.service)
		            func __safeDI_midBuilder(filter: Filter) -> Mid {
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(filter: filter)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(filter, aBuilder) } else { Mid(filter: filter, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid> {
		                __safeDI_midBuilder(filter: $0)
		            }
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(service, midBuilder) } else { A.mock(service: service, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(filter: nil)
		        }
		        return Screen(aBuilder: aBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Mid {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            _ safeDIBuilder: ((Filter, Instantiator<A>) -> Mid)? = nil
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((Filter, Instantiator<A>) -> Mid)?
		    }
		}

		extension A {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            service: Service.SafeDIOverrides = .init(),
		            midBuilder: Mid.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((Service, Instantiator<Mid>) -> A)? = nil
		        ) {
		            self.service = service
		            self.midBuilder = midBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let service: Service.SafeDIOverrides
		        let midBuilder: Mid.SafeDIMockConfiguration
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((Service, Instantiator<Mid>) -> A)?
		    }
		}
		#endif
		""" + "\n"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesForwardedParameterWhereClosedOnFunctionIsDeclared_whenMockedTypeForwardsLabelOnlyCallOfPublicMockReceives() async throws {
		// `Screen` forwards `filter`, so its mock takes `filter` and passes it to `A`'s builder function.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.publicMockLazyCycleModules(core: Self.coreWhosePublicMockTakesFilter, appFiles: [
			Self.screen(generateMock: "true", declarations: ["@Forwarded let filter: Filter"]),
			Self.aCallingPublicMock,
			Self.midForwardingFilter,
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init()
		        ) {
		            self.aBuilder = aBuilder
		        }

		        let aBuilder: A.SafeDIMockConfiguration
		    }

		    static func mock(
		        filter: Filter,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_aBuilder(filter: Filter?) -> A {
		            _ = Service.__safeDI_Service_mock_7257C1618F8CE2B3.self
		            let service = Service.mock(filter: filter, safeDIOverrides: safeDIOverrides.aBuilder.service)
		            func __safeDI_midBuilder(filter: Filter) -> Mid {
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(filter: filter)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(filter, aBuilder) } else { Mid(filter: filter, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid> {
		                __safeDI_midBuilder(filter: $0)
		            }
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(service, midBuilder) } else { A(service: service, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(filter: filter)
		        }
		        return Screen(filter: filter, aBuilder: aBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Mid {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            _ safeDIBuilder: ((Filter, Instantiator<A>) -> Mid)? = nil
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((Filter, Instantiator<A>) -> Mid)?
		    }
		}

		extension A {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            service: Service.SafeDIOverrides = .init(),
		            midBuilder: Mid.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((Service, Instantiator<Mid>) -> A)? = nil
		        ) {
		            self.service = service
		            self.midBuilder = midBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let service: Service.SafeDIOverrides
		        let midBuilder: Mid.SafeDIMockConfiguration
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((Service, Instantiator<Mid>) -> A)?
		    }
		}
		#endif
		""" + "\n"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesOverrideWhereClosedOnFunctionIsDeclared_whenTypeBesideCallOfPublicMockReceivesLabelOnlyIfAvailable() async throws {
		// `A` receives `filter` only if available beside its call of `Service`'s `public` mock, so `Screen`'s mock binds `filter` as an
		// override and passes it to `A`'s builder function.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.publicMockLazyCycleModules(core: Self.coreWhosePublicMockTakesFilter, appFiles: [
			Self.screen(generateMock: "true"),
			seamFixtureType(named: "A", declarations: ["@Received(onlyIfAvailable: true) let filter: Filter?", "@Instantiated let service: Service", "@Instantiated let midBuilder: Instantiator<Mid>"]),
			Self.midForwardingFilter,
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init(),
		            filter: Filter? = nil
		        ) {
		            self.aBuilder = aBuilder
		            self.filter = filter
		        }

		        let aBuilder: A.SafeDIMockConfiguration
		        let filter: Filter?
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let filter: Filter? = safeDIOverrides.filter
		        func __safeDI_aBuilder(filter: Filter?) -> A {
		            _ = Service.__safeDI_Service_mock_7257C1618F8CE2B3.self
		            let service = Service.mock(filter: filter, safeDIOverrides: safeDIOverrides.aBuilder.service)
		            func __safeDI_midBuilder(filter: Filter) -> Mid {
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(filter: filter)
		                }
		                return if let safeDIBuilder = safeDIOverrides.aBuilder.midBuilder.safeDIBuilder { safeDIBuilder(filter, aBuilder) } else { Mid(filter: filter, aBuilder: aBuilder) }
		            }
		            let midBuilder = Instantiator<Mid> {
		                __safeDI_midBuilder(filter: $0)
		            }
		            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(filter, service, midBuilder) } else { A(filter: filter, service: service, midBuilder: midBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(filter: filter)
		        }
		        return Screen(aBuilder: aBuilder)
		    }
		}
		#endif

		#if DEBUG
		extension Mid {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            _ safeDIBuilder: ((Filter, Instantiator<A>) -> Mid)? = nil
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((Filter, Instantiator<A>) -> Mid)?
		    }
		}

		extension A {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            service: Service.SafeDIOverrides = .init(),
		            midBuilder: Mid.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: ((Filter?, Service, Instantiator<Mid>) -> A)? = nil
		        ) {
		            self.service = service
		            self.midBuilder = midBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        let service: Service.SafeDIOverrides
		        let midBuilder: Mid.SafeDIMockConfiguration
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        let safeDIBuilder: ((Filter?, Service, Instantiator<Mid>) -> A)?
		    }
		}
		#endif
		""" + "\n"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func publicMock_passesItsParameterWhereClosedOnFunctionIsDeclared_whenCallOfPublicMockTakesLabel() async throws {
		// `Screen`'s `public` mock takes `filter`, which its call of `Service`'s `public` mock takes, as its own parameter, and passes it
		// to `A`'s builder function.
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.publicMockLazyCycleModules(core: Self.coreWhosePublicMockTakesFilter, appFiles: [
			Self.screen(generateMock: ".public"),
			Self.aCallingPublicMock,
			Self.midForwardingFilter,
		]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    public struct SafeDIOverrides {
		        public init(
		            aBuilder: __safeDI_App_A_MockConfiguration = .init()
		        ) {
		            self.aBuilder = aBuilder
		        }

		        public let aBuilder: __safeDI_App_A_MockConfiguration
		    }

		    public static func mock(
		        filter: Filter? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        func __safeDI_aBuilder(filter: Filter?) -> A {
		            _ = Service.__safeDI_Service_mock_7257C1618F8CE2B3.self
		            let service = Service.mock(filter: filter, safeDIOverrides: safeDIOverrides.aBuilder.service)
		            func __safeDI_midBuilder(filter: Filter) -> Mid {
		                let aBuilder = Instantiator<A> {
		                    __safeDI_aBuilder(filter: filter)
		                }
		                return Mid.__safeDI_init(filter: filter, aBuilder: aBuilder, safeDIBuilder: safeDIOverrides.aBuilder.midBuilder.safeDIBuilder)
		            }
		            let midBuilder = Instantiator<Mid> {
		                __safeDI_midBuilder(filter: $0)
		            }
		            return A.__safeDI_init(service: service, midBuilder: midBuilder, safeDIBuilder: safeDIOverrides.aBuilder.safeDIBuilder)
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(filter: filter)
		        }
		        return Screen(aBuilder: aBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_mock_7257C1618F8CE2B3 {}
		}
		#endif

		#if DEBUG
		/// Configuration for how `Mid` is constructed within the public mock trees of module `App`.
		public struct __safeDI_App_Mid_MockConfiguration {
		    public init(
		        _ safeDIBuilder: ((Filter, Instantiator<A>) -> Mid)? = nil
		    ) {
		        self.safeDIBuilder = safeDIBuilder
		    }

		    /// Overrides how `Mid` is constructed. Parameters match the type’s initializer or custom mock method.
		    public let safeDIBuilder: ((Filter, Instantiator<A>) -> Mid)?
		}

		extension Mid {
		    static func __safeDI_init(filter: Filter, aBuilder: Instantiator<A>, safeDIBuilder: ((Filter, Instantiator<A>) -> Mid)?) -> Mid {
		        if let safeDIBuilder { safeDIBuilder(filter, aBuilder) } else { Mid(filter: filter, aBuilder: aBuilder) }
		    }
		}

		/// Configuration for how `A` is constructed within the public mock trees of module `App`.
		public struct __safeDI_App_A_MockConfiguration {
		    public init(
		        service: Service.SafeDIOverrides = .init(),
		        midBuilder: __safeDI_App_Mid_MockConfiguration = .init(),
		        _ safeDIBuilder: ((Service, Instantiator<Mid>) -> A)? = nil
		    ) {
		        self.service = service
		        self.midBuilder = midBuilder
		        self.safeDIBuilder = safeDIBuilder
		    }

		    public let service: Service.SafeDIOverrides
		    public let midBuilder: __safeDI_App_Mid_MockConfiguration
		    /// Overrides how `A` is constructed. Parameters match the type’s initializer or custom mock method.
		    public let safeDIBuilder: ((Service, Instantiator<Mid>) -> A)?
		}

		extension A {
		    static func __safeDI_init(service: Service, midBuilder: Instantiator<Mid>, safeDIBuilder: ((Service, Instantiator<Mid>) -> A)?) -> A {
		        if let safeDIBuilder { safeDIBuilder(service, midBuilder) } else { A(service: service, midBuilder: midBuilder) }
		    }
		}
		#endif
		""" + "\n"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Feature`'s public seam `Service`, whose `Badge` receives the public protocol `Theme` only if available on a `package`
	/// initializer, the only declaration that mentions `Theme` that SafeDI reads, and `App`, in package `appPackage`, with
	/// `appFiles`.
	private static func tierOmissionModules(appPackage: String, appFiles: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				unrecordedTypeDeclaration("public protocol Theme {}"),
				"@Instantiable\npublic struct Badge: Instantiable {\n    package init(theme: (any Theme)?) {\n        self.theme = theme\n    }\n\n    @Received(onlyIfAvailable: true) let theme: (any Theme)?\n}",
				seamFixtureType(named: "Service", isSeam: true, declarations: ["@Instantiated let badge: Badge"]),
			]),
			ModuleFixture(name: "App", packageName: appPackage, swiftFileContent: appFiles.map { "import Feature\nimport SafeDI\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	/// The error a call of `Service`'s `public` tier in a tree of `tierOmissionModules` reports for the `theme` `provider`
	/// forwards, its first declaration.
	private static func tierOmissionError(provider: String, _ fixtures: [String: FixturePaths]) -> String {
		"""
		\(fixtures["App"]!["\(provider).swift"]):11:5: error: `\(provider)` provides `theme: any Theme`, but the `public` initializer SafeDI generated for `Service` in module `Feature`, the narrowest one module `App` can call, does not take it: `Service` takes `theme` only on its `package` initializer, so this call would pass `nil` to `Badge`, which the tree would hand `theme` were it built inline. `Theme` is `package` as far as SafeDI can tell: SafeDI reads no declaration of it, and every initializer, `instantiate(…)` and mock method that mentions it in module `Feature` or on a type that receives it is `package` (`Badge.init(theme:)`); a mention on any other declaration matches it by name alone, so it does not count. Widen `Badge.init(theme:)` to `public`; mention `Theme` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; give `Theme` a `public` `mockOnly` mock (`@Instantiable(mockOnly: true) public extension Theme { public static func mock() -> Theme }`), which proves `Theme` `public`; or stop providing `theme` on this path.
		\(fixtures["Feature"]!["Badge.swift"]):7:5: note: `Badge` receives `theme: (any Theme)?` here.
		"""
	}

	/// The path the differential value comparator builds from `output`, the run of `modules`: each module's files as the
	/// harness wrote them, and the files the tool generated for it.
	private static func differentialValuePath(of output: MultiModuleTestOutput, modules: [ModuleFixture]) throws -> DifferentialValuePath {
		try DifferentialValuePath(modules: modules.map { module in
			let sourceDirectory = output.fixtureRoot.appendingPathComponent(module.packageName).appendingPathComponent("Sources").appendingPathComponent(module.name)
			var fixtureFiles = [String: String]()
			for fileName in try FileManager.default.contentsOfDirectory(atPath: sourceDirectory.path) where fileName.hasSuffix(".swift") {
				fixtureFiles[fileName] = try String(contentsOf: sourceDirectory.appendingPathComponent(fileName), encoding: .utf8)
			}
			return DifferentialValueModule(
				name: module.name,
				packageName: module.packageName,
				dependencyModuleNames: module.dependencies,
				fixtureFiles: fixtureFiles,
				generatedFiles: output.modules[module.name]?.generatedFiles ?? [:],
			)
		})
	}

	private static let root = seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<T1>", "@Instantiated let t3Builder: Instantiator<T3>"])
	private static let t1 = seamFixtureType(named: "T1", isFinalClass: true, declarations: [])
	private static let t3 = seamFixtureType(named: "T3", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let t0Builder: Instantiator<T0>", "@Received let t1Builder: Instantiator<T1>"])
	private static let lazyCycleFixture = [
		root,
		seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<T1>", "@Instantiated let t3Builder: Instantiator<T3>"]),
		t1,
		t3,
	]
	private static let hiddenCycleFixture = [
		root,
		seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<Other>", "@Instantiated let t3Builder: Instantiator<T3>"]),
		t1,
		t3,
		seamFixtureType(named: "Other", isFinalClass: true, declarations: []),
	]

	/// `files` named as `executeSafeDIToolTest` names them, after the type each declares.
	private static func fixtureFiles(_ files: [String]) -> [String: String] {
		var fixtureFiles = [String: String]()
		for file in files {
			let name = file.split(separator: "\n").compactMap { line -> String? in
				guard let classRange = line.range(of: "final class ") else { return nil }
				return String(line[classRange.upperBound...].prefix { $0 != ":" })
			}.first ?? "File"
			fixtureFiles["\(name).swift"] = file
		}
		return fixtureFiles
	}

	/// `Core`, in package `pkg`, with `core` as its file `Service.swift`, and `App`, in package `appPackage`, with `appFiles`.
	private static func publicMockLazyCycleModules(core: String, appPackage: String = "app", appFiles: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "pkg", swiftFileContentByFilePath: ["Service.swift": core]),
			ModuleFixture(name: "App", packageName: appPackage, swiftFileContent: appFiles.map { "import Core\nimport SafeDI\n\n" + $0 }, dependencies: ["Core"]),
		]
	}

	/// `Core`'s file for a lazy cycle around a call of `Service`'s `public` mock: `Service`'s initializer is `package`, so a module
	/// of another package calls the mock rather than building `Service`'s tree, in which `TokenCache` receives `filter: Filter?`
	/// only if available on a `public` initializer, so the `public` mock takes `filter`. `Filter` is declared inside an `#if`
	/// block, where SafeDI records no declaration of it.
	private static let coreWhosePublicMockTakesFilter = """
	import SafeDI

	#if canImport(Foundation)
	public struct Filter {
	    public init() {}
	}
	#endif

	@Instantiable
	public struct TokenCache: Instantiable {
	    public init(filter: Filter?) {
	        self.filter = filter
	    }

	    @Received(onlyIfAvailable: true) let filter: Filter?
	}

	@Instantiable(generateMock: .public)
	public struct Service: Instantiable {
	    package init(tokenCache: TokenCache) {
	        self.tokenCache = tokenCache
	    }

	    @Instantiated let tokenCache: TokenCache
	}
	"""

	/// `coreWhosePublicMockTakesFilter` with `TokenCache` receiving `filterBuilder: Instantiator<Filter>?` instead, where `Filter`
	/// conforms to `Instantiable` by hand, so SafeDI builds no `Filter`.
	private static let coreWhosePublicMockTakesFilterBuilder = """
	import SafeDI

	#if canImport(Foundation)
	public struct Filter: Instantiable {
	    public init() {}
	}
	#endif

	@Instantiable
	public struct TokenCache: Instantiable {
	    public init(filterBuilder: Instantiator<Filter>?) {
	        self.filterBuilder = filterBuilder
	    }

	    @Received(onlyIfAvailable: true) let filterBuilder: Instantiator<Filter>?
	}

	@Instantiable(generateMock: .public)
	public struct Service: Instantiable {
	    package init(tokenCache: TokenCache) {
	        self.tokenCache = tokenCache
	    }

	    @Instantiated let tokenCache: TokenCache
	}
	"""

	/// `coreWhosePublicMockTakesFilter` with `TokenCache` receiving `filter: (any FilterProtocol)?` on a `package` initializer, the
	/// only declaration that mentions `FilterProtocol` that SafeDI reads, so the `public` mock omits `filter`.
	private static let coreWhosePublicMockOmitsFilter = """
	import SafeDI

	#if canImport(Foundation)
	public protocol FilterProtocol {}
	#endif

	@Instantiable
	package struct TokenCache: Instantiable {
	    package init(filter: (any FilterProtocol)?) {
	        self.filter = filter
	    }

	    @Received(onlyIfAvailable: true) let filter: (any FilterProtocol)?
	}

	@Instantiable(generateMock: .public)
	public struct Service: Instantiable {
	    package init(tokenCache: TokenCache) {
	        self.tokenCache = tokenCache
	    }

	    @Instantiated let tokenCache: TokenCache
	}
	"""

	/// `Screen`, whose mock `generateMock` generates, with `declarations` and then `aBuilder: Instantiator<A>`.
	private static func screen(generateMock: String, declarations: [String] = []) -> String {
		seamFixtureType(named: "Screen", declarations: declarations + ["@Instantiated let aBuilder: Instantiator<A>"])
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: \(generateMock))\n")
	}

	private static let aCallingPublicMock = seamFixtureType(named: "A", declarations: ["@Instantiated let service: Service", "@Instantiated let midBuilder: Instantiator<Mid>"])
	private static let midForwardingFilter = seamFixtureType(named: "Mid", declarations: ["@Forwarded let filter: Filter", "@Instantiated let aBuilder: Instantiator<A>"])
	private static let midInstantiatingFilter = seamFixtureType(named: "Mid", declarations: ["@Instantiated let filter: any FilterProtocol"])
	private static let appFilter = seamFixtureType(named: "AppFilter", declarations: ["@Instantiated let aBuilder: Instantiator<A>"], conformances: ", FilterProtocol")
		.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [FilterProtocol.self])\n")
}
