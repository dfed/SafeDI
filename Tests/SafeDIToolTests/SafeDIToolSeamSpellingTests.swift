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

/// A seam's generated initializer spells each parameter as a parsed initializer does, and every tree that calls it
/// matches its arguments to that spelling: a closure parameter is `@escaping`, an optional closure is not, and every
/// other spelling – a tuple, an existential, a nested or generic type, a typealias – is spelled as it is declared.
/// Each cell sits beside the inline build of the same graph, which passes each receiver the same value.
struct SafeDIToolSeamSpellingTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Closure-typed pass-throughs

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamPassingClosure_whenTreeRequiresClosureItsCallerForwards() async throws {
		let fixture = Self.passThroughFixture(forwarded: "onSelect: () -> Void", received: "@Received let onSelect: () -> Void")
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"List+SafeDI.swift": generatedFileHeader + """
			extension List {
			    public init(onSelect: @escaping () -> Void) {
			        let row = Row(onSelect: onSelect)
			        self.init(row: row)
			    }
			}

			extension List {
			    public enum __safeDI_List_6E4AFC77A9D161A1 {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_screenBuilder(onSelect: @escaping () -> Void) -> Screen {
			            func __safeDI_list() -> List {
			                _ = List.__safeDI_List_6E4AFC77A9D161A1.self
			                return List(onSelect: onSelect)
			            }
			            let list: List = __safeDI_list()
			            return Screen(onSelect: onSelect, list: list)
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(onSelect: $0)
			        }
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: Self.inline(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_screenBuilder(onSelect: @escaping () -> Void) -> Screen {
			            func __safeDI_list() -> List {
			                let row = Row(onSelect: onSelect)
			                return List(row: row)
			            }
			            let list: List = __safeDI_list()
			            return Screen(onSelect: onSelect, list: list)
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(onSelect: $0)
			        }
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOptionalPropertyBeforeRename_whenTreeRenamesClosureOnlyIfAvailable() async throws {
		let fixture = Self.passThroughFixture(
			forwarded: "onTap: () -> Void",
			received: "@Received(fulfilledByDependencyNamed: \"onTap\", ofType: (() -> Void).self, onlyIfAvailable: true) let action: (() -> Void)?",
		)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"List+SafeDI.swift": generatedFileHeader + """
			extension List {
			    public init(onTap: (() -> Void)? = nil) {
			        func __safeDI_row() -> Row {
			            #sourceLocation(file: "\(output.fixtures["Row.swift"])", line: 7)
			            let action: (() -> Void)? = onTap
			            #sourceLocation()
			            return Row(action: action)
			        }
			        let row: Row = __safeDI_row()
			        self.init(row: row)
			    }
			}

			extension List {
			    public enum __safeDI_List_2E27F40A01119D9A {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_screenBuilder(onTap: @escaping () -> Void) -> Screen {
			            func __safeDI_list() -> List {
			                _ = List.__safeDI_List_2E27F40A01119D9A.self
			                return List(onTap: onTap)
			            }
			            let list: List = __safeDI_list()
			            return Screen(onTap: onTap, list: list)
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(onTap: $0)
			        }
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: Self.inline(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_screenBuilder(onTap: @escaping () -> Void) -> Screen {
			            func __safeDI_list() -> List {
			                func __safeDI_row() -> Row {
			                    #sourceLocation(file: "\(inlineOutput.fixtures["Row.swift"])", line: 7)
			                    let action: (() -> Void)? = onTap
			                    #sourceLocation()
			                    return Row(action: action)
			                }
			                let row: Row = __safeDI_row()
			                return List(row: row)
			            }
			            let list: List = __safeDI_list()
			            return Screen(onTap: onTap, list: list)
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(onTap: $0)
			        }
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamWithOneGuard_whenClosureTakesExistentialSpelledWithAnyAboveAndWithoutBeneath() async throws {
		let fixture = Self.passThroughFixture(forwarded: "onFailure: (any Error) -> Void", received: "@Received let onFailure: (Error) -> Void")
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"List+SafeDI.swift": generatedFileHeader + """
			extension List {
			    public init(onFailure: @escaping (Error) -> Void) {
			        let row = Row(onFailure: onFailure)
			        self.init(row: row)
			    }
			}

			extension List {
			    public enum __safeDI_List_201E4556756848D3 {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_screenBuilder(onFailure: @escaping (any Error) -> Void) -> Screen {
			            func __safeDI_list() -> List {
			                _ = List.__safeDI_List_201E4556756848D3.self
			                return List(onFailure: onFailure)
			            }
			            let list: List = __safeDI_list()
			            return Screen(onFailure: onFailure, list: list)
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(onFailure: $0)
			        }
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: Self.inline(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_screenBuilder(onFailure: @escaping (any Error) -> Void) -> Screen {
			            func __safeDI_list() -> List {
			                let row = Row(onFailure: onFailure)
			                return List(row: row)
			            }
			            let list: List = __safeDI_list()
			            return Screen(onFailure: onFailure, list: list)
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(onFailure: $0)
			        }
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		])
	}

	/// A closure names no type but `Void`, which every module can name, so the seam's `public` initializer takes it
	/// whatever access the initializer that receives it has: required, or only if available.
	@Test(arguments: [
		(forwarded: "onSelect: () -> Void", received: "@Received let onSelect: () -> Void", parameter: "onSelect: @escaping () -> Void", guardHash: "6E4AFC77A9D161A1"),
		(forwarded: "onSelect: (() -> Void)?", received: "@Received(onlyIfAvailable: true) let onSelect: (() -> Void)?", parameter: "onSelect: (() -> Void)? = nil", guardHash: "AD44EC4607D4311B"),
	])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesClosureOnPublicTier_whenInternalInitializerReceivesIt(forwarded: String, received: String, parameter: String, guardHash: String) async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: Self.passThroughFixture(forwarded: forwarded, received: received, rowInitializerIsInternal: true),
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		let argumentType = forwarded.dropFirst("onSelect: ".count).replacingOccurrences(of: "() -> Void", with: parameter.contains("@escaping") ? "@escaping () -> Void" : "() -> Void")
		#expect(output.dependencyTreeFiles == [
			"List+SafeDI.swift": generatedFileHeader + """
			extension List {
			    public init(\(parameter)) {
			        let row = Row(onSelect: onSelect)
			        self.init(row: row)
			    }
			}

			extension List {
			    public enum __safeDI_List_\(guardHash) {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_screenBuilder(onSelect: \(argumentType)) -> Screen {
			            func __safeDI_list() -> List {
			                _ = List.__safeDI_List_\(guardHash).self
			                return List(onSelect: onSelect)
			            }
			            let list: List = __safeDI_list()
			            return Screen(onSelect: onSelect, list: list)
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(onSelect: $0)
			        }
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		])
	}

	// Kept by hand: the seam corpus draws this shape in 6 graphs and accepts none (census at 3b12802a); delete when the
	// per-shape accepted pin reaches 3.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamPassingOptionalSendableClosure_whenTreeReceivesItOnlyIfAvailable() async throws {
		// An optional `@Sendable` closure is not `@escaping` either.
		let fixture = Self.passThroughFixture(forwarded: "onSelect: (@Sendable () -> Void)?", received: "@Received(onlyIfAvailable: true) let onSelect: (@Sendable () -> Void)?")
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"List+SafeDI.swift": generatedFileHeader + """
			extension List {
			    public init(onSelect: (@Sendable () -> Void)? = nil) {
			        let row = Row(onSelect: onSelect)
			        self.init(row: row)
			    }
			}

			extension List {
			    public enum __safeDI_List_7F243DDBE260C44D {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_screenBuilder(onSelect: (@Sendable () -> Void)?) -> Screen {
			            func __safeDI_list() -> List {
			                _ = List.__safeDI_List_7F243DDBE260C44D.self
			                return List(onSelect: onSelect)
			            }
			            let list: List = __safeDI_list()
			            return Screen(onSelect: onSelect, list: list)
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(onSelect: $0)
			        }
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		])
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: Self.inline(fixture), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(inlineOutput.dependencyTreeFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_screenBuilder(onSelect: (@Sendable () -> Void)?) -> Screen {
			            func __safeDI_list() -> List {
			                let row = Row(onSelect: onSelect)
			                return List(row: row)
			            }
			            let list: List = __safeDI_list()
			            return Screen(onSelect: onSelect, list: list)
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(onSelect: $0)
			        }
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		])
	}

	// MARK: Other spellings

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamPassingErasedInstantiatorOfClosure_whenTreeReceivesBuilderOfTypeThatForwardsClosure() async throws {
		let fixture = [
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(rowBuilder: ErasedInstantiator<() -> Void, AnyRow>, list: List) {
			        self.rowBuilder = rowBuilder
			        self.list = list
			    }

			    @Instantiated(fulfilledByType: "Row", erasedToConcreteExistential: true) let rowBuilder: ErasedInstantiator<() -> Void, AnyRow>
			    @Instantiated let list: List
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public struct List: Instantiable {
			    public init(panel: Panel) {
			        self.panel = panel
			    }

			    @Instantiated let panel: Panel
			}
			""",
			"""
			@Instantiable
			public struct Panel: Instantiable {
			    public init(rowBuilder: ErasedInstantiator<() -> Void, AnyRow>) {
			        self.rowBuilder = rowBuilder
			    }

			    @Received let rowBuilder: ErasedInstantiator<() -> Void, AnyRow>
			}
			""",
			"""
			@Instantiable
			public struct Row: Instantiable {
			    public init(onTap: @escaping () -> Void) {
			        self.onTap = onTap
			    }

			    @Forwarded let onTap: () -> Void
			}

			public struct AnyRow {
			    public init(_ row: Row) {}
			}
			""",
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"List+SafeDI.swift": generatedFileHeader + """
			extension List {
			    public init(rowBuilder: ErasedInstantiator<() -> Void, AnyRow>) {
			        let panel = Panel(rowBuilder: rowBuilder)
			        self.init(panel: panel)
			    }
			}

			extension List {
			    public enum __safeDI_List_64115A2EC20EBC75 {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_rowBuilder(onTap: @escaping () -> Void) -> Row {
			            Row(onTap: onTap)
			        }
			        let rowBuilder = ErasedInstantiator<() -> Void, AnyRow> {
			            AnyRow(__safeDI_rowBuilder(onTap: $0))
			        }
			        func __safeDI_list() -> List {
			            _ = List.__safeDI_List_64115A2EC20EBC75.self
			            return List(rowBuilder: rowBuilder)
			        }
			        let list: List = __safeDI_list()
			        self.init(rowBuilder: rowBuilder, list: list)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesNoParameter_whenClosureIsForwardedInsideSeamsTree() async throws {
		let fixture = [
			"""
			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(list: List) {
			        self.list = list
			    }

			    @Instantiated let list: List
			}
			""",
			"""
			@Instantiable(generateDependencyTree: true)
			public struct List: Instantiable {
			    public init(rowBuilder: Instantiator<Row>) {
			        self.rowBuilder = rowBuilder
			    }

			    @Instantiated let rowBuilder: Instantiator<Row>
			}
			""",
			"""
			@Instantiable
			public struct Row: Instantiable {
			    public init(onTap: @escaping () -> Void, analytics: Analytics) {
			        self.onTap = onTap
			        self.analytics = analytics
			    }

			    @Forwarded let onTap: () -> Void
			    @Instantiated let analytics: Analytics
			}
			""",
			Self.analyticsContent,
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles == [
			"List+SafeDI.swift": generatedFileHeader + """
			extension List {
			    public init() {
			        func __safeDI_rowBuilder(onTap: @escaping () -> Void) -> Row {
			            let analytics = Analytics()
			            return Row(onTap: onTap, analytics: analytics)
			        }
			        let rowBuilder = Instantiator<Row> {
			            __safeDI_rowBuilder(onTap: $0)
			        }
			        self.init(rowBuilder: rowBuilder)
			    }
			}

			extension List {
			    public enum __safeDI_List_CBF29CE484222325 {}
			}
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public init() {
			        func __safeDI_list() -> List {
			            _ = List.__safeDI_List_CBF29CE484222325.self
			            return List()
			        }
			        let list: List = __safeDI_list()
			        self.init(list: list)
			    }
			}
			""",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Root`, which holds an instantiator of `Screen`, a type that forwards a value.
	private static let rootHoldingScreenBuilder = """
	@Instantiable(isRoot: true)
	public struct Root: Instantiable {
	    public init(screenBuilder: Instantiator<Screen>) {
	        self.screenBuilder = screenBuilder
	    }

	    @Instantiated let screenBuilder: Instantiator<Screen>
	}
	"""

	private static let analyticsContent = """
	@Instantiable
	public struct Analytics: Instantiable {
	    public init() {}
	}
	"""

	/// A spelling of a property whose type `Core`, a module `Feature` depends on, declares: plain, closure, existential,
	/// and nested. `Feature`'s seam `List` passes it through to `Row`, and `App` forwards it to `Screen`, which
	/// instantiates `List`; each module reads the type from `Core` by name, so the signature both sides compute spells
	/// it the same, under the `.safedi` flow as under the plugin's target graph.
	enum CoreSpelling: String, CaseIterable, CustomTestStringConvertible {
		case plain
		case closure
		case existential
		case nested

		var testDescription: String {
			rawValue
		}

		/// The property's type, as `Feature` and `App` spell it after `import Core`.
		var type: String {
			switch self {
			case .plain:
				"Settings"
			case .closure:
				"(Settings) -> Void"
			case .existential:
				"any Logging"
			case .nested:
				"Catalog.Entry"
			}
		}

		/// What `Core` declares.
		var coreDeclaration: String {
			switch self {
			case .plain, .closure:
				"public struct Settings: Sendable {\n    public init() {}\n}"
			case .existential:
				"public protocol Logging: Sendable {}"
			case .nested:
				"public enum Catalog {\n    public struct Entry: Sendable {\n        public init() {}\n    }\n}"
			}
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases, CoreSpelling.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsSeamOfAnotherModulePassingTypeOfThirdModule_whenTreeRequiresPropertyWhoseTypeCoreDeclares(integration: MultiModuleIntegration, spelling: CoreSpelling) async throws {
		// A pass-through whose type comes from a third module, `Core`, which neither the seam's module nor its caller
		// declares: both compute the parameter's type from the declaration they read and spell it alike, so the guard
		// hashes match and the call compiles, under both integrations and for each spelling. A `.safedi` records no
		// `public` declaration of `Core`'s, so under `.moduleInfo` the type is one SafeDI reads no declaration of, which the
		// comment names.
		let type = spelling.type
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [spelling.coreDeclaration]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.seamFiles(received: "@Received let value: \(type)", secondChild: nil, rowInitializerIsInternal: false).map { "import Core\n\n" + $0 }, dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: ["import Core\nimport Feature\n\n" + Self.rootHoldingScreenBuilder, "import Core\nimport Feature\n\n" + Self.screen(forwarding: "value: \(type)")], dependencies: ["Core", "Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let expectedFeatureFiles: [MultiModuleIntegration: [CoreSpelling: [String: String]]] = [
			.moduleInfo: [
				.plain: [
					"Feature.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif

					extension List {
					    // SafeDI counts `Settings` as `public`: no module it reads declares it narrower. If `Settings` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
					    public init(value: Settings) {
					        let row = Row(value: value)
					        self.init(row: row)
					    }
					}

					extension List {
					    public enum __safeDI_List_799D68846C7AF168 {}
					}
					""",
				],
				.closure: [
					"Feature.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif

					extension List {
					    // SafeDI counts `Settings` as `public`: no module it reads declares it narrower. If `Settings` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
					    public init(value: @escaping (Settings) -> Void) {
					        let row = Row(value: value)
					        self.init(row: row)
					    }
					}

					extension List {
					    public enum __safeDI_List_CA5CD86521ED15DA {}
					}
					""",
				],
				.existential: [
					"Feature.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif

					extension List {
					    // SafeDI counts `Logging` as `public`: no module it reads declares it narrower. If `Logging` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
					    public init(value: any Logging) {
					        let row = Row(value: value)
					        self.init(row: row)
					    }
					}

					extension List {
					    public enum __safeDI_List_86EFB7C4B110B9DE {}
					}
					""",
				],
				.nested: [
					"Feature.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif

					extension List {
					    // SafeDI counts `Catalog.Entry` as `public`: no module it reads declares it narrower. If `Catalog.Entry` is `package` in a first-party module, run SafeDI on that module and list it among this module's SafeDI dependencies.
					    public init(value: Catalog.Entry) {
					        let row = Row(value: value)
					        self.init(row: row)
					    }
					}

					extension List {
					    public enum __safeDI_List_9FC0BE131CCF7636 {}
					}
					""",
				],
			],
			.swiftPackagePlugin: [
				.plain: [
					"List+SafeDI.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif

					extension List {
					    public init(value: Settings) {
					        let row = Row(value: value)
					        self.init(row: row)
					    }
					}

					extension List {
					    public enum __safeDI_List_799D68846C7AF168 {}
					}
					""",
				],
				.closure: [
					"List+SafeDI.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif

					extension List {
					    public init(value: @escaping (Settings) -> Void) {
					        let row = Row(value: value)
					        self.init(row: row)
					    }
					}

					extension List {
					    public enum __safeDI_List_CA5CD86521ED15DA {}
					}
					""",
				],
				.existential: [
					"List+SafeDI.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif

					extension List {
					    public init(value: any Logging) {
					        let row = Row(value: value)
					        self.init(row: row)
					    }
					}

					extension List {
					    public enum __safeDI_List_86EFB7C4B110B9DE {}
					}
					""",
				],
				.nested: [
					"List+SafeDI.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif

					extension List {
					    public init(value: Catalog.Entry) {
					        let row = Row(value: value)
					        self.init(row: row)
					    }
					}

					extension List {
					    public enum __safeDI_List_9FC0BE131CCF7636 {}
					}
					""",
				],
			],
		]
		#expect(try #require(output.modules["Feature"]).generatedFiles == expectedFeatureFiles[integration]?[spelling])
		let expectedAppFiles: [MultiModuleIntegration: [CoreSpelling: [String: String]]] = [
			.moduleInfo: [
				.plain: [
					"App.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: Settings) -> Screen {
					            func __safeDI_list() -> List {
					                _ = List.__safeDI_List_799D68846C7AF168.self
					                return List(value: value)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
				.closure: [
					"App.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: @escaping (Settings) -> Void) -> Screen {
					            func __safeDI_list() -> List {
					                _ = List.__safeDI_List_CA5CD86521ED15DA.self
					                return List(value: value)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
				.existential: [
					"App.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: any Logging) -> Screen {
					            func __safeDI_list() -> List {
					                _ = List.__safeDI_List_86EFB7C4B110B9DE.self
					                return List(value: value)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
				.nested: [
					"App.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: Catalog.Entry) -> Screen {
					            func __safeDI_list() -> List {
					                _ = List.__safeDI_List_9FC0BE131CCF7636.self
					                return List(value: value)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
			],
			.swiftPackagePlugin: [
				.plain: [
					"Root+SafeDI.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: Settings) -> Screen {
					            func __safeDI_list() -> List {
					                _ = List.__safeDI_List_799D68846C7AF168.self // If this line does not compile, add the SafeDI plugin to the target that declares List.
					                return List(value: value)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
				.closure: [
					"Root+SafeDI.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: @escaping (Settings) -> Void) -> Screen {
					            func __safeDI_list() -> List {
					                _ = List.__safeDI_List_CA5CD86521ED15DA.self // If this line does not compile, add the SafeDI plugin to the target that declares List.
					                return List(value: value)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
				.existential: [
					"Root+SafeDI.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: any Logging) -> Screen {
					            func __safeDI_list() -> List {
					                _ = List.__safeDI_List_86EFB7C4B110B9DE.self // If this line does not compile, add the SafeDI plugin to the target that declares List.
					                return List(value: value)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
				.nested: [
					"Root+SafeDI.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: Catalog.Entry) -> Screen {
					            func __safeDI_list() -> List {
					                _ = List.__safeDI_List_9FC0BE131CCF7636.self // If this line does not compile, add the SafeDI plugin to the target that declares List.
					                return List(value: value)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
			],
		]
		#expect(try #require(output.modules["App"]).generatedFiles == expectedAppFiles[integration]?[spelling])
		if compileVerificationIsEnabled {
			#expect(try #require(output.compilation).modules.map(\.exitCode) == [0, 0, 0])
		}
		// The inline twin: `App` builds `List`'s tree itself, passing the value `Screen` forwards straight to `Row`.
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [spelling.coreDeclaration]),
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: Self.inline(Self.seamFiles(received: "@Received let value: \(type)", secondChild: nil, rowInitializerIsInternal: false)).map { "import Core\n\n" + $0 }, dependencies: ["Core"]),
				ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: ["import Core\nimport Feature\n\n" + Self.rootHoldingScreenBuilder, "import Core\nimport Feature\n\n" + Self.screen(forwarding: "value: \(type)")], dependencies: ["Core", "Feature"]),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)
		let expectedInlineFeatureFiles: [MultiModuleIntegration: [CoreSpelling: [String: String]]] = [
			.moduleInfo: [
				.plain: [
					"Feature.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif


					""",
				],
				.closure: [
					"Feature.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif


					""",
				],
				.existential: [
					"Feature.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif


					""",
				],
				.nested: [
					"Feature.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif


					""",
				],
			],
			.swiftPackagePlugin: [
				.plain: [:],
				.closure: [:],
				.existential: [:],
				.nested: [:],
			],
		]
		#expect(try #require(inlineOutput.modules["Feature"]).generatedFiles == expectedInlineFeatureFiles[integration]?[spelling])
		let expectedInlineAppFiles: [MultiModuleIntegration: [CoreSpelling: [String: String]]] = [
			.moduleInfo: [
				.plain: [
					"App.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: Settings) -> Screen {
					            func __safeDI_list() -> List {
					                let row = Row(value: value)
					                return List(row: row)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
				.closure: [
					"App.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: @escaping (Settings) -> Void) -> Screen {
					            func __safeDI_list() -> List {
					                let row = Row(value: value)
					                return List(row: row)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
				.existential: [
					"App.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: any Logging) -> Screen {
					            func __safeDI_list() -> List {
					                let row = Row(value: value)
					                return List(row: row)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
				.nested: [
					"App.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: Catalog.Entry) -> Screen {
					            func __safeDI_list() -> List {
					                let row = Row(value: value)
					                return List(row: row)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
			],
			.swiftPackagePlugin: [
				.plain: [
					"Root+SafeDI.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: Settings) -> Screen {
					            func __safeDI_list() -> List {
					                let row = Row(value: value)
					                return List(row: row)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
				.closure: [
					"Root+SafeDI.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: @escaping (Settings) -> Void) -> Screen {
					            func __safeDI_list() -> List {
					                let row = Row(value: value)
					                return List(row: row)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
				.existential: [
					"Root+SafeDI.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: any Logging) -> Screen {
					            func __safeDI_list() -> List {
					                let row = Row(value: value)
					                return List(row: row)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
				.nested: [
					"Root+SafeDI.swift": generatedFileHeader + """
					#if canImport(Core)
					import Core
					#endif
					#if canImport(Feature)
					import Feature
					#endif

					extension Root {
					    public init() {
					        func __safeDI_screenBuilder(value: Catalog.Entry) -> Screen {
					            func __safeDI_list() -> List {
					                let row = Row(value: value)
					                return List(row: row)
					            }
					            let list: List = __safeDI_list()
					            return Screen(value: value, list: list)
					        }
					        let screenBuilder = Instantiator<Screen> {
					            __safeDI_screenBuilder(value: $0)
					        }
					        self.init(screenBuilder: screenBuilder)
					    }
					}
					""",
				],
			],
		]
		#expect(try #require(inlineOutput.modules["App"]).generatedFiles == expectedInlineAppFiles[integration]?[spelling])
		if compileVerificationIsEnabled {
			#expect(try #require(inlineOutput.compilation).modules.map(\.exitCode) == [0, 0, 0])
		}
	}

	/// `Root` holds an instantiator of `Screen`, which forwards `forwarded` and instantiates the seam `List`, which
	/// instantiates `Row`, which declares `received`, and, when `secondChild` is given, `Footer`, which declares it.
	private static func passThroughFixture(forwarded: String, received: String, secondChild: String? = nil, rowInitializerIsInternal: Bool = false) -> [String] {
		[rootHoldingScreenBuilder, screen(forwarding: forwarded)] + seamFiles(received: received, secondChild: secondChild, rowInitializerIsInternal: rowInitializerIsInternal)
	}

	private static func screen(forwarding forwarded: String) -> String {
		let label = String(forwarded.prefix { $0 != ":" })
		let type = forwarded.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
		let parameterType = isFunctionType(type) ? "@escaping \(type)" : type
		return """
		@Instantiable
		public struct Screen: Instantiable {
		    public init(\(label): \(parameterType), list: List) {
		        self.\(label) = \(label)
		        self.list = list
		    }

		    @Forwarded let \(label): \(type)
		    @Instantiated let list: List
		}
		"""
	}

	private static func seamFiles(received: String, secondChild: String?, rowInitializerIsInternal: Bool) -> [String] {
		var files = [
			"""
			@Instantiable(generateDependencyTree: true)
			public struct List: Instantiable {
			    public init(row: Row\(secondChild == nil ? "" : ", footer: Footer")) {
			        self.row = row\(secondChild == nil ? "" : "\n        self.footer = footer")
			    }

			    @Instantiated let row: Row\(secondChild == nil ? "" : "\n    @Instantiated let footer: Footer")
			}
			""",
			type(named: "Row", declaring: received, initializerIsInternal: rowInitializerIsInternal),
		]
		if let secondChild {
			files.append(type(named: "Footer", declaring: secondChild, initializerIsInternal: false))
		}
		return files
	}

	/// A public type named `name` that declares the one property `declaration` and an initializer taking it.
	private static func type(named name: String, declaring declaration: String, initializerIsInternal: Bool) -> String {
		let letRange = declaration.range(of: " let ")!
		let property = declaration[letRange.upperBound...]
		let label = String(property.prefix { $0 != ":" })
		let type = property.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
		let parameterType = isFunctionType(type) ? "@escaping \(type)" : type
		return """
		@Instantiable
		public struct \(name): Instantiable {
		    \(initializerIsInternal ? "" : "public ")init(\(label): \(parameterType)) {
		        self.\(label) = \(label)
		    }

		    \(declaration)
		}
		"""
	}

	/// Whether `type` is a function type: after its attributes, a parenthesized parameter list followed by ` -> `.
	private static func isFunctionType(_ type: String) -> Bool {
		GraphFuzzerSpelling.isFunctionType(type)
	}

	/// `files` with no type declared as a seam, so every tree is built inline.
	private static func inline(_ files: [String]) -> [String] {
		files.map { $0.replacingOccurrences(of: "@Instantiable(generateDependencyTree: true)", with: "@Instantiable") }
	}
}
