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
import Testing
@testable import SafeDICore
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// Mock roots that call another module's public mock alike share the call's place in the construction memo, its fills
/// included (`.claude/rules/construction-memo-calls.md`). Every test runs module `App` with the memo shared between mock
/// roots, shared with the roots built in reverse order, shared by drawn schedules, and off, and expects the same generated
/// files each time; the multi-module executor also builds every tree with the memo and without it and compares them by
/// reflection, so a shared call that holds what another place's build would not fails each test.
struct SafeDIToolMockSharedCallTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_reusesCallOfPublicMock_whenMockRootsCallItAlike() async throws {
		// `Root0` and `Root1` each call `F`'s public mock and fill its `api` with `Live`, from the same context, so the
		// root built second reuses the call the first built, fill included, on the first pass.
		let appTypes = [
			Self.live(declarations: []),
			Self.mockedType(named: "Root0", declarations: ["@Instantiated let f: F"]),
			Self.mockedType(named: "Root1", declarations: ["@Instantiated let f: F"]),
		]
		#expect(try await reusedTypesOnFirstPass(appTypes: appTypes) == ["F"])
		try await expectSameAppFilesInEverySetting(appTypes: appTypes)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_reusesCallOfPublicMock_whenItsFillInstantiatesWhatCallersStackBuildsAboveSecondPlace() async throws {
		// `Live`, the fill of `F`'s `api`, instantiates `helperBuilder`, which the second root builds above its call. The fill
		// reads only its own path, so its miss is the call's own, and the second root reuses the call the first root built.
		let appTypes = [
			Self.live(declarations: ["@Instantiated let helperBuilder: Instantiator<Helper>"]),
			seamFixtureType(named: "Helper", isFinalClass: true, declarations: ["@Instantiated let f: F"]),
			Self.mockedType(named: "Root0", declarations: ["@Instantiated let f: F"]),
			Self.mockedType(named: "Root1", declarations: ["@Instantiated let helperBuilder: Instantiator<Helper>"]),
		]
		#expect(try await reusedTypesOnFirstPass(appTypes: appTypes) == ["F"])
		try await expectSameAppFilesInEverySetting(appTypes: appTypes)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesSameMocksWithMemoAsWithout_whenMockRootReachesCallAtTwoPlaces() async throws {
		// `Root` reaches `F` beneath `A` and beneath `B`, alike, and `Other` reaches it once. A tree holds each call's generator
		// once, since the mock's lowering keys a call's fills by it.
		let appTypes = [
			Self.live(declarations: []),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let f: F"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let f: F"]),
			Self.mockedType(named: "Other", declarations: ["@Instantiated let f: F"]),
			Self.mockedType(named: "Root", declarations: ["@Instantiated let a: A", "@Instantiated let b: B"]),
		]
		try await expectSameAppFilesInEverySetting(appTypes: appTypes)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsEachFillPlaceOnce_whenMockRootReachesCallWhoseFillHoldsPlaceAtTwoPlaces() async throws {
		// `Live`, the fill of `F`'s `api`, instantiates `logger: any Logger`, which nothing fulfills, so each mock takes a
		// builder for it, which the builder function of the call binds for the fill. `Root` reaches the call beneath `A` and
		// beneath `B`, alike: a tree that held one generator of the call at both places would bind the place twice.
		let appTypes = [
			"public protocol Logger: AnyObject {}",
			Self.live(declarations: ["@Instantiated let logger: any Logger"]),
			seamFixtureType(named: "A", isFinalClass: true, declarations: ["@Instantiated let f: F"]),
			seamFixtureType(named: "B", isFinalClass: true, declarations: ["@Instantiated let f: F"]),
			Self.mockedType(named: "Other", declarations: ["@Instantiated let f: F"]),
			Self.mockedType(named: "Root", declarations: ["@Instantiated let a: A", "@Instantiated let b: B"]),
		]
		try await expectSameAppFilesInEverySetting(appTypes: appTypes)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesSameMocksWithMemoAsWithout_whenMockRootsDifferInCallerValueFillReads() async throws {
		// `Live`, the fill of `F`'s `api`, receives `token`, which `F` does not hold, so the fill reads the caller's: `Root0`
		// declares the value, and `Root1` declares it lazily, so its fill reads the wrapper's instance.
		let appTypes = [
			seamFixtureType(named: "Token", isFinalClass: true, declarations: []),
			Self.live(declarations: ["@Received let token: Token"]),
			Self.mockedType(named: "Root0", declarations: ["@Instantiated let token: Token", "@Instantiated let f: F"]),
			Self.mockedType(named: "Root1", declarations: ["@Instantiated let token: LazilyInstantiated<Token>", "@Instantiated let f: F"]),
		]
		try await expectSameAppFilesInEverySetting(appTypes: appTypes)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesSameMocksWithMemoAsWithout_whenMockRootsCallPublicMockBeneathLazyCycle() async throws {
		// `Editor` lazily builds a `Preview` that builds `Editor` again, so each mock's tree takes a second pass, and `Editor`
		// calls `F`'s public mock beneath the cycle. A call is never settled, so no later pass reuses it settled.
		let appTypes = [
			Self.live(declarations: []),
			Self.mockedType(named: "First", declarations: ["@Instantiated let theme: Theme", "@Instantiated let editor: Editor"]),
			Self.mockedType(named: "Second", declarations: ["@Instantiated let theme: Theme", "@Instantiated let editor: Editor"]),
			seamFixtureType(named: "Editor", isFinalClass: true, declarations: ["@Instantiated let previewBuilder: Instantiator<Preview>", "@Instantiated let f: F"]),
			seamFixtureType(named: "Preview", isFinalClass: true, declarations: ["@Instantiated let theme: Theme", "@Instantiated let editor: LazilyInstantiated<Editor>"]),
			seamFixtureType(named: "Theme", isFinalClass: true, declarations: []),
		]
		try await expectSameAppFilesInEverySetting(appTypes: appTypes)
	}

	// MARK: Private

	/// How the module's mock roots share the construction memo.
	private enum MemoSetting: CaseIterable {
		case shared
		case sharedInReverseOrder
		case sharedByDrawnSchedule
		case sharedWithLaterPlacesCandidates
		case off

		func run<T>(_ body: () async throws -> T) async throws -> T {
			switch self {
			case .shared:
				try await body()
			case .sharedInReverseOrder:
				try await ConstructionMemoOracle.$buildsMockRootsInReverseOrder.withValue(true) { try await body() }
			case .sharedByDrawnSchedule:
				try await ConstructionSharingSchedule.$current.withValue(ConstructionSharingSchedule(seed: 7, offersLaterPlacesCandidates: false)) { try await body() }
			case .sharedWithLaterPlacesCandidates:
				try await ConstructionSharingSchedule.$current.withValue(ConstructionSharingSchedule(seed: 11, offersLaterPlacesCandidates: true)) { try await body() }
			case .off:
				try await ConstructionMemo.$isEnabled.withValue(false) { try await body() }
			}
		}
	}

	private var filesToDelete: [URL]

	/// Module `Feat`, which declares `F`, whose public mock takes a builder for its `api`, and module `App` of `appTypes`.
	private static func modules(appTypes: [String]) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Feat", packageName: "Feat", swiftFileContentByFilePath: ["FeatTypes.swift": """
			import SafeDI

			public protocol Api: AnyObject {}

			@Instantiable(generateMock: .public)
			public final class F: Instantiable {
			    init(api: any Api) {
			        self.api = api
			    }

			    @Instantiated let api: any Api
			}
			"""]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContentByFilePath: ["AppTypes.swift": "import Feat\nimport SafeDI\n\n" + appTypes.joined(separator: "\n\n")], dependencies: ["Feat"]),
		]
	}

	/// `Live`, which fulfills `Api` in module `App`.
	private static func live(declarations: [String]) -> String {
		seamFixtureType(named: "Live", isFinalClass: true, declarations: declarations, conformances: ", Api")
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(fulfillingAdditionalTypes: [Api.self])\n")
	}

	/// A final class named `name` whose mock is generated.
	private static func mockedType(named name: String, declarations: [String]) -> String {
		seamFixtureType(named: name, isFinalClass: true, declarations: declarations)
			.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n")
	}

	/// The types of the places a mock root of module `App`, with `appTypes`, reuses on its tree's first pass.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func reusedTypesOnFirstPass(appTypes: [String]) async throws -> Set<String> {
		let (stream, continuation) = AsyncStream.makeStream(of: String.self)
		_ = try await ConstructionMemoOracle.$reusedPlaceObserver.withValue(TaskLocalFunction { concreteType, isFirstPass in
			guard isFirstPass else { return }
			continuation.yield(concreteType)
		}) { [appTypes] in
			try await executeSafeDIToolMultiModuleTest(modules: Self.modules(appTypes: appTypes), integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var reusedTypes = Set<String>()
		for await reusedType in stream {
			reusedTypes.insert(reusedType)
		}
		return reusedTypes
	}

	/// Expects module `App`'s generated files, with `appTypes`, to be the same in every `MemoSetting`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectSameAppFilesInEverySetting(appTypes: [String]) async throws {
		var filesBySetting = [[String: String]]()
		for setting in MemoSetting.allCases {
			let output = try await setting.run { [appTypes] in
				try await executeSafeDIToolMultiModuleTest(modules: Self.modules(appTypes: appTypes), integration: .moduleInfo, filesToDelete: &filesToDelete)
			}
			filesBySetting.append(output.modules["App"]?.generatedFiles ?? [:])
		}
		#expect(!filesBySetting[0].isEmpty)
		for files in filesBySetting.dropFirst() {
			#expect(files == filesBySetting[0])
		}
	}
}
