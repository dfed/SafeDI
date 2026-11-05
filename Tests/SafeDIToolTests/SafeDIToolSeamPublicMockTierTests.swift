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

/// A seam whose `generateMock: .public` requires its type to be `public` keeps a `public` generated initializer, so a
/// required parameter narrower than `public` is still an error at the seam. The error says what requires the seam to be
/// `public`, offers no narrower seam, and leads with the cheapest fixes: widen the parameter's type, or receive it only
/// if available; building it inside the tree and declaring the tree on a narrower type follow. A seam that is `public`
/// with any other mock gets the error every `public` seam gets.
struct SafeDIToolSeamPublicMockTierTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: A pass-through a type in the tree receives

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorLeadingWithCheapestFixes_whenPublicMockSeamsTreeRequiresPackageType() async {
		// Cell 1: `Store`, in the tree, requires `storage`, whose own declaration is `package`.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `storage: Storage`, which `Store` receives, and cannot pass `nil` for it, since it is required. `generateMock: .public` requires `Screen` to be `public`, so its generated initializer is `public` too. `Storage`'s own `@Instantiable` declaration is `package`. Declare `Storage` `public`; receive `storage` with `onlyIfAvailable: true` and an optional type; build `storage` inside the tree; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Store.swift"]):7:5: note: `Store` receives `storage: Storage` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.storage(access: "package"), Self.store(access: "package", receives: ["storage: Storage"]), Self.screen(mock: ".public", declarations: ["@Instantiated private let store: Store"])])],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOnInternalType_whenPublicMockSeamsTreeRequiresInternalType() async {
		// Cell 3: `storage`'s type is `internal`, two levels beneath the seam's: the tree is offered an `internal` type.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `storage: Storage`, which `Store` receives, and cannot pass `nil` for it, since it is required. `generateMock: .public` requires `Screen` to be `public`, so its generated initializer is `public` too. `Storage`'s own `@Instantiable` declaration is `internal`. Declare `Storage` `public`; receive `storage` with `onlyIfAvailable: true` and an optional type; build `storage` inside the tree; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Store.swift"]):7:5: note: `Store` receives `storage: Storage` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.storage(access: ""), Self.store(access: "", receives: ["storage: Storage"]), Self.screen(mock: ".public", initializerAccess: "", declarations: ["@Instantiated private let store: Store"])])],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingOnlyIfAvailableAlias_whenPublicMockSeamsTreeRequiresPackageTypeThroughAlias() async {
		// `Store` requires `storage` only through its alias `cache`: the receive the error offers to relax is the alias's.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `storage: Storage`, which `Store` receives through its alias `cache` (`fulfilledByDependencyNamed: "storage"`), and cannot pass `nil` for it, since it is required. `generateMock: .public` requires `Screen` to be `public`, so its generated initializer is `public` too. `Storage`'s own `@Instantiable` declaration is `package`. Declare `Storage` `public`; receive `cache` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Store.swift"]):7:5: note: `Store` receives `storage: Storage` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					Self.storage(access: "package"),
					"""
					@Instantiable
					package final class Store: Instantiable {
					    package init(cache: Storage) {
					        self.cache = cache
					    }

					    @Received(fulfilledByDependencyNamed: "storage", ofType: Storage.self) private let cache: Storage
					}
					""",
					Self.screen(mock: ".public", declarations: ["@Instantiated private let store: Store"]),
				])],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingOtherModulesDeclarationFirst_whenPublicMockSeamsTreeRequiresTypeAnotherModuleDeclaresPackage(integration: MultiModuleIntegration) async {
		// Cell 8: `Theme` is declared exactly `package`, outside any `#if`, in module `Core`: the first remedy widens that
		// declaration, which a note with a fix-it points at.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			let corePath = Self.path(of: "Theme.swift", in: "Core", fixtures, integration)
			return """
			\(Self.path(of: "Screen.swift", in: "Feature", fixtures, integration)):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `theme: Theme`, which `Store` receives, and cannot pass `nil` for it, since it is required. `generateMock: .public` requires `Screen` to be `public`, so its generated initializer is `public` too. `Theme` is declared `package` in module `Core`. Declare `Theme` `public` in module `Core`; receive `theme` with `onlyIfAvailable: true` and an optional type; build `theme` inside the tree; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(corePath):1:1: note: `Theme` is declared `package` here.
			\(corePath):1:1-1:8: fixit: public
			\(Self.path(of: "Store.swift", in: "Feature", fixtures, integration)):9:5: note: `Store` receives `theme: Theme` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContentByFilePath: ["Theme.swift": "package struct Theme {\n    package init() {}\n}"]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"import Core\n\n" + Self.store(access: "package", receives: ["theme: Theme"]),
						"import Core\n\n" + Self.screen(mock: ".public", declarations: ["@Instantiated private let store: Store"]),
					], dependencies: ["Core"]),
				],
				integration: integration,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorPerParameterEachNamingPublicMockOnce_whenPublicMockSeamsTreeRequiresTwoPackageTypes() async {
		// Cell 9: two required `package` pass-throughs give two errors, each saying once what requires the seam's access.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `session: Session`, which `Store` receives, and cannot pass `nil` for it, since it is required. `generateMock: .public` requires `Screen` to be `public`, so its generated initializer is `public` too. `Session`'s own `@Instantiable` declaration is `package`. Declare `Session` `public`; receive `session` with `onlyIfAvailable: true` and an optional type; build `session` inside the tree; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Store.swift"]):9:5: note: `Store` receives `session: Session` here.
			\(fixtures["Feature"]!["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `storage: Storage`, which `Store` receives, and cannot pass `nil` for it, since it is required. `generateMock: .public` requires `Screen` to be `public`, so its generated initializer is `public` too. `Storage`'s own `@Instantiable` declaration is `package`. Declare `Storage` `public`; receive `storage` with `onlyIfAvailable: true` and an optional type; build `storage` inside the tree; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Store.swift"]):8:5: note: `Store` receives `storage: Storage` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					Self.storage(access: "package"),
					Self.storage(access: "package").replacingOccurrences(of: "Storage", with: "Session"),
					Self.store(access: "package", receives: ["storage: Storage", "session: Session"]),
					Self.screen(mock: ".public", declarations: ["@Instantiated private let store: Store"]),
				])],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorAtOuterSeamOnly_whenPublicMockSeamCallsPackageSeamThatTakesPackageType() async {
		// Cell 10: `Service`, a `package` seam of module `Core` in `Screen`'s tree, takes `storage` on its `package`
		// initializer, so `Screen` passes it on, and `Screen`'s `public` initializer cannot take it. `Service`, which
		// generates, is not reported.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):3:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `storage: Storage`, which `Store` receives, and cannot pass `nil` for it, since it is required. `generateMock: .public` requires `Screen` to be `public`, so its generated initializer is `public` too. `Storage`'s own `@Instantiable` declaration is `package`. Declare `Storage` `public`; receive `storage` with `onlyIfAvailable: true` and an optional type; build `storage` inside the tree; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Core"]!["Store.swift"]):7:5: note: `Store` receives `storage: Storage` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: [
						Self.storage(access: "package"),
						Self.store(access: "package", receives: ["storage: Storage"]),
						"""
						@Instantiable(generateDependencyTree: true)
						package struct Service: Instantiable {
						    package init(store: Store) {
						        self.store = store
						    }

						    @Instantiated private let store: Store
						}
						""",
					]),
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
						"import Core\n\n" + Self.screen(mock: ".public", declarations: ["@Instantiated private let service: Service"]),
					], dependencies: ["Core"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingNoNarrowerSeamInProofRemedy_whenPublicMockSeamsTreeRequiresTypeSafeDICannotProve() async {
		// B2.14 of `SafeDIToolSeamAccessProofTests` with a public mock: SafeDI cannot read the spelling `[3 of Int]`, so the
		// first remedy asks the seam to receive it, which puts it in an initializer the compiler checks. The seam cannot be
		// narrower, so the remedy says what the compiler then requires of `[3 of Int]` instead.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `session: [3 of Int]`, which `Consumer` receives through its alias `auth` (`fulfilledByDependencyNamed: "session"`), and cannot pass `nil` for it, since it is required. `generateMock: .public` requires `Screen` to be `public`, so its generated initializer is `public` too. `[3 of Int]` is `internal` as far as SafeDI can tell: SafeDI cannot read its spelling, and no initializer, `instantiate(…)` or mock method SafeDI records mentions it (`Consumer`'s initializer mentions only `any Auth`). Declare `@Received let session: [3 of Int]` on `Screen`, so that its initializer, which the compiler checks, states how visible `[3 of Int]` is (if `[3 of Int]` is narrower than `public`, the compiler then requires it to be `public`); mention `[3 of Int]` in a `public` initializer, `instantiate(…)` or mock method SafeDI records; receive `auth` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Consumer.swift"]):7:5: note: `Consumer` receives `session: [3 of Int]` here.
			"""
		}) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let consumer: Consumer"])
						.replacingOccurrences(of: "generateDependencyTree: true", with: "generateDependencyTree: true, generateMock: .public"),
					"public protocol Auth {}",
					"""
					@Instantiable
					public struct Consumer: Instantiable {
					    public init(auth: any Auth) {
					        self.auth = auth
					    }

					    @Received(fulfilledByDependencyNamed: "session", ofType: [3 of Int].self) let auth: any Auth
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: The seam's own properties

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingOnlyIfAvailableReceive_whenPublicMockSeamReceivesPackageType() async {
		// Cell 4: the seam's own required receive is not built inside the tree, so building it is not offered.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `storage: Storage`, which `Screen` receives, and cannot pass `nil` for it, since it is required. `generateMock: .public` requires `Screen` to be `public`, so its generated initializer is `public` too. `Storage`'s own `@Instantiable` declaration is `package`. Declare `Storage` `public`; receive `storage` with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Screen.swift"]):8:5: note: `Screen` receives `storage: Storage` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.storage(access: "package"), Self.store(access: "package", receives: []), Self.screen(mock: ".public", declarations: ["@Received private let storage: Storage", "@Instantiated private let store: Store"])])],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingNoReceive_whenPublicMockSeamForwardsPackageType() async {
		// Cell 5: a forwarded value is neither received nor built, so only widening its type and declaring the tree on a
		// narrower type are offered. `Storage`'s `mockOnly` mock lets the public mock build the value it forwards, which
		// the public mock's own error would otherwise report first.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `storage: Storage`, which `Screen`'s own initializer takes, and cannot pass `nil` for it, since it is required. `generateMock: .public` requires `Screen` to be `public`, so its generated initializer is `public` too. `Storage`'s own `@Instantiable` declaration is `package`. Declare `Storage` `public`; or declare the dependency tree on a `package` type that instantiates `Screen`.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					Self.storage(access: "package"),
					"@Instantiable(mockOnly: true)\nextension Storage {\n    package static func mock() -> Storage {\n        Storage()\n    }\n}",
					Self.store(access: "package", receives: []),
					Self.screen(mock: ".public", declarations: ["@Forwarded private let storage: Storage", "@Instantiated private let store: Store"]),
				])],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: A builder

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsTierOmitsBuilderLeadingWithCheapestFixes_whenPublicMockSeamsTreeHasPackageHole() async {
		// Cell 2: no declaration `Feature` reads fulfills `Service`, which is declared `package`, so `Screen`'s `public`
		// initializer cannot take the builder for it.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer cannot take `serviceBuilder: @escaping (Screen.SafeDIScope_Store_service) -> any Service`, the builder for `Store`'s `service: any Service`, which no @Instantiable declaration that module `Feature` can see fulfills. `generateMock: .public` requires `Screen` to be `public`, so its generated initializer is `public` too. `Service` is declared `package`. Declare `Service` `public`; make an @Instantiable declaration that fulfills `Service` one module `Feature` reads, so `Screen`'s tree builds it; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Service.swift"]):1:1: note: `Service` is declared `package` here.
			\(fixtures["Feature"]!["Service.swift"]):1:1-1:8: fixit: public
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [
					ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContentByFilePath: [
						"Service.swift": "package protocol Service {}",
						"Store.swift": Self.store(access: "package", receives: []).replacingOccurrences(of: "package init() {}", with: "package init(service: any Service) {\n        self.service = service\n    }\n\n    @Instantiated private let service: any Service"),
						"Screen.swift": Self.screen(mock: ".public", declarations: ["@Instantiated private let store: Store"]),
					]),
					ModuleFixture(name: "App", packageName: "Shop", swiftFileContent: [
						"import Feature\n\n@Instantiable(fulfillingAdditionalTypes: [Service.self])\npackage final class DefaultService: Service, Instantiable {\n    package init() {}\n}",
						"import Feature\n\n" + seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let screen: Screen"]),
					], dependencies: ["Feature"]),
				],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: A seam that is `public` with any other mock

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorOfferingNarrowerSeam_whenPublicSeamWithInternalMockRequiresPackageType() async {
		// Cell 6: `generateMock: true` does not require `Screen` to be `public`, so declaring it `package` is offered, in
		// the order every `public` seam's error gives.
		await assertThrowsMultiModuleError(inModule: "Feature", diagnostics: { fixtures in
			"""
			\(fixtures["Feature"]!["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`'s `public` access requires, cannot take `storage: Storage`, which `Store` receives, and cannot pass `nil` for it, since it is required. `Storage`'s own `@Instantiable` declaration is `package`. Declare `Storage` `public`; declare `Screen` `package`; build `storage` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on a `package` type that instantiates `Screen`.
			\(fixtures["Feature"]!["Store.swift"]):7:5: note: `Store` receives `storage: Storage` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: [ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [Self.storage(access: "package"), Self.store(access: "package", receives: ["storage: Storage"]), Self.screen(mock: "true", declarations: ["@Instantiated private let store: Store"])])],
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Storage`, declared `access`, or `internal` when `access` is empty.
	private static func storage(access: String) -> String {
		let modifier = access.isEmpty ? "" : "\(access) "
		return """
		@Instantiable
		\(modifier)final class Storage: Instantiable {
		    \(modifier)init() {}
		}
		"""
	}

	/// `Store`, declared `access`, or `internal` when `access` is empty, which receives each of `receives` – a
	/// `label: Type` pair – privately.
	private static func store(access: String, receives: [String]) -> String {
		let modifier = access.isEmpty ? "" : "\(access) "
		let labels = receives.map { String($0.prefix { $0 != ":" }) }
		let initializer = receives.isEmpty
			? "\(modifier)init() {}"
			: "\(modifier)init(\(receives.joined(separator: ", "))) {\n" + labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n") + "\n    }\n\n" + receives.map { "    @Received private let \($0)" }.joined(separator: "\n")
		return """
		@Instantiable
		\(modifier)final class Store: Instantiable {
		    \(initializer)
		}
		"""
	}

	/// `Screen`, a `public` seam with `generateMock: mock`, whose initializer, at `initializerAccess` (`internal` when
	/// empty), takes each of `declarations`.
	private static func screen(mock: String, initializerAccess: String = "package", declarations: [String]) -> String {
		let properties = declarations.map { declaration -> (label: String, type: String) in
			let property = declaration[declaration.range(of: " let ")!.upperBound...]
			return (String(property.prefix { $0 != ":" }), property.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces))
		}
		let modifier = initializerAccess.isEmpty ? "" : "\(initializerAccess) "
		return """
		@Instantiable(generateDependencyTree: true, generateMock: \(mock))
		public struct Screen: Instantiable {
		    \(modifier)init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {
		\(properties.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n"))
		    }

		\(declarations.map { "    \($0)" }.joined(separator: "\n"))
		}
		"""
	}

	/// The path a diagnostic names `file` of `module` by under `integration`.
	private static func path(of file: String, in module: String, _ fixtures: [String: FixturePaths], _ integration: MultiModuleIntegration) -> String {
		guard let moduleFixtures = fixtures[module] else { return "<\(module) did not run>/\(file)" }
		return switch integration {
		case .moduleInfo:
			moduleFixtures[file]
		case .swiftPackagePlugin:
			NormalizedFilePath(moduleFixtures.compilerPath(of: file)).path
		}
	}
}
