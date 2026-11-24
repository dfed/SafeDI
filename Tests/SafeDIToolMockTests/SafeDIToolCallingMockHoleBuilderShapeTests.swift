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

/// The labels, families and read sites of the optional builders a calling mock takes for the hole types its calls of
/// other modules' public mocks fill: each takes the label a builder of its hole type and family would take were the
/// place passed up, and every call that fills, or re-enters a fill of, a place of that hole type and family reads it.
struct SafeDIToolCallingMockHoleBuilderShapeTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – labels

	@Test(arguments: [Caller.internal, .public])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesOptionalBuilderUnderLabelOfBuilderItTakesWhenPlaceIsPassedUp_whenCallFillsPlace(caller: Caller) async throws {
		// `Root` calls `F`, whose place of `any Api` only `App` fulfills: `Root`'s mock fills it and takes an optional
		// builder. Without `Live`, the call passes the place up and the mock takes the builder required, under the same
		// label and in the same position.
		let feat = """
		import Base
		import SafeDI

		@Instantiable(generateMock: .public)
		public struct F: Instantiable {
		    init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}
		"""
		let root = """
		\(caller.attribute)
		public struct Root: Instantiable {
		    \(caller.initializerAccess)init(token: Token?, f: F) {
		        self.token = token
		        self.f = f
		    }

		    @Received(onlyIfAvailable: true) \(caller.tokenAccess)let token: Token?
		    @Instantiated public let f: F
		}
		"""
		let token = "\(caller.tokenAccess)final class Token {\n    \(caller.tokenAccess)init() {}\n}"
		let filled = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(feat: feat, app: [Self.live, token, root]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		let passedUp = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(feat: feat, app: [token, root]), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: filled) == caller.filledParameterLines)
		#expect(Self.mockParameterLines(of: passedUp) == caller.passedUpParameterLines)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_namesFilledBuilderAsPassedUpGraphDoes_whenFilledHoleTypesPlainLabelEqualsPassedUpHoleTypesSendableLabel() async throws {
		// `ServiceSendable`'s plain label is `Service`'s `@Sendable` label, so a pass over both names `ServiceSendable` apart
		// by its types. Filled, it takes that label too, beside the passed-up `Service`, which keeps its own.
		let feat = """
		import Base
		import SafeDI

		@Instantiable(generateMock: .public)
		public struct F: Instantiable {
		    init(service: any Service, serviceSendable: any ServiceSendable) {
		        self.service = service
		        self.serviceSendable = serviceSendable
		    }

		    @Instantiated public let service: any Service
		    @Instantiated public let serviceSendable: any ServiceSendable
		}
		"""
		let filledServiceSendable = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(feat: feat, app: [Self.liveServiceSendable, Self.root(instantiating: ["f: F"])]), integration: .moduleInfo, filesToDelete: &filesToDelete)
		let bothPassedUp = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(feat: feat, app: [Self.root(instantiating: ["f: F"])]), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: filledServiceSendable) == [
			"serviceBuilder: @escaping () -> any Service,",
			"serviceSendable_ServiceSendableBuilder: (() -> any ServiceSendable)? = nil,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		#expect(Self.mockParameterLines(of: bothPassedUp) == [
			"serviceBuilder: @escaping () -> any Service,",
			"serviceSendable_ServiceSendableBuilder: @escaping () -> any ServiceSendable,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsPassedUpBuildersLabel_whenNamingFilledHoleTypeWithItWouldRenameIt() async throws {
		// `Service`'s `@Sendable` label is `ServiceSendable`'s plain label, so a pass over both would rename the passed-up
		// `ServiceSendable`: its label stays what the mock took without the filled `Service`.
		let feat = """
		import Base
		import SafeDI

		@Instantiable(generateMock: .public)
		public struct F: Instantiable {
		    init(service: any Service, serviceSendable: any ServiceSendable) {
		        self.service = service
		        self.serviceSendable = serviceSendable
		    }

		    @Instantiated public let service: any Service
		    @Instantiated public let serviceSendable: any ServiceSendable
		}
		"""
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules(feat: feat, app: [Self.liveService, Self.root(instantiating: ["f: F"])]), integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output) == [
			"serviceBuilder: (() -> any Service)? = nil,",
			"serviceSendableBuilder: @escaping () -> any ServiceSendable,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesSameLabelsInEveryDeclarationOrder_whenTwentyFilledHoleTypesNameEachOtherApart() async throws {
		// Ten pairs of hole types, each pair's plain label the other's `@Sendable` label, declared in six orders: the labels
		// never depend on the order, and equal those of the graph that passes every place up.
		let pairs = (0..<10).map { index in (plain: "Service\(index)", sendable: "Service\(index)Sendable") }
		let holeTypes = pairs.flatMap { [$0.plain, $0.sendable] }
		let orders = [
			holeTypes,
			Array(holeTypes.reversed()),
			holeTypes.enumerated().sorted { ($0.offset % 3, $0.offset) < ($1.offset % 3, $1.offset) }.map(\.element),
			holeTypes.enumerated().sorted { ($0.offset % 7, $0.offset) > ($1.offset % 7, $1.offset) }.map(\.element),
			Array(holeTypes[10...] + holeTypes[..<10]),
			holeTypes.enumerated().sorted { ($0.offset % 2, $0.offset) < ($1.offset % 2, $1.offset) }.map(\.element),
		]
		func modules(order: [String], filled: Bool) -> [ModuleFixture] {
			let base = (["import SafeDI"] + holeTypes.map { "public protocol \($0) {}" }).joined(separator: "\n\n")
			let properties = order.map { "@Instantiated public let \(Self.lowered($0)): any \($0)" }
			let feat = """
			import Base
			import SafeDI

			@Instantiable(generateMock: .public)
			public struct F: Instantiable {
			    init(\(order.map { "\(Self.lowered($0)): any \($0)" }.joined(separator: ", "))) {
			\(order.map { "        self.\(Self.lowered($0)) = \(Self.lowered($0))" }.joined(separator: "\n"))
			    }

			\(properties.map { "    \($0)" }.joined(separator: "\n"))
			}
			"""
			let lives = order.map { "@Instantiable(fulfillingAdditionalTypes: [\($0).self])\npublic struct Live\($0): \($0), Instantiable {\n    public init() {}\n}" }
			return Self.modules(base: base, feat: feat, app: (filled ? lives : []) + [Self.root(instantiating: ["f: F"])])
		}
		var filledLines = [[String]]()
		for order in orders {
			let output = try await executeSafeDIToolMultiModuleTest(modules: modules(order: order, filled: true), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
			filledLines.append(Self.mockParameterLines(of: output))
		}
		let passedUp = try await executeSafeDIToolMultiModuleTest(modules: modules(order: holeTypes, filled: false), integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)

		#expect(Set(filledLines).count == 1)
		#expect(filledLines.first?.map(Self.labelOfParameterLine) == Self.mockParameterLines(of: passedUp).map(Self.labelOfParameterLine))
		#expect(filledLines.first?.count == 21)
	}

	// MARK: Tests – families

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsEachFamilysPlacesWithItsOwnBuilder_whenCallsFillPlacesInsideAndOutsideSendableFunction() async throws {
		// `Root` builds `F` directly and inside a `@Sendable` builder function: the call there captures a `@Sendable`
		// builder, so the mock takes one builder of each family, and each replaces only its own call's fill.
		let feat = """
		import Base
		import SafeDI

		@Instantiable(generateMock: .public)
		public struct F: Instantiable, Sendable {
		    init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}
		"""
		let modules = Self.modules(base: Self.sendableApi, feat: feat, app: [Self.sendableLive, Self.sendableFakes, Self.root(instantiating: ["f: F", "fBuilder: SendableInstantiator<F>"])])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output) == [
			"apiBuilder: (() -> any Api)? = nil,",
			"apiSendableBuilder: (@Sendable () -> any Api)? = nil,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		try await expectValues(of: output, modules: modules, pairs: [
			("Root.mock().f.api", "App.Live()"),
			("Root.mock().fBuilder.instantiate().api", "App.Live()"),
			("Root.mock(apiBuilder: { App.Fake() }).f.api", "App.Fake()"),
			("Root.mock(apiBuilder: { App.Fake() }).fBuilder.instantiate().api", "App.Live()"),
			("Root.mock(apiSendableBuilder: { App.Other() }).f.api", "App.Live()"),
			("Root.mock(apiSendableBuilder: { App.Other() }).fBuilder.instantiate().api", "App.Other()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesSendableBuilder_whenCallFillsPlaceInsideAnotherCallsSendableFill() async throws {
		// `G`'s place of `any Store` is held in a `SendableInstantiator`, so `Root`'s fill of it, `LiveStore`, is built in a
		// `@Sendable` function, and the call of `F` that fill makes captures a `@Sendable` builder of `F`'s plain place.
		let feat = """
		import Base
		import SafeDI

		@Instantiable(generateMock: .public)
		public struct F: Instantiable, Sendable {
		    init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}

		@Instantiable(generateMock: .public)
		public struct G: Instantiable {
		    init(storeBuilder: SendableErasedInstantiator<(), any Store>) {
		        self.storeBuilder = storeBuilder
		    }

		    @Instantiated(fulfilledByType: "LiveStore", erasedToConcreteExistential: false) public let storeBuilder: SendableErasedInstantiator<(), any Store>
		}
		"""
		let liveStore = """
		@Instantiable
		public struct LiveStore: Store, Instantiable {
		    public init(f: F) {
		        self.f = f
		    }

		    @Instantiated public let f: F
		}
		"""
		let modules = Self.modules(base: Self.sendableApi + "\n\npublic protocol Store: Sendable {}", feat: feat, app: [Self.sendableLive, Self.sendableFakes, liveStore, Self.root(instantiating: ["g: G"])])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output) == [
			"apiSendableBuilder: (@Sendable () -> any Api)? = nil,",
			"liveStore_StoreSendableBuilder: (@Sendable () -> any Store)? = nil,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		try await expectValues(of: output, modules: modules, pairs: [
			("(Root.mock().g.storeBuilder.instantiate() as! App.LiveStore).f.api", "App.Live()"),
			("(Root.mock(apiSendableBuilder: { App.Fake() }).g.storeBuilder.instantiate() as! App.LiveStore).f.api", "App.Fake()"),
		])
	}

	// MARK: Tests – read sites

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_compilesAndBuildsReenteringCallsPlaces_whenFillOfHoleTypeBuildsCalledTypeAgain() async throws {
		// `F`'s fill of `any Api`, `Live`, holds an `Instantiator<F>`: the call it makes re-enters the first call's fills,
		// handed what the first call is handed, so `Root`'s mock still takes one builder of `any Api`.
		let app = """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public struct Live: Api, Instantiable {
		    public init(fBuilder: Instantiator<F>) {
		        self.fBuilder = fBuilder
		    }

		    @Instantiated public let fBuilder: Instantiator<F>
		}
		"""
		let modules = Self.modules(feat: Self.featWithApi, app: [app, Self.fakes, Self.root(instantiating: ["f: F"])])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output) == [
			"apiBuilder: (() -> any Api)? = nil,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		try await expectValues(of: output, modules: modules, pairs: [
			("(Root.mock().f.api as! App.Live).fBuilder.instantiate().api is App.Live", "true"),
			("Root.mock(apiBuilder: { App.Fake() }).f.api", "App.Fake()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsInnerCallsPlacesWithItsOwnBuilder_whenFillBuildsAnotherCalledTypeWithPlaceOfOtherHoleType() async throws {
		// `F`'s fill of `any Api`, `Live`, builds `G`, whose place of `any Store` `Root`'s mock fills too: the mock takes a
		// builder of each hole type, and each call reads its own.
		let feat = """
		import Base
		import SafeDI

		@Instantiable(generateMock: .public)
		public struct F: Instantiable {
		    init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}

		@Instantiable(generateMock: .public)
		public struct G: Instantiable {
		    init(store: any Store) {
		        self.store = store
		    }

		    @Instantiated public let store: any Store
		}
		"""
		let app = """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public struct LiveBuildingG: Api, Instantiable {
		    public init(g: G) {
		        self.g = g
		    }

		    @Instantiated public let g: G
		}

		@Instantiable(fulfillingAdditionalTypes: [Store.self])
		public struct LiveStore: Store, Instantiable {
		    public init() {}
		}

		public struct FakeStore: Store {
		    public init() {}
		}
		"""
		let modules = Self.modules(base: "public protocol Api {}\n\npublic protocol Store {}", feat: feat, app: [app, Self.fakes, Self.root(instantiating: ["f: F"])])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output) == [
			"apiBuilder: (() -> any Api)? = nil,",
			"storeBuilder: (() -> any Store)? = nil,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		try await expectValues(of: output, modules: modules, pairs: [
			("(Root.mock().f.api as! App.LiveBuildingG).g.store", "App.LiveStore()"),
			("(Root.mock(storeBuilder: { App.FakeStore() }).f.api as! App.LiveBuildingG).g.store", "App.FakeStore()"),
			("Root.mock(apiBuilder: { App.Fake() }, storeBuilder: { App.FakeStore() }).f.api", "App.Fake()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsBuilderUnderNameApart_whenFillsTreeBindsBuildersLabel() async throws {
		// `Live`, the fill of `any Api`, instantiates a property labeled `apiBuilder`, which hides the parameter inside the
		// fill: the call reads the builder under a name apart.
		let app = """
		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public struct Live: Api, Instantiable {
		    public init(apiBuilder: Gadget) {
		        self.apiBuilder = apiBuilder
		    }

		    @Instantiated public let apiBuilder: Gadget
		}

		@Instantiable
		public struct Gadget: Instantiable {
		    public init() {}
		}
		"""
		let modules = Self.modules(feat: Self.featWithApi, app: [app, Self.fakes, Self.root(instantiating: ["f: F"])])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output) == [
			"apiBuilder: (() -> any Api)? = nil,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		try await expectValues(of: output, modules: modules, pairs: [
			("Root.mock().f.api is App.Live", "true"),
			("Root.mock(apiBuilder: { App.Fake() }).f.api", "App.Fake()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_namesOptionalBuilderApart_whenAliasInMockTreeHasBuildersLabel() async throws {
		// `G`, beside the call of `F`, renames `f` as `apiBuilder`, the label the optional builder of `any Api` would take.
		let app = """
		@Instantiable
		public struct G: Instantiable {
		    public init(apiBuilder: F) {
		        self.apiBuilder = apiBuilder
		    }

		    @Received(fulfilledByDependencyNamed: "f", ofType: F.self) public let apiBuilder: F
		}
		"""
		let modules = Self.modules(feat: Self.featWithApi, app: [app, Self.live, Self.fakes, Self.root(instantiating: ["f: F", "g: G"])])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output) == [
			"apiBuilder: (() -> any Api)? = nil,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		try await expectValues(of: output, modules: modules, pairs: [
			("Root.mock().f.api is App.Live", "true"),
			("Root.mock(apiBuilder: { App.Fake() }).g.apiBuilder.api", "App.Fake()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesBuilderOfFillsPlaceAfterPassedUpBuilder_whenFillPlaceIsOfAnotherHoleType() async throws {
		// `F`'s place of `any Api` has no fulfiller in `App`, so the mock passes it up; its place of `any Service` is filled by
		// `LiveService`, whose `any Store` no declaration fulfills.
		let feat = """
		import Base
		import SafeDI

		@Instantiable(generateMock: .public)
		public struct F: Instantiable {
		    init(api: any Api, service: any Service) {
		        self.api = api
		        self.service = service
		    }

		    @Instantiated public let api: any Api
		    @Instantiated public let service: any Service
		}
		"""
		let app = """
		@Instantiable(fulfillingAdditionalTypes: [Service.self])
		public struct LiveService: Service, Instantiable {
		    public init(store: any Store) {
		        self.store = store
		    }

		    @Instantiated public let store: any Store
		}

		public struct FakeStore: Store {
		    public init() {}
		}
		"""
		let modules = Self.modules(base: "public protocol Api {}\n\npublic protocol Service {}\n\npublic protocol Store {}", feat: feat, app: [app, Self.fakes, Self.root(instantiating: ["f: F"])])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output) == [
			"apiBuilder: @escaping () -> any Api,",
			"serviceBuilder: (() -> any Service)? = nil,",
			"storeBuilder: @escaping () -> any Store,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		try await expectValues(of: output, modules: modules, pairs: [
			("(Root.mock(apiBuilder: { App.Fake() }, storeBuilder: { App.FakeStore() }).f.service as! App.LiveService).store", "App.FakeStore()"),
			("Root.mock(apiBuilder: { App.Fake() }, storeBuilder: { App.FakeStore() }).f.api", "App.Fake()"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsEachRootsOwnBuilder_whenTwoRootsMakeOneCallUnderOtherNamesAndFamilies() async throws {
		// `Hub`, which makes the call of `F`, is built by two mock roots: `First` directly, whose builder is `apiBuilder`,
		// and `Second` inside a `@Sendable` function beside a property labeled `apiSendableBuilder`, whose builder is
		// `@Sendable` and read under a name apart. Each root's call reads its own builder.
		let feat = """
		import Base
		import SafeDI

		@Instantiable(generateMock: .public)
		public struct F: Instantiable, Sendable {
		    init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}
		"""
		let app = """
		@Instantiable
		public struct Hub: Instantiable, Sendable {
		    public init(f: F) {
		        self.f = f
		    }

		    @Instantiated public let f: F
		}

		@Instantiable(generateMock: true)
		public struct First: Instantiable {
		    public init(hub: Hub) {
		        self.hub = hub
		    }

		    @Instantiated public let hub: Hub
		}

		@Instantiable(generateMock: true)
		public struct Second: Instantiable {
		    public init(hubBuilder: SendableInstantiator<Hub>, apiSendableBuilder: Gadget) {
		        self.hubBuilder = hubBuilder
		        self.apiSendableBuilder = apiSendableBuilder
		    }

		    @Instantiated public let hubBuilder: SendableInstantiator<Hub>
		    @Instantiated public let apiSendableBuilder: Gadget
		}

		@Instantiable
		public struct Gadget: Instantiable, Sendable {
		    public init() {}
		}
		"""
		let modules = Self.modules(base: Self.sendableApi, feat: feat, app: [Self.sendableLive, Self.sendableFakes, app])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output, type: "First") == [
			"apiBuilder: (() -> any Api)? = nil,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		#expect(Self.mockParameterLines(of: output, type: "Second") == [
			"apiSendableBuilder: (@Sendable () -> any Api)? = nil,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		try await expectValues(of: output, modules: modules, pairs: [
			("First.mock(apiBuilder: { App.Fake() }).hub.f.api", "App.Fake()"),
			("Second.mock(apiSendableBuilder: { App.Other() }).hubBuilder.instantiate().f.api", "App.Other()"),
			("Second.mock().hubBuilder.instantiate().f.api", "App.Live()"),
		])
	}

	@Test(arguments: [Caller.internal, .public])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsRequiredBuilderToFillingCall_whenAnotherCallPassesSameHoleTypeUp(caller: Caller) async throws {
		// `F` holds `any Api` twice, beneath levels whose `log` differs, and `Live` reads `log` lazily, so a pass-up gate
		// passes `F`'s places up whole and `Root`'s mock takes `apiBuilder` required. `H`'s one place is filled; its call
		// takes the required builder, so no optional one is added, and an override of `H` is handed it too.
		let modules = Self.joinModules(caller: caller, buildsGInline: false)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output) == [
			"apiBuilder: @escaping () -> any Api,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		try await expectValues(of: output, modules: modules, pairs: [
			("Root.mock(apiBuilder: { App.Fake() }).h.api is App.Fake", "true"),
			("Root.mock(apiBuilder: { App.Fake() }).f.a.api is App.Fake", "true"),
			("Root.mock(apiBuilder: { App.Fake() }, safeDIOverrides: .init(h: { apiBuilder in H.mock(apiBuilder: apiBuilder) })).h.api is App.Fake", "true"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWithCallersFills_whenThirdModuleCallsPublicCallingMockFromItsSafeDIFile() async throws {
		// `Top`, in module `Third`, calls `Root`'s public mock, which takes an optional builder, knowing `Root` only from
		// `App`'s `.safedi` file: its guard compiles, and `Root`'s fills build the place.
		let third = """
		import App
		import SafeDI

		@Instantiable(generateMock: true)
		public struct Top: Instantiable {
		    public init(root: Root) {
		        self.root = root
		    }

		    @Instantiated public let root: Root
		}
		"""
		var modules = Self.modules(feat: Self.featWithApi, app: [Self.live, Self.root(instantiating: ["f: F"], attribute: "@Instantiable(generateMock: .public)")])
		modules.append(ModuleFixture(name: "Third", packageName: "Third", swiftFileContentByFilePath: ["ThirdTypes.swift": third], dependencies: ["App", "Feat", "Base"]))
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output, type: "Root", module: "App") == [
			"apiBuilder: (() -> any Api)? = nil,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		try await expectValues(of: output, modules: modules, pairs: [
			("Top.mock().root.f.api is App.Live", "true"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsInlineBuiltPublicMocksPlaceWithRequiredBuilder_whenAnotherCallPassesSameHoleTypeUp() async throws {
		// `G` is built inline, and its place of `any Api` reads the builder `mock()` takes required for its hole type, unless
		// the place's own override is set.
		let modules = Self.joinModules(caller: .internal, buildsGInline: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output) == [
			"apiBuilder: @escaping () -> any Api,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		try await expectValues(of: output, modules: modules, pairs: [
			("Root.mock(apiBuilder: { App.Fake() }).g.api is App.Fake", "true"),
			("Root.mock(apiBuilder: { App.Fake() }, safeDIOverrides: .init(g: .init(api: { _ in App.Other() }))).g.api is App.Other", "true"),
		])
	}

	@Test(arguments: [Caller.public, .seamPublic])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_callsPublicMockItCouldBuildInlineWithRequiredBuilder_whenPublicMockTakesBuilderOfItsPlace(caller: Caller) async throws {
		// A `.public` mock calls `G`'s public mock, whose tree it could build, since it takes `apiBuilder` as a struct with no
		// member for a place it builds inline; the call is handed the builder, and an override of `G` replaces the call.
		let modules = Self.joinModules(caller: caller, buildsGInline: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output) == [
			"apiBuilder: @escaping () -> any Api,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		try await expectValues(of: output, modules: modules, pairs: [
			("Root.mock(apiBuilder: { App.Fake() }).g.api is App.Fake", "true"),
			("Root.mock(apiBuilder: { App.Fake() }, safeDIOverrides: .init(g: { _ in G(api: App.Other()) })).g.api is App.Other", "true"),
		])
	}

	@Test(arguments: [Caller.public, .seamPublic])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_callsPublicMockItCouldBuildInlineWithRequiredBuilder_whenNoCallFillsPlaceOfItsHoleType(caller: Caller) async throws {
		// No call fills a place of `any Api`, so the `.public` mock takes no optional builder of it to hand an inline place: it
		// calls `G`'s public mock, whose tree it could build, and the call is handed the required builder.
		let modules = Self.joinModules(caller: caller, buildsGInline: true, holdsH: false)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output) == [
			"apiBuilder: @escaping () -> any Api,",
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		try await expectValues(of: output, modules: modules, pairs: [
			("Root.mock(apiBuilder: { App.Fake() }).g.api is App.Fake", "true"),
			("Root.mock(apiBuilder: { App.Fake() }).f.a.api is App.Fake", "true"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsPublicMockInlineAndFillsItsPlace_whenFillReceivesValueItsTreeDeclaresOutsideSendableBuilder() async throws {
		// `Live` fills `Host`'s place of `any Api` and receives `context`, which `G` declares outside the `@Sendable` function
		// that builds `hostBuilder`: a call of `G`'s public mock could not hand the fill `context`, so the `.public` mock builds
		// `G` inline, as its tree hands the fill every value, fills the place itself, and takes no builder of it.
		let feat = """
		import SafeDI

		public protocol Api: Sendable {}

		@Instantiable
		public final class Context: Instantiable, Sendable {
		    public init() {}
		}

		@Instantiable
		public final class Host: Instantiable, Sendable {
		    public init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}

		@Instantiable
		public final class Unused: Instantiable {
		    init() {}
		}

		@Instantiable(generateMock: .public)
		public final class G: Instantiable, Sendable {
		    public init(context: Context, hostBuilder: SendableInstantiator<Host>) {
		        self.context = context
		        self.hostBuilder = hostBuilder
		    }

		    @Instantiated public let context: Context
		    @Instantiated public let hostBuilder: SendableInstantiator<Host>
		}
		"""
		let app = """
		import Feat
		import SafeDI

		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class Live: Api, Instantiable {
		    public init(context: Context) {
		        self.context = context
		    }

		    @Received public let context: Context
		}

		@Instantiable(generateMock: .public)
		public final class Root: Instantiable {
		    public init(g: G) {
		        self.g = g
		    }

		    @Instantiated public let g: G
		}
		"""
		let modules = [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": feat]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": app], dependencies: ["Feat"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output) == [
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
		try await expectValues(of: output, modules: modules, pairs: [
			("{ let g = Root.mock().g; return (g.hostBuilder.instantiate().api as? App.Live)?.context === g.context }()", "true"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsPublicMockInlineAndFillsItsPlace_whenDeclaringModuleGeneratesMocksUnderAnotherCondition() async throws {
		// `Feat` generates its mocks under `TESTING` and `App` under `DEBUG`, so no call of `G`'s public mock compiles in
		// `App`: the `.public` mock builds `G` inline, fills its place of `any Api` itself, and takes no builder of it.
		let feat = """
		import SafeDI

		public protocol Api {}

		@Instantiable
		public final class Unused: Instantiable {
		    init() {}
		}

		@Instantiable(generateMock: .public)
		public final class G: Instantiable {
		    public init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}
		"""
		let app = """
		import Feat
		import SafeDI

		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class Live: Api, Instantiable {
		    public init() {}
		}

		@Instantiable(generateMock: .public)
		public final class Root: Instantiable {
		    public init(g: G) {
		        self.g = g
		    }

		    @Instantiated public let g: G
		}
		"""
		let modules = [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: [
				"FeatTypes.swift": feat,
				"SafeDIConfiguration.swift": "#SafeDIConfiguration(mockConditionalCompilation: \"TESTING\")",
			], mockConditionalCompilation: "TESTING"),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": app], dependencies: ["Feat"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, compileVerification: .returningOutcomeOnly, filesToDelete: &filesToDelete)

		#expect(Self.mockParameterLines(of: output) == [
			"safeDIOverrides: SafeDIOverrides = .init()",
		])
	}

	/// The modules of the join: `F` holds `any Api` twice, beneath levels whose `log` differs, and `Live` reads `log` lazily,
	/// so a pass-up gate passes `F`'s places up whole and `Root`'s mock takes `apiBuilder` required, and `H`'s one place is
	/// filled. Where `buildsGInline`, `Root` also instantiates `G`, whose public initializer lets the mock build it inline.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_handsInstantiatorPlaceAnAdapterOfItsBuilder_whenAnotherCallsPlaceOfHoleTypeIsPlain() async throws {
		// `First` holds `Gizmo` in an `Instantiator` and `Second` by value; `App` sees no `Gizmo` it can build, so `Screen`'s
		// mock takes one builder, `() -> Gizmo`, and hands `First`'s call an adapter that takes the forwarded value.
		let modules = [
			ModuleFixture(name: "Core", packageName: "core", swiftFileContentByFilePath: [
				"Core.swift": """
				import SafeDI

				open class Gizmo: Instantiable {
				    public init() {}
				}

				@Instantiable(generateMock: .public)
				public struct First: Instantiable {
				    init(gizmoBuilder: Instantiator<Gizmo>) {
				        self.gizmoBuilder = gizmoBuilder
				    }

				    @Instantiated let gizmoBuilder: Instantiator<Gizmo>
				}

				@Instantiable(generateMock: .public)
				public struct Second: Instantiable {
				    init(gizmo: Gizmo) {
				        self.gizmo = gizmo
				    }

				    @Instantiated let gizmo: Gizmo
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: [
				"Screen.swift": """
				import Core
				import SafeDI

				@Instantiable(generateMock: true)
				public struct Screen: Instantiable {
				    public init(first: First, second: Second) {
				        self.first = first
				        self.second = second
				    }

				    @Instantiated let first: First
				    @Instantiated let second: Second
				}
				""",
			], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		let pluginComment = MultiModuleIntegration.moduleInfo.seamCallComment(type: "First", declaringModule: "Core")
		#expect(output.modules["App"]?.generatedFiles == [
			"App.swift": generatedFileHeader + """
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
			            first: ((@escaping Instantiator<Gizmo>.Builder) -> First)? = nil,
			            second: ((@escaping () -> Gizmo) -> Second)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                first: first,
			                second: second
			            )
			        }

			        var first: ((@escaping Instantiator<Gizmo>.Builder) -> First)? { __safeDI_storage.first }
			        var second: ((@escaping () -> Gizmo) -> Second)? { __safeDI_storage.second }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                first: ((@escaping Instantiator<Gizmo>.Builder) -> First)?,
			                second: ((@escaping () -> Gizmo) -> Second)?
			            ) {
			                self.first = first
			                self.second = second
			            }

			            let first: ((@escaping Instantiator<Gizmo>.Builder) -> First)?
			            let second: ((@escaping () -> Gizmo) -> Second)?
			        }
			    }

			    static func mock(
			        gizmoBuilder: @escaping () -> Gizmo,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        let __safeDI_gizmoBuilder = gizmoBuilder
			        let __safeDI_gizmoBuilder_: Instantiator<Gizmo>.Builder = { _ in __safeDI_gizmoBuilder() }
			        _ = First.__safeDI_First_mock_F35A1ABA2A8BD0CD.self\(pluginComment)
			        func __safeDI_first() -> First {
			            let gizmoBuilder: Instantiator<Gizmo>.Builder = __safeDI_gizmoBuilder_
			            return if let safeDIBuilder = safeDIOverrides.first { safeDIBuilder(gizmoBuilder) } else { First.__safeDI_mock(gizmoBuilder: .init(__safeDI_noScope: gizmoBuilder)) }
			        }
			        let first: First = __safeDI_first()
			        _ = Second.__safeDI_Second_mock_4AA306DE1EA05F15.self\(pluginComment)
			        func __safeDI_second() -> Second {
			            let gizmoBuilder: () -> Gizmo = __safeDI_gizmoBuilder
			            return if let safeDIBuilder = safeDIOverrides.second { safeDIBuilder(gizmoBuilder) } else { Second.__safeDI_mock(gizmoBuilder: .init(__safeDI_noScope: gizmoBuilder)) }
			        }
			        let second: Second = __safeDI_second()
			        return Screen(first: first, second: second)
			    }
			}
			#endif
			""",
		])
	}

	private static func joinModules(caller: Caller, buildsGInline: Bool, holdsH: Bool = true) -> [ModuleFixture] {
		let feat = """
		import SafeDI

		public protocol Api {}

		@Instantiable
		public final class Log: Instantiable, Sendable {
		    public init() {}
		}

		@Instantiable
		public final class A: Instantiable {
		    init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}

		@Instantiable
		public final class Z: Instantiable {
		    init(log: Log) {
		        self.log = log
		    }

		    @Received public let log: Log
		}

		@Instantiable
		public final class B: Instantiable {
		    init(log: LazilyInstantiated<Log>, a: A) {
		        self.log = log
		        self.a = a
		    }

		    @Instantiated public let log: LazilyInstantiated<Log>
		    @Instantiated public let a: A
		}

		@Instantiable(generateMock: .public)
		public final class F: Instantiable {
		    public init(a: A, b: B, z: Z) {
		        self.a = a
		        self.b = b
		        self.z = z
		    }

		    @Instantiated public let a: A
		    @Instantiated public let b: B
		    @Instantiated public let z: Z
		}

		\(buildsGInline ? Self.inlineBuiltG : "")@Instantiable(generateMock: .public)
		public final class H: Instantiable {
		    init(api: any Api) {
		        self.api = api
		    }

		    @Instantiated public let api: any Api
		}
		"""
		let app = """
		import Feat
		import SafeDI

		@Instantiable(fulfillingAdditionalTypes: [Api.self])
		public final class Live: Api, Instantiable {
		    public init(log: LazilyInstantiated<Log>) {
		        self.log = log
		    }

		    @Received public let log: LazilyInstantiated<Log>
		}

		public final class Fake: Api {
		    public init() {}
		}

		public final class Other: Api {
		    public init() {}
		}

		\(caller.attribute)
		public final class Root: Instantiable {
		    public init(log: LazilyInstantiated<Log>, f: F\(holdsH ? ", h: H" : "")\(buildsGInline ? ", g: G" : "")) {
		        self.log = log
		        self.f = f\(holdsH ? "\n        self.h = h" : "")\(buildsGInline ? "\n        self.g = g" : "")
		    }

		    @Instantiated public let log: LazilyInstantiated<Log>
		    @Instantiated public let f: F\(holdsH ? "\n    @Instantiated public let h: H" : "")\(buildsGInline ? "\n    @Instantiated public let g: G" : "")
		}
		"""
		let featForCaller = caller == .seamPublic ? feat
			.replacingOccurrences(of: "@Instantiable(generateMock: .public)\npublic final class F", with: "@Instantiable(generateDependencyTree: true, generateMock: .public)\npublic final class F")
			.replacingOccurrences(of: "@Instantiable(generateMock: .public)\npublic final class H", with: "@Instantiable(generateDependencyTree: true, generateMock: .public)\npublic final class H") : feat
		return [
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": featForCaller]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": app], dependencies: ["Feat"]),
		]
	}

	/// A public mock whose initializer is public, so a calling mock builds it inline, holding a place of `any Api`.
	private static let inlineBuiltG = """
	@Instantiable(generateMock: .public)
	public final class G: Instantiable {
	    public init(api: any Api) {
	        self.api = api
	    }

	    @Instantiated public let api: any Api
	}


	"""

	// MARK: Private

	private var filesToDelete: [URL]

	/// The calling mock's kind.
	enum Caller: CaseIterable, CustomTestStringConvertible {
		case `internal`
		case `public`
		/// A seam whose mock is public, which calls `F` and `H` as seams too.
		case seamPublic

		var testDescription: String {
			switch self {
			case .internal: "internal"
			case .public: "public"
			case .seamPublic: "seamPublic"
			}
		}

		var attribute: String {
			switch self {
			case .internal: "@Instantiable(generateMock: true)"
			case .public: "@Instantiable(generateMock: .public)"
			case .seamPublic: "@Instantiable(generateDependencyTree: true, generateMock: .public)"
			}
		}

		/// A public mock's `token` is a `package` value, so the mock has a `package` tier beside its `public` one.
		var tokenAccess: String {
			switch self {
			case .internal: ""
			case .public, .seamPublic: "package "
			}
		}

		var initializerAccess: String {
			switch self {
			case .internal: ""
			case .public, .seamPublic: "package "
			}
		}

		var filledParameterLines: [String] {
			["apiBuilder: (() -> any Api)? = nil,", "safeDIOverrides: SafeDIOverrides = .init()"]
		}

		var passedUpParameterLines: [String] {
			["apiBuilder: @escaping () -> any Api,", "safeDIOverrides: SafeDIOverrides = .init()"]
		}
	}

	private static let live = """
	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public struct Live: Api, Instantiable {
	    public init() {}
	}
	"""

	private static let fakes = """
	public struct Fake: Api {
	    public init() {}
	}

	public struct Other: Api {
	    public init() {}
	}
	"""

	private static let sendableApi = """
	import SafeDI

	public protocol Api: Sendable {}
	"""

	private static let sendableLive = """
	@Instantiable(fulfillingAdditionalTypes: [Api.self])
	public struct Live: Api, Instantiable, Sendable {
	    public init() {}
	}
	"""

	private static let sendableFakes = """
	public struct Fake: Api, Sendable {
	    public init() {}
	}

	public struct Other: Api, Sendable {
	    public init() {}
	}
	"""

	private static let liveService = """
	@Instantiable(fulfillingAdditionalTypes: [Service.self])
	public struct LiveService: Service, Instantiable {
	    public init() {}
	}
	"""

	private static let liveServiceSendable = """
	@Instantiable(fulfillingAdditionalTypes: [ServiceSendable.self])
	public struct LiveServiceSendable: ServiceSendable, Instantiable {
	    public init() {}
	}
	"""

	private static let featWithApi = """
	import Base
	import SafeDI

	@Instantiable(generateMock: .public)
	public struct F: Instantiable {
	    init(api: any Api) {
	        self.api = api
	    }

	    @Instantiated public let api: any Api
	}
	"""

	/// A mock root `Root` that instantiates each of `properties`, spelled `label: Type`.
	private static func root(instantiating properties: [String], attribute: String = "@Instantiable(generateMock: true)") -> String {
		let labels = properties.map { String($0.prefix { $0 != ":" }) }
		return """
		\(attribute)
		public struct Root: Instantiable {
		    public init(\(properties.joined(separator: ", "))) {
		\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
		    }

		\(properties.map { "    @Instantiated public let \($0)" }.joined(separator: "\n"))
		}
		"""
	}

	/// Module `Base` declares the hole types, `Feat` the called public mocks, and `App`, of `appFiles`, the caller.
	private static func modules(
		base: String = "import SafeDI\n\npublic protocol Api {}\n\npublic protocol Service {}\n\npublic protocol ServiceSendable {}",
		feat: String,
		app appFiles: [String],
	) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Base", packageName: "Base", swiftFileContentByFilePath: ["BaseTypes.swift": base]),
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": feat], dependencies: ["Base"]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": (["import Base", "import Feat", "import SafeDI"] + appFiles).joined(separator: "\n\n")], dependencies: ["Base", "Feat"]),
		]
	}

	private static func lowered(_ typeName: String) -> String {
		typeName.prefix(1).lowercased() + typeName.dropFirst()
	}

	/// The lines of the parameters of `type`'s `mock()` in `module`'s generated file, without their indentation.
	private static func mockParameterLines(of output: MultiModuleTestOutput, type: String = "Root", module: String = "App") -> [String] {
		guard let file = output.modules[module]?.generatedFiles["\(module).swift"] else { return [] }
		let lines = file.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
		guard let extensionIndex = lines.firstIndex(of: "extension \(type) {"),
		      let mockIndex = lines[extensionIndex...].firstIndex(where: { $0.hasSuffix("static func mock(") })
		else { return [] }
		return Array(lines[(mockIndex + 1)...].prefix { !$0.hasPrefix(")") })
	}

	/// The label of a parameter line.
	private static func labelOfParameterLine(_ line: String) -> String {
		String(line.prefix { $0 != ":" })
	}

	/// Compares each pair's expressions, built in `output`'s generated code.
	private mutating func expectValues(of output: MultiModuleTestOutput, modules: [ModuleFixture], pairs: [(String, String)]) async throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		#expect(compilation.failure == nil, "\(compilation.failure.map { "\($0)" } ?? "")")
		guard compilation.failure == nil else { return }
		let graph = DifferentialValueGraph(
			name: "",
			path: try DifferentialValuePath(output: output, modules: modules),
			probePairs: pairs.map { DifferentialValueProbePair(name: $0.0, featureExpression: $0.0, knownRightExpression: $0.1) },
		)
		let comparisons = try #require(try await DifferentialValueOracle.compare(graphs: [graph], filesToDelete: &filesToDelete))
		for comparison in comparisons {
			let result = try comparison.result.get()
			for difference in result.differences {
				Issue.record("The mock builds another value than expected for \(difference)\n\(result.report)")
			}
		}
	}
}
