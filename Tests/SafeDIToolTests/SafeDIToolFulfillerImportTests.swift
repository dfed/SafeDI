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

/// A `fulfilledByType:` string lets a module build a type of a module that none of its files imports. The generated
/// code names that type, so the file that names it imports the module that declares it.
struct SafeDIToolFulfillerImportTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – The file that names the fulfiller imports its module

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfFulfiller_inDependencyTree_whenNoFileReadImportsThatModule(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.root], dependencies: ["Contracts", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases, [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfFulfiller_whenTreeAlsoBuildsFulfillerForPropertyThatNamesIt(integration: MultiModuleIntegration, declaresErasedPropertyFirst: Bool) async throws {
		// `Holder` builds `DefaultThing` for a property that names it, which asks for no import, and its file reaches the
		// type through a module that exports the fulfiller's, so no file SafeDI read imports `Impl` itself; the root builds
		// the same type for a property that does not name it, which asks for `Impl`. Only the walk that collects a tree's
		// fulfillers can add that import. It visits each generator once, and the two builds are two generators whichever
		// it meets first, so the root's file imports the fulfiller's module in either order of the declarations.
		let holder = ModuleFixture(name: "Feature", packageName: "App", swiftFileContent: [
			"import Reexport\n\n" + seamFixtureType(named: "Holder", declarations: ["@Instantiated let thing: DefaultThing"]),
		], dependencies: ["Contracts", "Impl", "Reexport"])
		let declarations = ["@Instantiated let holder: Holder", Self.erasedThing]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				Self.reexport,
				holder,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
					"import Contracts\nimport Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: declaresErasedPropertyFirst ? declarations.reversed() : declarations),
				], dependencies: ["Contracts", "Feature", "Impl", "Reexport"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let imports = """
		#if canImport(Contracts)
		import Contracts
		#endif
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(Impl)
		import Impl
		#endif
		#if canImport(Reexport)
		import Reexport
		#endif
		"""
		let body = if declaresErasedPropertyFirst {
			"""
			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        func __safeDI_holder() -> Holder {
			            let thing = DefaultThing()
			            return Holder(thing: thing)
			        }
			        let holder: Holder = __safeDI_holder()
			        self.init(thing: thing, holder: holder)
			    }
			}
			"""
		} else {
			"""
			extension Root {
			    public init() {
			        func __safeDI_holder() -> Holder {
			            let thing = DefaultThing()
			            return Holder(thing: thing)
			        }
			        let holder: Holder = __safeDI_holder()
			        let thing = AnyThing(DefaultThing())
			        self.init(holder: holder, thing: thing)
			    }
			}
			"""
		}
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + imports + "\n\n" + body,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_visitsEachGeneratorOnceCollectingFulfillers_whenEveryScreenBuildsEveryScreenOfNextLayer() async throws {
		// Three screens a layer, each building every screen of the next layer through an `Instantiator`: the places of a
		// screen share one generator, and the paths to the last layer triple with each layer. The walk that collects the
		// types a root's tree builds entered a generator again at every place, so it visited 121 generators at four layers
		// and 9,841 at eight, and 16 layers of four screens took 35 seconds; it visits the root and each screen once.
		var generatorsVisited = [Int]()
		for layerCount in [4, 8] {
			var fixture = [seamFixtureType(named: "Root", isRoot: true, declarations: (0..<3).map { "@Instantiated let screen0x\($0)Builder: Instantiator<Screen0x\($0)>" })]
			for layer in 0..<layerCount {
				for screen in 0..<3 {
					fixture.append(seamFixtureType(named: "Screen\(layer)x\(screen)", isFinalClass: true, declarations: layer + 1 < layerCount
							? (0..<3).map { "@Instantiated let screen\(layer + 1)x\($0)Builder: Instantiator<Screen\(layer + 1)x\($0)>" }
							: []))
				}
			}
			let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
			_ = try await GenerationWork.$observer.withValue({ continuation.yield($0) }) { [fixture] in
				try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, skipCompileVerification: true)
			}
			continuation.finish()
			var visited = 0
			for await work in stream where work.step == .collectingTypesOfATree {
				visited += work.elementCount
			}
			generatorsVisited.append(visited)
		}
		#expect(generatorsVisited == [13, 25])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_visitsEachGeneratorOnceCollectingTypesOfMock_whenEveryScreenBuildsEveryScreenOfNextLayer() async throws {
		// The same layers of screens under a root with a generated mock, in a module that sees another module's public
		// mock: the mock's tree is walked for the types it names and again for the public mocks it reaches, as the root's
		// own tree is walked once. The three walks visit 43 generators at four layers and 79 at eight, 9 more a layer.
		var generatorsVisited = [Int]()
		for layerCount in [4, 8] {
			var fixture = [seamFixtureType(named: "Root", isRoot: true, declarations: (0..<3).map { "@Instantiated let screen0x\($0)Builder: Instantiator<Screen0x\($0)>" })
				.replacingOccurrences(of: "@Instantiable(isRoot: true)", with: "@Instantiable(isRoot: true, generateMock: true)")]
			for layer in 0..<layerCount {
				for screen in 0..<3 {
					fixture.append(seamFixtureType(named: "Screen\(layer)x\(screen)", isFinalClass: true, declarations: layer + 1 < layerCount
							? (0..<3).map { "@Instantiated let screen\(layer + 1)x\($0)Builder: Instantiator<Screen\(layer + 1)x\($0)>" }
							: ["@Instantiated let gadget: Gadget"]))
				}
			}
			let (stream, continuation) = AsyncStream.makeStream(of: GenerationWork.self)
			try await GenerationWork.$observer.withValue({ continuation.yield($0) }) { [fixture] in
				_ = try await executeSafeDIToolMultiModuleTest(
					modules: [
						ModuleFixture(name: "Kit", packageName: "App", swiftFileContent: ["""
						@Instantiable(generateMock: .public)
						public struct Gadget: Instantiable {
						    public init() {}
						}
						"""]),
						ModuleFixture(name: "App", packageName: "App", swiftFileContent: fixture.map { "import Kit\n\n" + $0 }, dependencies: ["Kit"]),
					],
					integration: .moduleInfo,
					compileVerification: .skipped,
					filesToDelete: &filesToDelete,
				)
			}
			continuation.finish()
			var visited = 0
			for await work in stream where work.step == .collectingTypesOfATree {
				visited += work.elementCount
			}
			generatorsVisited.append(visited)
		}
		#expect(generatorsVisited == [43, 79])
	}

	@Test(arguments: MultiModuleIntegration.allCases, FulfilledProperty.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfFulfiller_whateverPropertyTheStringFulfills(integration: MultiModuleIntegration, property: FulfilledProperty) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [property.declaration])], dependencies: ["Contracts", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			\(property.expectedImports.map { "#if canImport(\($0))\nimport \($0)\n#endif" }.joined(separator: "\n"))

			\(property.expectedBody)
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfNestedFulfiller_whenStringNamesNestedType(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				ModuleFixture(name: "Impl", packageName: "App", swiftFileContent: ["""
				import Contracts

				public enum Namespace {
				    @Instantiable
				    public struct NestedThing: Instantiable, Thing {
				        public init() {}
				    }
				}
				"""], dependencies: ["Contracts"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [#"@Instantiated(fulfilledByType: "Namespace.NestedThing", erasedToConcreteExistential: true) let thing: AnyThing"#])], dependencies: ["Contracts", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(Namespace.NestedThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfExtension_whenFulfillerIsExtensionOfTypeAnotherModuleDeclares(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Contracts", packageName: "App", swiftFileContent: [Self.contractsSource + "\n\npublic struct Widget: Thing {\n    public init() {}\n}\n"]),
				ModuleFixture(name: "Impl", packageName: "App", swiftFileContent: ["""
				import Contracts

				@Instantiable
				extension Widget: Instantiable {
				    public static func instantiate() -> Widget {
				        Widget()
				    }
				}
				"""], dependencies: ["Contracts"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [#"@Instantiated(fulfilledByType: "Widget", erasedToConcreteExistential: true) let thing: AnyThing"#])], dependencies: ["Contracts", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(Widget.instantiate())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfFulfiller_inMockAndMockConfigurationFiles_whenNoFileReadImportsThatModule() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.implWithChild,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.mockedFeature], dependencies: ["Contracts", "Impl"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"Feature+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			#if DEBUG
			extension Feature {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            thing: DefaultThing.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                thing: thing
			            )
			        }

			        var thing: DefaultThing.SafeDIMockConfiguration { __safeDI_storage.thing }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                thing: DefaultThing.SafeDIMockConfiguration
			            ) {
			                self.thing = thing
			            }

			            let thing: DefaultThing.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Feature {
			        func __safeDI_thing() -> AnyThing {
			            let clock = if let safeDIBuilder = safeDIOverrides.thing.clock { safeDIBuilder() } else { Clock() }
			            return if let safeDIBuilder = safeDIOverrides.thing.safeDIBuilder { AnyThing(safeDIBuilder(clock)) } else { AnyThing(DefaultThing(clock: clock)) }
			        }
			        let thing: AnyThing = __safeDI_thing()
			        return Feature(thing: thing)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			#if DEBUG
			extension DefaultThing {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            clock: (() -> Clock)? = nil,
			            _ safeDIBuilder: ((Clock) -> DefaultThing)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                clock: clock,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var clock: (() -> Clock)? { __safeDI_storage.clock }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Clock) -> DefaultThing)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                clock: (() -> Clock)?,
			                safeDIBuilder: ((Clock) -> DefaultThing)?
			            ) {
			                self.clock = clock
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let clock: (() -> Clock)?
			            let safeDIBuilder: ((Clock) -> DefaultThing)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfFulfiller_inCombinedFileHoldingMocks_whenNoFileReadImportsThatModule() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.implWithChild,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.mockedFeature], dependencies: ["Contracts", "Impl"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			#if DEBUG
			extension Feature {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            thing: DefaultThing.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                thing: thing
			            )
			        }

			        var thing: DefaultThing.SafeDIMockConfiguration { __safeDI_storage.thing }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                thing: DefaultThing.SafeDIMockConfiguration
			            ) {
			                self.thing = thing
			            }

			            let thing: DefaultThing.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Feature {
			        func __safeDI_thing() -> AnyThing {
			            let clock = if let safeDIBuilder = safeDIOverrides.thing.clock { safeDIBuilder() } else { Clock() }
			            return if let safeDIBuilder = safeDIOverrides.thing.safeDIBuilder { AnyThing(safeDIBuilder(clock)) } else { AnyThing(DefaultThing(clock: clock)) }
			        }
			        let thing: AnyThing = __safeDI_thing()
			        return Feature(thing: thing)
			    }
			}
			#endif

			#if DEBUG
			extension DefaultThing {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            clock: (() -> Clock)? = nil,
			            _ safeDIBuilder: ((Clock) -> DefaultThing)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                clock: clock,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var clock: (() -> Clock)? { __safeDI_storage.clock }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Clock) -> DefaultThing)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                clock: (() -> Clock)?,
			                safeDIBuilder: ((Clock) -> DefaultThing)?
			            ) {
			                self.clock = clock
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let clock: (() -> Clock)?
			            let safeDIBuilder: ((Clock) -> DefaultThing)?
			        }
			    }
			}
			#endif

			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfFulfiller_inSeamsOwnCodeButNotInCaller_whenSeamBuildsFulfiller(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(name: "Feature", packageName: "App", swiftFileContent: ["import Contracts\n\n" + seamFixtureType(named: "FeatureScreen", isSeam: true, declarations: [Self.erasedThing])], dependencies: ["Contracts", "Impl"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let featureScreen: FeatureScreen"])], dependencies: ["Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == [
			integration == .moduleInfo ? "Feature.swift" : "FeatureScreen+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			extension FeatureScreen {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}

			extension FeatureScreen {
			    public enum __safeDI_FeatureScreen_CBF29CE484222325 {}
			}
			""",
		])
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_featureScreen() -> FeatureScreen {
			            _ = FeatureScreen.__safeDI_FeatureScreen_CBF29CE484222325.self\(integration.seamCallComment(type: "FeatureScreen", declaringModule: "Feature"))
			            return FeatureScreen()
			        }
			        let featureScreen: FeatureScreen = __safeDI_featureScreen()
			        self.init(featureScreen: featureScreen)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfFulfiller_inOnlyTheFilesThatNameIt_whenSeveralFilesOfOneModuleAreGenerated() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				ModuleFixture(name: "Impl", packageName: "App", swiftFileContent: [Self.defaultThing, Self.clock], dependencies: ["Contracts"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
					"import Contracts\n\n" + seamFixtureType(named: "FirstRoot", isRoot: true, declarations: [Self.erasedThing]),
					"import Contracts\n\n" + seamFixtureType(named: "SecondRoot", isRoot: true, declarations: [Self.erasedThing]),
					"import Contracts\n\n" + seamFixtureType(named: "ThirdRoot", isRoot: true, declarations: []),
					"import Contracts\n\n" + seamFixtureType(named: "FourthRoot", isRoot: true, declarations: ["@Instantiated let local: Local"]),
					seamFixtureType(named: "Local", declarations: []),
				], dependencies: ["Contracts", "Impl"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"FirstRoot+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			extension FirstRoot {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
			"FourthRoot+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif

			extension FourthRoot {
			    public init() {
			        let local = Local()
			        self.init(local: local)
			    }
			}
			""",
			"SecondRoot+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			extension SecondRoot {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
			"ThirdRoot+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif


			""",
		])
	}

	// MARK: Tests – Nothing changes for a build that compiles

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesNoByte_whenModuleReadsStringButBuildsNoTreeThatNamesTheFulfiller(integration: MultiModuleIntegration) async throws {
		func modules(featureDeclaration: String) -> [ModuleFixture] {
			[
				Self.contracts,
				ModuleFixture(name: "Impl", packageName: "App", swiftFileContent: [Self.defaultThing, Self.clock], dependencies: ["Contracts"]),
				ModuleFixture(name: "Feature", packageName: "App", swiftFileContent: ["import Contracts\n\n" + seamFixtureType(named: "UnbuiltFeature", declarations: [featureDeclaration])], dependencies: ["Contracts", "Impl"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let local: Local"]), seamFixtureType(named: "Local", declarations: [])], dependencies: ["Contracts", "Impl", "Feature"]),
			]
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: modules(featureDeclaration: Self.erasedThing),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let reference = try await executeSafeDIToolMultiModuleTest(
			modules: modules(featureDeclaration: "@Received let thing: AnyThing"),
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == reference.modules["App"]?.generatedFiles)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif

			extension Root {
			    public init() {
			        let local = Local()
			        self.init(local: local)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfFulfiller_andCompiles_whenListedModuleReExportsThatModule(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(name: "Facade", packageName: "App", swiftFileContent: ["@_exported import Impl\n"], dependencies: ["Impl"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\nimport Facade\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [Self.erasedThing])], dependencies: ["Contracts", "Facade", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Facade)
			import Facade
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheImportAFileSpells_whenFileReadImportsModuleOfFulfillerWithAttribute(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				// The initializer is visible only through an `@_spi` import, which a plain import would replace in the header.
				ModuleFixture(name: "Impl", packageName: "App", swiftFileContent: ["""
				import Contracts

				@Instantiable
				public struct DefaultThing: Instantiable, Thing {
				    @_spi(Inner) public init() {}
				}
				"""], dependencies: ["Contracts"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\n@_spi(Inner) import Impl\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [Self.erasedThing])], dependencies: ["Contracts", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			@_spi(Inner) import Impl
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesNoByte_whenConfigurationListsModuleOfFulfillerInAdditionalImportedModules(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.root], swiftFileContentByFilePath: ["SafeDIConfiguration.swift": #"#SafeDIConfiguration(additionalImportedModules: ["Impl"])"#], dependencies: ["Contracts", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotImportEmittingModule_whenFulfillerIsDeclaredInEmittingModule(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.root, Self.defaultThing], dependencies: ["Contracts"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsTheListedModule_whenConfigurationNamesItForFulfillerOfNoKnownModule() async throws {
		// A file read through `additionalDirectoriesToInclude` belongs to no module SafeDI knows, as every other file does
		// under the Xcode project plugin, so the configuration names the module.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				ModuleFixture(name: "Impl", packageName: "Impl", swiftFileContent: [Self.defaultThing], dependencies: ["Contracts"], isCheckoutPackage: true),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.root], swiftFileContentByFilePath: ["SafeDIConfiguration.swift": ##"#SafeDIConfiguration(additionalImportedModules: ["Impl"], additionalDirectoriesToInclude: ["$FIXTURE_ROOT/checkouts/Impl/Sources/Impl"])"##], dependencies: ["Contracts", "Impl"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsNoLevelOnImportOfModuleOfFulfiller_whenOwnFileSpellsLevelOnAnotherImport(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["internal import Contracts\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [#"@Instantiated(fulfilledByType: "DefaultThing", erasedToConcreteExistential: true) private let thing: AnyThing"#]).replacingOccurrences(of: "public init(thing: AnyThing)", with: "init(thing: AnyThing)")], dependencies: ["Contracts", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			internal import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	// MARK: Tests – What makes the fulfiller visible

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesNoByte_whenFileReadImportsTheFulfillerByItself(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\nimport struct Impl.DefaultThing\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [Self.erasedThing])], dependencies: ["Contracts", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import struct Impl.DefaultThing
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_addsNoImport_whenFileReadImportsTypeOfFulfillersNameByItselfFromAnotherModule(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(name: "Other", packageName: "App", swiftFileContent: ["import Contracts\n\npublic struct DefaultThing: Thing {\n    public init() {}\n}\n"], dependencies: ["Contracts"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\nimport struct Other.DefaultThing\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [Self.erasedThing])], dependencies: ["Contracts", "Impl", "Other"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Other)
			import struct Other.DefaultThing
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesNoByte_whenFileReadImportsTheFulfillerByItselfThroughModuleThatReExportsIt(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				Self.reexport,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\nimport struct Reexport.DefaultThing\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [Self.erasedThing])], dependencies: ["Contracts", "Impl", "Reexport"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Reexport)
			import struct Reexport.DefaultThing
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfFulfiller_whenFileReadImportsOnlyAnotherTypeOfThatModule(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				ModuleFixture(name: "Impl", packageName: "App", swiftFileContent: [Self.defaultThing, "public struct Unrelated {}\n"], dependencies: ["Contracts"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\nimport struct Impl.Unrelated\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [Self.erasedThing])], dependencies: ["Contracts", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif
			#if canImport(Impl)
			import struct Impl.Unrelated
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases, [true, false])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsAttributedImportOfAnotherTypeOfThatModule_whenAddingImportOfModuleOfFulfiller(integration: MultiModuleIntegration, importsReExportingModule: Bool) async throws {
		let facadeImport = importsReExportingModule ? "import Facade\n" : ""
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				ModuleFixture(name: "Impl", packageName: "App", swiftFileContent: [Self.defaultThing, "@_spi(Inside) public struct Secret {\n    public init() {}\n}\n"], dependencies: ["Contracts"]),
				ModuleFixture(name: "Facade", packageName: "App", swiftFileContent: ["@_exported import Impl\n"], dependencies: ["Impl"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["""
				import Contracts
				\(facadeImport)@_spi(Inside) import struct Impl.Secret

				@Instantiable(isRoot: true)
				struct Root: Instantiable {
				    init(thing: AnyThing, childBuilder: Instantiator<Child>) {
				        self.thing = thing
				        self.childBuilder = childBuilder
				    }

				    \(Self.erasedThing)
				    @Instantiated let childBuilder: Instantiator<Child>
				}

				@Instantiable
				struct Child: Instantiable {
				    init(value: Secret) {
				        self.value = value
				    }

				    @Forwarded let value: Secret
				}
				"""], dependencies: ["Contracts", "Facade", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let facadeHeader = importsReExportingModule ? "#if canImport(Facade)\nimport Facade\n#endif\n" : ""
		#expect(output.modules["App"]?.generatedFiles == [integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
		#if canImport(Contracts)
		import Contracts
		#endif
		\(facadeHeader)#if canImport(Impl)
		@_spi(Inside) import struct Impl.Secret
		#endif
		#if canImport(Impl)
		import Impl
		#endif

		extension Root {
		    public init() {
		        let thing = AnyThing(DefaultThing())
		        func __safeDI_childBuilder(value: Secret) -> Child {
		            Child(value: value)
		        }
		        let childBuilder = Instantiator<Child> {
		            __safeDI_childBuilder(value: $0)
		        }
		        self.init(thing: thing, childBuilder: childBuilder)
		    }
		}
		"""])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsImportOfAnotherTypeThatTellsItFromTheTypeOfAnotherModule_whenAddingImportOfModuleOfFulfiller(integration: MultiModuleIntegration) async throws {
		let imports = "import Contracts\nimport Other\nimport struct Impl.Unrelated\n\n"
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				ModuleFixture(name: "Other", packageName: "App", swiftFileContent: ["public struct Unrelated {\n    public init() {}\n}\n"]),
				ModuleFixture(name: "Impl", packageName: "App", swiftFileContent: [Self.defaultThing, "public struct Unrelated {\n    public init() {}\n}\n"], dependencies: ["Contracts"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
					imports + seamFixtureType(named: "Root", isRoot: true, declarations: [Self.erasedThing, "@Instantiated let childBuilder: Instantiator<Child>"]),
					imports + seamFixtureType(named: "Child", declarations: ["@Forwarded let value: Unrelated"]),
				], dependencies: ["Contracts", "Other", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif
			#if canImport(Impl)
			import struct Impl.Unrelated
			#endif
			#if canImport(Other)
			import Other
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        func __safeDI_childBuilder(value: Unrelated) -> Child {
			            Child(value: value)
			        }
			        let childBuilder = Instantiator<Child> {
			            __safeDI_childBuilder(value: $0)
			        }
			        self.init(thing: thing, childBuilder: childBuilder)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsOnlyModuleOfTheFulfillerNamed_whenTwoModulesExtendOneOuterTypeWithFulfillers(integration: MultiModuleIntegration) async throws {
		func nestedThing(named name: String) -> String {
			"""
			import Contracts

			extension Namespace {
			    @Instantiable
			    public struct \(name): Instantiable, Thing {
			        public init() {}
			    }
			}
			"""
		}
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Contracts", packageName: "App", swiftFileContent: [Self.contractsSource + "\n\npublic enum Namespace {}\n"]),
				ModuleFixture(name: "ImplOne", packageName: "App", swiftFileContent: [nestedThing(named: "FirstThing")], dependencies: ["Contracts"]),
				ModuleFixture(name: "ImplTwo", packageName: "App", swiftFileContent: [nestedThing(named: "SecondThing")], dependencies: ["Contracts"]),
				// `Unbuilt` keeps the string that names the second type in a module the root's run reads and builds nothing of.
				ModuleFixture(name: "Feature", packageName: "App", swiftFileContent: ["import Contracts\n\n" + seamFixtureType(named: "Unbuilt", declarations: [#"@Instantiated(fulfilledByType: "Namespace.SecondThing", erasedToConcreteExistential: true) let thing: AnyThing"#])], dependencies: ["Contracts", "ImplTwo"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [#"@Instantiated(fulfilledByType: "Namespace.FirstThing", erasedToConcreteExistential: true) let thing: AnyThing"#])], dependencies: ["Contracts", "ImplOne", "ImplTwo", "Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(ImplOne)
			import ImplOne
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(Namespace.FirstThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesNoByte_whenGeneratedCodeNamesOnlyANestedTypeWithTheNameOfAFulfiller(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(name: "ImplTwo", packageName: "App", swiftFileContent: ["""
				import Contracts

				public enum Namespace {
				    @Instantiable
				    public struct DefaultThing: Instantiable, Thing {
				        public init() {}
				    }
				}
				"""], dependencies: ["Contracts"]),
				// `Unbuilt` keeps the string that names the top-level type in a module the root's run reads and builds nothing of.
				ModuleFixture(name: "Feature", packageName: "App", swiftFileContent: ["import Contracts\n\n" + seamFixtureType(named: "Unbuilt", declarations: [Self.erasedThing])], dependencies: ["Contracts", "Impl"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\nimport ImplTwo\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [#"@Instantiated(fulfilledByType: "Namespace.DefaultThing", erasedToConcreteExistential: true) let thing: AnyThing"#])], dependencies: ["Contracts", "Impl", "ImplTwo", "Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(ImplTwo)
			import ImplTwo
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(Namespace.DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	// MARK: Tests – Which module declares the name

	@Test(arguments: MultiModuleIntegration.allCases, 0..<6)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsTheModuleThatDeclaresTheFulfiller_whateverOtherModulesDeclareATypeOfThatName(integration: MultiModuleIntegration, fulfillerModuleIndex: Int) async throws {
		let moduleNames = ["Alpha", "Bravo", "Charlie", "Xray", "Yankee", "Zulu"]
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [Self.contracts] + moduleNames.enumerated().map { index, moduleName in
				ModuleFixture(
					name: moduleName,
					packageName: "App",
					swiftFileContent: [index == fulfillerModuleIndex ? Self.defaultThing : "public struct DefaultThing {\n    public init() {}\n}\n"],
					dependencies: ["Contracts"],
				)
			} + [
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.root], dependencies: ["Contracts"] + moduleNames),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
		\(["Contracts", moduleNames[fulfillerModuleIndex]].sorted().map { "#if canImport(\($0))\nimport \($0)\n#endif" }.joined(separator: "\n"))

		extension Root {
		    public init() {
		        let thing = AnyThing(DefaultThing())
		        self.init(thing: thing)
		    }
		}
		"""])
	}

	@Test(arguments: [["Alpha", "Zulu"], ["Zulu", "Alpha"]])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsDuplicate_whenTwoModulesDeclareInstantiableFulfillerOfOneName(moduleNames: [String]) async {
		await assertThrowsMultiModuleError(
			inModule: "App",
			diagnostics: { fixtures in
				["Alpha", "Zulu"].map { moduleName in
					"\(fixtures[moduleName]!["DefaultThing.swift"]):3:1: error: `DefaultThing` is declared in modules `Alpha` and `Zulu`. SafeDI tells apart by name the @Instantiable types a module can name. Rename one."
				}.joined(separator: "\n")
			},
			block: {
				try await executeSafeDIToolMultiModuleTest(
					modules: [Self.contracts] + moduleNames.map { ModuleFixture(name: $0, packageName: "App", swiftFileContent: [Self.defaultThing], dependencies: ["Contracts"]) } + [
						ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.root], dependencies: ["Contracts"] + moduleNames),
					],
					integration: .moduleInfo,
					filesToDelete: &filesToDelete,
				)
			},
		)
	}

	// MARK: Tests – A type of the same name that the file does not build

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotImportModuleOfFulfiller_inDependencyTree_whenFileBuildsNoFulfillerAndNamesTypeOfThatNameFromAnotherModule(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				Self.otherDeclaringPlainDefaultThing,
				Self.sideReadingStringItDoesNotBuild,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
					"import Contracts\nimport Other\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let childBuilder: Instantiator<Child>"]),
					"import Other\n\n" + seamFixtureType(named: "Child", declarations: ["@Forwarded let value: DefaultThing"]),
				], dependencies: ["Contracts", "Other", "Impl", "Side"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Other)
			import Other
			#endif

			extension Root {
			    public init() {
			        func __safeDI_childBuilder(value: DefaultThing) -> Child {
			            Child(value: value)
			        }
			        let childBuilder = Instantiator<Child> {
			            __safeDI_childBuilder(value: $0)
			        }
			        self.init(childBuilder: childBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotImportModuleOfFulfiller_inMock_whenMockBuildsNoFulfillerAndNamesTypeOfThatNameFromAnotherModule() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				Self.otherDeclaringPlainDefaultThing,
				Self.sideReadingStringItDoesNotBuild,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["""
				import Other

				@Instantiable(generateMock: true)
				public struct Feature: Instantiable {
				    public init(value: DefaultThing) {
				        self.value = value
				    }

				    @Forwarded let value: DefaultThing
				}
				"""], dependencies: ["Other", "Impl", "Side"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"Feature+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Other)
			import Other
			#endif

			#if DEBUG
			extension Feature {
			    static func mock(
			        value: DefaultThing
			    ) -> Feature {
			        return Feature(value: value)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Other)
			import Other
			#endif


			""",
		])
	}

	// MARK: Tests – A type another type’s declaration fulfills

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfFulfiller_inDependencyTree_whenFulfillingAdditionalTypesReachesIt(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.implFulfillingThing,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let thing: any Thing"])], dependencies: ["Contracts", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			extension Root {
			    public init() {
			        let thing: any Thing = DefaultThing()
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfFulfiller_inMock_whenMockBuildsReceivedTypeThatFulfillingAdditionalTypesReaches() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.implFulfillingThing,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["""
				import Contracts

				@Instantiable(generateMock: true)
				public struct Feature: Instantiable {
				    public init(thing: any Thing) {
				        self.thing = thing
				    }

				    @Received let thing: any Thing
				}
				"""], dependencies: ["Contracts", "Impl"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"Feature+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			#if DEBUG
			extension Feature {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            thing: (() -> any Thing)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                thing: thing
			            )
			        }

			        var thing: (() -> any Thing)? { __safeDI_storage.thing }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                thing: (() -> any Thing)?
			            ) {
			                self.thing = thing
			            }

			            let thing: (() -> any Thing)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Feature {
			        let thing: any Thing = if let safeDIBuilder = safeDIOverrides.thing { safeDIBuilder() } else { DefaultThing() }
			        return Feature(thing: thing)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif


			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesNoByte_whenFileReadImportsModuleOfFulfillerThatFulfillingAdditionalTypesReaches(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.implFulfillingThing,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\nimport Impl\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let thing: any Thing"])], dependencies: ["Contracts", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			extension Root {
			    public init() {
			        let thing: any Thing = DefaultThing()
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	// MARK: Tests – A module named with a keyword

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleNamedWithKeywordInBackticks_whenItDeclaresTheFulfiller(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				ModuleFixture(name: "class", packageName: "App", swiftFileContent: [Self.defaultThing], dependencies: ["Contracts"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.root], dependencies: ["Contracts", "class"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(`class`)
			import `class`
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_changesNoByte_whenFileReadImportsModuleNamedWithKeywordThatDeclaresTheFulfiller(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				ModuleFixture(name: "class", packageName: "App", swiftFileContent: [Self.defaultThing], dependencies: ["Contracts"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["import Contracts\nimport `class`\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [Self.erasedThing])], dependencies: ["Contracts", "class"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(`class`)
			import `class`
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	// MARK: Tests – An added import agrees with the module's files SafeDI does not read

	@Test(arguments: MultiModuleIntegration.allCases, ["5", "6"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsLevelOfUnreadFilesImport_whenBuildReachesFulfillerThroughReexport(integration: MultiModuleIntegration, languageMode: String) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				Self.reexport,
				ModuleFixture(
					name: "App",
					packageName: "App",
					swiftFileContent: ["import Contracts\nimport Reexport\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [Self.erasedThing])],
					swiftFileContentByFilePath: ["Helper.swift": "internal import Impl\n"],
					dependencies: ["Contracts", "Impl", "Reexport"],
					compilerSettings: VerificationCompilerSettings(swiftLanguageMode: languageMode),
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			internal import Impl
			#endif
			#if canImport(Reexport)
			import Reexport
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases, UnreadFileImport.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsImportOfFulfillersModuleAsUnreadFileRequires_whateverImportTheFileSpells(integration: MultiModuleIntegration, unreadFileImport: UnreadFileImport) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(
					name: "App",
					packageName: "App",
					swiftFileContent: [Self.root],
					swiftFileContentByFilePath: ["Helper.swift": unreadFileImport.source + "\n"],
					dependencies: ["Contracts", "Impl"],
					compilerSettings: VerificationCompilerSettings(swiftLanguageMode: "5"),
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
		#if canImport(Contracts)
		import Contracts
		#endif
		#if canImport(Impl)
		\(unreadFileImport.expectedGeneratedImport)
		#endif

		extension Root {
		    public init() {
		        let thing = AnyThing(DefaultThing())
		        self.init(thing: thing)
		    }
		}
		"""])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsLevelOfUnreadFilesImportOnlyOnImportOfThatModule_whenAnotherGeneratedImportSpellsNone() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(
					name: "App",
					packageName: "App",
					swiftFileContent: [Self.root],
					swiftFileContentByFilePath: ["Helper.swift": "internal import Impl\nimport Contracts\n"],
					dependencies: ["Contracts", "Impl"],
				),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			internal import Impl
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsLevelOfUnreadFilesImport_inEveryFileThatGainsTheImport() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(
					name: "App",
					packageName: "App",
					swiftFileContent: [Self.mockedRoot(importing: "Contracts", declaration: Self.erasedThing, propertyType: "AnyThing")],
					swiftFileContentByFilePath: ["Helper.swift": "internal import Impl\n"],
					dependencies: ["Contracts", "Impl"],
				),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			internal import Impl
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			internal import Impl
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            thing: (() -> AnyThing)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                thing: thing
			            )
			        }

			        var thing: (() -> AnyThing)? { __safeDI_storage.thing }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                thing: (() -> AnyThing)?
			            ) {
			                self.thing = thing
			            }

			            let thing: (() -> AnyThing)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let thing = if let safeDIBuilder = safeDIOverrides.thing { safeDIBuilder() } else { AnyThing(DefaultThing()) }
			        return Root(thing: thing)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif


			""",
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotImportModuleOfFulfiller_whenModuleDeclaresTypeOfThatNameWhichShadowsEveryImport(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				ModuleFixture(name: "Other", packageName: "App", swiftFileContent: ["@Instantiable\npublic struct Config: Instantiable {\n    public init() {}\n}\n"]),
				ModuleFixture(name: "Impl", packageName: "App", swiftFileContent: [Self.defaultThing], swiftFileContentByFilePath: ["ImplConfig.swift": "public struct Config {\n    public init() {}\n}\n"], dependencies: ["Contracts"]),
				ModuleFixture(
					name: "App",
					packageName: "App",
					swiftFileContent: ["import Contracts\nimport Other\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [Self.erasedThing, "@Instantiated let config: Config"])],
					swiftFileContentByFilePath: ["DefaultThing.swift": "import Contracts\n\nstruct DefaultThing: Thing {}\n"],
					dependencies: ["Contracts", "Other", "Impl"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Other)
			import Other
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        let config = Config()
			        self.init(thing: thing, config: config)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotImportModuleOfFulfiller_whenModuleDeclaresTypealiasOfThatName() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(
					name: "App",
					packageName: "App",
					swiftFileContent: [Self.root],
					swiftFileContentByFilePath: ["DefaultThing.swift": "import Contracts\n\nstruct OwnThing: Thing {}\n\ntypealias DefaultThing = OwnThing\n"],
					dependencies: ["Contracts", "Impl"],
				),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotImportModuleOfFulfiller_whenModuleDeclaresTypeOfThatNameWithCommentBeforeTheName() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(
					name: "App",
					packageName: "App",
					swiftFileContent: [Self.root],
					swiftFileContentByFilePath: ["DefaultThing.swift": "import Contracts\n\nstruct /* The module's own. */ DefaultThing: Thing {}\n"],
					dependencies: ["Contracts", "Impl"],
				),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: [0, 11, 23])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsLevelOfUnreadFilesImport_whicheverOfManyFilesSpellsIt(fileSpellingLevel: Int) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(
					name: "App",
					packageName: "App",
					swiftFileContent: [Self.root],
					swiftFileContentByFilePath: Dictionary(uniqueKeysWithValues: (0..<24).map { index in
						("Helper\(index).swift", index == fileSpellingLevel ? "internal import Impl\n" : "enum Helper\(index) {}\n")
					}),
					dependencies: ["Contracts", "Impl"],
				),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			internal import Impl
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	@Test(arguments: OwnTypeThatShadowsNothing.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfFulfiller_whenModulesOwnTypeOfThatNameIsNotVisibleWhereFileBuildsIt(ownType: OwnTypeThatShadowsNothing) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				ModuleFixture(
					name: "App",
					packageName: "App",
					swiftFileContent: [Self.root],
					swiftFileContentByFilePath: ["Helper.swift": ownType.source],
					dependencies: ["Contracts", "Impl"],
				),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			#if canImport(Contracts)
			import Contracts
			#endif
			#if canImport(Impl)
			import Impl
			#endif

			extension Root {
			    public init() {
			        let thing = AnyThing(DefaultThing())
			        self.init(thing: thing)
			    }
			}
			""",
		])
	}

	// MARK: Tests – A mock imports the module of each type it names

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfHandWrittenMock_whenFlatForwardedParameterDefaultsToIt(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Contracts", packageName: "App", swiftFileContent: ["public protocol Service {}\n"]),
				ModuleFixture(name: "Fakes", packageName: "App", swiftFileContent: ["""
				import Contracts

				@Instantiable(fulfillingAdditionalTypes: [(any Service).self], mockOnly: true)
				public struct FakeService: Instantiable, Service {
				    public static func mock() -> FakeService {
				        FakeService()
				    }
				}
				"""], dependencies: ["Contracts"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["""
				import Contracts

				@Instantiable(generateMock: true)
				public struct Feature: Instantiable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Forwarded let service: any Service
				}
				"""], dependencies: ["Contracts", "Fakes"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let expectedFiles: [String: String] = switch integration {
		case .moduleInfo:
			[
				"App.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Fakes)
				import Fakes
				#endif

				#if DEBUG
				extension Feature {
				    static func mock(
				        service: any Service = FakeService.mock()
				    ) -> Feature {
				        return Feature(service: service)
				    }
				}
				#endif
				""",
			]
		case .swiftPackagePlugin:
			[
				"Feature+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Fakes)
				import Fakes
				#endif

				#if DEBUG
				extension Feature {
				    static func mock(
				        service: any Service = FakeService.mock()
				    ) -> Feature {
				        return Feature(service: service)
				    }
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif


				""",
			]
		}
		#expect(output.modules["App"]?.generatedFiles == expectedFiles)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfHandWrittenMock_whenFlatReceivedParameterDefaultsToIt(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Contracts", packageName: "App", swiftFileContent: ["public protocol Service {}\n"]),
				ModuleFixture(name: "Impl", packageName: "App", swiftFileContent: ["""
				import Contracts

				@Instantiable(fulfillingAdditionalTypes: [(any Service).self])
				public struct WithForwarded: Instantiable, Service {
				    public init(name: String) {
				        self.name = name
				    }

				    public static func mock(name: String = "") -> WithForwarded {
				        WithForwarded(name: name)
				    }

				    @Forwarded let name: String
				}
				"""], dependencies: ["Contracts"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: ["""
				import Contracts

				@Instantiable(generateMock: true)
				public struct Feature: Instantiable {
				    public init(service: any Service) {
				        self.service = service
				    }

				    @Received let service: any Service
				}
				"""], dependencies: ["Contracts", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let expectedFiles: [String: String] = switch integration {
		case .moduleInfo:
			[
				"App.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Impl)
				import Impl
				#endif

				#if DEBUG
				extension Feature {
				    static func mock(
				        service: any Service = WithForwarded.mock()
				    ) -> Feature {
				        return Feature(service: service)
				    }
				}
				#endif
				""",
			]
		case .swiftPackagePlugin:
			[
				"Feature+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Impl)
				import Impl
				#endif

				#if DEBUG
				extension Feature {
				    static func mock(
				        service: any Service = WithForwarded.mock()
				    ) -> Feature {
				        return Feature(service: service)
				    }
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif


				""",
			]
		}
		#expect(output.modules["App"]?.generatedFiles == expectedFiles)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfMergedHandWrittenMock_inMockThatBuildsFulfillerWithIt(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				Self.fakesExtendingDefaultThing,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.mockedRoot(importing: "Contracts", declaration: Self.erasedThing, propertyType: "AnyThing")], dependencies: ["Contracts", "Impl", "Fakes"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let expectedFiles: [String: String] = switch integration {
		case .moduleInfo:
			[
				"App.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Fakes)
				import Fakes
				#endif
				#if canImport(Impl)
				import Impl
				#endif

				extension Root {
				    public init() {
				        let thing = AnyThing(DefaultThing())
				        self.init(thing: thing)
				    }
				}

				#if DEBUG
				extension Root {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            thing: (() -> AnyThing)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                thing: thing
				            )
				        }

				        var thing: (() -> AnyThing)? { __safeDI_storage.thing }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                thing: (() -> AnyThing)?
				            ) {
				                self.thing = thing
				            }

				            let thing: (() -> AnyThing)?
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Root {
				        let thing = if let safeDIBuilder = safeDIOverrides.thing { safeDIBuilder() } else { AnyThing(DefaultThing.fake()) }
				        return Root(thing: thing)
				    }
				}
				#endif
				""",
			]
		case .swiftPackagePlugin:
			[
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Impl)
				import Impl
				#endif

				extension Root {
				    public init() {
				        let thing = AnyThing(DefaultThing())
				        self.init(thing: thing)
				    }
				}
				""",
				"Root+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Fakes)
				import Fakes
				#endif
				#if canImport(Impl)
				import Impl
				#endif

				#if DEBUG
				extension Root {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            thing: (() -> AnyThing)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                thing: thing
				            )
				        }

				        var thing: (() -> AnyThing)? { __safeDI_storage.thing }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                thing: (() -> AnyThing)?
				            ) {
				                self.thing = thing
				            }

				            let thing: (() -> AnyThing)?
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Root {
				        let thing = if let safeDIBuilder = safeDIOverrides.thing { safeDIBuilder() } else { AnyThing(DefaultThing.fake()) }
				        return Root(thing: thing)
				    }
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Impl)
				import Impl
				#endif


				""",
			]
		}
		#expect(output.modules["App"]?.generatedFiles == expectedFiles)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfMergedHandWrittenMock_whenPropertyNamesTheType(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				Self.fakesExtendingDefaultThing,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.mockedRoot(importing: "Impl", declaration: "@Instantiated let thing: DefaultThing", propertyType: "DefaultThing")], dependencies: ["Impl", "Fakes"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let expectedFiles: [String: String] = switch integration {
		case .moduleInfo:
			[
				"App.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Fakes)
				import Fakes
				#endif
				#if canImport(Impl)
				import Impl
				#endif

				extension Root {
				    public init() {
				        let thing = DefaultThing()
				        self.init(thing: thing)
				    }
				}

				#if DEBUG
				extension Root {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            thing: (() -> DefaultThing)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                thing: thing
				            )
				        }

				        var thing: (() -> DefaultThing)? { __safeDI_storage.thing }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                thing: (() -> DefaultThing)?
				            ) {
				                self.thing = thing
				            }

				            let thing: (() -> DefaultThing)?
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Root {
				        let thing = if let safeDIBuilder = safeDIOverrides.thing { safeDIBuilder() } else { DefaultThing.fake() }
				        return Root(thing: thing)
				    }
				}
				#endif
				""",
			]
		case .swiftPackagePlugin:
			[
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Impl)
				import Impl
				#endif

				extension Root {
				    public init() {
				        let thing = DefaultThing()
				        self.init(thing: thing)
				    }
				}
				""",
				"Root+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Fakes)
				import Fakes
				#endif
				#if canImport(Impl)
				import Impl
				#endif

				#if DEBUG
				extension Root {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            thing: (() -> DefaultThing)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                thing: thing
				            )
				        }

				        var thing: (() -> DefaultThing)? { __safeDI_storage.thing }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                thing: (() -> DefaultThing)?
				            ) {
				                self.thing = thing
				            }

				            let thing: (() -> DefaultThing)?
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Root {
				        let thing = if let safeDIBuilder = safeDIOverrides.thing { safeDIBuilder() } else { DefaultThing.fake() }
				        return Root(thing: thing)
				    }
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Impl)
				import Impl
				#endif


				""",
			]
		}
		#expect(output.modules["App"]?.generatedFiles == expectedFiles)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfMergedHandWrittenMock_whenFileReadImportsTheTypeByItself(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.impl,
				Self.fakesExtendingDefaultThing,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.mockedRoot(importing: "struct Impl.DefaultThing", declaration: "@Instantiated let thing: DefaultThing", propertyType: "DefaultThing")], dependencies: ["Impl", "Fakes"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let expectedFiles: [String: String] = switch integration {
		case .moduleInfo:
			[
				"App.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Fakes)
				import Fakes
				#endif
				#if canImport(Impl)
				import Impl
				#endif

				extension Root {
				    public init() {
				        let thing = DefaultThing()
				        self.init(thing: thing)
				    }
				}

				#if DEBUG
				extension Root {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            thing: (() -> DefaultThing)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                thing: thing
				            )
				        }

				        var thing: (() -> DefaultThing)? { __safeDI_storage.thing }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                thing: (() -> DefaultThing)?
				            ) {
				                self.thing = thing
				            }

				            let thing: (() -> DefaultThing)?
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Root {
				        let thing = if let safeDIBuilder = safeDIOverrides.thing { safeDIBuilder() } else { DefaultThing.fake() }
				        return Root(thing: thing)
				    }
				}
				#endif
				""",
			]
		case .swiftPackagePlugin:
			[
				"Root+SafeDI.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Impl)
				import Impl
				#endif

				extension Root {
				    public init() {
				        let thing = DefaultThing()
				        self.init(thing: thing)
				    }
				}
				""",
				"Root+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Fakes)
				import Fakes
				#endif
				#if canImport(Impl)
				import Impl
				#endif

				#if DEBUG
				extension Root {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            thing: (() -> DefaultThing)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                thing: thing
				            )
				        }

				        var thing: (() -> DefaultThing)? { __safeDI_storage.thing }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                thing: (() -> DefaultThing)?
				            ) {
				                self.thing = thing
				            }

				            let thing: (() -> DefaultThing)?
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Root {
				        let thing = if let safeDIBuilder = safeDIOverrides.thing { safeDIBuilder() } else { DefaultThing.fake() }
				        return Root(thing: thing)
				    }
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Impl)
				import Impl
				#endif


				""",
			]
		}
		#expect(output.modules["App"]?.generatedFiles == expectedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfMergedHandWrittenMock_inMockConfigurationFile_whenItsDefaultNamesATypeOfThatModule() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.implWithChild,
				ModuleFixture(name: "Fakes", packageName: "App", swiftFileContent: ["""
				import Impl

				public enum FakeSeed {
				    public static let standard = 1
				}

				@Instantiable(mockOnly: true, customMockName: "fake")
				extension DefaultThing: Instantiable {
				    public static func fake(clock: Clock = Clock(), seed: Int = FakeSeed.standard) -> DefaultThing {
				        DefaultThing(clock: clock)
				    }
				}
				"""], dependencies: ["Impl"]),
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.mockedFeature], dependencies: ["Contracts", "Impl", "Fakes"]),
			],
			integration: .swiftPackagePlugin,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["App"]?.generatedFiles["SafeDIMockConfiguration.swift"] == generatedFileHeader + """
		#if canImport(Contracts)
		import Contracts
		#endif
		#if canImport(Fakes)
		import Fakes
		#endif
		#if canImport(Impl)
		import Impl
		#endif

		#if DEBUG
		extension DefaultThing {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            clock: (() -> Clock)? = nil,
		            seed: Int = FakeSeed.standard,
		            _ safeDIBuilder: ((Clock, Int) -> DefaultThing)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                clock: clock,
		                seed: seed,
		                safeDIBuilder: safeDIBuilder
		            )
		        }

		        var clock: (() -> Clock)? { __safeDI_storage.clock }
		        var seed: Int { __safeDI_storage.seed }
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        var safeDIBuilder: ((Clock, Int) -> DefaultThing)? { __safeDI_storage.safeDIBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                clock: (() -> Clock)?,
		                seed: Int,
		                safeDIBuilder: ((Clock, Int) -> DefaultThing)?
		            ) {
		                self.clock = clock
		                self.seed = seed
		                self.safeDIBuilder = safeDIBuilder
		            }

		            let clock: (() -> Clock)?
		            let seed: Int
		            let safeDIBuilder: ((Clock, Int) -> DefaultThing)?
		        }
		    }
		}
		#endif

		""")
	}

	// MARK: Tests – A listed mock imports the module of the type it extends

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfListedType_whenModulesOnlyFileListsItInAdditionalMocksToGenerate(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.sideKit,
				Self.testSupport,
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let expectedFiles: [String: String] = switch integration {
		case .moduleInfo:
			[
				"TestSupport.swift": generatedFileHeader + """
				#if canImport(SideKit)
				import SideKit
				#endif

				#if DEBUG
				extension SideFeature {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            clock: (() -> Clock)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                clock: clock
				            )
				        }

				        var clock: (() -> Clock)? { __safeDI_storage.clock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                clock: (() -> Clock)?
				            ) {
				                self.clock = clock
				            }

				            let clock: (() -> Clock)?
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> SideFeature {
				        let clock = if let safeDIBuilder = safeDIOverrides.clock { safeDIBuilder() } else { Clock() }
				        return SideFeature(clock: clock)
				    }
				}
				#endif
				""",
			]
		case .swiftPackagePlugin:
			[
				"SafeDIMockConfiguration.swift": generatedFileHeader + """

				""",
				"SideFeature+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SideKit)
				import SideKit
				#endif

				#if DEBUG
				extension SideFeature {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            clock: (() -> Clock)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                clock: clock
				            )
				        }

				        var clock: (() -> Clock)? { __safeDI_storage.clock }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                clock: (() -> Clock)?
				            ) {
				                self.clock = clock
				            }

				            let clock: (() -> Clock)?
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> SideFeature {
				        let clock = if let safeDIBuilder = safeDIOverrides.clock { safeDIBuilder() } else { Clock() }
				        return SideFeature(clock: clock)
				    }
				}
				#endif
				""",
			]
		}
		#expect(output.modules["TestSupport"]?.generatedFiles == expectedFiles)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfListedType_inMockConfigurationFile_whenListedTypeBuildsAnotherTypeOfThatModule(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "SideKit", packageName: "App", swiftFileContent: [
					seamFixtureType(named: "SideFeature", declarations: ["@Instantiated let panel: Panel"]),
					seamFixtureType(named: "Panel", declarations: ["@Instantiated let clock: Clock"]),
					Self.clock,
				]),
				Self.testSupport,
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let expectedFiles: [String: String] = switch integration {
		case .moduleInfo:
			[
				"TestSupport.swift": generatedFileHeader + """
				#if canImport(SideKit)
				import SideKit
				#endif

				#if DEBUG
				extension SideFeature {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            panel: Panel.SafeDIMockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                panel: panel
				            )
				        }

				        var panel: Panel.SafeDIMockConfiguration { __safeDI_storage.panel }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                panel: Panel.SafeDIMockConfiguration
				            ) {
				                self.panel = panel
				            }

				            let panel: Panel.SafeDIMockConfiguration
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> SideFeature {
				        func __safeDI_panel() -> Panel {
				            let clock = if let safeDIBuilder = safeDIOverrides.panel.clock { safeDIBuilder() } else { Clock() }
				            return if let safeDIBuilder = safeDIOverrides.panel.safeDIBuilder { safeDIBuilder(clock) } else { Panel(clock: clock) }
				        }
				        let panel: Panel = __safeDI_panel()
				        return SideFeature(panel: panel)
				    }
				}
				#endif

				#if DEBUG
				extension Panel {
				    /// Configuration for how this type is constructed within a mock tree.
				    struct SafeDIMockConfiguration {
				        init(
				            clock: (() -> Clock)? = nil,
				            _ safeDIBuilder: ((Clock) -> Panel)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                clock: clock,
				                safeDIBuilder: safeDIBuilder
				            )
				        }

				        var clock: (() -> Clock)? { __safeDI_storage.clock }
				        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
				        var safeDIBuilder: ((Clock) -> Panel)? { __safeDI_storage.safeDIBuilder }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                clock: (() -> Clock)?,
				                safeDIBuilder: ((Clock) -> Panel)?
				            ) {
				                self.clock = clock
				                self.safeDIBuilder = safeDIBuilder
				            }

				            let clock: (() -> Clock)?
				            let safeDIBuilder: ((Clock) -> Panel)?
				        }
				    }
				}
				#endif

				""",
			]
		case .swiftPackagePlugin:
			[
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(SideKit)
				import SideKit
				#endif

				#if DEBUG
				extension Panel {
				    /// Configuration for how this type is constructed within a mock tree.
				    struct SafeDIMockConfiguration {
				        init(
				            clock: (() -> Clock)? = nil,
				            _ safeDIBuilder: ((Clock) -> Panel)? = nil
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                clock: clock,
				                safeDIBuilder: safeDIBuilder
				            )
				        }

				        var clock: (() -> Clock)? { __safeDI_storage.clock }
				        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
				        var safeDIBuilder: ((Clock) -> Panel)? { __safeDI_storage.safeDIBuilder }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                clock: (() -> Clock)?,
				                safeDIBuilder: ((Clock) -> Panel)?
				            ) {
				                self.clock = clock
				                self.safeDIBuilder = safeDIBuilder
				            }

				            let clock: (() -> Clock)?
				            let safeDIBuilder: ((Clock) -> Panel)?
				        }
				    }
				}
				#endif

				""",
				"SideFeature+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(SideKit)
				import SideKit
				#endif

				#if DEBUG
				extension SideFeature {
				    /// Overrides for the mock dependency tree.
				    struct SafeDIOverrides {
				        init(
				            panel: Panel.SafeDIMockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                panel: panel
				            )
				        }

				        var panel: Panel.SafeDIMockConfiguration { __safeDI_storage.panel }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                panel: Panel.SafeDIMockConfiguration
				            ) {
				                self.panel = panel
				            }

				            let panel: Panel.SafeDIMockConfiguration
				        }
				    }

				    static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> SideFeature {
				        func __safeDI_panel() -> Panel {
				            let clock = if let safeDIBuilder = safeDIOverrides.panel.clock { safeDIBuilder() } else { Clock() }
				            return if let safeDIBuilder = safeDIOverrides.panel.safeDIBuilder { safeDIBuilder(clock) } else { Panel(clock: clock) }
				        }
				        let panel: Panel = __safeDI_panel()
				        return SideFeature(panel: panel)
				    }
				}
				#endif
				""",
			]
		}
		#expect(output.modules["TestSupport"]?.generatedFiles == expectedFiles)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_importsModuleOfFulfiller_inConfigurationOfPublicMock(integration: MultiModuleIntegration) async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.contracts,
				Self.implWithChild,
				ModuleFixture(name: "App", packageName: "App", swiftFileContent: [Self.publicMockedFeature], dependencies: ["Contracts", "Impl"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let expectedFiles: [String: String] = switch integration {
		case .moduleInfo:
			[
				"App.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Impl)
				import Impl
				#endif

				#if DEBUG
				extension Feature {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            thing: __safeDI_App_DefaultThing_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                thing: thing
				            )
				        }

				        public var thing: __safeDI_App_DefaultThing_MockConfiguration { __safeDI_storage.thing }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                thing: __safeDI_App_DefaultThing_MockConfiguration
				            ) {
				                self.thing = thing
				            }

				            let thing: __safeDI_App_DefaultThing_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Feature {
				        Feature.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Feature {
				        func __safeDI_thing() -> AnyThing {
				            let clock = if let safeDIBuilder = safeDIOverrides.thing.clock { safeDIBuilder() } else { Clock() }
				            return AnyThing(DefaultThing.__safeDI_init(clock: clock, safeDIBuilder: safeDIOverrides.thing.safeDIBuilder))
				        }
				        let thing: AnyThing = __safeDI_thing()
				        return Feature(thing: thing)
				    }
				}

				extension Feature {
				    public enum __safeDI_Feature_mock_51799E6AA5E7B634 {}
				}
				#endif

				#if DEBUG
				/// Configuration for how `DefaultThing` is constructed within the public mock trees of module `App`.
				nonisolated public struct __safeDI_App_DefaultThing_MockConfiguration {
				    public init(
				        clock: (() -> Clock)? = nil,
				        _ safeDIBuilder: ((Clock) -> DefaultThing)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            clock: clock,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var clock: (() -> Clock)? { __safeDI_storage.clock }
				    /// Overrides how `DefaultThing` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((Clock) -> DefaultThing)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            clock: (() -> Clock)?,
				            safeDIBuilder: ((Clock) -> DefaultThing)?
				        ) {
				            self.clock = clock
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let clock: (() -> Clock)?
				        let safeDIBuilder: ((Clock) -> DefaultThing)?
				    }
				}

				extension DefaultThing {
				    static func __safeDI_init(clock: Clock, safeDIBuilder: ((Clock) -> DefaultThing)?) -> DefaultThing {
				        if let safeDIBuilder { safeDIBuilder(clock) } else { DefaultThing(clock: clock) }
				    }
				}
				#endif

				""",
			]
		case .swiftPackagePlugin:
			[
				"Feature+SafeDIMock.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Impl)
				import Impl
				#endif

				#if DEBUG
				extension Feature {
				    /// Overrides for the mock dependency tree.
				    nonisolated public struct SafeDIOverrides {
				        public init(
				            thing: __safeDI_App_DefaultThing_MockConfiguration = .init()
				        ) {
				            __safeDI_storage = __safeDI_Storage(
				                thing: thing
				            )
				        }

				        public var thing: __safeDI_App_DefaultThing_MockConfiguration { __safeDI_storage.thing }

				        private let __safeDI_storage: __safeDI_Storage

				        private final class __safeDI_Storage {
				            init(
				                thing: __safeDI_App_DefaultThing_MockConfiguration
				            ) {
				                self.thing = thing
				            }

				            let thing: __safeDI_App_DefaultThing_MockConfiguration
				        }
				    }

				    public static func mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Feature {
				        Feature.__safeDI_mock(safeDIOverrides: safeDIOverrides)
				    }

				    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
				    public static func __safeDI_mock(
				        safeDIOverrides: SafeDIOverrides = .init()
				    ) -> Feature {
				        func __safeDI_thing() -> AnyThing {
				            let clock = if let safeDIBuilder = safeDIOverrides.thing.clock { safeDIBuilder() } else { Clock() }
				            return AnyThing(DefaultThing.__safeDI_init(clock: clock, safeDIBuilder: safeDIOverrides.thing.safeDIBuilder))
				        }
				        let thing: AnyThing = __safeDI_thing()
				        return Feature(thing: thing)
				    }
				}

				extension Feature {
				    public enum __safeDI_Feature_mock_51799E6AA5E7B634 {}
				}
				#endif
				""",
				"SafeDIMockConfiguration.swift": generatedFileHeader + """
				#if canImport(Contracts)
				import Contracts
				#endif
				#if canImport(Impl)
				import Impl
				#endif

				#if DEBUG
				/// Configuration for how `DefaultThing` is constructed within the public mock trees of module `App`.
				nonisolated public struct __safeDI_App_DefaultThing_MockConfiguration {
				    public init(
				        clock: (() -> Clock)? = nil,
				        _ safeDIBuilder: ((Clock) -> DefaultThing)? = nil
				    ) {
				        __safeDI_storage = __safeDI_Storage(
				            clock: clock,
				            safeDIBuilder: safeDIBuilder
				        )
				    }

				    public var clock: (() -> Clock)? { __safeDI_storage.clock }
				    /// Overrides how `DefaultThing` is constructed. Parameters match the type’s initializer or custom mock method.
				    public var safeDIBuilder: ((Clock) -> DefaultThing)? { __safeDI_storage.safeDIBuilder }

				    private let __safeDI_storage: __safeDI_Storage

				    private final class __safeDI_Storage {
				        init(
				            clock: (() -> Clock)?,
				            safeDIBuilder: ((Clock) -> DefaultThing)?
				        ) {
				            self.clock = clock
				            self.safeDIBuilder = safeDIBuilder
				        }

				        let clock: (() -> Clock)?
				        let safeDIBuilder: ((Clock) -> DefaultThing)?
				    }
				}

				extension DefaultThing {
				    static func __safeDI_init(clock: Clock, safeDIBuilder: ((Clock) -> DefaultThing)?) -> DefaultThing {
				        if let safeDIBuilder { safeDIBuilder(clock) } else { DefaultThing(clock: clock) }
				    }
				}
				#endif

				""",
			]
		}
		#expect(output.modules["App"]?.generatedFiles == expectedFiles)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Re-exports the module that declares the fulfiller, so a file that imports it reaches the fulfiller.
	private static let reexport = ModuleFixture(name: "Reexport", packageName: "App", swiftFileContent: ["@_exported import Impl\n"], dependencies: ["Impl"])

	/// Declares a hand-written mock of the fulfiller `impl` declares, in a module of its own.
	private static let fakesExtendingDefaultThing = ModuleFixture(name: "Fakes", packageName: "App", swiftFileContent: ["""
	import Impl

	@Instantiable(mockOnly: true, customMockName: "fake")
	extension DefaultThing: Instantiable {
	    public static func fake() -> DefaultThing {
	        DefaultThing()
	    }
	}
	"""], dependencies: ["Impl"])

	private static func mockedRoot(importing moduleName: String, declaration: String, propertyType: String) -> String {
		"""
		import \(moduleName)

		@Instantiable(isRoot: true, generateMock: true)
		public struct Root: Instantiable {
		    public init(thing: \(propertyType)) {
		        self.thing = thing
		    }

		    \(declaration)
		}
		"""
	}

	private static let publicMockedFeature = """
	import Contracts

	@Instantiable(generateMock: .public)
	public struct Feature: Instantiable {
	    public init(thing: AnyThing) {
	        self.thing = thing
	    }

	    \(erasedThing)
	}
	"""

	private static let contractsSource = """
	public protocol Thing {}

	public struct AnyThing: Thing {
	    public init(_ thing: some Thing) {
	        self.thing = thing
	    }

	    let thing: any Thing
	}
	"""

	private static let contracts = ModuleFixture(name: "Contracts", packageName: "App", swiftFileContent: [contractsSource])

	private static let defaultThing = """
	import Contracts

	@Instantiable
	public struct DefaultThing: Instantiable, Thing {
	    public init() {}
	}
	"""

	/// A plain type with the name of the fulfiller `impl` declares.
	private static let otherDeclaringPlainDefaultThing = ModuleFixture(name: "Other", packageName: "App", swiftFileContent: ["public struct DefaultThing {\n    public init() {}\n}\n"])

	/// A module whose string names the fulfiller `impl` declares, in a type no tree of a module that reads it reaches.
	private static let sideReadingStringItDoesNotBuild = ModuleFixture(name: "Side", packageName: "App", swiftFileContent: ["import Contracts\n\n" + seamFixtureType(named: "Unbuilt", declarations: [erasedThing])], dependencies: ["Contracts", "Impl"])

	/// The fulfiller fulfills `Thing` by its own declaration, so no property’s declaration names it.
	private static let implFulfillingThing = ModuleFixture(name: "Impl", packageName: "App", swiftFileContent: ["""
	import Contracts

	@Instantiable(fulfillingAdditionalTypes: [(any Thing).self])
	public struct DefaultThing: Instantiable, Thing {
	    public init() {}
	}
	"""], dependencies: ["Contracts"])

	/// Declares a type that a module of test support generates the mock of.
	private static let sideKit = ModuleFixture(name: "SideKit", packageName: "App", swiftFileContent: [
		seamFixtureType(named: "SideFeature", declarations: ["@Instantiated let clock: Clock"]),
		clock,
	])

	/// A module of test support: its only file lists the type another module declares, so none of its files imports that module.
	private static let testSupport = ModuleFixture(
		name: "TestSupport",
		packageName: "App",
		swiftFileContentByFilePath: ["SafeDIConfiguration.swift": #"#SafeDIConfiguration(additionalMocksToGenerate: ["SideFeature"])"#],
		dependencies: ["SideKit"],
	)

	private static let clock = seamFixtureType(named: "Clock", declarations: [])

	private static let impl = ModuleFixture(name: "Impl", packageName: "App", swiftFileContent: [defaultThing], dependencies: ["Contracts"])

	/// The fulfiller has a dependency of its own, so a mock's configuration file names it.
	private static let implWithChild = ModuleFixture(name: "Impl", packageName: "App", swiftFileContent: ["""
	import Contracts

	@Instantiable
	public struct DefaultThing: Instantiable, Thing {
	    public init(clock: Clock) {
	        self.clock = clock
	    }

	    @Instantiated let clock: Clock
	}
	""", clock], dependencies: ["Contracts"])

	private static let erasedThing = #"@Instantiated(fulfilledByType: "DefaultThing", erasedToConcreteExistential: true) let thing: AnyThing"#

	private static let root = "import Contracts\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: [erasedThing])

	private static let mockedFeature = """
	import Contracts

	@Instantiable(generateMock: true)
	public struct Feature: Instantiable {
	    public init(thing: AnyThing) {
	        self.thing = thing
	    }

	    \(erasedThing)
	}
	"""
}

/// An import of the module that declares a fulfiller in a file SafeDI does not read, with how the generated file must
/// import that module for the two to compile side by side.
enum UnreadFileImport: CaseIterable {
	case internalLevel
	case packageLevel
	case publicLevel
	case noLevel
	case internalImportOfOneType
	case implementationOnly
	case implementationOnlyAtInternalLevel

	var source: String {
		switch self {
		case .internalLevel:
			"internal import Impl"
		case .packageLevel:
			"package import Impl"
		case .publicLevel:
			"public import Impl"
		case .noLevel:
			"import Impl"
		case .internalImportOfOneType:
			"internal import struct Impl.DefaultThing"
		case .implementationOnly:
			"@_implementationOnly import Impl"
		case .implementationOnlyAtInternalLevel:
			"@_implementationOnly internal import Impl"
		}
	}

	var expectedGeneratedImport: String {
		switch self {
		case .internalLevel, .packageLevel, .internalImportOfOneType:
			"internal import Impl"
		case .publicLevel, .noLevel:
			"import Impl"
		case .implementationOnly:
			"@_implementationOnly import Impl"
		case .implementationOnlyAtInternalLevel:
			"@_implementationOnly internal import Impl"
		}
	}
}

/// A type the module declares with the name of a fulfiller of another module that is not what the name finds in a
/// generated file.
enum OwnTypeThatShadowsNothing: CaseIterable {
	case fileprivateType
	case nestedType
	case nestedInExtension

	var source: String {
		switch self {
		case .fileprivateType:
			"fileprivate struct DefaultThing {}\n"
		case .nestedType:
			"enum Space {\n    struct DefaultThing {}\n}\n"
		case .nestedInExtension:
			"struct Space {}\n\nextension Space {\n    struct DefaultThing {}\n}\n"
		}
	}
}

/// A property a `fulfilledByType:` string fulfills, with what the root that declares it generates.
enum FulfilledProperty: CaseIterable {
	case erasedInstantiator
	case castToExistential

	var declaration: String {
		switch self {
		case .erasedInstantiator:
			#"@Instantiated(fulfilledByType: "DefaultThing", erasedToConcreteExistential: true) let thingBuilder: ErasedInstantiator<(), AnyThing>"#
		case .castToExistential:
			#"@Instantiated(fulfilledByType: "DefaultThing") let thing: any Thing"#
		}
	}

	var expectedImports: [String] {
		switch self {
		case .erasedInstantiator, .castToExistential:
			["Contracts", "Impl"]
		}
	}

	var expectedBody: String {
		switch self {
		case .erasedInstantiator:
			"""
			extension Root {
			    public init() {
			        func __safeDI_thingBuilder() -> DefaultThing {
			            DefaultThing()
			        }
			        let thingBuilder = ErasedInstantiator<(), AnyThing> {
			            AnyThing(__safeDI_thingBuilder())
			        }
			        self.init(thingBuilder: thingBuilder)
			    }
			}
			"""
		case .castToExistential:
			"""
			extension Root {
			    public init() {
			        let thing: any Thing = DefaultThing()
			        self.init(thing: thing)
			    }
			}
			"""
		}
	}
}
