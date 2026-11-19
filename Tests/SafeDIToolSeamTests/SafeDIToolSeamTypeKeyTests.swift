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

/// The seam type key (R2a): a seam's initializer shares builder functions as a root's body does under the production
/// type key, and the code its callers generate does not change. Each test pins the seam module's and the calling
/// module's whole generated files, and checks that the expected files compile and build the values the generated ones
/// do.
///
/// Written before the type key exists: each test fails on the seam module's file until R2a switches seam bodies to the
/// type key. The calling module's expected file is today's, which R2a must leave byte for byte.
struct SafeDIToolSeamTypeKeyTests: ~Copyable {
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
	mutating func generate_buildsSharedTypeInOneFunctionInsideSeamInitializer_whenSeamTreeBuildsTypeTwice() async throws {
		// `Host`'s tree builds `Leaf` under `A` and under `B`, and both read `Host`'s `service`: the seam's initializer declares one function for both. Callers are unchanged.
		try await expectSeamTypeKeyFiles(
			ofFeature: [
				Self.type("Host", isSeam: true, "@Instantiated public let service: Service", "@Instantiated public let a: A", "@Instantiated public let b: B"),
				Self.type("A", "@Instantiated public let leafBuilder: Instantiator<Leaf>"),
				Self.type("B", "@Instantiated public let leafBuilder: Instantiator<Leaf>"),
				Self.type("Leaf", "@Received public let service: Service"),
				Self.type("Service"),
			],
			feature: """
			extension Host {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public convenience init() {
			        let service = Service()
			        func __safeDI_leafBuilder() -> Leaf {
			            Leaf(service: service)
			        }
			        func __safeDI_a() -> A {
			            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			            return A(leafBuilder: leafBuilder)
			        }
			        let a: A = __safeDI_a()
			        func __safeDI_b() -> B {
			            let leafBuilder = Instantiator<Leaf>(__safeDI_leafBuilder)
			            return B(leafBuilder: leafBuilder)
			        }
			        let b: B = __safeDI_b()
			        self.init(service: service, a: a, b: b)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_CBF29CE484222325 {}
			}
			""",
			app: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host()
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesReadAsParameterInsideSeamInitializer_whenPlacesResolveLabelToDifferentDeclarations() async throws {
		// `A` and `B` each declare their own `cache`, so the seam's shared `Leaf` function takes it as a parameter. Callers are unchanged.
		try await expectSeamTypeKeyFiles(
			ofFeature: [
				Self.type("Host", isSeam: true, "@Instantiated public let a: A", "@Instantiated public let b: B"),
				Self.type("A", "@Instantiated public let cache: Cache", "@Instantiated public let leafBuilder: Instantiator<Leaf>"),
				Self.type("B", "@Instantiated public let cache: Cache", "@Instantiated public let leafBuilder: Instantiator<Leaf>"),
				Self.type("Leaf", "@Received public let cache: Cache"),
				Self.type("Cache"),
			],
			feature: """
			extension Host {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public convenience init() {
			        func __safeDI_leafBuilder(cache: Cache) -> Leaf {
			            Leaf(cache: cache)
			        }
			        func __safeDI_a() -> A {
			            let cache = Cache()
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(cache: cache)
			            }
			            return A(cache: cache, leafBuilder: leafBuilder)
			        }
			        let a: A = __safeDI_a()
			        func __safeDI_b() -> B {
			            let cache = Cache()
			            let leafBuilder = Instantiator<Leaf> {
			                __safeDI_leafBuilder(cache: cache)
			            }
			            return B(cache: cache, leafBuilder: leafBuilder)
			        }
			        let b: B = __safeDI_b()
			        self.init(a: a, b: b)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_CBF29CE484222325 {}
			}
			""",
			app: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host()
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesOneFunctionPerFamily_whenSeamBuildsTypeInsideAndOutsideSendableBuilder() async throws {
		// d2 in a seam: `Leaf` is built in `Host`'s initializer and inside `Panel`'s `@Sendable` builder function, so it has one function per family; `Item`'s `@Sendable` builders share one. Callers are unchanged.
		try await expectSeamTypeKeyFiles(
			ofFeature: [
				Self.type("Host", isSeam: true, "@Instantiated public let leaf: Leaf", "@Instantiated public let panelBuilder: SendableInstantiator<Panel>"),
				Self.sendableType("Panel", "@Instantiated public let leaf: Leaf"),
				Self.sendableType("Leaf", "@Instantiated public let itemBuilder: SendableInstantiator<Item>"),
				Self.sendableType("Item"),
			],
			feature: """
			extension Host {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public convenience init() {
			        @Sendable func __safeDI_itemBuilder() -> Item {
			            Item()
			        }
			        func __safeDI_leaf() -> Leaf {
			            let itemBuilder = SendableInstantiator<Item>(__safeDI_itemBuilder)
			            return Leaf(itemBuilder: itemBuilder)
			        }
			        let leaf: Leaf = __safeDI_leaf()
			        @Sendable func __safeDI_panelBuilder() -> Panel {
			            func __safeDI_leaf_() -> Leaf {
			                let itemBuilder = SendableInstantiator<Item>(__safeDI_itemBuilder)
			                return Leaf(itemBuilder: itemBuilder)
			            }
			            let leaf: Leaf = __safeDI_leaf_()
			            return Panel(leaf: leaf)
			        }
			        let panelBuilder = SendableInstantiator<Panel>(__safeDI_panelBuilder)
			        self.init(leaf: leaf, panelBuilder: panelBuilder)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_CBF29CE484222325 {}
			}
			""",
			app: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host()
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEachLoopMemberInOneFunctionInsideSeamInitializer_whenInstantiatorLoopReentersType() async throws {
		// `Screen` and `Step` build each other inside `Host`, which builds both: one function per member, declared together. Callers are unchanged.
		try await expectSeamTypeKeyFiles(
			ofFeature: [
				Self.type("Host", isSeam: true, "@Instantiated public let screenBuilder: Instantiator<Screen>", "@Instantiated public let stepBuilder: Instantiator<Step>"),
				Self.type("Screen", "@Instantiated public let stepBuilder: Instantiator<Step>"),
				Self.type("Step", "@Instantiated public let screenBuilder: Instantiator<Screen>"),
			],
			feature: """
			extension Host {
			    /// Code you write and code SafeDI generates can both call this initializer.
			    public convenience init() {
			        func __safeDI_screenBuilder() -> Screen {
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            return Screen(stepBuilder: stepBuilder)
			        }
			        func __safeDI_stepBuilder() -> Step {
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			            return Step(screenBuilder: screenBuilder)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			        self.init(screenBuilder: screenBuilder, stepBuilder: stepBuilder)
			    }
			}

			extension Host {
			    public enum __safeDI_Host_CBF29CE484222325 {}
			}
			""",
			app: """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public convenience init() {
			        func __safeDI_host() -> Host {
			            _ = Host.__safeDI_Host_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Host()
			        }
			        let host: Host = __safeDI_host()
			        self.init(host: host)
			    }
			}
			""",
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Generates `Feature`, which declares the seam `Host`, and `App`, whose root instantiates `Host`, and compares each
	/// module's generated file with the expected one. Then compiles the modules once with the generated files and once
	/// with the expected ones, and compares the values `Root()` builds.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectSeamTypeKeyFiles(
		ofFeature featureFiles: [String],
		feature expectedFeature: String,
		app expectedApp: String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: featureFiles),
			ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
				"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated public let host: Host"]),
			], dependencies: ["Feature"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + expectedFeature], sourceLocation: sourceLocation)
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + expectedApp], sourceLocation: sourceLocation)
		let generated = try DifferentialValuePath(output: output, modules: modules)
		let expected = DifferentialValuePath(modules: generated.modules.map { module in
			DifferentialValueModule(
				name: module.name,
				packageName: module.packageName,
				dependencyModuleNames: module.dependencyModuleNames,
				fixtureFiles: module.fixtureFiles,
				generatedFiles: ["\(module.name).swift": generatedFileHeader + (module.name == "Feature" ? expectedFeature : expectedApp)],
			)
		})
		try await expectDifferentialValuesAgree(
			feature: generated,
			knownRight: expected,
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	private static func type(_ name: String, isSeam: Bool = false, _ declarations: String...) -> String {
		seamFixtureType(named: name, isSeam: isSeam, isFinalClass: true, declarations: declarations)
	}

	private static func sendableType(_ name: String, _ declarations: String...) -> String {
		seamFixtureType(named: name, declarations: declarations, conformances: ", Sendable")
	}
}
