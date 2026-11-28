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

/// A calling mock takes one builder for each filling type, returned type and family over its whole tree, labeled as a
/// seam labels it: `<filling type>Builder`, or `<filling type>_<returned type>Builder` where the two differ, never after
/// the type whose public mock it calls, with a trailing `_` only where another parameter of its `mock()` has the label.
/// Places of one builder that forward different values are an error, reported for the calling mock as for its twin.
struct SafeDIToolCallingMockBuilderLabelTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – one builder for every place of one kind

	@Test(arguments: CallingMockCaller.allCases, CalledTypeDeclaration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_handsOneBuilderToEveryCalledType_whenTwoCalledTypesPassUpPlacesOfOneKind(caller: CallingMockCaller, calledTypes: CalledTypeDeclaration) async throws {
		// `Panel` and `Deck` each pass up an `any Service` place. The calling mock takes one `serviceBuilder`, as its twin
		// does, and hands it to both calls: each place gets its own `CountedService` from a call of the one builder, as the
		// twin’s do.
		let result = try await GraphFuzzerCallingMockCheck.run(GraphFuzzerCallingMockGraph(
			name: "two called types passing up places of one kind",
			mockFiles: Self.files(of: Self.mergeModules(caller: caller.attribute, callee: calledTypes.attribute)),
			twinFiles: Self.files(of: Self.mergeModules(caller: Self.twinCaller, callee: Self.twinCalledTypes)),
			callerTypeName: "Screen",
			callerIsPublic: caller == .public,
			flatParameterLabels: [],
			implementationIsVisible: false,
			expectedTwinInitializerLabels: nil,
			expectedPassUpLabels: ["serviceBuilder"],
			expectedTwinErrorSite: nil,
			valueProbes: [DifferentialValueProbe(
				name: "Screen",
				expression: "App.Screen.mock(serviceBuilder: { App.CountedService() })",
				knownRightExpression: "App.Screen(serviceBuilder: { App.CountedService() })",
			)],
		), seed: 0)

		#expect(result.twinHasIntendedOutcome, "\(result.drawingDefect ?? "")")
		#expect(result.passUps.map(\.label) == ["serviceBuilder"])
		#expect(result.failure == nil, "\(result.failure?.details ?? "")")
		#expect(result.comparedValues == compileVerificationIsEnabled)
	}

	@Test(arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_appendsUnderscoreToBuildersLabel_whenCallingMockTakesValueUnderTheBuildersLabel(caller: CallingMockCaller) async throws {
		// `Screen` receives `serviceBuilder`, a value nothing in its tree builds, so `mock()` takes it under its own label,
		// and the builder for `Panel`’s place takes the trailing `_`, as the twin’s initializer names them. An internal mock
		// lists its builders among its received parameters by label, and a public one lists its builders after them, so both
		// take the value first.
		let mock = try await executeSafeDIToolMultiModuleTest(modules: Self.clashModules(caller: caller.attribute, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let twin = try await executeSafeDIToolMultiModuleTest(modules: Self.clashModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)

		#expect(GraphFuzzerCallingMockCheck.mockParameterLabels(ofType: "Screen", inGeneratedFile: mock.modules["App"]?.generatedFiles["App.swift"] ?? "") == ["serviceBuilder", "serviceBuilder_", "safeDIOverrides"])
		#expect(Self.generatedOnlyInitializerLabels(ofType: "Screen", inGeneratedFile: twin.modules["App"]?.generatedFiles["App.swift"] ?? "") == ["serviceBuilder", "serviceBuilder_"])
	}

	@Test(arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_labelsBuilderByItsTypeAlone_whenCallingMocksTreeInstantiatesPropertyUnderTheBuildersLabel(caller: CallingMockCaller) async throws {
		// `Screen` instantiates `serviceBuilder`, a property of its tree and no parameter of `mock()`, so the builder for
		// `Panel`’s place keeps its label, as the twin’s initializer names it.
		let mock = try await executeSafeDIToolMultiModuleTest(modules: Self.treePropertyUnderBuilderLabelModules(caller: caller.attribute, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let twin = try await executeSafeDIToolMultiModuleTest(modules: Self.treePropertyUnderBuilderLabelModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)

		#expect(GraphFuzzerCallingMockCheck.mockParameterLabels(ofType: "Screen", inGeneratedFile: mock.modules["App"]?.generatedFiles["App.swift"] ?? "") == ["serviceBuilder", "safeDIOverrides"])
		#expect(Self.generatedOnlyInitializerLabels(ofType: "Screen", inGeneratedFile: twin.modules["App"]?.generatedFiles["App.swift"] ?? "") == ["serviceBuilder"])
	}

	@Test(arguments: CallingMockCaller.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesOneBuilderPerFamily_whenOneCalledTypesPlaceIsBuiltInSendableFunction(caller: CallingMockCaller) async throws {
		// `Panel`’s `any Service` place is plain, and `Deck`’s is built inside a `SendableInstantiator`’s function: two
		// families, so two builders, as the twin’s initializer takes them.
		let mock = try await executeSafeDIToolMultiModuleTest(modules: Self.familyModules(caller: caller.attribute, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		let twin = try await executeSafeDIToolMultiModuleTest(modules: Self.familyModules(caller: Self.twinCaller, callee: Self.twinCalledTypes), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)

		#expect(GraphFuzzerCallingMockCheck.mockParameterLabels(ofType: "Screen", inGeneratedFile: mock.modules["App"]?.generatedFiles["App.swift"] ?? "") == ["serviceBuilder", "serviceSendableBuilder", "safeDIOverrides"])
		#expect(Self.generatedOnlyInitializerLabels(ofType: "Screen", inGeneratedFile: twin.modules["App"]?.generatedFiles["App.swift"] ?? "") == ["serviceBuilder", "serviceSendableBuilder"])
	}

	// MARK: Tests – places of one builder that forward different values

	@Test(arguments: CallingMockCaller.allCases, MergedPlaceOrder.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsError_whenCallingMocksMergedPlacesForwardDifferentValues(caller: CallingMockCaller, order: MergedPlaceOrder) async {
		// `Panel`, `Deck` and `Card` each pass up a place `LiveService` fills, forwarding `Int`, `String` and `Bool`. The
		// place reached through `Screen`’s first-declared property is the one the others are compared with, and each other
		// is reported at the property through which `Screen` reaches it, in every order of the three.
		let diagnostics = { (fixtures: [String: FixturePaths]) in
			switch order {
			case .panelDeckCard:
				"""
				\(fixtures["App"]!["Screen.swift"]):8:5: error: `serviceBuilder: ErasedInstantiator<String, any Service>` on `Deck` forwards `String`, and `serviceBuilder: ErasedInstantiator<Int, any Service>` on `Panel` forwards `Int`. `Screen` takes one builder for both, since `LiveService` fills each and each returns `any Service`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				\(fixtures["App"]!["Screen.swift"]):9:5: error: `serviceBuilder: ErasedInstantiator<Bool, any Service>` on `Card` forwards `Bool`, and `serviceBuilder: ErasedInstantiator<Int, any Service>` on `Panel` forwards `Int`. `Screen` takes one builder for both, since `LiveService` fills each and each returns `any Service`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				"""
			case .panelCardDeck:
				"""
				\(fixtures["App"]!["Screen.swift"]):8:5: error: `serviceBuilder: ErasedInstantiator<Bool, any Service>` on `Card` forwards `Bool`, and `serviceBuilder: ErasedInstantiator<Int, any Service>` on `Panel` forwards `Int`. `Screen` takes one builder for both, since `LiveService` fills each and each returns `any Service`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				\(fixtures["App"]!["Screen.swift"]):9:5: error: `serviceBuilder: ErasedInstantiator<String, any Service>` on `Deck` forwards `String`, and `serviceBuilder: ErasedInstantiator<Int, any Service>` on `Panel` forwards `Int`. `Screen` takes one builder for both, since `LiveService` fills each and each returns `any Service`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				"""
			case .deckPanelCard:
				"""
				\(fixtures["App"]!["Screen.swift"]):8:5: error: `serviceBuilder: ErasedInstantiator<Int, any Service>` on `Panel` forwards `Int`, and `serviceBuilder: ErasedInstantiator<String, any Service>` on `Deck` forwards `String`. `Screen` takes one builder for both, since `LiveService` fills each and each returns `any Service`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				\(fixtures["App"]!["Screen.swift"]):9:5: error: `serviceBuilder: ErasedInstantiator<Bool, any Service>` on `Card` forwards `Bool`, and `serviceBuilder: ErasedInstantiator<String, any Service>` on `Deck` forwards `String`. `Screen` takes one builder for both, since `LiveService` fills each and each returns `any Service`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				"""
			case .deckCardPanel:
				"""
				\(fixtures["App"]!["Screen.swift"]):8:5: error: `serviceBuilder: ErasedInstantiator<Bool, any Service>` on `Card` forwards `Bool`, and `serviceBuilder: ErasedInstantiator<String, any Service>` on `Deck` forwards `String`. `Screen` takes one builder for both, since `LiveService` fills each and each returns `any Service`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				\(fixtures["App"]!["Screen.swift"]):9:5: error: `serviceBuilder: ErasedInstantiator<Int, any Service>` on `Panel` forwards `Int`, and `serviceBuilder: ErasedInstantiator<String, any Service>` on `Deck` forwards `String`. `Screen` takes one builder for both, since `LiveService` fills each and each returns `any Service`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				"""
			case .cardPanelDeck:
				"""
				\(fixtures["App"]!["Screen.swift"]):8:5: error: `serviceBuilder: ErasedInstantiator<Int, any Service>` on `Panel` forwards `Int`, and `serviceBuilder: ErasedInstantiator<Bool, any Service>` on `Card` forwards `Bool`. `Screen` takes one builder for both, since `LiveService` fills each and each returns `any Service`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				\(fixtures["App"]!["Screen.swift"]):9:5: error: `serviceBuilder: ErasedInstantiator<String, any Service>` on `Deck` forwards `String`, and `serviceBuilder: ErasedInstantiator<Bool, any Service>` on `Card` forwards `Bool`. `Screen` takes one builder for both, since `LiveService` fills each and each returns `any Service`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				"""
			case .cardDeckPanel:
				"""
				\(fixtures["App"]!["Screen.swift"]):8:5: error: `serviceBuilder: ErasedInstantiator<String, any Service>` on `Deck` forwards `String`, and `serviceBuilder: ErasedInstantiator<Bool, any Service>` on `Card` forwards `Bool`. `Screen` takes one builder for both, since `LiveService` fills each and each returns `any Service`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				\(fixtures["App"]!["Screen.swift"]):9:5: error: `serviceBuilder: ErasedInstantiator<Int, any Service>` on `Panel` forwards `Int`, and `serviceBuilder: ErasedInstantiator<Bool, any Service>` on `Card` forwards `Bool`. `Screen` takes one builder for both, since `LiveService` fills each and each returns `any Service`, and a builder’s places must forward the same values. Give both the same first generic argument, or name another type in the `fulfilledByType` of one.
				"""
			}
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.mismatchModules(caller: caller.attribute, callee: Self.twinCalledTypes, order: order), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: diagnostics) {
			try await executeSafeDIToolMultiModuleTest(modules: Self.mismatchModules(caller: Self.twinCaller, callee: Self.twinCalledTypes, order: order), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The caller’s attribute line in its production twin.
	private static let twinCaller = "@Instantiable(generateDependencyTree: true)"
	/// A called type’s attribute line in the production twin: a seam as well as a public mock.
	private static let twinCalledTypes = CalledTypeDeclaration.seamAndPublicMock.attribute

	/// The order in which `Screen` declares the properties that reach `Panel`, `Deck` and `Card`.
	enum MergedPlaceOrder: CaseIterable, CustomTestStringConvertible {
		case panelDeckCard
		case panelCardDeck
		case deckPanelCard
		case deckCardPanel
		case cardPanelDeck
		case cardDeckPanel

		var calledTypes: [String] {
			switch self {
			case .panelDeckCard: ["Panel", "Deck", "Card"]
			case .panelCardDeck: ["Panel", "Card", "Deck"]
			case .deckPanelCard: ["Deck", "Panel", "Card"]
			case .deckCardPanel: ["Deck", "Card", "Panel"]
			case .cardPanelDeck: ["Card", "Panel", "Deck"]
			case .cardDeckPanel: ["Card", "Deck", "Panel"]
			}
		}

		var testDescription: String {
			calledTypes.joined(separator: ", ")
		}
	}

	/// The labels of the initializer only generated code calls that `generatedFile` declares directly in an extension of
	/// `typeName` (a twin seam’s, at four spaces), without their `__safeDI_` prefix, in order.
	private static func generatedOnlyInitializerLabels(ofType typeName: String, inGeneratedFile generatedFile: String) -> [String] {
		var isInExtension = false
		for line in generatedFile.split(separator: "\n", omittingEmptySubsequences: false) {
			if line.hasPrefix("extension ") {
				isInExtension = line == "extension \(typeName) {"
			} else if isInExtension, line.hasPrefix("    public init(__safeDI_") || line.hasPrefix("    init(__safeDI_") || line.hasPrefix("    public convenience init(__safeDI_") {
				let parameters = line.drop { $0 != "(" }.dropFirst().split(separator: ", ")
				return parameters.map { parameter in
					String(parameter.prefix { $0 != " " && $0 != ":" }.dropFirst("__safeDI_".count))
				}
			}
		}
		return []
	}

	private static func files(of modules: [ModuleFixture]) -> [GraphFuzzerCallingMockGraph.File] {
		modules.map { module in
			GraphFuzzerCallingMockGraph.File(module: module.name, dependencies: module.dependencies, content: module.swiftFileContentByFilePath["\(module.name)Types.swift"] ?? "")
		}
	}

	// MARK: Fixtures

	/// `Panel`, `Deck` and `Card`, each with a place `LiveService` fills, forwarding `Int`, `String` and `Bool`; no module
	/// declares `LiveService`. `Screen` reaches the three in `order`, its properties on lines 7, 8 and 9 of `Screen.swift`.
	private static func mismatchModules(caller: String, callee: String, order: MergedPlaceOrder) -> [ModuleFixture] {
		let calledTypes = order.calledTypes
		let parameters = calledTypes.map { "\($0.lowercased()): \($0)" }.joined(separator: ", ")
		let assignments = calledTypes.map { "self.\($0.lowercased()) = \($0.lowercased())" }.joined(separator: "; ")
		let properties = calledTypes.map { "    @Instantiated public let \($0.lowercased()): \($0)" }.joined(separator: "\n")
		return [
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContentByFilePath: [
				"Service.swift": """
				public protocol Service: Sendable {}
				""",
				"Panel.swift": """
				import SafeDI

				\(callee)
				public struct Panel: Instantiable, Sendable {
				    init(serviceBuilder: ErasedInstantiator<Int, any Service>) { self.serviceBuilder = serviceBuilder }
				    @Instantiated(fulfilledByType: "LiveService") public let serviceBuilder: ErasedInstantiator<Int, any Service>
				}
				""",
				"Deck.swift": """
				import SafeDI

				\(callee)
				public struct Deck: Instantiable, Sendable {
				    init(serviceBuilder: ErasedInstantiator<String, any Service>) { self.serviceBuilder = serviceBuilder }
				    @Instantiated(fulfilledByType: "LiveService") public let serviceBuilder: ErasedInstantiator<String, any Service>
				}
				""",
				"Card.swift": """
				import SafeDI

				\(callee)
				public struct Card: Instantiable, Sendable {
				    init(serviceBuilder: ErasedInstantiator<Bool, any Service>) { self.serviceBuilder = serviceBuilder }
				    @Instantiated(fulfilledByType: "LiveService") public let serviceBuilder: ErasedInstantiator<Bool, any Service>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"Screen.swift": """
				import SafeDI
				import Core

				\(caller)
				public struct Screen: Instantiable {
				    public init(\(parameters)) { \(assignments) }
				\(properties)
				}
				""",
			], dependencies: ["Core"]),
		]
	}

	/// `Panel` and `Deck`, two called types with one hole type, `any Service`, that no SafeDI declaration fulfills; `CountedService` conforms to it for the probe.
	private static func mergeModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContentByFilePath: [
				"CoreTypes.swift": """
				import SafeDI

				public protocol Service: Sendable {}

				\(callee)
				public struct Panel: Instantiable, Sendable {
				    init(service: any Service) { self.service = service }
				    @Instantiated public let service: any Service
				}

				\(callee)
				public struct Deck: Instantiable, Sendable {
				    init(service: any Service) { self.service = service }
				    @Instantiated public let service: any Service
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"AppTypes.swift": """
				import SafeDI
				import Core

				public final class CountedService: Service {
				    public init() {}
				}

				\(caller)
				public struct Screen: Instantiable {
				    public init(panel: Panel, deck: Deck) { self.panel = panel; self.deck = deck }
				    @Instantiated public let panel: Panel
				    @Instantiated public let deck: Deck
				}
				""",
			], dependencies: ["Core"]),
		]
	}

	/// `Screen` receives `serviceBuilder`, a value nothing builds, beside `Panel`, whose `any Service` place it passes up.
	private static func clashModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContentByFilePath: [
				"Service.swift": """
				public protocol Service: Sendable {}
				""",
				"Panel.swift": """
				import SafeDI

				\(callee)
				public struct Panel: Instantiable, Sendable {
				    init(service: any Service) { self.service = service }
				    @Instantiated public let service: any Service
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"Screen.swift": """
				import SafeDI
				import Core

				public struct Thing: Sendable {
				    public init() {}
				}

				\(caller)
				public struct Screen: Instantiable {
				    public init(serviceBuilder: Thing, panel: Panel) { self.serviceBuilder = serviceBuilder; self.panel = panel }
				    @Received public let serviceBuilder: Thing
				    @Instantiated public let panel: Panel
				}
				""",
			], dependencies: ["Core"]),
		]
	}

	/// `Screen` instantiates `serviceBuilder`, a property of its tree, beside `Panel`, whose `any Service` place it passes up.
	private static func treePropertyUnderBuilderLabelModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContentByFilePath: [
				"Service.swift": """
				public protocol Service: Sendable {}
				""",
				"Panel.swift": """
				import SafeDI

				\(callee)
				public struct Panel: Instantiable, Sendable {
				    init(service: any Service) { self.service = service }
				    @Instantiated public let service: any Service
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"Screen.swift": """
				import SafeDI
				import Core

				@Instantiable
				public struct Thing: Instantiable, Sendable {
				    public init() {}
				}

				\(caller)
				public struct Screen: Instantiable {
				    public init(serviceBuilder: Thing, panel: Panel) { self.serviceBuilder = serviceBuilder; self.panel = panel }
				    @Instantiated public let serviceBuilder: Thing
				    @Instantiated public let panel: Panel
				}
				""",
			], dependencies: ["Core"]),
		]
	}

	/// `Panel`’s `any Service` place is plain, and `Deck`’s is built inside a `SendableInstantiator`’s function.
	private static func familyModules(caller: String, callee: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Core", packageName: "Core", swiftFileContentByFilePath: [
				"Service.swift": """
				public protocol Service: Sendable {}
				""",
				"Panel.swift": """
				import SafeDI

				\(callee)
				public struct Panel: Instantiable, Sendable {
				    init(service: any Service) { self.service = service }
				    @Instantiated public let service: any Service
				}
				""",
				"Deck.swift": """
				import SafeDI

				@Instantiable
				public struct Row: Instantiable, Sendable {
				    public init(service: any Service) { self.service = service }
				    @Instantiated public let service: any Service
				}

				\(callee)
				public struct Deck: Instantiable, Sendable {
				    init(rowBuilder: SendableInstantiator<Row>) { self.rowBuilder = rowBuilder }
				    @Instantiated public let rowBuilder: SendableInstantiator<Row>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: [
				"Screen.swift": """
				import SafeDI
				import Core

				public final class CountedService: Service {
				    public init() {}
				}

				\(caller)
				public struct Screen: Instantiable {
				    public init(panel: Panel, deck: Deck) { self.panel = panel; self.deck = deck }
				    @Instantiated public let panel: Panel
				    @Instantiated public let deck: Deck
				}
				""",
			], dependencies: ["Core"]),
		]
	}
}
