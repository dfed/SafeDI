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

/// What a test sees of the entry `<label>IsUnavailable: Bool = false`, which binds a dependency instantiated only if
/// available, that a declaration fulfills, to `nil`: at every position the Manual promises it, each test builds the
/// mock, passes `true`, and compares the values the mock builds with what production builds where nothing fulfills
/// the dependency. Each comparison runs the generated code: across modules against the same types built in one
/// module, and in one module against the value production holds.
///
/// A test marked with a known issue names the change that closes it. "Row 5" is the mock writer's rewrite of the
/// contract between a calling and a called mock, which writes the entry once, at every position, and takes these
/// tests as its acceptance.
struct SafeDIToolMockUnavailableEntryAcceptanceTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – A called public mock is handed nil

	/// How the called type receives the dependency its caller instantiates only if available.
	enum CalledTypeReceive: String, CaseIterable, CustomTestStringConvertible {
		/// `@Received let p: (any P)?`, which production passes the caller's optional.
		case requiredOptional
		/// `@Received(onlyIfAvailable: true) let p: (any P)?`.
		case onlyIfAvailable
		/// `@Received(fulfilledByDependencyNamed: "p", ofType: (any P)?.self) let renamed: (any P)?`.
		case requiredRename
		/// `@Received let p: (any P)?` on a type the caller holds in an `Instantiator`.
		case requiredOptionalThroughInstantiator

		var testDescription: String {
			rawValue
		}

		var receive: String {
			switch self {
			case .requiredOptional, .requiredOptionalThroughInstantiator:
				"@Received public let p: (any P)?"
			case .onlyIfAvailable:
				"@Received(onlyIfAvailable: true) public let p: (any P)?"
			case .requiredRename:
				"@Received(fulfilledByDependencyNamed: \"p\", ofType: (any P)?.self) public let renamed: (any P)?"
			}
		}

		var label: String {
			switch self {
			case .requiredOptional, .onlyIfAvailable, .requiredOptionalThroughInstantiator:
				"p"
			case .requiredRename:
				"renamed"
			}
		}

		var callerProperty: String {
			switch self {
			case .requiredOptional, .onlyIfAvailable, .requiredRename:
				"@Instantiated let closed: Closed"
			case .requiredOptionalThroughInstantiator:
				"@Instantiated let closed: Instantiator<Closed>"
			}
		}

		var callerPropertyType: String {
			switch self {
			case .requiredOptional, .onlyIfAvailable, .requiredRename:
				"Closed"
			case .requiredOptionalThroughInstantiator:
				"Instantiator<Closed>"
			}
		}

		/// Whether the calling mock hands the called mock `nil`, which the called mock reads as "build it", where
		/// production hands the called type `nil`: every required receive. Row 5 closes it.
		var isKnownIssue: Bool {
			switch self {
			case .requiredOptional, .requiredRename, .requiredOptionalThroughInstantiator:
				true
			case .onlyIfAvailable:
				false
			}
		}
	}

	@Test(arguments: CalledTypeReceive.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsCalledPublicMockNil_whenEntryBindsDependencyItReceivesToNil(receive: CalledTypeReceive) async throws {
		// `Screen` instantiates `p` only if available, which `Impl` fulfills, and instantiates `Closed`, another
		// module's type whose internal initializer only its public mock calls, which receives `p`. With the entry
		// `true`, production’s value is `nil` in `Screen` and in `Closed` alike.
		let modules = [
			ModuleFixture(name: "Core", packageName: "core", swiftFileContentByFilePath: ["Core.swift": """
			import SafeDI

			public protocol P {}

			@Instantiable(fulfillingAdditionalTypes: [P.self])
			public final class Impl: P, Instantiable {
			    public init() {}
			}

			@Instantiable
			final class Hidden: Instantiable {
			    init() {}
			}

			@Instantiable(generateMock: .public)
			public final class Closed: Instantiable {
			    init(\(receive.label): (any P)?, hidden: Hidden) {
			        self.\(receive.label) = \(receive.label)
			        self.hidden = hidden
			    }

			    \(receive.receive)
			    @Instantiated let hidden: Hidden
			}

			"""]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
			import Core
			import SafeDI

			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(p: (any P)?, closed: \(receive.callerPropertyType)) {
			        self.p = p
			        self.closed = closed
			    }

			    @Instantiated(onlyIfAvailable: true) let p: (any P)?
			    \(receive.callerProperty)
			}

			"""], dependencies: ["Core"]),
		]
		try await withKnownIssue("Row 5: a called public mock reads nil as “build it”", isIntermittent: false) {
			let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
			try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
				DifferentialValueProbe("Screen.mock(safeDIOverrides: .init(pIsUnavailable: true))"),
			])
		} when: {
			receive.isKnownIssue
		}
	}

	// MARK: Tests – A dependency a called public mock builds

	/// Where the type that instantiates the dependency only if available, which another module's public mock builds,
	/// is built.
	enum CallerPosition: String, CaseIterable, CustomTestStringConvertible {
		/// `Screen` is the mocked type.
		case internalRoot
		/// `Screen` is a type in `Home`'s tree.
		case nested
		/// `Screen` is the mocked type, and its mock is public.
		case publicRoot
		/// `Screen` is built by `Home`'s `SendableInstantiator`, in a `@Sendable` builder function.
		case insideSendableFunction

		var testDescription: String {
			rawValue
		}

		var screenMock: String {
			switch self {
			case .internalRoot, .insideSendableFunction, .nested:
				"generateMock: true"
			case .publicRoot:
				"generateMock: .public"
			}
		}

		var homeProperty: String? {
			switch self {
			case .internalRoot, .publicRoot:
				nil
			case .nested:
				"screen: Screen"
			case .insideSendableFunction:
				"screenBuilder: SendableInstantiator<Screen>"
			}
		}

		/// The probe that passes the entry `true`, and reads the dependency it binds to `nil`.
		var probe: String {
			switch self {
			case .internalRoot, .publicRoot:
				"Screen.mock(safeDIOverrides: .init(analyticsIsUnavailable: true)).analytics == nil"
			case .nested:
				"Home.mock(safeDIOverrides: .init(screen: .init(analyticsIsUnavailable: true))).screen.analytics == nil"
			case .insideSendableFunction:
				"Home.mock(safeDIOverrides: .init(screenBuilder: .init(analyticsIsUnavailable: true))).screenBuilder.instantiate().analytics == nil"
			}
		}
	}

	/// Whether the fulfilling type's public mock takes `SafeDIOverrides`, so that the call has a member of its own.
	enum CalledMockOverrides: String, CaseIterable, CustomTestStringConvertible {
		case none
		case some

		var testDescription: String {
			rawValue
		}
	}

	@Test(arguments: CallerPosition.allCases, CalledMockOverrides.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesEntry_whenOtherModulesPublicMockBuildsFulfillingType(position: CallerPosition, overrides: CalledMockOverrides) async throws {
		// `LiveAnalytics` fulfills `Analytics` in `Lib`, whose public mock alone builds it, since its initializer is
		// internal. A mock in `App` whose tree instantiates `analytics: (any Analytics)?` only if available calls that
		// mock, and takes the entry beside the call as beside any other built dependency.
		let liveAnalytics = switch overrides {
		case .none:
			"""
			@Instantiable(fulfillingAdditionalTypes: [Analytics.self], generateMock: .public)
			public final class LiveAnalytics: Analytics, Instantiable {
			    init() {}
			}
			"""
		case .some:
			"""
			@Instantiable
			final class Session: Instantiable {
			    init() {}
			}

			@Instantiable(fulfillingAdditionalTypes: [Analytics.self], generateMock: .public)
			public final class LiveAnalytics: Analytics, Instantiable {
			    init(session: Session) {
			        self.session = session
			    }

			    @Instantiated let session: Session
			}
			"""
		}
		var appFiles = ["Screen.swift": """
		import Lib
		import SafeDI

		@Instantiable(\(position.screenMock))
		public final class Screen: Instantiable {
		    public init(analytics: (any Analytics)?) {
		        self.analytics = analytics
		    }

		    @Instantiated(onlyIfAvailable: true) let analytics: (any Analytics)?
		}

		"""]
		if let homeProperty = position.homeProperty {
			let label = String(homeProperty.prefix { $0 != ":" })
			appFiles["Home.swift"] = """
			import Lib
			import SafeDI

			@Instantiable(generateMock: true)
			public final class Home: Instantiable {
			    public init(\(homeProperty)) {
			        self.\(label) = \(label)
			    }

			    @Instantiated let \(homeProperty)
			}

			"""
		}
		let modules = [
			ModuleFixture(name: "Lib", packageName: "lib", swiftFileContentByFilePath: ["Lib.swift": """
			import SafeDI

			public protocol Analytics {}

			\(liveAnalytics)

			"""]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: appFiles, dependencies: ["Lib"]),
		]
		try await withKnownIssue("Row 5: a dependency another module’s public mock builds takes no entry", isIntermittent: false) {
			let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
			try await expectProbesHold(of: modules, output: output, probes: [position.probe])
		}
	}

	// MARK: Tests – Swift 5 trailing closures

	/// The dependency `Screen` builds beside the one it instantiates only if available, `c: C?`.
	enum EarlierDependency: String, CaseIterable, CustomTestStringConvertible {
		/// `b: B`, whose entry takes another closure type than `c`'s.
		case otherType
		/// `b: C`, whose entry takes `c`'s closure type.
		case sameType

		var testDescription: String {
			rawValue
		}

		var type: String {
			switch self {
			case .otherType: "B"
			case .sameType: "C"
			}
		}
	}

	@Test(arguments: EarlierDependency.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_matchesUnlabeledTrailingClosureToLastEntry_whenSwift5CallsOverridesOfTypeInstantiatingDependencyOnlyIfAvailable(earlier: EarlierDependency) async throws {
		// Swift 5 matches an unlabeled trailing closure to the last parameter it can take, backward, as a call written
		// against 2.4.0 relies on: the last entry of `SafeDIOverrides` is `c`'s override, and the entry that binds `c`
		// to `nil` is declared before it, so the closure still overrides `c`.
		let modules = [
			ModuleFixture(
				name: "App",
				packageName: "app",
				swiftFileContentByFilePath: ["Screen.swift": """
				import SafeDI

				@Instantiable
				public final class B: Instantiable {
				    public init() {}
				}

				@Instantiable
				public class C: Instantiable {
				    public init() {}
				}

				public final class OverridingC: C {}

				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(b: \(earlier.type), c: C?) {
				        self.b = b
				        self.c = c
				    }

				    @Instantiated let b: \(earlier.type)
				    @Instantiated(onlyIfAvailable: true) let c: C?
				}

				#if DEBUG
				func screenOverridingLastEntryWithTrailingClosure() -> Screen {
				    Screen.mock(safeDIOverrides: .init { OverridingC() })
				}
				#endif

				"""],
				compilerSettings: VerificationCompilerSettings(swiftLanguageMode: "5"),
			),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let path = try DifferentialValuePath(output: output, modules: modules)
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: [
				DifferentialValueProbe(
					name: "trailing closure",
					expression: "screenOverridingLastEntryWithTrailingClosure()",
					knownRightExpression: "Screen.mock(safeDIOverrides: .init(c: { OverridingC() }))",
				),
			],
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Tests – An erased dependency

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsErasedDependencyToNil_whenEntryIsTrue(fulfillerHasConfiguration: Bool) async throws {
		// `Screen` instantiates `logger: AnyLogger?` only if available, erasing the `DefaultLogger` it is fulfilled by:
		// the mock wraps the fulfiller in the unwrapped eraser, as production does, and the entry binds it to `nil`.
		let defaultLogger = fulfillerHasConfiguration
			? """
			@Instantiable
			public final class DefaultLogger: Instantiable {
			    public init(store: Store) {
			        self.store = store
			    }

			    @Instantiated let store: Store
			}

			@Instantiable
			public final class Store: Instantiable {
			    public init() {}
			}
			"""
			: """
			@Instantiable
			public final class DefaultLogger: Instantiable {
			    public init() {}
			}
			"""
		let modules = [
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Screen.swift": """
			import SafeDI

			\(defaultLogger)

			public struct AnyLogger {
			    public init(_ logger: DefaultLogger) {
			        self.logger = logger
			    }

			    public let logger: DefaultLogger
			}

			@Instantiable(generateMock: true)
			public final class Screen: Instantiable {
			    public init(logger: AnyLogger?) {
			        self.logger = logger
			    }

			    @Instantiated(fulfilledByType: "DefaultLogger", erasedToConcreteExistential: true, onlyIfAvailable: true) let logger: AnyLogger?
			}

			"""]),
		]
		try await withKnownIssue("The erased-optional fix: the mock wraps the fulfiller in `AnyLogger?(…)`", isIntermittent: false) {
			let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
			try await expectProbesHold(of: modules, output: output, probes: [
				"Screen.mock(safeDIOverrides: .init(loggerIsUnavailable: true)).logger == nil",
				"Screen.mock().logger != nil",
			])
		}
	}

	// MARK: Tests – A cycle

	/// The names of a cycle's three types, which decide the edge the mock cuts.
	enum CycleNames: String, CaseIterable, CustomTestStringConvertible {
		/// `Root`, `Holder` and `Built`.
		case holderAfterBuilt
		/// `ARoot`, `Holder` and `Zone`.
		case holderBeforeBuilt

		var testDescription: String {
			rawValue
		}

		var root: String {
			switch self {
			case .holderAfterBuilt: "Root"
			case .holderBeforeBuilt: "ARoot"
			}
		}

		var built: String {
			switch self {
			case .holderAfterBuilt: "Built"
			case .holderBeforeBuilt: "Zone"
			}
		}
	}

	@Test(arguments: CycleNames.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesEntry_whenDependencyInstantiatedOnlyIfAvailableClosesCycle(names: CycleNames) async throws {
		// `Holder` instantiates the cycle's type only if available, and that type builds `Holder` again through an
		// instantiator. Which edge of the cycle the mock cuts follows the types' names, but the entry exists, and
		// binds `Holder`'s dependency to `nil`, whatever they are named.
		let modules = [
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Cycle.swift": """
			import SafeDI

			@Instantiable(generateMock: true)
			public final class \(names.root): Instantiable {
			    public init(holder: Holder, built: \(names.built)) {
			        self.holder = holder
			        self.built = built
			    }

			    @Instantiated let holder: Holder
			    @Instantiated let built: \(names.built)
			}

			@Instantiable
			public final class Holder: Instantiable {
			    public init(cycle: \(names.built)?) {
			        self.cycle = cycle
			    }

			    @Instantiated(onlyIfAvailable: true) let cycle: \(names.built)?
			}

			@Instantiable
			public final class \(names.built): Instantiable {
			    public init(holderBuilder: Instantiator<Holder>) {
			        self.holderBuilder = holderBuilder
			    }

			    @Instantiated let holderBuilder: Instantiator<Holder>
			}

			"""]),
		]
		try await withKnownIssue("Row 5: a dependency on a cycle’s cut edge takes no entry", isIntermittent: false) {
			let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
			try await expectProbesHold(of: modules, output: output, probes: [
				"\(names.root).mock(safeDIOverrides: .init(holder: .init(cycleIsUnavailable: true))).holder.cycle == nil",
				"\(names.root).mock().holder.cycle != nil",
			])
		} when: {
			names == .holderAfterBuilt
		}
	}

	// MARK: Tests – A calling mock's optional builder

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsDependencyToNil_whenCallingMockIsPassedBuilderReturningNilForPlaceItFills() async throws {
		// `Screen`'s public mock in `Lib` instantiates `p` only if available, which nothing `Lib` sees fulfills. `Home`,
		// in `App`, calls it and fills the place with `Impl`, which `App` declares, and takes an optional builder that
		// replaces the fill: a builder that returns `nil` binds `p` to `nil`, as the entry does where the same types are
		// built in one module, and one that builds `Impl` with `nil` binds the dependency `Impl` instantiates only if
		// available to `nil`.
		let modules = [
			ModuleFixture(name: "Lib", packageName: "lib", swiftFileContentByFilePath: ["Lib.swift": """
			import SafeDI

			public protocol P {}

			@Instantiable
			final class Dependency: Instantiable {
			    init() {}
			}

			@Instantiable(generateMock: .public)
			public final class Screen: Instantiable {
			    init(dependency: Dependency, p: (any P)?) {
			        self.dependency = dependency
			        self.p = p
			    }

			    @Instantiated let dependency: Dependency
			    @Instantiated(onlyIfAvailable: true) public let p: (any P)?
			}

			"""]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Home.swift": """
			import Lib
			import SafeDI

			public protocol Q {}

			@Instantiable(fulfillingAdditionalTypes: [Q.self])
			public final class QImpl: Q, Instantiable {
			    public init() {}
			}

			@Instantiable(fulfillingAdditionalTypes: [P.self])
			public final class Impl: P, Instantiable {
			    public init(q: (any Q)?) {
			        self.q = q
			    }

			    @Instantiated(onlyIfAvailable: true) let q: (any Q)?
			}

			@Instantiable(generateMock: true)
			public final class Home: Instantiable {
			    public init(screen: Screen) {
			        self.screen = screen
			    }

			    @Instantiated let screen: Screen
			}

			"""], dependencies: ["Lib"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectValuesAgreeWithInlineMocks(of: modules, output: output, probes: [
			DifferentialValueProbe(
				name: "p is nil",
				expression: "Home.mock(pOptionalBuilder: { nil })",
				knownRightExpression: "Home.mock(safeDIOverrides: .init(screen: .init(pIsUnavailable: true)))",
			),
			DifferentialValueProbe(
				name: "q is nil",
				expression: "Home.mock(pOptionalBuilder: { Impl(q: nil) })",
				knownRightExpression: "Home.mock(safeDIOverrides: .init(screen: .init(p: .init(qIsUnavailable: true))))",
			),
		])
	}

	// MARK: Tests – One mock, several entries

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsOnlyPlaceWhoseEntryIsTrue_whenMockBuildsTypeInstantiatingDependencyOnlyIfAvailableAtTwoPlaces() async throws {
		// `Home` builds `Panel` twice, and each `Panel` instantiates `analytics` only if available: each place has its
		// own configuration, and so its own entry.
		let modules = [
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Home.swift": """
			import SafeDI

			public protocol Analytics {}

			@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
			public final class DefaultAnalytics: Analytics, Instantiable {
			    public init() {}
			}

			@Instantiable
			public final class Panel: Instantiable {
			    public init(analytics: (any Analytics)?) {
			        self.analytics = analytics
			    }

			    @Instantiated(onlyIfAvailable: true) let analytics: (any Analytics)?
			}

			@Instantiable(generateMock: true)
			public final class Home: Instantiable {
			    public init(left: Panel, right: Panel) {
			        self.left = left
			        self.right = right
			    }

			    @Instantiated let left: Panel
			    @Instantiated let right: Panel
			}

			"""]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectProbesHold(of: modules, output: output, probes: [
			"{ let home = Home.mock(safeDIOverrides: .init(left: .init(analyticsIsUnavailable: true))); return home.left.analytics == nil && home.right.analytics != nil }()",
			"{ let home = Home.mock(safeDIOverrides: .init(right: .init(analyticsIsUnavailable: true))); return home.left.analytics != nil && home.right.analytics == nil }()",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_namesEntryApart_whenConfigurationHoldsDefaultValuedParameterLabeledAsEntry() async throws {
		// `Panel` takes a default-valued `analyticsIsUnavailable: Int`, a field of its configuration, so the entry is
		// `analyticsIsUnavailable_`, as the Manual says.
		let modules = [
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["Home.swift": """
			import SafeDI

			public protocol Analytics {}

			@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
			public final class DefaultAnalytics: Analytics, Instantiable {
			    public init() {}
			}

			@Instantiable
			public final class Panel: Instantiable {
			    public init(analytics: (any Analytics)?, analyticsIsUnavailable: Int = 1) {
			        self.analytics = analytics
			        self.analyticsIsUnavailable = analyticsIsUnavailable
			    }

			    @Instantiated(onlyIfAvailable: true) let analytics: (any Analytics)?
			    let analyticsIsUnavailable: Int
			}

			@Instantiable(generateMock: true)
			public final class Home: Instantiable {
			    public init(panel: Panel) {
			        self.panel = panel
			    }

			    @Instantiated let panel: Panel
			}

			"""]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectProbesHold(of: modules, output: output, probes: [
			"{ let panel = Home.mock(safeDIOverrides: .init(panel: .init(analyticsIsUnavailable_: true, analyticsIsUnavailable: 2))).panel; return panel.analytics == nil && panel.analyticsIsUnavailable == 2 }()",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesEntry_whenConfigurationListsMockOfTypeInstantiatingDependencyOnlyIfAvailable() async throws {
		// `Screen` declares no generated mock; `additionalMocksToGenerate` lists it, and its mock takes the entry.
		let modules = [
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: [
				"Screen.swift": """
				import SafeDI

				public protocol Analytics {}

				@Instantiable(fulfillingAdditionalTypes: [Analytics.self])
				public final class DefaultAnalytics: Analytics, Instantiable {
				    public init() {}
				}

				@Instantiable
				public final class Screen: Instantiable {
				    public init(analytics: (any Analytics)?) {
				        self.analytics = analytics
				    }

				    @Instantiated(onlyIfAvailable: true) let analytics: (any Analytics)?
				}

				""",
				"SafeDIConfiguration.swift": "import SafeDI\n\n#SafeDIConfiguration(additionalMocksToGenerate: [\"Screen\"])\n",
			]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectProbesHold(of: modules, output: output, probes: [
			"Screen.mock(safeDIOverrides: .init(analyticsIsUnavailable: true)).analytics == nil",
			"Screen.mock().analytics != nil",
		])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Runs `output`'s generated code with its fixture and checks that each of `probes`, a `Bool` expression, is
	/// `true`.
	private mutating func expectProbesHold(
		of modules: [ModuleFixture],
		output: MultiModuleTestOutput,
		probes: [String],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let path = try DifferentialValuePath(output: output, modules: modules)
		try await expectDifferentialValuesAgree(
			feature: path,
			knownRight: path,
			probes: probes.map { DifferentialValueProbe(name: $0, expression: $0, knownRightExpression: "true") },
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// Compiles `output` and the same types built in one module, with every public mock an internal one, and compares what
	/// `probes` build in each.
	private mutating func expectValuesAgreeWithInlineMocks(
		of modules: [ModuleFixture],
		output: MultiModuleTestOutput,
		probes: [DifferentialValueProbe],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let moduleNames = Set(modules.map(\.name))
		func inline(_ source: String) -> String {
			source
				.split(separator: "\n", omittingEmptySubsequences: false)
				.filter { line in !moduleNames.contains { line == "import \($0)" } }
				.joined(separator: "\n")
				.replacingOccurrences(of: "generateMock: .public", with: "generateMock: true")
		}
		var inlineFiles = [String: String]()
		for module in modules {
			for (fileName, content) in module.swiftFileContentByFilePath {
				inlineFiles["\(module.name)_\(fileName)"] = inline(content)
			}
		}
		let inlineModules = [ModuleFixture(name: modules[0].name, packageName: modules[0].packageName, swiftFileContentByFilePath: inlineFiles)]
		let inlineOutput = try await executeSafeDIToolMultiModuleTest(modules: inlineModules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: inlineOutput, modules: inlineModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
